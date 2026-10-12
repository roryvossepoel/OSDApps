Describe 'Transactional multi-app repository synchronization' {
    BeforeAll {
        $moduleRoot = Split-Path -Parent $PSScriptRoot
        Import-Module (Join-Path $moduleRoot 'OSDApps.psd1') -Force

        function global:New-Snapshot {
            param(
                [Parameter(Mandatory)][string]$Root,
                [Parameter(Mandatory)][string]$Version,
                [switch]$CorruptSecondPackage
            )

            $apps = @()
            foreach ($id in @('AppA','AppB')) {
                $dir = Join-Path $Root "Apps\$id\$Version\x64"
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
                $zip = Join-Path $dir 'Package.zip'
                Set-Content -LiteralPath $zip -Encoding ASCII -Value "Test archive $id $Version"
                $sha = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
                @{
                    SchemaVersion=1
                    Id=$id
                    DisplayName=$id
                    Version=$Version
                    Architecture='x64'
                    SuccessCodes=@(0,3010)
                    Archive=@{FileName='Package.zip';Sha256=$sha}
                } | ConvertTo-Json -Depth 10 |
                    Set-Content -LiteralPath (Join-Path $dir 'manifest.json') -Encoding UTF8
                $apps += @{
                    Id=$id
                    Packages=@(@{Architecture='x64';Manifest="Apps/$id/$Version/x64/manifest.json"})
                }
                if ($id -eq 'AppB' -and $CorruptSecondPackage) {
                    Set-Content -LiteralPath $zip -Encoding ASCII -Value 'intentionally corrupted after hashing'
                }
            }
            $catalogPath = Join-Path $Root 'catalog.json'
            @{
                SchemaVersion=1
                GeneratedAt=(Get-Date).ToUniversalTime().ToString('o')
                Applications=$apps
            } | ConvertTo-Json -Depth 20 |
                Set-Content -LiteralPath $catalogPath -Encoding UTF8

            return $catalogPath
        }
    }

    AfterAll {
        Remove-Item Function:\New-Snapshot -ErrorAction SilentlyContinue
    }

    It 'does not mutate a prior two-package cache when the second download fails SHA-256' {
        InModuleScope OSDApps {
            $cache = Join-Path $TestDrive 'Cache'
            $oldCatalog = New-Snapshot -Root (Join-Path $TestDrive 'Old') -Version '1.0.0'
            $newCatalog = New-Snapshot -Root (Join-Path $TestDrive 'New') -Version '2.0.0' -CorruptSecondPackage
            Sync-OSDAppCache -CatalogPath $oldCatalog -CachePath $cache -Confirm:$false | Out-Null

            $catalogBefore = [IO.File]::ReadAllText((Join-Path $cache 'CacheCatalog.json'))
            $aBefore = (Get-FileHash -LiteralPath (Join-Path $cache 'Packages\AppA\Package.zip') -Algorithm SHA256).Hash
            $bBefore = (Get-FileHash -LiteralPath (Join-Path $cache 'Packages\AppB\Package.zip') -Algorithm SHA256).Hash

            { Sync-OSDAppCache -CatalogPath $newCatalog -CachePath $cache -Confirm:$false } |
                Should -Throw '*SHA-256 validation failed*'

            [IO.File]::ReadAllText((Join-Path $cache 'CacheCatalog.json')) | Should -Be $catalogBefore
            (Get-FileHash -LiteralPath (Join-Path $cache 'Packages\AppA\Package.zip') -Algorithm SHA256).Hash | Should -Be $aBefore
            (Get-FileHash -LiteralPath (Join-Path $cache 'Packages\AppB\Package.zip') -Algorithm SHA256).Hash | Should -Be $bBefore
            @((Get-ChildItem -LiteralPath (Join-Path $cache '.staging') -Directory -ErrorAction SilentlyContinue)).Count | Should -Be 0
        }
    }

    It 'commits both packages together when downloads and hashes are valid' {
        InModuleScope OSDApps {
            $cache = Join-Path $TestDrive 'Cache'
            $oldCatalog = New-Snapshot -Root (Join-Path $TestDrive 'Old') -Version '1.0.0'
            $newCatalog = New-Snapshot -Root (Join-Path $TestDrive 'New') -Version '2.0.0'
            Sync-OSDAppCache -CatalogPath $oldCatalog -CachePath $cache -Confirm:$false | Out-Null
            Sync-OSDAppCache -CatalogPath $newCatalog -CachePath $cache -Confirm:$false | Out-Null
            $entries = @(Test-OSDAppRepositoryCache -CachePath $cache)
            $entries.Count | Should -Be 2
            @($entries.Version | Select-Object -Unique) | Should -Be @('2.0.0')
            @($entries | Where-Object { -not $_.Valid }).Count | Should -Be 0
            @((Get-ChildItem -LiteralPath (Join-Path $cache '.staging') -Directory -ErrorAction SilentlyContinue)).Count | Should -Be 0
        }
    }

    It 'restores all prior packages and the catalog when catalog commit fails' {
        InModuleScope OSDApps {
            $cache = Join-Path $TestDrive 'Cache'
            $oldCatalog = New-Snapshot -Root (Join-Path $TestDrive 'Old') -Version '1.0.0'
            $newCatalog = New-Snapshot -Root (Join-Path $TestDrive 'New') -Version '2.0.0'
            Sync-OSDAppCache -CatalogPath $oldCatalog -CachePath $cache -Confirm:$false | Out-Null
            $catalogBefore = [IO.File]::ReadAllText((Join-Path $cache 'CacheCatalog.json'))
            $oldHashes = @{}
            foreach ($id in 'AppA','AppB') {
                $oldHashes[$id] = (Get-FileHash -LiteralPath (Join-Path $cache "Packages\$id\Package.zip") -Algorithm SHA256).Hash
            }

            # Fault injection at the catalog publish boundary. Mocking Move-Item
            # directly would recursively intercept every fallback Move-Item.
            Mock Publish-OSDAppCacheCatalog { throw 'Simulated catalog commit failure' }

            { Sync-OSDAppCache -CatalogPath $newCatalog -CachePath $cache -Confirm:$false } |
                Should -Throw '*Simulated catalog commit failure*'

            [IO.File]::ReadAllText((Join-Path $cache 'CacheCatalog.json')) | Should -Be $catalogBefore
            foreach ($id in 'AppA','AppB') {
                (Get-FileHash -LiteralPath (Join-Path $cache "Packages\$id\Package.zip") -Algorithm SHA256).Hash |
                    Should -Be $oldHashes[$id]
            }
        }
    }

    It 'does not write any cache data in WhatIf mode' {
        InModuleScope OSDApps {
            $cache = Join-Path $TestDrive 'WhatIfCache'
            $source = New-Snapshot -Root (Join-Path $TestDrive 'WhatIfSource') -Version '1.0.0'
            Sync-OSDAppCache -CatalogPath $source -CachePath $cache -WhatIf | Out-Null
            (Test-Path -LiteralPath $cache) | Should -BeFalse
        }
    }
}
