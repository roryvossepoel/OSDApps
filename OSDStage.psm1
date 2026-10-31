$moduleRoot = $PSScriptRoot
. (Join-Path $moduleRoot 'Runtime\Invoke-OSDStageWindowsCapabilities.ps1')
. (Join-Path $moduleRoot 'Runtime\Invoke-OSDStageDefaultAssociations.ps1')
. (Join-Path $moduleRoot 'Runtime\Invoke-OSDStageDesktopSettings.ps1')
. (Join-Path $moduleRoot 'Runtime\Invoke-OSDStageServices.ps1')
. (Join-Path $moduleRoot 'Runtime\Invoke-OSDStageEnvironmentVariables.ps1')
. (Join-Path $moduleRoot 'Runtime\OSDStageDriver.ps1')
. (Join-Path $moduleRoot 'Runtime\OSDStageCertificate.ps1')
. (Join-Path $moduleRoot 'Runtime\OSDStagePayloadFile.ps1')
. (Join-Path $moduleRoot 'Runtime\OSDStage7Zip.ps1')
. (Join-Path $moduleRoot 'Runtime\OSDStageVisualStudioCode.ps1')
. (Join-Path $moduleRoot 'Runtime\OSDStagePrerequisite.ps1')
. (Join-Path $moduleRoot 'Runtime\Enter-OSDStageCacheLock.ps1')
. (Join-Path $moduleRoot 'Runtime\Assert-OSDStageTransactionSpace.ps1')
. (Join-Path $moduleRoot 'Runtime\Restore-OSDStageCacheGeneration.ps1')

. (Join-Path $moduleRoot 'Runtime\Test-OSDStageOfficeCacheCompatibility.ps1')

foreach ($folder in @('Private','Public')) {
    $path = Join-Path $moduleRoot $folder
    if (Test-Path $path) {
        Get-ChildItem -Path $path -Filter '*.ps1' -File |
            Sort-Object Name |
            ForEach-Object { . $_.FullName }
    }
}

Export-ModuleMember -Function @(
    'Set-OSDStageConfiguration',
    'Get-OSDStageConfiguration',
    'Get-OSDStageCatalog',
    'Get-OSDStage',
    'Get-OSDStageCache',
    'Get-OSDStageCacheHealth',
    'Get-OSDStageDeploymentResult',
    'Test-OSDStageCache',
    'Test-OSDStageDeployment',
    'Show-OSDStageUI',
    'Remove-OSDStageStaging',
    'Sync-OSDStageRepository',
    'Sync-OSDStageCMTraceOpen',
    'Sync-OSDStageMicrosoftCompanyPortal',
    'Sync-OSDStageMicrosoft365Apps',
    'Sync-OSDStageMicrosoftTeams',
    'Sync-OSDStageAdobeAcrobatUnified',
    'Sync-OSDStageGoogleChromeEnterprise',
    'Sync-OSDStageCiscoWebex',
    'Sync-OSDStageZoomWorkplace',
    'Sync-OSDStage7Zip',
    'Sync-OSDStageVisualStudioCode',
    'Sync-OSDStageVisualCRedist',
    'Sync-OSDStageDotNetRuntime',
    'Sync-OSDStageMozillaFirefoxEnterprise',
    'Clear-OSDStageCache',
    'Add-OSDStage',
    'Add-OSDStageFont',
        'Add-OSDStageDriver',
    'Add-OSDStageRegistryKey',
    'Add-OSDStageRegistryValue',
    'Add-OSDStageWindowsFeature',
    'Add-OSDStageWindowsCapability',
    'Add-OSDStageDefaultAssociation',
    'Add-OSDStageEnvironmentVariable',
    'Add-OSDStageService',
    'Add-OSDStageStartPins',
    'Add-OSDStageTaskbarPins',
    'Add-OSDStageWiFiProfile',
    'Add-OSDStageCertificate',
    'Add-OSDStageWindowsInboxCleanup',
    'Add-OSDStageCMTraceOpen',
    'Add-OSDStageMicrosoftCompanyPortal',
    'Add-OSDStageMicrosoft365Apps',
    'Add-OSDStageMicrosoftTeams',
    'Add-OSDStageAdobeAcrobatUnified',
    'Add-OSDStageGoogleChromeEnterprise',
    'Add-OSDStageCiscoWebex',
    'Add-OSDStageZoomWorkplace',
    'Add-OSDStage7Zip',
    'Add-OSDStageVisualStudioCode',
    'Add-OSDStageVisualCRedist',
    'Add-OSDStageDotNetRuntime',
    'Add-OSDStageMozillaFirefoxEnterprise',
    'New-OSDStageRepository',
    'New-OSDStagePackage',
    'Add-OSDStagePackage',
    'Test-OSDStagePackage',
    'Test-OSDStageRepository'
)
