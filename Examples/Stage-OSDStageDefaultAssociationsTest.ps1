# Run in WinPE after OSDCloud applies a fresh x64 Windows 11 image, before first boot.
# Example ProgIds must match the selected Adobe/Chrome versions; use a reference export.
[CmdletBinding()]
param([string]$XmlPath)
$ErrorActionPreference='Stop'
if (-not (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT')) { throw 'Run this example in WinPE, not on the preparation PC.' }
Set-OSDStageConfiguration -CacheVolumeLabel OSDCloud -CleanupMode Never -EnableBuiltIns $true
# App installation does not request OSDStage defaults. Normal cache rules apply.
# Stage installers before the separately requested association import.
Add-OSDStageAdobeAcrobatUnified -Architecture x64 | Out-Null
Add-OSDStageGoogleChromeEnterprise -Architecture x64 | Out-Null
if ($XmlPath) {
    # Every identifier in the supplied XML is an explicit selection.
    Add-OSDStageDefaultAssociation -XmlPath $XmlPath | Out-Null
} else {
    # Select only PDF for Adobe and the four web identifiers for Chrome.
    # Omit these calls to leave defaults to Windows/vendor registration.
    Add-OSDStageDefaultAssociation -Identifier '.pdf' -ProgId 'Acrobat.Document.DC' -AppName 'Adobe Acrobat' | Out-Null
    Add-OSDStageDefaultAssociation -Identifier @('.htm','.html','http','https') -ProgId 'ChromeHTML' -AppName 'Google Chrome' | Out-Null
}
Test-OSDStageDeployment -RequireOfflineReady -ThrowOnFailure |
    Format-List Valid,OfflineReady,NetworkRequired,PackageCount,WindowsPath
Write-Host 'Associations queued after Adobe/Chrome. Continue the normal Windows/OOBE flow; no extra reboot or follow-up task is added.'
