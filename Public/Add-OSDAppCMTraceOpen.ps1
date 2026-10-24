function Add-OSDAppCMTraceOpen {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateSet('x64','arm64')][string]$Architecture='x64',
        [bool]$DisableUpdateChecks=$true,
        [ValidateRange(1,120)][int]$InstallTimeoutMinutes=10,
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
    if ([string]$info.Version -notmatch '^\d+\.\d+\.\d+
    if ($info.Id -ne 'CMTraceOpen' -or $info.Architecture -ne $Architecture -or
        [string]$info.Sha256 -notmatch '^[a-fA-F0-9]{64}$' -or
        (Get-FileHash -LiteralPath $msi -Algorithm SHA256).Hash -ne $info.Sha256) {
        throw 'CMTrace Open cache SHA-256 validation failed.'
    }
    # WinPE does not guarantee a complete WinTrust/Authenticode trust environment.
    # The full-Windows Sync command verifies the publisher signature and official
    # GitHub release SHA-256 before recording cache metadata. In WinPE, require
    # that same cached hash; SetupComplete independently rechecks Authenticode.
    if (-not (Test-OSDAppWinPE)) {
        $signature = Get-AuthenticodeSignature -FilePath $msi
        if ($signature.Status -ne 'Valid') {
            throw ('Invalid CMTrace Open MSI signature: {0}.' -f $signature.Status)
        }
    }

    $stage = Join-Path $target 'Windows\Temp\OSDApps'
    $rel = 'BuiltIn\CMTraceOpen\' + $Architecture
    $destination = Join-Path $stage $rel
    if (-not $PSCmdlet.ShouldProcess($destination, 'Stage CMTrace Open MSI for SetupComplete')) { return }
    New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
    if (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination -Recurse -Force }
    Copy-Item -LiteralPath $source -Destination $destination -Recurse -Force -ErrorAction Stop
    if ((Split-Path -Path $msi -Leaf) -eq 'Package.msi') {
        # Restore vendor filename in Windows staging; never mutate USB in WinPE.
        Rename-Item -LiteralPath (Join-Path $destination 'Package.msi') -NewName $vendorName -ErrorAction Stop
    }
    $stagedMsi = Join-Path $destination $vendorName
    if ((Get-FileHash -LiteralPath $stagedMsi -Algorithm SHA256).Hash -ne [string]$info.Sha256) {
        throw 'CMTrace Open staged MSI hash mismatch.'
    }

    $manifestPath = Join-Path $stage 'DeviceManifest.json'
    $manifest = if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    } else {
        [pscustomobject]@{SchemaVersion=1;StagedAt=(Get-Date).ToUniversalTime().ToString('o');Apps=@()}
    }
    $app = [pscustomobject]@{
        Id='CMTraceOpen';DisplayName='CMTrace Open';Source='BuiltIn'
        PackageType='Application';Type='VendorMsi';Vendor='CMTrace Open'
        Version=[string]$info.Version;Architecture=$Architecture
        Package=(Join-Path $rel $vendorName)
        ExpectedSha256=[string]$info.Sha256
        MsiProperties=@(if ($DisableUpdateChecks) { 'DISABLEUPDATECHECKS=1' })
        InstallTimeoutMinutes=$InstallTimeoutMinutes
    }
    $manifest = Set-OSDAppManifestApp -Manifest $manifest -App $app
    $manifest = Set-OSDAppManifestRuntimeConfiguration -Manifest $manifest
    $manifest.StagedAt = (Get-Date).ToUniversalTime().ToString('o')
    $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    Add-OSDAppSetupComplete -WindowsPath $target -StagedRelativePath 'Windows\Temp\OSDApps' -Confirm:$false | Out-Null
    [pscustomobject]@{Name='CMTraceOpen';Version=[string]$info.Version;Source='BuiltIn';PackageType='Application';WindowsPath=$target}
}
) {
        throw 'Unexpected CMTrace Open cached version.'
    }
    $vendorName = 'CMTrace-Open_{0}_{1}.msi' -f $info.Version,$Architecture
    if ([string]$info.AssetName -cne $vendorName) {
        throw 'CMTrace Open cache filename differs from the official release asset.'
    }
    $msi = Join-Path $source $vendorName
    $legacyMsi = Join-Path $source 'Package.msi'
    if (-not (Test-Path -LiteralPath $msi -PathType Leaf) -and
        (Test-Path -LiteralPath $legacyMsi -PathType Leaf)) {
        # Previously verified cache: keep it usable without downloading again.
        $msi = $legacyMsi
    }
    if (-not (Test-Path -LiteralPath $msi -PathType Leaf)) {
        throw 'CMTrace Open MSI is missing from the verified USB cache.'
    }
    if ($info.Id -ne 'CMTraceOpen' -or $info.Architecture -ne $Architecture -or
        [string]$info.Sha256 -notmatch '^[a-fA-F0-9]{64}$' -or
        (Get-FileHash -LiteralPath $msi -Algorithm SHA256).Hash -ne $info.Sha256) {
        throw 'CMTrace Open cache SHA-256 validation failed.'
    }
    # WinPE does not guarantee a complete WinTrust/Authenticode trust environment.
    # The full-Windows Sync command verifies the publisher signature and official
    # GitHub release SHA-256 before recording cache metadata. In WinPE, require
    # that same cached hash; SetupComplete independently rechecks Authenticode.
    if (-not (Test-OSDAppWinPE)) {
        $signature = Get-AuthenticodeSignature -FilePath $msi
        if ($signature.Status -ne 'Valid') {
            throw ('Invalid CMTrace Open MSI signature: {0}.' -f $signature.Status)
        }
    }

    $stage = Join-Path $target 'Windows\Temp\OSDApps'
    $rel = 'BuiltIn\CMTraceOpen\' + $Architecture
    $destination = Join-Path $stage $rel
    if (-not $PSCmdlet.ShouldProcess($destination, 'Stage CMTrace Open MSI for SetupComplete')) { return }
    New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
    if (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination -Recurse -Force }
    Copy-Item -LiteralPath $source -Destination $destination -Recurse -Force -ErrorAction Stop

    $manifestPath = Join-Path $stage 'DeviceManifest.json'
    $manifest = if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    } else {
        [pscustomobject]@{SchemaVersion=1;StagedAt=(Get-Date).ToUniversalTime().ToString('o');Apps=@()}
    }
    $app = [pscustomobject]@{
        Id='CMTraceOpen';DisplayName='CMTrace Open';Source='BuiltIn'
        PackageType='Application';Type='VendorMsi';Vendor='CMTrace Open'
        Version=[string]$info.Version;Architecture=$Architecture
        Package=(Join-Path $rel 'Package.msi')
        ExpectedSha256=[string]$info.Sha256
        MsiProperties=@(if ($DisableUpdateChecks) { 'DISABLEUPDATECHECKS=1' })
        InstallTimeoutMinutes=$InstallTimeoutMinutes
    }
    $manifest = Set-OSDAppManifestApp -Manifest $manifest -App $app
    $manifest = Set-OSDAppManifestRuntimeConfiguration -Manifest $manifest
    $manifest.StagedAt = (Get-Date).ToUniversalTime().ToString('o')
    $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    Add-OSDAppSetupComplete -WindowsPath $target -StagedRelativePath 'Windows\Temp\OSDApps' -Confirm:$false | Out-Null
    [pscustomobject]@{Name='CMTraceOpen';Version=[string]$info.Version;Source='BuiltIn';PackageType='Application';WindowsPath=$target}
}
