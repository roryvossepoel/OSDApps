Describe 'Combined acceptance result integrity' {
    BeforeAll {
        $script:root = Split-Path $PSScriptRoot -Parent
        $script:validator = Join-Path $script:root 'tools/Test-OSDStageCombinedResult.ps1'
        $script:acceptanceExpectedIds = @('RepositoryApp','RepositoryScript','TestFont','TestCA','TestDriver','GoogleChromeEnterprise','AdobeAcrobatUnified','RegistrySettings','EnvironmentVariables','Services','WindowsFeatures','WindowsCapabilities','WiFiProfiles','DesktopSettings','WindowsInboxCleanup','DefaultAssociations')
        function Save-Fixtures {
            $script:record | ConvertTo-Json -Depth 5 | Set-Content $script:recordPath
            $script:result | ConvertTo-Json -Depth 5 | Set-Content $script:resultPath
        }
        function Invoke-Validation {
            & $script:validator -RecordPath $script:recordPath -ResultPath $script:resultPath -StagePath (Join-Path $TestDrive 'stage')
        }
    }
    BeforeEach {
        $script:recordPath = Join-Path $TestDrive 'record.json'
        $script:resultPath = Join-Path $TestDrive 'result.json'
        $script:record = [pscustomobject]@{DeploymentId=[guid]::NewGuid().ToString();Revision=('a'*40);ExpectedIds=$script:acceptanceExpectedIds;CleanupMode='OnSuccess'}
        $script:result = [pscustomobject]@{
            DeploymentId=$script:record.DeploymentId;Status='Succeeded';CleanupMode='OnSuccess'
            ExpectedPackageCount=16;SuccessfulPackageCount=16;FailedPackageCount=0;SkippedPackageCount=0
            Packages=@($script:acceptanceExpectedIds | ForEach-Object { [pscustomobject]@{Id=$_;Status='Succeeded'} })
        }
        Save-Fixtures
    }
    It 'accepts correlated complete results without claiming visual acceptance' {
        $report = Invoke-Validation
        $report.RunnerStatus | Should -Be Succeeded
        $report.UserExperience | Should -Be 'Manual acceptance still required'
    }
    It 'rejects results from another deployment' {
        $script:result.DeploymentId = [guid]::NewGuid().ToString(); Save-Fixtures
        { Invoke-Validation } | Should -Throw '*another deployment*'
    }
    It 'rejects an empty deployment GUID' {
        $script:record.DeploymentId = [guid]::Empty.ToString(); Save-Fixtures
        { Invoke-Validation } | Should -Throw '*Invalid staging*'
    }
    It 'rejects a partial queue' {
        $script:result.Packages = $script:result.Packages[0..14]; Save-Fixtures
        { Invoke-Validation } | Should -Throw '*expected package IDs*'
    }
    It 'rejects duplicate IDs even with a successful count' {
        $script:result.Packages[0].Id = $script:result.Packages[1].Id; Save-Fixtures
        { Invoke-Validation } | Should -Throw '*expected package IDs*'
    }
    It 'rejects skipped or failed entries behind a successful overall status' -ForEach @('Skipped','Failed','Running') {
        $script:result.Packages[0].Status = $_; Save-Fixtures
        { Invoke-Validation } | Should -Throw '*every selected entry*'
    }
    It 'rejects a missing counter' {
        $script:result.PSObject.Properties.Remove('FailedPackageCount'); Save-Fixtures
        { Invoke-Validation } | Should -Throw
    }
    It 'rejects a null counter instead of converting it to zero' {
        $script:result.FailedPackageCount = $null; Save-Fixtures
        { Invoke-Validation } | Should -Throw '*Invalid result counter*'
    }
    It 'rejects misleading success counters' {
        $script:result.SuccessfulPackageCount = 15; Save-Fixtures
        { Invoke-Validation } | Should -Throw '*Unexpected result counter*'
    }
    It 'does not claim cleanup while staging still exists' {
        New-Item -ItemType Directory (Join-Path $TestDrive 'stage') | Out-Null
        try { { Invoke-Validation } | Should -Throw '*Staging still exists*' }
        finally { Remove-Item (Join-Path $TestDrive 'stage') }
    }
    It 'rejects a reduced selection masquerading as the full profile' {
        $script:record.ExpectedIds = $script:acceptanceExpectedIds[0..14]; Save-Fixtures
        { Invoke-Validation } | Should -Throw '*Invalid combined test selection*'
    }
    It 'rejects unknown source revisions' {
        $script:record.Revision = 'main'; Save-Fixtures
        { Invoke-Validation } | Should -Throw '*pinned module revision*'
    }
}
Describe 'Combined test context guards' {
    BeforeAll {
        $script:runner = Join-Path (Split-Path $PSScriptRoot -Parent) 'tools/Invoke-OSDStageCombinedTest.ps1'
        $script:parameters = @{CatalogUri='https://example.invalid/catalog.json';AppId='App';ScriptId='Script';FontId='Font';CertificateId='CA';DriverId='Driver';WiFiProfilePath='absent.xml'}
    }
    It 'refuses staging on the preparation PC before importing or changing anything' {
        Mock Test-Path { $false }
        Mock Import-Module { throw 'Must not import.' }
        { & $script:runner -Phase Stage @script:parameters } | Should -Throw '*Run Stage in WinPE*'
        Should -Invoke Import-Module -Times 0 -Exactly
    }
    It 'refuses cache preparation in WinPE before importing or changing anything' {
        Mock Test-Path { $true }
        Mock Import-Module { throw 'Must not import.' }
        { & $script:runner -Phase Prepare @script:parameters } | Should -Throw '*full Windows preparation PC*'
        Should -Invoke Import-Module -Times 0 -Exactly
    }
}
Describe 'Combined staging orchestration with isolated dependencies' {
    BeforeAll {
        $script:root = Split-Path $PSScriptRoot -Parent
        $script:runner = Join-Path $script:root 'tools/Invoke-OSDStageCombinedTest.ps1'
        Import-Module (Join-Path $script:root 'OSDStage.psd1') -Force
        $script:acceptanceModule = Get-Module OSDStage
        $script:oldCombinedState = $global:OSDStageCombinedTestState
        $script:oldArchitecture = $env:PROCESSOR_ARCHITECTURE
        $env:PROCESSOR_ARCHITECTURE = 'AMD64'
        if (-not (Get-Command Get-Volume -ErrorAction SilentlyContinue)) { function Get-Volume { } }
        $script:parameters = @{Phase='Stage';CatalogUri='https://example.invalid/catalog.json';AppId='App';ScriptId='Script';FontId='Font';CertificateId='CA';DriverId='Driver';WiFiProfilePath='fixture.xml';WindowsPath=$TestDrive}
        $script:acceptanceExpectedIds = @('App','Script','Font','CA','Driver','GoogleChromeEnterprise','AdobeAcrobatUnified','RegistrySettings','EnvironmentVariables','Services','WindowsFeatures','WindowsCapabilities','WiFiProfiles','DesktopSettings','WindowsInboxCleanup','DefaultAssociations')
    }
    AfterAll { $global:OSDStageCombinedTestState = $script:oldCombinedState; $env:PROCESSOR_ARCHITECTURE = $script:oldArchitecture; Remove-Module OSDStage -Force -ErrorAction SilentlyContinue }
    BeforeEach {
        $global:OSDStageCombinedTestState = @{Ids=$script:acceptanceExpectedIds}
        $global:OSDStageCombinedTestState.Order = [System.Collections.Generic.List[string]]::new()
        $global:OSDStageCombinedTestState.Cache = @(
            @{Id='App';PackageType='App'},@{Id='Script';PackageType='Script'},@{Id='Font';PackageType='Font'},
            @{Id='CA';PackageType='Certificate'},@{Id='Driver';PackageType='Driver'},
            @{Id='GoogleChromeEnterprise';PackageType='App'},@{Id='AdobeAcrobatUnified';PackageType='App'}
        ) | ForEach-Object { [pscustomobject]@{Id=$_.Id;PackageType=$_.PackageType;Architecture='x64';Valid=$true;Version='1.0'} }
        Mock Test-Path { $LiteralPath -like '*MiniNT' -or $LiteralPath -like '*TestRevision.txt' }
        Mock Get-Volume { [pscustomobject]@{FileSystemLabel='OSDCloud';DriveLetter='Z'} }
        Mock Get-Content { 'a'*40 } -ParameterFilter { $LiteralPath -like '*TestRevision.txt' }
        Mock Get-Content { @{DeploymentId=[guid]::NewGuid().ToString();Packages=@($global:OSDStageCombinedTestState.Ids | ForEach-Object { @{Id=$_} })} | ConvertTo-Json -Depth 5 } -ParameterFilter { $LiteralPath -like '*DeviceManifest.json' }
        Mock Import-Module { Get-Module OSDStage }
        Mock Remove-Module { }
        Mock Set-OSDStageConfiguration { }
        Mock Get-OSDStageCache { $global:OSDStageCombinedTestState.Cache }
        Mock Get-OSDStage {
            $global:OSDStageCombinedTestState.Cache | Where-Object Id -eq $Name[0] | ForEach-Object {
                [pscustomobject]@{Id=$_.Id;Source='Repository';PackageType=$_.PackageType;Availability='CachedOnly';Valid=$true}
            }
        }
        Mock Sync-OSDStageRepository { }
        Mock Sync-OSDStageGoogleChromeEnterprise { }
        Mock Sync-OSDStageAdobeAcrobatUnified { }
        Mock Read-OSDStageWiFiProfile { } -ModuleName OSDStage
        Mock Resolve-OSDStageWindowsPath { $WindowsPath } -ModuleName OSDStage
        foreach ($name in @('Add-OSDStageFont','Add-OSDStageCertificate','Add-OSDStageDriver','Add-OSDStageEnvironmentVariable','Add-OSDStageService','Add-OSDStageWindowsFeature','Add-OSDStageWindowsCapability','Add-OSDStageWiFiProfile','Add-OSDStageStartPins','Add-OSDStageTaskbarPins','Add-OSDStageWindowsInboxCleanup')) { Mock $name { } }
        Mock Add-OSDStage { $global:OSDStageCombinedTestState.Order.Add('App') }
        Mock Add-OSDStageAdobeAcrobatUnified { $global:OSDStageCombinedTestState.Order.Add('Adobe') }
        Mock Add-OSDStageGoogleChromeEnterprise { $global:OSDStageCombinedTestState.Order.Add('Chrome') }
        Mock Add-OSDStageRegistryValue { $global:OSDStageCombinedTestState.Order.Add('Registry') }
        Mock Add-OSDStageRegistryKey { }
        Mock Add-OSDStageDefaultAssociation { $global:OSDStageCombinedTestState.Order.Add('Association') }
        Mock Test-OSDStageDeployment { [pscustomobject]@{Valid=$true;NetworkRequired=$true} }
        Mock New-Item { }
        Mock Set-Content { }
        Mock Write-Host { }
    }
    It 'prepares valid cache-only selections without requesting absent online IDs' {
        Mock Test-Path { $false } -ParameterFilter { $LiteralPath -like '*MiniNT' }
        $prepareParameters = $script:parameters.Clone(); $prepareParameters.Phase = 'Prepare'
        & $script:runner @prepareParameters | Out-Null
        Should -Invoke Sync-OSDStageRepository -Times 0 -Exactly
        Should -Invoke Sync-OSDStageGoogleChromeEnterprise -Times 1 -Exactly
        Should -Invoke Add-OSDStage -Times 0 -Exactly
    }
    It 'refreshes only the online selection while retaining other cached packages' {
        Mock Test-Path { $false } -ParameterFilter { $LiteralPath -like '*MiniNT' }
        Mock Get-OSDStage { [pscustomobject]@{Id='App';Source='Repository';PackageType='App';Availability='Online';Valid=$null} } -ParameterFilter { $Name[0] -eq 'App' }
        $prepareParameters = $script:parameters.Clone(); $prepareParameters.Phase = 'Prepare'
        & $script:runner @prepareParameters | Out-Null
        Should -Invoke Sync-OSDStageRepository -Times 1 -Exactly -ParameterFilter { $Name.Count -eq 1 -and $Name[0] -eq 'App' }
    }
    It 'rejects an invalid cache-only selection before any synchronization' {
        Mock Test-Path { $false } -ParameterFilter { $LiteralPath -like '*MiniNT' }
        Mock Get-OSDStage { [pscustomobject]@{Id='Font';Source='Repository';PackageType='Font';Availability='InvalidCache';Valid=$false} } -ParameterFilter { $Name[0] -eq 'Font' }
        $prepareParameters = $script:parameters.Clone(); $prepareParameters.Phase = 'Prepare'
        { & $script:runner @prepareParameters | Out-Null } | Should -Throw '*unavailable or its cache is invalid*'
        Should -Invoke Sync-OSDStageRepository -Times 0 -Exactly
        Should -Invoke Sync-OSDStageGoogleChromeEnterprise -Times 0 -Exactly
    }
    It 'stages the complete queue with installers before association import' {
        & $script:runner @script:parameters | Out-Null
        $global:OSDStageCombinedTestState.Order.IndexOf('Association') | Should -BeGreaterThan $global:OSDStageCombinedTestState.Order.IndexOf('Chrome')
        $global:OSDStageCombinedTestState.Order.IndexOf('Association') | Should -BeGreaterThan $global:OSDStageCombinedTestState.Order.IndexOf('Adobe')
        Should -Invoke Add-OSDStageWindowsCapability -Times 2 -Exactly
        Should -Invoke Add-OSDStageEnvironmentVariable -Times 4 -Exactly
        Should -Invoke Add-OSDStageWiFiProfile -Times 1 -Exactly
        Should -Invoke Set-Content -Times 1 -Exactly -ParameterFilter { $LiteralPath -like '*Combined-Staging.json' }
    }
    It 'refuses corrupt cache before any installer is staged' {
        $global:OSDStageCombinedTestState.Cache[0].Valid = $false
        { & $script:runner @script:parameters } | Should -Throw '*invalid or ambiguous cached package*'
        Should -Invoke Add-OSDStage -Times 0 -Exactly
    }
    It 'refuses a repository type mismatch before staging' {
        $global:OSDStageCombinedTestState.Cache[4].PackageType = 'App'
        { & $script:runner @script:parameters } | Should -Throw '*invalid or ambiguous cached package*'
        Should -Invoke Add-OSDStage -Times 0 -Exactly
    }
    It 'preserves existing staging' {
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like '*Temp*OSDStage' }
        { & $script:runner @script:parameters } | Should -Throw '*Existing staging found*'
        Should -Invoke Add-OSDStage -Times 0 -Exactly
    }
    It 'validates Wi-Fi without staging earlier entries on failure' {
        Mock Read-OSDStageWiFiProfile { throw 'Invalid profile.' } -ModuleName OSDStage
        { & $script:runner @script:parameters } | Should -Throw '*Invalid profile*'
        Should -Invoke Add-OSDStage -Times 0 -Exactly
    }
    It 'does not write a success record after a staging failure' {
        Mock Add-OSDStageService { throw 'Injected staging failure.' }
        { & $script:runner @script:parameters } | Should -Throw '*Injected staging failure*'
        Should -Invoke Set-Content -Times 0 -Exactly
        Should -Invoke Test-OSDStageDeployment -Times 0 -Exactly
    }
}
