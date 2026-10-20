@{
    RootModule        = 'OSDApps.psm1'
    ModuleVersion     = '0.46.0'
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
        'Sync-OSDAppMicrosoft365Apps',
        'Sync-OSDAppMicrosoftTeams',
        'Sync-OSDAppAdobeAcrobatUnified',
        'Sync-OSDAppGoogleChromeEnterprise',
        'Sync-OSDAppCiscoWebex',
        'Sync-OSDAppZoomWorkplace',
        'Sync-OSDAppMozillaFirefoxEnterprise',
        'Clear-OSDAppCache',
        'Add-OSDApp',
        'Add-OSDAppMicrosoft365Apps',
        'Add-OSDAppMicrosoftTeams',
        'Add-OSDAppAdobeAcrobatUnified',
        'Add-OSDAppGoogleChromeEnterprise',
        'Add-OSDAppCiscoWebex',
        'Add-OSDAppZoomWorkplace',
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
            ReleaseNotes = '0.46.0: Prevent automatic idle sleep during PreInstall and application installation with temporary Windows power requests. Enabled by default; use Set-OSDAppConfiguration -PreventSleep $false to opt out before staging. Requests are released on completion, failure or process termination without changing power plans. Validated on Windows PowerShell 5.1 and PowerShell 7 and in a physical WinPE-to-OOBE deployment.'
            RequireLicenseAcceptance = $false
        }
    }
}
