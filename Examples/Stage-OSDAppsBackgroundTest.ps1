# Run in WinPE after OSDCloud applies a fresh Windows 11 Pro/Enterprise/Education image. Pro lock screen support is advisory.
[CmdletBinding()]
param([string]$WindowsPath,[switch]$EnforceWallpaper,[switch]$EnforceLockScreen)
$ErrorActionPreference='Stop'
if (-not (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT')) { throw 'Run this example in WinPE, not on the preparation PC.' }
Set-OSDAppConfiguration -CacheVolumeLabel 'OSDCloud' -EnableBuiltIns $true -EnableRepository $true -CleanupMode Never
$target=@{};if ($WindowsPath) { $target.WindowsPath=$WindowsPath }
Add-OSDAppWallpaper -Id OSDAppsTestWallpaper -SkipCacheRefresh -Enforce:$EnforceWallpaper @target | Out-Null
Add-OSDAppLockScreen -Id OSDAppsTestLockScreen -SkipCacheRefresh -Enforce:$EnforceLockScreen @target | Out-Null
Test-OSDAppDeployment @target -RequireOfflineReady -ThrowOnFailure | Format-List Valid,OfflineReady,NetworkRequired,AppCount,WindowsPath
Write-Host ('Expected wallpaper: green labeled test image; enforced: '+[bool]$EnforceWallpaper)
Write-Host ('Expected lock screen: blue labeled test image; enforced: '+[bool]$EnforceLockScreen)
Write-Host 'Continue the normal Windows/OOBE flow. No extra reboot, verification task or correction task is installed.'
