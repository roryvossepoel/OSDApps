# Full Windows: Prepare. WinPE after OSDCloud: Stage. Never reboots the device.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Prepare','Stage')][string]$Phase,
    [Parameter(Mandatory)][uri]$CatalogUri,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$AppId,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ScriptId,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$FontId,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$CertificateId,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$DriverId,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$WiFiProfilePath,
    [string]$WindowsPath
)
$ErrorActionPreference = 'Stop'
$isWinPE = Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT'
if ($Phase -eq 'Stage' -and -not $isWinPE) { throw 'Run Stage in WinPE after applying fresh Windows.' }
if ($Phase -eq 'Prepare' -and $isWinPE) { throw 'Run Prepare on the full Windows preparation PC.' }
if ($env:PROCESSOR_ARCHITECTURE -ne 'AMD64') { throw 'This combined test profile requires x64 Windows/WinPE.' }
if ($CatalogUri.Scheme -notin @('https','http')) { throw 'CatalogUri must use HTTP or HTTPS.' }
$packages = @(
    @{Id=$AppId;Type='App'}, @{Id=$ScriptId;Type='Script'}, @{Id=$FontId;Type='Font'},
    @{Id=$CertificateId;Type='Certificate'}, @{Id=$DriverId;Type='Driver'}
)
if (@($packages.Id | Sort-Object -Unique).Count -ne 5) { throw 'Select five distinct repository package IDs.' }
foreach ($package in $packages) {
    if ($package.Id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or $package.Id.Contains('..')) {
        throw 'Replace all example package IDs with valid IDs from your repository.'
    }
}
$volumes = @(Get-Volume | Where-Object { $_.FileSystemLabel -eq 'OSDCloud' -and $_.DriveLetter })
if ($volumes.Count -ne 1) { throw 'Expected exactly one mounted volume labeled OSDCloud.' }
$root = Split-Path $PSScriptRoot -Parent
$revisionFile = Join-Path $root 'TestRevision.txt'
if (-not (Test-Path -LiteralPath $revisionFile)) { throw 'Use Prepare-OSDAppsCombinedTest.ps1 to create a pinned test module first.' }
$revision = (Get-Content -LiteralPath $revisionFile -Raw).Trim()
if ($revision -notmatch '^[a-fA-F0-9]{40}$') { throw 'Invalid test revision marker.' }
Remove-Module OSDApps -Force -ErrorAction SilentlyContinue
$module = Import-Module (Join-Path $root 'OSDApps.psd1') -Force -PassThru -Global
Set-OSDAppConfiguration -CatalogUri $CatalogUri -CacheVolumeLabel OSDCloud -CleanupMode OnSuccess -EnableBuiltIns $true -EnableRepository $true
# Validate XML privately; never emit the returned profile or include it in test evidence.
& $module { param($Path) $null = Read-OSDAppWiFiProfile -LiteralPath $Path } $WiFiProfilePath
if ($Phase -eq 'Prepare') {
    # Validate selections before downloads. Preserve valid packages that exist only in cache.
    $onlineIds = [System.Collections.Generic.List[string]]::new()
    foreach ($package in $packages) {
        $candidates = @(Get-OSDApp -Name $package.Id | Where-Object { $_.Source -eq 'Repository' -and $_.Id -eq $package.Id })
        if ($candidates.Count -ne 1 -or $candidates[0].PackageType -ne $package.Type) {
            throw ('Repository selection must resolve to one {0}: {1}' -f $package.Type,$package.Id)
        }
        if ($candidates[0].Availability -in @('Cached','Online')) {
            $onlineIds.Add([string]$package.Id)
        }
        elseif ($candidates[0].Availability -ne 'CachedOnly' -or -not $candidates[0].Valid) {
            throw ('Repository selection is unavailable or its cache is invalid: ' + $package.Id)
        }
    }
    if ($onlineIds.Count -gt 0) {
        Sync-OSDAppRepository -Name $onlineIds.ToArray() -Architecture x64 | Out-Null
    }
    Sync-OSDAppGoogleChromeEnterprise -Architecture x64 | Out-Null
    Sync-OSDAppAdobeAcrobatUnified -Architecture x64 | Out-Null
}
# Check payload hashes for every selected package before the first staging operation.
$expectedCache = @($packages) + @(@{Id='GoogleChromeEnterprise';Type='App'},@{Id='AdobeAcrobatUnified';Type='App'})
$cache = @(Get-OSDAppCache -Name $expectedCache.Id)
foreach ($package in $expectedCache) {
    $candidates = @($cache | Where-Object { $_.Id -eq $package.Id -and $_.Architecture -in @('x64','any') })
    if ($candidates.Count -ne 1 -or -not $candidates[0].Valid -or $candidates[0].PackageType -ne $package.Type) {
        throw ('Missing, invalid or ambiguous cached package: {0}. Run Prepare first.' -f $package.Id)
    }
}
if ($Phase -eq 'Prepare') {
    $cache | Select-Object Id,PackageType,Architecture,Version,Valid
    Write-Host 'Preparation passed. Run this same revision and selections with -Phase Stage in WinPE.'
    return
}
$target = & $module { param($Path) Resolve-OSDAppWindowsPath -WindowsPath $Path } $WindowsPath
if ([IO.Path]::GetPathRoot($target).TrimEnd('\') -ieq ('{0}:' -f $volumes[0].DriveLetter)) {
    throw 'Offline Windows must not be on the OSDCloud cache volume.'
}
$stage = Join-Path $target 'Windows\Temp\OSDApps'
if (Test-Path -LiteralPath $stage) { throw 'Existing staging found. Use a fresh deployment; this test does not remove or merge it.' }
$destination = @{WindowsPath=$target}
# All app installers precede association import. Select a harmless repository script.
Add-OSDApp -Name @($AppId,$ScriptId) -SkipCacheRefresh @destination | Out-Null
Add-OSDAppAdobeAcrobatUnified -Architecture x64 @destination | Out-Null
Add-OSDAppGoogleChromeEnterprise -Architecture x64 @destination | Out-Null
Add-OSDAppFont -Id $FontId -SkipCacheRefresh @destination | Out-Null
Add-OSDAppCertificate -Id $CertificateId -SkipCacheRefresh @destination | Out-Null
Add-OSDAppDriver -Id $DriverId -SkipCacheRefresh @destination | Out-Null
$key = 'HKLM:\SOFTWARE\OSDApps\Tests\Combined'
foreach ($view in @('Registry64','Registry32')) {
    $viewParameter = @{}; $viewParameter[$view] = $true
    Add-OSDAppRegistryKey -Path "$key\EmptyKey" @viewParameter @destination | Out-Null
    Add-OSDAppRegistryValue -Path $key -Name Marker -Type String -Value $view @viewParameter @destination | Out-Null
    Add-OSDAppRegistryValue -Path $key -Name Number -Type DWord -Value 42 @viewParameter @destination | Out-Null
}
# Seed a dedicated variable through the earlier registry step to test actual removal.
Add-OSDAppRegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' -Name OSDAppsMegaRemove -Type String -Value RemoveMe -Registry64 @destination | Out-Null
Add-OSDAppEnvironmentVariable -Name OSDAppsMega -Value CombinedTest @destination | Out-Null
Add-OSDAppEnvironmentVariable -Name OSDAppsMegaExpanded -Value '%SystemDrive%\OSDAppsMega' -ExpandString @destination | Out-Null
Add-OSDAppEnvironmentVariable -AppendPath '%SystemDrive%\OSDAppsMega\bin' @destination | Out-Null
Add-OSDAppEnvironmentVariable -Name OSDAppsMegaRemove -Remove @destination | Out-Null
Add-OSDAppService -Name WSearch -StartupType Manual -State Stopped @destination | Out-Null
Add-OSDAppService -Name Spooler -StartupType Automatic -State Running @destination | Out-Null
Add-OSDAppWindowsFeature -Enable TelnetClient -Disable WorkFolders-Client @destination | Out-Null
Add-OSDAppWindowsCapability -Name 'XPS.Viewer~~~~0.0.1.0' -Action Add @destination | Out-Null
Add-OSDAppWindowsCapability -Name 'OpenSSH.Client~~~~0.0.1.0' -Action Remove @destination | Out-Null
Add-OSDAppWiFiProfile -Path $WiFiProfilePath @destination | Out-Null
$settings = @{packagedAppId='windows.immersivecontrolpanel_cw5n1h2txyewy!microsoft.windows.immersivecontrolpanel'}
$explorer = @{desktopAppId='Microsoft.Windows.Explorer'}
Add-OSDAppStartPins -Pins @(@{desktopAppId='MSEdge'},$explorer,$settings) @destination | Out-Null
Add-OSDAppTaskbarPins -Pins @($settings,$explorer) @destination | Out-Null
Add-OSDAppWindowsInboxCleanup -Remove @('Microsoft.MicrosoftSolitaireCollection','Microsoft.BingWeather','Microsoft.BingNews') @destination | Out-Null
Add-OSDAppDefaultAssociation -Identifier '.pdf' -ProgId Acrobat.Document.DC -AppName 'Adobe Acrobat' @destination | Out-Null
Add-OSDAppDefaultAssociation -Identifier @('http','https','.htm','.html') -ProgId ChromeHTML -AppName 'Google Chrome' @destination | Out-Null
# Capability Add needs Windows Update in SetupComplete; offline readiness is not required.
$validation = Test-OSDAppDeployment @destination -ThrowOnFailure
$manifest = Get-Content -LiteralPath (Join-Path $stage 'DeviceManifest.json') -Raw | ConvertFrom-Json
$expected = @($expectedCache.Id) + @('RegistrySettings','EnvironmentVariables','Services','WindowsFeatures','WindowsCapabilities','WiFiProfiles','DesktopSettings','WindowsInboxCleanup','DefaultAssociations')
if (@($manifest.Apps).Count -ne $expected.Count -or @(Compare-Object ($expected | Sort-Object) (@($manifest.Apps.Id) | Sort-Object)).Count -ne 0) {
    throw 'Staged entries do not match the combined test selections. Do not continue to Windows.'
}
$record = [ordered]@{
    SchemaVersion=1; Revision=$revision; DeploymentId=$manifest.DeploymentId
    ExpectedIds=$expected; CleanupMode='OnSuccess'; NetworkRequired=$validation.NetworkRequired
    CachedPackages=@($cache | Select-Object Id,Version,Architecture)
    CreatedAt=(Get-Date).ToUniversalTime().ToString('o')
}
$recordDirectory = Join-Path $target 'ProgramData\OSDApps\Tests'
New-Item -ItemType Directory -Path $recordDirectory -Force | Out-Null
$record | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $recordDirectory 'Combined-Staging.json') -Encoding UTF8
$validation | Format-List Valid,OfflineReady,NetworkRequired,AppCount,WindowsPath
Write-Host 'Combined test staged. Keep network available and continue the normal Windows/OOBE flow.'
