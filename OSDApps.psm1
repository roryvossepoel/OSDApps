$moduleRoot = $PSScriptRoot
. (Join-Path $moduleRoot 'Runtime\OSDAppPayloadFile.ps1')
. (Join-Path $moduleRoot 'Runtime\OSDApp7Zip.ps1')
. (Join-Path $moduleRoot 'Runtime\OSDAppVisualStudioCode.ps1')
. (Join-Path $moduleRoot 'Runtime\OSDAppPrerequisite.ps1')
. (Join-Path $moduleRoot 'Runtime\Enter-OSDAppCacheLock.ps1')
. (Join-Path $moduleRoot 'Runtime\Assert-OSDAppTransactionSpace.ps1')
. (Join-Path $moduleRoot 'Runtime\Restore-OSDAppCacheGeneration.ps1')

. (Join-Path $moduleRoot 'Runtime\Test-OSDAppOfficeCacheCompatibility.ps1')

foreach ($folder in @('Private','Public')) {
    $path = Join-Path $moduleRoot $folder
    if (Test-Path $path) {
        Get-ChildItem -Path $path -Filter '*.ps1' -File |
            Sort-Object Name |
            ForEach-Object { . $_.FullName }
    }
}

Export-ModuleMember -Function @(
    'Set-OSDAppConfiguration',
    'Get-OSDAppConfiguration',
    'Get-OSDAppCatalog',
    'Get-OSDApp',
    'Get-OSDAppCache',
    'Get-OSDAppCacheHealth',
    'Get-OSDAppDeploymentResult',
    'Test-OSDAppCache',
    'Test-OSDAppDeployment',
    'Show-OSDAppUI',
    'Remove-OSDAppStaging',
    'Sync-OSDAppRepository',
    'Sync-OSDAppCMTraceOpen',
    'Sync-OSDAppMicrosoft365Apps',
    'Sync-OSDAppMicrosoftTeams',
    'Sync-OSDAppAdobeAcrobatUnified',
    'Sync-OSDAppGoogleChromeEnterprise',
    'Sync-OSDAppCiscoWebex',
    'Sync-OSDAppZoomWorkplace',
    'Sync-OSDApp7Zip',
    'Sync-OSDAppVisualStudioCode',
    'Sync-OSDAppVisualCRedist',
    'Sync-OSDAppDotNetRuntime',
    'Sync-OSDAppMozillaFirefoxEnterprise',
    'Clear-OSDAppCache',
    'Add-OSDApp',
    'Add-OSDAppWindowsInboxCleanup',
    'Add-OSDAppCMTraceOpen',
    'Add-OSDAppMicrosoft365Apps',
    'Add-OSDAppMicrosoftTeams',
    'Add-OSDAppAdobeAcrobatUnified',
    'Add-OSDAppGoogleChromeEnterprise',
    'Add-OSDAppCiscoWebex',
    'Add-OSDAppZoomWorkplace',
    'Add-OSDApp7Zip',
    'Add-OSDAppVisualStudioCode',
    'Add-OSDAppVisualCRedist',
    'Add-OSDAppDotNetRuntime',
    'Add-OSDAppMozillaFirefoxEnterprise',
    'New-OSDAppRepository',
    'New-OSDAppPackage',
    'Add-OSDAppPackage',
    'Test-OSDAppPackage',
    'Test-OSDAppRepository'
)
