. (Join-Path $PSScriptRoot 'OSDStagePayloadFile.ps1')
# Shared by the module and standalone PreInstall. No deployment is started here.
function Restore-OSDStageCacheGeneration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][scriptblock]$Validate
    )

    # Never replace an existing active generation, even if it is incomplete.
    # Recovery is only for the gap between the two directory renames.
    if (Test-Path -LiteralPath $Root) { return }
    $parent = Split-Path -Path $Root -Parent
    $leaf = Split-Path -Path $Root -Leaf
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { return }
    $pattern = '^' + [regex]::Escape($leaf) + '\.osdstage-old-[0-9a-f]{32}$'
    $backups = @(Get-ChildItem -LiteralPath $parent -Directory -ErrorAction Stop |
        Where-Object { $_.Name -match $pattern })
    if ($backups.Count -eq 0) { return }

    $validBackups = @(
        foreach ($backup in $backups) {
            try {
                if (($backup.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                    throw 'Recovery does not follow directory links.'
                }
                $links = @(Get-ChildItem -LiteralPath $backup.FullName -Recurse -Force -ErrorAction Stop |
                    Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 })
                if ($links.Count -gt 0) { throw 'Recovery generation contains a file or directory link.' }
                # Validation callbacks must throw on invalid content.
                & $Validate $backup.FullName | Out-Null
                $backup
            }
            catch {
                Write-Verbose "Preserving rejected recovery candidate '$($backup.FullName)': $($_.Exception.Message)"
            }
        }
    )

    if ($validBackups.Count -ne 1) {
        throw "Cache recovery requires exactly one valid previous generation for '$Root'; found $($validBackups.Count). All transaction directories were preserved."
    }
    # Do not guess by version or timestamp and do not promote an uncommitted
    # .new directory. Keep all other residue for validation/cleanup after sync.
    if (Test-Path -LiteralPath $Root) {
        throw "Cache recovery stopped because the active path appeared during validation: $Root"
    }
    $source = $validBackups[0].FullName
    Move-Item -LiteralPath $source -Destination $Root -ErrorAction Stop
    [pscustomobject]@{ Root = $Root; PreviousPath = $source; Recovered = $true }
}

function Assert-OSDStageRecoverableBuiltInGeneration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][ValidateSet('Microsoft365Apps','MicrosoftTeams','GoogleChromeEnterprise','MozillaFirefoxEnterprise','CiscoWebex','ZoomWorkplace','AdobeAcrobatUnified')][string]$Id,
        [Parameter(Mandatory)][scriptblock]$SignatureValidator,
        [Parameter(Mandatory)][scriptblock]$OfficeValidator,
        [Parameter(Mandatory)][scriptblock]$TeamsVersionReader
    )

    $info = Get-Content -LiteralPath (Join-Path $Root 'CacheInfo.json') -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ([string]$info.Id -ne $Id -or $info.Cached -ne $true) {
        throw "Recovery metadata does not describe a cached '$Id' generation."
    }
    $payloadPath = $null
    if ($Id -ne 'Microsoft365Apps') {
        $extension = if ($Id -eq 'MicrosoftTeams') { '.msix' } elseif ($Id -eq 'AdobeAcrobatUnified') { '.zip' } else { '.msi' }
        $payloadPath = Assert-OSDStageCachedPayload -Root $Root -ExpectedExtension $extension -Id $Id
    }
    $required = switch ($Id) {
        'Microsoft365Apps' { 'setup.exe'; 'configuration.xml' }
        'MicrosoftTeams' { 'teamsbootstrapper.exe'; [string]$info.PayloadFileName }
        default { [string]$info.PayloadFileName }
    }
    foreach ($file in $required) {
        $path = (Resolve-OSDStageBuiltInPayloadPath -Path (Join-Path $Root $file))
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -le 0) {
            throw "Recovery generation '$Id' is missing nonempty '$file'."
        }
    }
    switch ($Id) {
        'Microsoft365Apps' {
            if ([string]$info.Version -notmatch '^\d+\.\d+\.\d+\.\d+$' -or [string]$info.Architecture -notin @('x86','x64')) {
                throw 'Office recovery metadata has no valid version or architecture.'
            }
            & $OfficeValidator $Root ([string]$info.Version) ([string]$info.Architecture) | Out-Null
            & $SignatureValidator $Id (Join-Path $Root 'setup.exe') | Out-Null
        }
        'MicrosoftTeams' {
            & $SignatureValidator $Id (Join-Path $Root 'teamsbootstrapper.exe') | Out-Null
            $version = & $TeamsVersionReader $payloadPath
            if (-not $version -or [string]$version -ne [string]$info.Version) {
                throw 'Teams recovery package version does not match its metadata.'
            }
        }
        'AdobeAcrobatUnified' {
            Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
            $archive = [IO.Compression.ZipFile]::OpenRead($payloadPath)
            try {
                if ($archive.Entries.Count -eq 0) { throw 'Adobe recovery archive is empty.' }
            }
            finally { $archive.Dispose() }
        }
        default { & $SignatureValidator $Id $payloadPath | Out-Null }
    }
}
