# Run in WinPE AFTER Deploy-OSDCloud has applied Windows, BEFORE booting Windows.
# Import your test module before this example. No Gallery access or cache reset.
[CmdletBinding()]
param([string]$TimeZoneId='Tokyo Standard Time',[string]$WindowsPath)
$ErrorActionPreference='Stop'
if (-not (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT')) { throw 'Run this example in WinPE, not on the preparation PC.' }
Set-OSDAppConfiguration -CacheVolumeLabel 'OSDCloud' -CleanupMode Never
$target=@{}
if ($WindowsPath) { $target.WindowsPath=$WindowsPath }
Add-OSDAppTimeZone -Id $TimeZoneId @target | Out-Null
Add-OSDAppStartPins -Pins @(
    @{desktopAppId='MSEdge'}
    @{desktopAppId='Microsoft.Windows.Explorer'}
    @{packagedAppId='windows.immersivecontrolpanel_cw5n1h2txyewy!microsoft.windows.immersivecontrolpanel'}
) @target | Out-Null
# Deliberately differs from the Windows default taskbar, including removal of Edge.
Add-OSDAppTaskbarPins -Pins @(
    @{packagedAppId='windows.immersivecontrolpanel_cw5n1h2txyewy!microsoft.windows.immersivecontrolpanel'}
    @{desktopAppId='Microsoft.Windows.Explorer'}
) @target | Out-Null
Test-OSDAppDeployment @target -RequireOfflineReady -ThrowOnFailure |
    Format-List Valid,OfflineReady,NetworkRequired,AppCount,WindowsPath
Write-Host 'Expected: Start Edge/Explorer/Settings; taskbar ONLY Settings/Explorer; time zone Tokyo Standard Time.'
Write-Host 'The time zone result must say Applied with different Before/After values. Unchanged is not a change-path test.'
Write-Host 'Desktop settings prepared. Continue the normal Windows/OOBE flow; no additional reboot or follow-up task is added.'
