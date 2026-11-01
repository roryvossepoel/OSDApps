@{
    RootModule        = 'OSDStage.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'e06a7e0b-f50e-4cd9-821c-97723b3f1730'
    Author            = 'Rory Vossepoel'
    Copyright         = '(c) 2026 Rory Vossepoel. Licensed under the MIT License.'
    Description       = 'Stage software and device configuration before OOBE, with built-in integrations, repository packages and optional OSDCloud USB caching.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
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
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData = @{
        PSData = @{
            Tags = @('PowerShell','OSDCloud','OSDCloudV2','WinPE','WindowsDeployment','AppDeployment','AppDeployment','ScriptDeployment','OOBE','Autopilot','SetupComplete','OfflineCache','AppCache','AppPackaging','Repository')
            ProjectUri = 'https://github.com/roryvossepoel/OSDApps'
            LicenseUri = 'https://github.com/roryvossepoel/OSDApps/blob/main/LICENSE'
            ReleaseNotes = 'First OSDStage release candidate: renamed module and cmdlets, schema v2 repository contracts, and fresh OSDStage cache and staging paths.'
            RequireLicenseAcceptance = $false
        }
    }
}
