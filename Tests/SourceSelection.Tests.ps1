Describe 'OSDStage source selection' {
    BeforeEach {
        $script:moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $script:manifestPath = Join-Path $script:moduleRoot 'OSDStage.psd1'
        Remove-Module OSDStage -Force -ErrorAction SilentlyContinue
        Import-Module $script:manifestPath -Force
    }

    It 'enables both sources by default' {
        $configuration = Get-OSDStageConfiguration
        $configuration.EnableBuiltIns | Should -BeTrue
        $configuration.EnableRepository | Should -BeTrue
    }

    It 'supports BuiltIn-only and Repository-only while preserving unrelated settings' {
        Set-OSDStageConfiguration -CacheVolumeLabel TestCache -EnableRepository $false
        $builtInOnly = Get-OSDStageConfiguration
        $builtInOnly.EnableBuiltIns | Should -BeTrue
        $builtInOnly.EnableRepository | Should -BeFalse
        $builtInOnly.CacheVolumeLabel | Should -Be 'TestCache'

        Set-OSDStageConfiguration -EnableRepository $true -EnableBuiltIns $false
        $repositoryOnly = Get-OSDStageConfiguration
        $repositoryOnly.EnableBuiltIns | Should -BeFalse
        $repositoryOnly.EnableRepository | Should -BeTrue
        $repositoryOnly.CacheVolumeLabel | Should -Be 'TestCache'
    }

    It 'rejects disabling both sources without mutating the effective configuration' {
        Set-OSDStageConfiguration -EnableRepository $false
        { Set-OSDStageConfiguration -EnableBuiltIns $false } | Should -Throw '*At least one app source*'
        $configuration = Get-OSDStageConfiguration
        $configuration.EnableBuiltIns | Should -BeTrue
        $configuration.EnableRepository | Should -BeFalse
    }

    It 'records source selection in the staged runtime configuration' {
        InModuleScope OSDStage {
            Set-OSDStageConfiguration -EnableRepository $false
            $manifest = Set-OSDStageManifestRuntimeConfiguration -Manifest ([pscustomobject]@{})
            $manifest.Runtime.EnableBuiltIns | Should -BeTrue
            $manifest.Runtime.EnableRepository | Should -BeFalse
        }
    }

    It 'treats missing source properties as the historical enabled default' {
        InModuleScope OSDStage {
            $legacy = [pscustomobject]@{ CatalogUri=$null }
            (Test-OSDStageSourceEnabled -Source BuiltIn -Configuration $legacy) | Should -BeTrue
            (Test-OSDStageSourceEnabled -Source Repository -Configuration $legacy) | Should -BeTrue
        }
    }

    It 'blocks repository Add before staging when Repository is disabled' {
        Set-OSDStageConfiguration -EnableRepository $false
        { Add-OSDStage -Name SampleApp -WhatIf } | Should -Throw '*Repository packages are disabled*'
    }

    It 'blocks built-in Add before Windows or cache discovery when BuiltIns are disabled' {
        Set-OSDStageConfiguration -EnableBuiltIns $false
        { Add-OSDStage7Zip -WhatIf } | Should -Throw '*Built-in apps*disabled*'
    }

    It 'treats registry staging as an OSDStage-owned built-in feature' {
        Set-OSDStageConfiguration -EnableBuiltIns $false
        { Add-OSDStageRegistryKey -Path 'HKLM\SOFTWARE\OSDStage\SourceSelection' -WhatIf } |
            Should -Throw '*Built-in apps*disabled*'
    }

    It 'does not query or return Repository apps when Repository is disabled' {
        InModuleScope OSDStage {
            Set-OSDStageConfiguration -CatalogUri 'https://example.org/catalog.json' -EnableRepository $false
            Mock Get-OSDStageCachePath { throw 'No USB' }
            Mock Get-OSDStageCatalogPackages { throw 'Repository lookup must remain disabled.' }

            $apps = @(Get-OSDStage)
            @($apps | Where-Object Source -eq 'Repository').Count | Should -Be 0
            @($apps | Where-Object Source -eq 'BuiltIn').Count | Should -BeGreaterThan 10
            Should -Invoke Get-OSDStageCatalogPackages -Exactly 0
        }
    }

    It 'returns only Repository apps when BuiltIns are disabled' {
        InModuleScope OSDStage {
            Set-OSDStageConfiguration -CatalogUri 'https://example.org/catalog.json' -EnableBuiltIns $false
            Mock Get-OSDStageCachePath { throw 'No USB' }
            Mock Get-OSDStageHostArchitecture { 'x64' }
            Mock Get-OSDStageCatalogPackages {
                [pscustomobject]@{
                    Packages = @([pscustomobject]@{
                        Id='SampleApp';DisplayName='Sample App';Vendor='Example'
                        Architecture='x64';Version='1.0.0';PackageType='App'
                    })
                }
            }

            $apps = @(Get-OSDStage)
            $apps.Count | Should -Be 1
            $apps[0].Id | Should -Be 'SampleApp'
            $apps[0].Source | Should -Be 'Repository'
        }
    }

    It 'reports Repository catalog as disabled without network access' {
        InModuleScope OSDStage {
            Set-OSDStageConfiguration -CatalogUri 'https://example.org/catalog.json' -EnableRepository $false
            Mock Invoke-WebRequest { throw 'Network access must not occur.' }
            $status = Get-OSDStageCatalog
            $status.Enabled | Should -BeFalse
            $status.Available | Should -BeFalse
            $status.PackageCount | Should -Be 0
            Should -Invoke Invoke-WebRequest -Exactly 0
        }
    }
}
