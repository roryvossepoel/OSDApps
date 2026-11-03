# Run in WinPE after OSDCloud applies fresh x64 Windows. Never reboots.
[CmdletBinding()]
param(
    [uri]$CatalogUri = 'https://msintune.blob.core.windows.net/osdstage/catalog.json',
    [string]$WindowsPath
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT')) {
    throw 'Run this staging test in WinPE after applying fresh Windows, not in OOBE or on your preparation PC.'
}
if ($env:PROCESSOR_ARCHITECTURE -ne 'AMD64') { throw 'This profile requires x64 WinPE.' }
$root = Split-Path $PSScriptRoot -Parent
$revision = (Get-Content -LiteralPath (Join-Path $root 'TestRevision.txt') -Raw).Trim()
if ($revision -notmatch '^[a-fA-F0-9]{40}$') { throw 'Missing pinned test revision.' }
Remove-Module OSDStage -Force -ErrorAction SilentlyContinue
$module = Import-Module (Join-Path $root 'OSDStage.psd1') -Force -PassThru -Global
$volumes = @(Get-Volume | Where-Object { $_.FileSystemLabel -eq 'OSDCloud' -and $_.DriveLetter })
if ($volumes.Count -ne 1) { throw 'Connect exactly one volume labeled OSDCloud.' }
Set-OSDStageConfiguration -CatalogUri $CatalogUri -CacheVolumeLabel OSDCloud -CleanupMode Never -EnableBuiltIns $true -EnableRepository $true
$target = & $module { param($Path) Resolve-OSDStageWindowsPath -WindowsPath $Path } $WindowsPath
if ([IO.Path]::GetPathRoot($target).TrimEnd('\') -ieq ('{0}:' -f $volumes[0].DriveLetter)) {
    throw 'Windows must not be on the OSDCloud volume.'
}
$stage = Join-Path $target 'Windows\Temp\OSDStage'
if (Test-Path -LiteralPath $stage) { throw 'Existing staging found. Use a fresh Windows deployment; nothing was removed.' }
$packages = @(
    @{Id='OmnissaHorizonClient';Type='App'},
    @{Id='RepoTestFonts';Type='Font'},
    @{Id='RepoTestRootCA';Type='Certificate'},
    @{Id='RepoTestRealtekUSB';Type='Driver'},
    @{Id='RepoTestWiFiProfile';Type='Script'}
)
foreach ($package in $packages) {
    $matches = @(Get-OSDStage -Name $package.Id | Where-Object { $_.Id -eq $package.Id -and $_.Source -eq 'Repository' })
    if ($matches.Count -ne 1 -or $matches[0].PackageType -ne $package.Type) {
        throw ('Missing, ambiguous or incorrect repository package: ' + $package.Id)
    }
}
Sync-OSDStageRepository -Name $packages.Id -Architecture x64 | Out-Null
$cache = @(Get-OSDStageCache -Name $packages.Id)
foreach ($package in $packages) {
    $matches = @($cache | Where-Object { $_.Id -eq $package.Id -and $_.Architecture -in @('x64','any') })
    if ($matches.Count -ne 1 -or -not $matches[0].Valid -or $matches[0].PackageType -ne $package.Type) {
        throw ('Cache hash/type verification failed: ' + $package.Id)
    }
}
$destination = @{WindowsPath=$target}
Add-OSDStage7Zip -Architecture x64 @destination | Out-Null
Add-OSDStageMicrosoft365Apps -Architecture x64 -Channel MonthlyEnterprise -Language 'nl-nl' @destination | Out-Null
Add-OSDStageAdobeAcrobatUnified -Architecture x64 @destination | Out-Null
Add-OSDStageGoogleChromeEnterprise -Architecture x64 @destination | Out-Null
Add-OSDStage -Name @('OmnissaHorizonClient','RepoTestWiFiProfile') -SkipCacheRefresh @destination | Out-Null
Add-OSDStageFont -Id RepoTestFonts -SkipCacheRefresh @destination | Out-Null
Add-OSDStageCertificate -Id RepoTestRootCA -SkipCacheRefresh @destination | Out-Null
Add-OSDStageDriver -Id RepoTestRealtekUSB -SkipCacheRefresh @destination | Out-Null
$key = 'HKLM:\SOFTWARE\OSDStage\Tests\Combined'
foreach ($view in @('Registry64','Registry32')) {
    $viewParameter = @{}; $viewParameter[$view] = $true
    Add-OSDStageRegistryKey -Path "$key\EmptyKey" @viewParameter @destination | Out-Null
    Add-OSDStageRegistryValue -Path $key -Name Marker -Type String -Value $view @viewParameter @destination | Out-Null
    Add-OSDStageRegistryValue -Path $key -Name Number -Type DWord -Value 42 @viewParameter @destination | Out-Null
}
# Seed a dedicated variable through the earlier registry step to test actual removal.
Add-OSDStageRegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' -Name OSDStageMegaRemove -Type String -Value RemoveMe -Registry64 @destination | Out-Null
Add-OSDStageEnvironmentVariable -Name OSDStageMega -Value CombinedTest @destination | Out-Null
Add-OSDStageEnvironmentVariable -Name OSDStageMegaExpanded -Value '%SystemDrive%\OSDStageMega' -ExpandString @destination | Out-Null
Add-OSDStageEnvironmentVariable -AppendPath '%SystemDrive%\OSDStageMega\bin' @destination | Out-Null
Add-OSDStageEnvironmentVariable -Name OSDStageMegaRemove -Remove @destination | Out-Null
Add-OSDStageService -Name WSearch -StartupType Manual -State Stopped @destination | Out-Null
Add-OSDStageService -Name Spooler -StartupType Automatic -State Running @destination | Out-Null
Add-OSDStageWindowsFeature -Enable TelnetClient -Disable WorkFolders-Client @destination | Out-Null
Add-OSDStageWindowsCapability -Name 'XPS.Viewer~~~~0.0.1.0' -Action Add @destination | Out-Null
Add-OSDStageWindowsCapability -Name 'OpenSSH.Client~~~~0.0.1.0' -Action Remove @destination | Out-Null
$settings = @{packagedAppId='windows.immersivecontrolpanel_cw5n1h2txyewy!microsoft.windows.immersivecontrolpanel'}
$explorer = @{desktopAppId='Microsoft.Windows.Explorer'}
Add-OSDStageStartPins -Pins @(@{desktopAppId='MSEdge'},$explorer,$settings) @destination | Out-Null
Add-OSDStageTaskbarPins -Pins @($settings,$explorer) @destination | Out-Null
Add-OSDStageWindowsInboxCleanup -Remove @('Microsoft.MicrosoftSolitaireCollection','Microsoft.BingWeather','Microsoft.BingNews') @destination | Out-Null
Add-OSDStageDefaultAssociation -Identifier '.pdf' -ProgId Acrobat.Document.DC -AppName 'Adobe Acrobat' @destination | Out-Null
Add-OSDStageDefaultAssociation -Identifier @('http','https','.htm','.html') -ProgId ChromeHTML -AppName 'Google Chrome' @destination | Out-Null

Add-OSDStageDirectory -Path 'C:\ProgramData\OSDStageAcceptance' @destination | Out-Null
Add-OSDStageFile -Path 'C:\ProgramData\OSDStageAcceptance\FullReportTest.txt' -Content ('Configuration applied before Windows Update; test revision ' + $revision) @destination | Out-Null
Add-OSDStageWindowsUpdate -IncludeDrivers -TimeoutMinutes 60 @destination | Out-Null
$validation = Test-OSDStageDeployment @destination -ThrowOnFailure
$manifest = Get-Content -LiteralPath (Join-Path $stage 'DeviceManifest.json') -Raw | ConvertFrom-Json
$expected = @($packages.Id) + @('7Zip','Microsoft365Apps','AdobeAcrobatUnified','GoogleChromeEnterprise',
    'RegistrySettings','EnvironmentVariables','Services','WindowsFeatures','WindowsCapabilities',
    'DesktopSettings','WindowsInboxCleanup','DefaultAssociations','FileSystem','WindowsUpdate')
if (@($manifest.Packages).Count -ne $expected.Count -or
    @(Compare-Object ($expected | Sort-Object) (@($manifest.Packages.Id) | Sort-Object)).Count -ne 0 -or
    @($manifest.Packages)[-1].Id -ne 'WindowsUpdate') {
    throw 'Unexpected staging selection/order. Do not restart; inspect DeviceManifest.json.'
}
$recordDirectory = Join-Path $target 'ProgramData\OSDStage\Tests'
New-Item -ItemType Directory -Path $recordDirectory -Force | Out-Null
[ordered]@{
    SchemaVersion=1; Revision=$revision; DeploymentId=$manifest.DeploymentId
    ExpectedIds=$expected; CleanupMode='Never'; NetworkRequired=$validation.NetworkRequired
    CachedPackages=@($cache | Select-Object Id,Version,Architecture,Valid)
    CreatedAtUtc=(Get-Date).ToUniversalTime().ToString('o')
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $recordDirectory 'DeliveryReport-Staging.json') -Encoding UTF8
$validation | Format-List Valid,OfflineReady,NetworkRequired,PackageCount,WindowsPath
Write-Host 'READY: 19 entries staged. Keep USB, power and network connected; restart manually into Windows.' -ForegroundColor Green
Write-Host 'Windows Update includes firmware. This script never requests a restart. Staging is retained for inspection.'
