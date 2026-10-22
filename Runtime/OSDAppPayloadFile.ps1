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
        $name = [uri]::UnescapeDataString(($Response.RequestMessage.RequestUri.AbsolutePath -split '/')[-1])
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
