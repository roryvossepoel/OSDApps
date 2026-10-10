$moduleRoot = $PSScriptRoot

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
    'Show-OSDAppUI',
    'Sync-OSDAppRepository',
    'Sync-OSDAppMicrosoft365Apps',
    'Sync-OSDAppMicrosoftTeams',
    'Sync-OSDAppAdobeAcrobatUnified',
    'Sync-OSDAppGoogleChromeEnterprise',
    'Sync-OSDAppCiscoWebex',
    'Sync-OSDAppMozillaFirefoxEnterprise',
    'Clear-OSDAppCache',
    'Add-OSDApp',
    'Add-OSDAppMicrosoft365Apps',
    'Add-OSDAppMicrosoftTeams',
    'Add-OSDAppAdobeAcrobatUnified',
    'Add-OSDAppGoogleChromeEnterprise',
    'Add-OSDAppCiscoWebex',
    'Add-OSDAppMozillaFirefoxEnterprise',
    'New-OSDAppRepository',
    'New-OSDAppPackage',
    'Add-OSDAppPackage',
    'Test-OSDAppPackage',
    'Test-OSDAppRepository'
)
