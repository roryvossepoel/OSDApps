@{
    RootModule        = 'OSDApps.psm1'
    ModuleVersion     = '0.51.0'
    GUID              = 'efc06c0c-6a69-4c21-8f34-2f539a7d5409'
    Author            = 'Rory Vossepoel'
    Copyright         = '(c) 2026 Rory Vossepoel. Licensed under the MIT License.'
    Description       = 'Your apps. Ready before OOBE. Stage apps and PowerShell scripts in WinPE after OSDCloud applies Windows, using built-in integrations or your own repository and optional USB flash drive caching.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
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
        'Sync-OSDAppMicrosoftCompanyPortal',
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
        'Add-OSDAppFont',
        'Add-OSDAppDriver',
        'Add-OSDAppRegistryKey',
    'Add-OSDAppRegistryValue',
    'Add-OSDAppWindowsFeature',
    'Add-OSDAppEnvironmentVariable',
    'Add-OSDAppService',
    'Add-OSDAppTimeZone',
    'Add-OSDAppStartPins',
    'Add-OSDAppTaskbarPins',
    'Add-OSDAppWiFiProfile',
    'Add-OSDAppCertificate',
    'Add-OSDAppWindowsInboxCleanup',
        'Add-OSDAppCMTraceOpen',
        'Add-OSDAppMicrosoftCompanyPortal',
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
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData = @{
        PSData = @{
            Tags = @('PowerShell','OSDCloud','OSDCloudV2','WinPE','WindowsDeployment','AppDeployment','AppDeployment','ScriptDeployment','OOBE','Autopilot','SetupComplete','OfflineCache','AppCache','AppPackaging','Repository')
            ProjectUri = 'https://github.com/roryvossepoel/OSDApps'
            LicenseUri = 'https://github.com/roryvossepoel/OSDApps/blob/main/LICENSE'
            ReleaseNotes = '0.51.0: Add Microsoft Company Portal offline provisioning with automatic download from the official Microsoft Download Center and optional manual Preinstall Kit; add CMTrace Open with upstream MSI SHA-256 and Authenticode verification and original vendor filenames. Validated x64 WinPE to SetupComplete deployment (4/4 succeeded) and direct Microsoft download on Windows.'
            RequireLicenseAcceptance = $false
        }
    }
}
