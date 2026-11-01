Describe 'OSDStage product and schema contract' {
    BeforeAll {
        $script:root=Split-Path $PSScriptRoot -Parent
        Import-Module (Join-Path $script:root 'OSDStage.psd1') -Force
    }

    It 'exports the complete renamed command set and no command aliases' {
        $expected=@(
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
        $module=Get-Module OSDStage
        @($module.ExportedFunctions.Keys | Sort-Object) | Should -Be @($expected | Sort-Object)
        @($module.ExportedAliases.Keys).Count | Should -Be 0
        $module.Guid | Should -Not -Be ([guid]'efc06c0c-6a69-4c21-8f34-2f539a7d5409')
    }

    It 'authors and reads the new catalog and payload contract without changing ZIP content' {
        $source=Join-Path $TestDrive 'Source'
        New-Item -ItemType Directory -Path $source -Force | Out-Null
        Set-Content (Join-Path $source 'Install.ps1') 'exit 0'
        $zip=New-OSDStagePackage -Id Fixture -Version 1.0 -SourcePath $source -OutputPath (Join-Path $TestDrive 'Build')
        $repo=Join-Path $TestDrive 'Repository'
        $published=Add-OSDStagePackage -Id Fixture -DisplayName Fixture -Version 1.0 -Architecture x64 -PackagePath $zip.PackagePath -RepositoryPath $repo
        $catalog=Get-Content (Join-Path $repo 'catalog.json') -Raw | ConvertFrom-Json
        $catalog.SchemaVersion | Should -Be 2
        $catalog.Packages[0].Architectures[0].Architecture | Should -Be x64
        $published.ManifestPath | Should -Be 'Packages/Fixture/1.0/x64/manifest.json'
        $manifest=Get-Content (Join-Path $repo $published.ManifestPath) -Raw | ConvertFrom-Json
        $manifest.SchemaVersion | Should -Be 2
        $manifest.Payload.FileName | Should -Be 'Package.zip'
        $manifest.Payload.Sha256 | Should -Be $zip.Sha256
        @($manifest.PSObject.Properties.Name) | Should -Not -Contain 'Archive'
        (Test-OSDStageRepository $repo).Valid | Should -BeTrue
    }

    It 'rejects unsupported catalog schemas instead of attempting migration' {
        InModuleScope OSDStage {
            foreach ($version in @(1,3,$null)) {
                { Assert-OSDStageCatalog -Catalog ([pscustomobject]@{SchemaVersion=$version;Packages=@()}) } |
                    Should -Throw '*SchemaVersion 2*'
            }
            { Assert-OSDStageCatalog -Catalog ([pscustomobject]@{SchemaVersion=2;Packages=@([pscustomobject]@{Id='Fixture';Packages=@()})}) } |
                Should -Throw '*Architectures*'
        }
    }

    It 'rejects a package manifest from an unsupported schema before content acquisition' {
        InModuleScope OSDStage {
            Mock Get-OSDStageManifest {
                if ($Uri.AbsoluteUri.EndsWith('catalog.json')) {
                    return [pscustomobject]@{SchemaVersion=2;Packages=@([pscustomobject]@{
                        Id='Fixture';Architectures=@([pscustomobject]@{Architecture='x64';Manifest='manifest.json'})
                    })}
                }
                [pscustomobject]@{SchemaVersion=1;Id='Fixture';Architecture='x64';Version='1.0'}
            }
            { Get-OSDStageCatalogPackages -CatalogUri 'https://example.invalid/catalog.json' } |
                Should -Throw '*SchemaVersion 2*'
        }
    }

    It 'keeps the USB label while using a fresh cache namespace and dynamic letter' {
        InModuleScope OSDStage {
            function Get-Volume { param($ErrorAction) }
            Mock Get-OSDStageConfiguration { [pscustomobject]@{CacheVolumeLabel='OSDCloud'} }
            Mock Get-Volume { [pscustomobject]@{DriveLetter='R';FileSystemLabel='OSDCloud'} }
            Get-OSDStageCachePath | Should -Be 'R:\OSDStage'
        }
    }

    It 'does not publish automatically when the rename is merged' {
        $release=Get-Content (Join-Path $script:root '.github/workflows/release.yml') -Raw
        $release | Should -Match '(?m)^  workflow_dispatch:'
        $release | Should -Not -Match '(?m)^  push:'
    }
}
