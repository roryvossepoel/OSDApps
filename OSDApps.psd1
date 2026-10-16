@{
    RootModule        = 'OSDApps.psm1'
    ModuleVersion     = '0.43.0'
    GUID              = 'efc06c0c-6a69-4c21-8f34-2f539a7d5409'
    Author            = 'Rory Vossepoel'
    Copyright         = '(c) 2026 Rory Vossepoel. Licensed under the MIT License.'
    Description       = 'Deploy apps and PowerShell scripts with OSDCloud v2 before the first sign-in. Stage in WinPE, run through SetupComplete, and reuse a validated USB cache. Includes vendor-native apps and support for your own repository packages.'
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
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData = @{
        PSData = @{
            Tags = @('PowerShell','OSDCloud','OSDCloudV2','WinPE','WindowsDeployment','ApplicationDeployment','AppDeployment','ScriptDeployment','OOBE','Autopilot','SetupComplete','OfflineCache','ApplicationCache','ApplicationPackaging','Repository')
            ProjectUri = 'https://github.com/roryvossepoel/OSDApps'
            LicenseUri = 'https://github.com/roryvossepoel/OSDApps/blob/main/LICENSE'
            ReleaseNotes = '0.43.0: Select x64 or arm64 repository variants explicitly during cache synchronization and desired-state health checks. Keep host-architecture defaults, neutral-package fallback and transactional replacement. Clarify acquisition outcomes in getting-started examples.'
            RequireLicenseAcceptance = $false
        }
    }
}
