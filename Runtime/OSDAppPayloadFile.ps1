# Built-in generations contain one primary payload per format. Repository ZIPs
# are deliberately outside this contract and keep their Package.zip name.
function Resolve-OSDAppBuiltInPayloadPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $leaf = Split-Path -Path $Path -Leaf
    if ($leaf -notin @('Package.exe','Package.msi','Package.zip','teams.msix')) { return $Path }
    $directory = Split-Path -Path $Path -Parent
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { return $Path }
    $extension = [IO.Path]::GetExtension($leaf)
    $files = @(Get-ChildItem -LiteralPath $directory -File -Force -ErrorAction Stop |
        Where-Object { $_.Extension -eq $extension })
    if ($files.Count -gt 1) { throw "Ambiguous built-in payload: more than one $extension file in '$directory'." }
    if ($files.Count -eq 0) { return $Path }
    if (($files[0].Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Built-in payload links are not supported.' }
    return $files[0].FullName
}

function Get-OSDAppDownloadFileName {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Response, [Parameter(Mandatory)][string]$ExpectedExtension)

    $disposition = $Response.Content.Headers.ContentDisposition
    $name = $null
    if ($disposition) {
        if ($disposition.FileNameStar) { $name = [string]$disposition.FileNameStar }
        elseif ($disposition.FileName) { $name = ([string]$disposition.FileName).Trim('"') }
    }
    if (-not $name) {
        # .NET Framework can normalize trailing dots in AbsolutePath. Read the
        # original final URI so validation rejects them instead of changing a name.
        $rawPath = [regex]::Match([string]$Response.RequestMessage.RequestUri.OriginalString, '^[a-zA-Z][a-zA-Z0-9+.-]*://[^/?#]*(?<path>/[^?#]*)?').Groups['path'].Value
        $name = [uri]::UnescapeDataString(($rawPath -split '/')[-1])
    }
    # A server-provided name must be a Windows leaf filename, never a path.
    if ([string]::IsNullOrWhiteSpace($name) -or $name.Length -gt 240 -or
        $name -match '[\x00-\x1f<>:"/\\|?*]' -or $name -match '[. ]$' -or
        $name -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)' -or
        [IO.Path]::GetExtension($name) -ine $ExpectedExtension) {
        throw "The vendor response did not provide a safe $ExpectedExtension filename."
    }
    return $name
}

function Copy-OSDAppBuiltInPayload {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$DestinationDirectory)

    $source = Get-Item -LiteralPath (Resolve-OSDAppBuiltInPayloadPath -Path $Path) -ErrorAction Stop
    New-Item -ItemType Directory -Path $DestinationDirectory -Force | Out-Null
    $destination = Join-Path $DestinationDirectory $source.Name
    $temporary = Join-Path $DestinationDirectory ('.osdapps-copy-' + [guid]::NewGuid().ToString('N'))
    try {
        Copy-Item -LiteralPath $source.FullName -Destination $temporary -ErrorAction Stop
        if ((Get-Item -Force -LiteralPath $temporary).Length -ne $source.Length) { throw 'Staged payload copy is incomplete.' }
        Move-Item -LiteralPath $temporary -Destination $destination -Force -ErrorAction Stop
        # Remove a previous staged filename only after its replacement is complete.
        Get-ChildItem -LiteralPath $DestinationDirectory -File -Force -ErrorAction Stop |
            Where-Object { $_.Extension -eq $source.Extension -and $_.Name -ne $source.Name } |
            Remove-Item -Force -ErrorAction Stop
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}

function Remove-OSDAppRetiredCacheVariant {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][ValidateSet('VisualCRedist','7Zip')][string]$Id,
        [Parameter(Mandatory)][ValidateSet('x86','x64','arm64')][string]$Architecture,
        [Parameter(Mandatory)][scriptblock]$Validate
    )
    # Called under the cache writer lock, only after successful synchronization.
    # Never infer ownership from an unknown directory name alone.
    try {
        $active = Get-Item -LiteralPath $Root -Force -ErrorAction Stop
        $app = $active.Parent
        $builtIn = $app.Parent
        if ($active.Name -ne $Architecture -or $app.Name -ne $Id -or $builtIn.Name -ne 'BuiltIn') { return }
        $ancestor = $active
        while ($null -ne $ancestor) {
            if (($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return }
            $ancestor = $ancestor.Parent
        }
        $retiredId = if ($Id -eq 'VisualCRedist') { 'VisualCppRedist' } else { 'SevenZip' }
        $retiredRoot = Join-Path $builtIn.FullName $retiredId
        if (-not (Test-Path -LiteralPath $retiredRoot -PathType Container)) { return }
        $retired = Get-Item -LiteralPath $retiredRoot -Force -ErrorAction Stop
        if (($retired.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return }
        $path = Join-Path $retiredRoot $Architecture
        if (-not (Test-Path -LiteralPath $path -PathType Container)) { return }
        $pending = [System.Collections.Generic.Stack[System.IO.FileSystemInfo]]::new()
        $pending.Push((Get-Item -LiteralPath $path -Force -ErrorAction Stop))
        while ($pending.Count -gt 0) {
            $item = $pending.Pop()
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
                $item.Name -match '\.osdapps-' -or $item.Name -eq '.staging') { return }
            if ($item -is [IO.DirectoryInfo]) {
                foreach ($child in @(Get-ChildItem -LiteralPath $item.FullName -Force -ErrorAction Stop)) { $pending.Push($child) }
            }
        }
        $info = Get-Content -LiteralPath (Join-Path $path 'CacheInfo.json') -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ([string]$info.Id -ne $retiredId -or [string]$info.Architecture -ne $Architecture) { return }
        & $Validate $Root | Out-Null
        Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
        Write-Information "Retired cache variant removed after replacement validation: $path" -Tags 'OSDApps','CacheAliasPruned'
        # Only remove the parent when no other variants or recovery files remain.
        if (@(Get-ChildItem -LiteralPath $retiredRoot -Force -ErrorAction Stop).Count -eq 0) {
            Remove-Item -LiteralPath $retiredRoot -Force -ErrorAction Stop
        }
    }
    catch { Write-Warning "Retired cache cleanup was not completed: $($_.Exception.Message)" }
}
