# Import the test module, then run in WinPE after OSDCloud applies fresh Windows 11 25H2+.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
if (-not (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT')) {
    throw 'Run this example in WinPE, not on the preparation PC.'
}
Set-OSDAppConfiguration -CacheVolumeLabel OSDCloud -CleanupMode Never -EnableBuiltIns $true
Add-OSDAppWindowsCapability -Name 'XPS.Viewer~~~~0.0.1.0' -Action Add | Out-Null
Add-OSDAppWindowsCapability -Name 'OpenSSH.Client~~~~0.0.1.0' -Action Remove | Out-Null
# Add can require a Windows Update download; do not require offline readiness.
Test-OSDAppDeployment -ThrowOnFailure |
    Format-List Valid,OfflineReady,NetworkRequired,AppCount,WindowsPath
Write-Host 'Expected: XPS NotPresent -> Installed; OpenSSH Client Installed -> NotPresent.'
Write-Host 'Keep network available during SetupComplete. Continue normal Windows/OOBE; no additional reboot or follow-up task is added.'
