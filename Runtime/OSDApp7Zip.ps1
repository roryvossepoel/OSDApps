. (Join-Path $PSScriptRoot 'OSDAppPayloadFile.ps1')
# Shared by the module, PreInstall and Runner. Loading this file performs no I/O.
function Get-OSDApp7ZipAssetName {
    param([Parameter(Mandatory)][string]$Version, [Parameter(Mandatory)][ValidateSet('x64','x86','arm64')][string]$Architecture)
    if ($Version -notmatch '^\d{2}\.\d{2}$') { throw 'Unsupported 7Zip release version format.' }
    $suffix = switch ($Architecture) { 'x64' { '-x64' } 'arm64' { '-arm64' } 'x86' { '' } }
    '7z{0}{1}.exe' -f $Version.Replace('.',''), $suffix
}

function Get-OSDApp7ZipRelease {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('x64','x86','arm64')][string]$Architecture)
    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/ip7z/7zip/releases/latest' -Headers @{
        Accept='application/vnd.github+json'; 'User-Agent'='OSDApps'
    } -TimeoutSec 60 -ErrorAction Stop
    if ($release.draft -ne $false -or $release.prerelease -ne $false) { throw '7Zip stable release metadata is invalid.' }
    $version = [string]$release.tag_name
    $name = Get-OSDApp7ZipAssetName -Version $version -Architecture $Architecture
    $assets = @($release.assets | Where-Object { [string]$_.name -ceq $name })
    if ($assets.Count -ne 1) { throw "7Zip release must contain exactly one '$name' asset." }
    $asset = $assets[0]
    $expectedUri = "https://github.com/ip7z/7zip/releases/download/$version/$name"
    if ([string]$asset.browser_download_url -cne $expectedUri -or [string]$asset.digest -notmatch '^sha256:[a-fA-F0-9]{64}$' -or [long]$asset.size -le 0) {
        throw '7Zip release asset has an unexpected URL, missing SHA-256 or invalid size.'
    }
    [pscustomobject]@{ Version=$version; Architecture=$Architecture; PackageUri=$expectedUri; Sha256=([string]$asset.digest).Substring(7); Size=[long]$asset.size }
}

function Assert-OSDApp7ZipGeneration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][ValidateSet('x64','x86','arm64')][string]$Architecture,
        [psobject]$Release
    )
    $info = Get-Content -LiteralPath (Join-Path $Root 'CacheInfo.json') -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $name = Get-OSDApp7ZipAssetName -Version ([string]$info.Version) -Architecture $Architecture
    $expectedUri = "https://github.com/ip7z/7zip/releases/download/$($info.Version)/$name"
    if ([string]$info.Id -ne '7Zip' -or [string]$info.Architecture -ne $Architecture -or
        [string]$info.PackageUri -cne $expectedUri -or [string]$info.Sha256 -notmatch '^[a-fA-F0-9]{64}$' -or
        [long]$info.Size -le 0) { throw '7Zip cache metadata is invalid or incompatible.' }
    if ($Release -and ([string]$info.Version -ne [string]$Release.Version -or
        [string]$info.Sha256 -ne [string]$Release.Sha256 -or [long]$info.Size -ne [long]$Release.Size -or
        [string]$info.PackageUri -cne [string]$Release.PackageUri)) { throw '7Zip cache does not match the current official release.' }
    $package = (Resolve-OSDAppBuiltInPayloadPath -Path (Join-Path $Root 'Package.exe'))
    if ((Get-Item -LiteralPath $package -ErrorAction Stop).Length -ne [long]$info.Size -or
        (Get-FileHash -LiteralPath $package -Algorithm SHA256 -ErrorAction Stop).Hash -ne [string]$info.Sha256) {
        throw '7Zip package size or SHA-256 does not match the recorded release.'
    }
    # Validate the PE architecture as well as the release asset mapping.
    $stream = [IO.File]::OpenRead($package)
    $reader = [IO.BinaryReader]::new($stream)
    try {
        if ($stream.Length -lt 64 -or $reader.ReadUInt16() -ne 0x5A4D) { throw '7Zip package is not a Windows executable.' }
        $stream.Position = 60
        $offset = $reader.ReadInt32()
        if ($offset -lt 64 -or $offset -gt ($stream.Length - 6)) { throw '7Zip PE header is invalid.' }
        $stream.Position = $offset
        if ($reader.ReadUInt32() -ne 0x4550) { throw '7Zip PE signature is invalid.' }
        $expectedMachine = switch ($Architecture) { 'x64' { 0x8664 } 'x86' { 0x14c } 'arm64' { 0xaa64 } }
        if ($reader.ReadUInt16() -ne $expectedMachine) { throw '7Zip executable architecture does not match the requested architecture.' }
    }
    finally { $reader.Dispose(); $stream.Dispose() }
    $info
}

function Sync-OSDApp7ZipGeneration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][ValidateSet('x64','x86','arm64')][string]$Architecture,
        [Parameter(Mandatory)][scriptblock]$Download,
        [ValidateRange(0, [double]::MaxValue)][double]$MinimumFreeSpaceGB = 1,
        [scriptblock]$Log
    )
    # Callback is invoked from the transaction build scope.
    $downloadAction = $Download
    Restore-OSDAppCacheGeneration -Root $Root -Validate {
        param($candidate)
        Assert-OSDApp7ZipGeneration -Root $candidate -Architecture $Architecture
    } | Out-Null
    $release = Get-OSDApp7ZipRelease -Architecture $Architecture
    $current = $false
    $cacheDecisionReason = 'The existing generation passed integrity and selection checks against the current official release metadata.'
    try { Assert-OSDApp7ZipGeneration -Root $Root -Architecture $Architecture -Release $release | Out-Null; $current = $true }
    catch {
        $cacheDecisionReason = 'The existing generation could not be reused. ' + $_.Exception.Message
        Write-Verbose "7Zip cache requires acquisition: $($_.Exception.Message)"
    }
    if (-not $current) {
        Invoke-OSDAppBuiltInCacheTransaction -Root $Root -ExpectedBytes $release.Size -MinimumFreeSpaceGB $MinimumFreeSpaceGB -Build {
            param($candidate)
            & $downloadAction $release.PackageUri ((Resolve-OSDAppBuiltInPayloadPath -Path (Join-Path $candidate 'Package.exe'))) | Out-Null
            [ordered]@{
                Id='7Zip'; Cached=$true; Version=$release.Version; VersionSource='GitHubRelease'; Architecture=$Architecture;
                PackageUri=$release.PackageUri; Sha256=$release.Sha256; Size=$release.Size;
                SourcePolicy='Evergreen'; SyncMethod='ReleaseSha256'; SyncedAt=(Get-Date).ToUniversalTime().ToString('o')
            } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $candidate 'CacheInfo.json') -Encoding UTF8
        } -Validate {
            param($candidate)
            Assert-OSDApp7ZipGeneration -Root $candidate -Architecture $Architecture -Release $release
        } | Out-Null
    }
    [pscustomobject]@{ Id='7Zip'; Version=$release.Version; Architecture=$Architecture; Root=$Root; Updated=(-not $current); CacheDecisionReason=$cacheDecisionReason }
}
