function Add-OSDAppCMTraceOpen {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateSet('x64','arm64')][string]$Architecture = 'x64',
        [bool]$DisableUpdateChecks = $true,
        [ValidateRange(1,120)][int]$InstallTimeoutMinutes = 10,
        [string]$WindowsPath
    )

    $target = Resolve-OSDAppWindowsPath -WindowsPath $WindowsPath
    $cache = Get-OSDAppCachePath
    $source = Join-Path $cache ('BuiltIn\CMTraceOpen\' + $Architecture)
    $infoPath = Join-Path $source 'CacheInfo.json'
    if (-not (Test-Path -LiteralPath $infoPath -PathType Leaf)) {
        throw 'CMTrace Open is not cached. Run Sync-OSDAppCMTraceOpen first.'
    }

    $info = Get-Content -LiteralPath $infoPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    if ($info.Id -ne 'CMTraceOpen' -or $info.Architecture -ne $Architecture -or
        [string]$info.Version -notmatch '^\d+\.\d+\.\d+$' -or
        [string]$info.Sha256 -notmatch '^[a-fA-F0-9]{64}$') {
        throw 'Invalid CMTrace Open cache metadata.'
    }

    $vendorFileName = 'CMTrace-Open_{0}_{1}.msi' -f $info.Version,$Architecture
    if ([string]$info.PayloadFileName -cne $vendorFileName) {
        throw 'CMTrace Open cached asset name differs from the official release.'
    }

    $sourceMsi = Join-Path $source $vendorFileName
    if (-not (Test-Path -LiteralPath $sourceMsi -PathType Leaf) -or
        (Get-FileHash -LiteralPath $sourceMsi -Algorithm SHA256).Hash -ne [string]$info.Sha256) {
        throw 'CMTrace Open cached MSI is missing or failed SHA-256 verification.'
    }

    # Sync (full Windows) validates GitHub's release SHA-256 and Authenticode.
    # SetupComplete validates SHA-256 and Authenticode again. WinPE only stages
    # content already matched to the signed-release cache hash.
    $stage = Join-Path $target 'Windows\Temp\OSDApps'
    $relativeRoot = 'BuiltIn\CMTraceOpen\' + $Architecture
    $destination = Join-Path $stage $relativeRoot
    if (-not $PSCmdlet.ShouldProcess($destination, 'Stage verified CMTrace Open MSI')) { return }

    New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force -ErrorAction Stop | Out-Null
    if (Test-Path -LiteralPath $destination) {
        Remove-Item -LiteralPath $destination -Recurse -Force -ErrorAction Stop
    }
    New-Item -ItemType Directory -Path $destination -Force -ErrorAction Stop | Out-Null
    $stagedMsi = Join-Path $destination $vendorFileName
    Copy-Item -LiteralPath $sourceMsi -Destination $stagedMsi -Force -ErrorAction Stop
    Copy-Item -LiteralPath $infoPath -Destination (Join-Path $destination 'CacheInfo.json') -Force -ErrorAction Stop
    if ((Get-FileHash -LiteralPath $stagedMsi -Algorithm SHA256).Hash -ne [string]$info.Sha256) {
        throw 'CMTrace Open staged MSI failed SHA-256 verification.'
    }

    $manifestPath = Join-Path $stage 'DeviceManifest.json'
    $manifest = if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    }
    else {
        [pscustomobject]@{SchemaVersion=1;StagedAt=(Get-Date).ToUniversalTime().ToString('o');Apps=@()}
    }
    $app = [pscustomobject]@{
        Id='CMTraceOpen'; DisplayName='CMTrace Open'; Source='BuiltIn'
        PackageType='App'; Type='VendorMsi'; Vendor='CMTrace Open'
        Version=[string]$info.Version; Architecture=$Architecture
        Package=(Join-Path $relativeRoot $vendorFileName)
        ExpectedSha256=[string]$info.Sha256
        MsiProperties=@(if ($DisableUpdateChecks) { 'DISABLEUPDATECHECKS=1' })
        InstallTimeoutMinutes=$InstallTimeoutMinutes
    }
    $manifest = Set-OSDAppManifestApp -Manifest $manifest -App $app
    $manifest = Set-OSDAppManifestRuntimeConfiguration -Manifest $manifest
    $manifest.StagedAt = (Get-Date).ToUniversalTime().ToString('o')
    $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $manifestPath -Encoding UTF8 -ErrorAction Stop
    Add-OSDAppSetupComplete -WindowsPath $target -StagedRelativePath 'Windows\Temp\OSDApps' -Confirm:$false | Out-Null

    [pscustomobject]@{
        PSTypeName='OSDApps.StagedApp'
        Name='CMTraceOpen'; Version=[string]$info.Version; Source='BuiltIn'
        PackageType='App'; WindowsPath=$target; StagedPath=$destination
    }
}
