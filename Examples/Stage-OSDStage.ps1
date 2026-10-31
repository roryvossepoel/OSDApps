# Run with powershell.exe -NoProfile -File from the launcher's WinPE process.
# Exit 0 permits the launcher to continue; exit 1 must block its reboot path.
$ErrorActionPreference = 'Stop'

try {
    if (-not (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT')) {
        throw 'Run this example in WinPE after Windows has been applied.'
    }

    Install-Module OSDStage -Force -SkipPublisherCheck
    Import-Module OSDStage -Force

    # Edit this queue for your deployment. These three apps default to x64.
    Add-OSDStageMicrosoft365Apps -Channel MonthlyEnterprise -Language en-us | Out-Host
    Add-OSDStageAdobeAcrobatUnified | Out-Host
    Add-OSDStageGoogleChromeEnterprise | Out-Host

    # Add any repository packages above this final check, in the required order.
    $validation = Test-OSDStageDeployment -ThrowOnFailure
    $validation | Select-Object WindowsPath, DeploymentId, PackageCount,
        Valid, OfflineReady, NetworkRequired | Format-List | Out-Host

    Write-Host 'OSDStage staging passed. The launcher may continue to its reboot step.'
    exit 0
}
catch {
    Write-Error "OSDStage staging failed. Do not reboot: $($_.Exception.Message)" -ErrorAction Continue
    exit 1
}
