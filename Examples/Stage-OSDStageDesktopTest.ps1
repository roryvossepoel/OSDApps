# Run in WinPE AFTER Deploy-OSDCloud has applied Windows, BEFORE booting Windows.
# Import your test module before this example. No Gallery access or cache reset.
[CmdletBinding()]
param([string]$WindowsPath)
$ErrorActionPreference='Stop'
if (-not (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT')) { throw 'Run this example in WinPE, not on the preparation PC.' }
Set-OSDStageConfiguration -CacheVolumeLabel 'OSDCloud' -CleanupMode Never
$target=@{}
if ($WindowsPath) { $target.WindowsPath=$WindowsPath }
Add-OSDStageStartPins -Pins @(
    @{desktopAppId='MSEdge'}
    @{desktopAppId='Microsoft.Windows.Explorer'}
    @{packagedAppId='windows.immersivecontrolpanel_cw5n1h2txyewy!microsoft.windows.immersivecontrolpanel'}
) @target | Out-Null
# Deliberately differs from the Windows default taskbar, including removal of Edge.
Add-OSDStageTaskbarPins -Pins @(
    @{packagedAppId='windows.immersivecontrolpanel_cw5n1h2txyewy!microsoft.windows.immersivecontrolpanel'}
    @{desktopAppId='Microsoft.Windows.Explorer'}
) @target | Out-Null
Test-OSDStageDeployment @target -RequireOfflineReady -ThrowOnFailure |
    Format-List Valid,OfflineReady,NetworkRequired,PackageCount,WindowsPath
Write-Host 'Expected: Start Edge/Explorer/Settings; taskbar ONLY Settings/Explorer.'
Write-Host 'Desktop settings prepared. Continue the normal Windows/OOBE flow; no additional reboot or follow-up task is added.'
