Describe 'OSDApps source selection' {
    BeforeEach {
        $script:moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $script:manifestPath = Join-Path $script:moduleRoot 'OSDApps.psd1'
        Remove-Module OSDApps -Force -ErrorAction SilentlyContinue
        Import-Module $script:manifestPath -Force
    }

    It 'enables both sources by default' {
        $configuration = Get-OSDAppConfiguration
        $configuration.EnableBuiltIns | Should -BeTrue
        $configuration.EnableRepository | Should -BeTrue
    }

    It 'supports BuiltIn-only and Repository-only while preserving unrelated settings' {
        Set-OSDAppConfiguration -CacheVolumeLabel TestCache -EnableRepository $false
        $builtInOnly = Get-OSDAppConfiguration
        $builtInOnly.EnableBuiltIns | Should -BeTrue
        $builtInOnly.EnableRepository | Should -BeFalse
        $builtInOnly.CacheVolumeLabel | Should -Be 'TestCache'

        Set-OSDAppConfiguration -EnableRepository $true -EnableBuiltIns $false
        $repositoryOnly = Get-OSDAppConfiguration
        $repositoryOnly.EnableBuiltIns | Should -BeFalse
        $repositoryOnly.EnableRepository | Should -BeTrue
        $repositoryOnly.CacheVolumeLabel | Should -Be 'TestCache'
    }

    It 'rejects disabling both sources without mutating the effective configuration' {
        Set-OSDAppConfiguration -EnableRepository $false
        { Set-OSDAppConfiguration -EnableBuiltIns $false } | Should -Throw '*At least one app source*'
        $configuration = Get-OSDAppConfiguration
        $configuration.EnableBuiltIns | Should -BeTrue
        $configuration.EnableRepository | Should -BeFalse
    }

    It 'records source selection in the staged runtime configuration' {
        InModuleScope OSDApps {
            Set-OSDAppConfiguration -EnableRepository $false
            $manifest = Set-OSDAppManifestRuntimeConfiguration -Manifest ([pscustomobject]@{})
            $manifest.Runtime.EnableBuiltIns | Should -BeTrue
            $manifest.Runtime.EnableRepository | Should -BeFalse
        }
    }

    It 'treats missing source properties as the historical enabled default' {
        InModuleScope OSDApps {
            $legacy = [pscustomobject]@{ CatalogUri=$null }
            (Test-OSDAppSourceEnabled -Source BuiltIn -Configuration $legacy) | Should -BeTrue
            (Test-OSDAppSourceEnabled -Source Repository -Configuration $legacy) | Should -BeTrue
        }
    }

    It 'blocks repository Add before staging when Repository is disabled' {
        Set-OSDAppConfiguration -EnableRepository $false
        { Add-OSDApp -Name SampleApp -WhatIf } | Should -Throw '*Repository packages are disabled*'
    }

    It 'blocks built-in Add before Windows or cache discovery when BuiltIns are disabled' {
        Set-OSDAppConfiguration -EnableBuiltIns $false
        { Add-OSDApp7Zip -WhatIf } | Should -Throw '*Built-in apps*disabled*'
    }

    It 'treats registry staging as an OSDApps-owned built-in feature' {
        Set-OSDAppConfiguration -EnableBuiltIns $false
        { Add-OSDAppRegistryKey -Path 'HKLM\SOFTWARE\OSDApps\SourceSelection' -WhatIf } |
            Should -Throw '*Built-in apps*disabled*'
    }

    It 'does not query or return Repository apps when Repository is disabled' {
        InModuleScope OSDApps {
            Set-OSDAppConfiguration -CatalogUri 'https://example.org/catalog.json' -EnableRepository $false
            Mock Get-OSDAppCachePath { throw 'No USB' }
            Mock Get-OSDAppCatalogPackages { throw 'Repository lookup must remain disabled.' }

            $apps = @(Get-OSDApp)
            @($apps | Where-Object Source -eq 'Repository').Count | Should -Be 0
            @($apps | Where-Object Source -eq 'BuiltIn').Count | Should -BeGreaterThan 10
            Should -Invoke Get-OSDAppCatalogPackages -Exactly 0
        }
    }

    It 'returns only Repository apps when BuiltIns are disabled' {
        InModuleScope OSDApps {
            Set-OSDAppConfiguration -CatalogUri 'https://example.org/catalog.json' -EnableBuiltIns $false
            Mock Get-OSDAppCachePath { throw 'No USB' }
            Mock Get-OSDAppHostArchitecture { 'x64' }
            Mock Get-OSDAppCatalogPackages {
                [pscustomobject]@{
                    Packages = @([pscustomobject]@{
                        Id='SampleApp';DisplayName='Sample App';Vendor='Example'
                        Architecture='x64';Version='1.0.0';PackageType='App'
                    })
                }
            }

            $apps = @(Get-OSDApp)
            $apps.Count | Should -Be 1
            $apps[0].Id | Should -Be 'SampleApp'
            $apps[0].Source | Should -Be 'Repository'
        }
    }

    It 'reports Repository catalog as disabled without network access' {
        InModuleScope OSDApps {
            Set-OSDAppConfiguration -CatalogUri 'https://example.org/catalog.json' -EnableRepository $false
            Mock Invoke-WebRequest { throw 'Network access must not occur.' }
            $status = Get-OSDAppCatalog
            $status.Enabled | Should -BeFalse
            $status.Available | Should -BeFalse
            $status.AppCount | Should -Be 0
            Should -Invoke Invoke-WebRequest -Exactly 0
        }
    }
}
