Describe 'P1 offline repository staging and WhatIf safety' {
    BeforeAll {
        $moduleRoot = Split-Path -Parent $PSScriptRoot
        Import-Module (Join-Path $moduleRoot 'OSDStage.psd1') -Force
    }

    It 'does not synchronize or change the disk with WhatIf' {
        InModuleScope OSDStage {
            $winRoot = Join-Path $TestDrive 'WhatIfWindows'
            Mock Get-OSDStageCachePath { throw 'No USB' }
            Mock Resolve-OSDStageWindowsPath { $winRoot }
            Mock Sync-OSDStageCache { throw 'Must not be called' }
            Mock Copy-OSDStageContent { throw 'Must not be called' }
            Mock Add-OSDStageSetupComplete { throw 'Must not be called' }

            Add-OSDStage -Name ExampleApp -WindowsPath $winRoot -WhatIf | Out-Null

            Should -Invoke Sync-OSDStageCache -Exactly 0
            Should -Invoke Copy-OSDStageContent -Exactly 0
            Should -Invoke Add-OSDStageSetupComplete -Exactly 0
            (Test-Path -LiteralPath $winRoot) | Should -BeFalse
        }
    }

    It 'stages a SHA-256 validated offline package without trying a sync' {
        InModuleScope OSDStage {
            $cacheRoot = Join-Path $TestDrive 'Cache'
            $winRoot = Join-Path $TestDrive 'OfflineWindows'
            $pkgRoot = Join-Path $cacheRoot 'Packages\ExampleApp'
            New-Item -ItemType Directory -Path $pkgRoot,$winRoot -Force | Out-Null
            $archive = Join-Path $pkgRoot 'Package.zip'
            Set-Content -LiteralPath $archive -Value 'known test bytes' -Encoding ASCII
            $sha256 = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
            @{
                SchemaVersion = 2
                Packages = @(
                    @{
                        Id = 'ExampleApp'
                        Version = '1.0'
                        Architecture = 'any'
                        Payload = @{ Sha256 = $sha256; FileName = 'Package.zip' }
                    }
                )
            } | ConvertTo-Json -Depth 10 |
                Set-Content -LiteralPath (Join-Path $cacheRoot 'CacheCatalog.json') -Encoding UTF8

            Mock Get-OSDStageCachePath { $cacheRoot }
            Mock Resolve-OSDStageWindowsPath { $winRoot }
            Mock Get-OSDStageConfiguration { [pscustomobject]@{ CatalogUri = 'https://invalid.example.org/catalog.json' } }

            Mock Sync-OSDStageCache { throw 'Must not synchronize' }

            Add-OSDStage -Name ExampleApp -WindowsPath $winRoot -SkipCacheRefresh | Out-Null
            Add-OSDStage -Name ExampleApp -WindowsPath $winRoot -SkipCacheRefresh | Out-Null

            Should -Invoke Sync-OSDStageCache -Exactly 0
            $staged = Join-Path $winRoot 'Windows\Temp\OSDStage'
            (Test-Path -LiteralPath (Join-Path $staged 'Packages\ExampleApp\Package.zip')) | Should -BeTrue
            $manifest = Get-Content -LiteralPath (Join-Path $staged 'DeviceManifest.json') -Raw | ConvertFrom-Json
            @($manifest.Packages).Count | Should -Be 1
            @($manifest.Packages.Id) | Should -Be @('ExampleApp')
            $setup = Get-Content -LiteralPath (Join-Path $winRoot 'Windows\Setup\Scripts\SetupComplete.cmd') -Raw
            ([regex]::Matches($setup, '(?m)^:: OSDStage PreInstall\r?$')).Count | Should -Be 1
            ([regex]::Matches($setup, '(?m)^:: OSDStage Begin\r?$')).Count | Should -Be 1
            ([regex]::Matches($setup, '(?m)^:: OSDStage End\r?$')).Count | Should -Be 1
        }
    }

    It 'resolves a retired repository alias to the canonical cached Id before staging' {
        InModuleScope OSDStage {
            $cacheRoot = Join-Path $TestDrive 'AliasCache'
            $winRoot = Join-Path $TestDrive 'AliasWindows'
            $pkgRoot = Join-Path $cacheRoot 'Packages\NewApp'
            New-Item -ItemType Directory -Path $pkgRoot,$winRoot -Force | Out-Null
            $archive = Join-Path $pkgRoot 'Package.zip'
            Set-Content -LiteralPath $archive -Value 'canonical package' -Encoding ASCII
            $sha256 = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
            @{
                SchemaVersion = 2
                Packages = @(
                    @{
                        Id='NewApp';Aliases=@('OldApp');Version='2.0';Architecture='any'
                        Payload=@{Sha256=$sha256;FileName='Package.zip'}
                    }
                )
            } | ConvertTo-Json -Depth 10 |
                Set-Content -LiteralPath (Join-Path $cacheRoot 'CacheCatalog.json') -Encoding UTF8
            Mock Get-OSDStageCachePath { $cacheRoot }
            Mock Resolve-OSDStageWindowsPath { $winRoot }
            Mock Get-OSDStageConfiguration { [pscustomobject]@{ CatalogUri = $null } }

            $result = @(Add-OSDStage -Name OldApp -WindowsPath $winRoot -SkipCacheRefresh)

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be 'NewApp'
            (Test-Path -LiteralPath (Join-Path $winRoot 'Windows\Temp\OSDStage\Packages\NewApp\Package.zip')) | Should -BeTrue
            $manifest = Get-Content -LiteralPath (Join-Path $winRoot 'Windows\Temp\OSDStage\DeviceManifest.json') -Raw | ConvertFrom-Json
            @($manifest.Packages.Id) | Should -Be @('NewApp')
        }
    }

    It 'falls back to a valid cache when online synchronization fails' {
        InModuleScope OSDStage {
            $cacheRoot = Join-Path $TestDrive 'Cache'
            $winRoot = Join-Path $TestDrive 'OfflineWindows'
            $pkgRoot = Join-Path $cacheRoot 'Packages\ExampleApp'
            New-Item -ItemType Directory -Path $pkgRoot,$winRoot -Force | Out-Null
            $archive = Join-Path $pkgRoot 'Package.zip'
            Set-Content -LiteralPath $archive -Value 'known test bytes' -Encoding ASCII
            $sha256 = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
            @{
                SchemaVersion = 2
                Packages = @(
                    @{
                        Id = 'ExampleApp'
                        Version = '1.0'
                        Architecture = 'any'
                        Payload = @{ Sha256 = $sha256; FileName = 'Package.zip' }
                    }
                )
            } | ConvertTo-Json -Depth 10 |
                Set-Content -LiteralPath (Join-Path $cacheRoot 'CacheCatalog.json') -Encoding UTF8

            Mock Get-OSDStageCachePath { $cacheRoot }
            Mock Resolve-OSDStageWindowsPath { $winRoot }
            Mock Get-OSDStageConfiguration { [pscustomobject]@{ CatalogUri = 'https://invalid.example.org/catalog.json' } }

            Mock Sync-OSDStageCache { throw 'Simulated connection failure' }

            Add-OSDStage -Name ExampleApp -WindowsPath $winRoot -WarningAction SilentlyContinue | Out-Null

            Should -Invoke Sync-OSDStageCache -Exactly 1
            (Test-Path -LiteralPath (Join-Path $winRoot 'Windows\Temp\OSDStage\DeviceManifest.json')) | Should -BeTrue
        }
    }

    It 'refuses fallback when a cached alias conflicts with a canonical Id' {
        InModuleScope OSDStage {
            $cacheRoot = Join-Path $TestDrive 'AmbiguousAliasCache'
            $winRoot = Join-Path $TestDrive 'AmbiguousAliasWindows'
            New-Item -ItemType Directory -Path $cacheRoot,$winRoot -Force | Out-Null
            @{
                SchemaVersion = 2
                Packages = @(
                    @{Id='OldApp';Version='1.0';Architecture='any';Payload=@{Sha256=('0' * 64);FileName='Package.zip'}},
                    @{Id='NewApp';Aliases=@('OldApp');Version='2.0';Architecture='any';Payload=@{Sha256=('1' * 64);FileName='Package.zip'}}
                )
            } | ConvertTo-Json -Depth 10 |
                Set-Content -LiteralPath (Join-Path $cacheRoot 'CacheCatalog.json') -Encoding UTF8

            Mock Get-OSDStageCachePath { $cacheRoot }
            Mock Resolve-OSDStageWindowsPath { $winRoot }
            Mock Get-OSDStageConfiguration { [pscustomobject]@{ CatalogUri = 'https://invalid.example.org/catalog.json' } }
            Mock Sync-OSDStageCache { throw 'Simulated connection failure' }
            Mock Copy-OSDStageContent { throw 'Staging must not be attempted' }

            { Add-OSDStage -Name OldApp -WindowsPath $winRoot -WarningAction SilentlyContinue } |
                Should -Throw '*cannot be resolved safely*ambiguous*'

            Should -Invoke Copy-OSDStageContent -Exactly 0
        }
    }

    It 'refuses offline fallback if the cached archive is corrupted' {
        InModuleScope OSDStage {
            $cacheRoot = Join-Path $TestDrive 'Cache'
            $winRoot = Join-Path $TestDrive 'OfflineWindows'
            $pkgRoot = Join-Path $cacheRoot 'Packages\ExampleApp'
            New-Item -ItemType Directory -Path $pkgRoot,$winRoot -Force | Out-Null
            $archive = Join-Path $pkgRoot 'Package.zip'
            Set-Content -LiteralPath $archive -Value 'known test bytes' -Encoding ASCII
            $sha256 = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
            @{
                SchemaVersion = 2
                Packages = @(
                    @{
                        Id = 'ExampleApp'
                        Version = '1.0'
                        Architecture = 'any'
                        Payload = @{ Sha256 = $sha256; FileName = 'Package.zip' }
                    }
                )
            } | ConvertTo-Json -Depth 10 |
                Set-Content -LiteralPath (Join-Path $cacheRoot 'CacheCatalog.json') -Encoding UTF8

            Mock Get-OSDStageCachePath { $cacheRoot }
            Mock Resolve-OSDStageWindowsPath { $winRoot }
            Mock Get-OSDStageConfiguration { [pscustomobject]@{ CatalogUri = 'https://invalid.example.org/catalog.json' } }

            Set-Content -LiteralPath $archive -Value 'tampered archive' -Encoding ASCII
            Mock Sync-OSDStageCache { throw 'Simulated connection failure' }
            Mock Copy-OSDStageContent { throw 'Staging must not be attempted' }

            { Add-OSDStage -Name ExampleApp -WindowsPath $winRoot -WarningAction SilentlyContinue } |
                Should -Throw '*No valid offline cache*'

            Should -Invoke Copy-OSDStageContent -Exactly 0
        }
    }
}
