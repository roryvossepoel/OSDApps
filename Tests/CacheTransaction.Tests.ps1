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
                Apps=$apps
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

    It 'rejects a batch that cannot fit even when each package fits individually' {
        InModuleScope OSDApps {
            Mock Get-OSDAppAvailableDiskBytes { 100GB }
            $cache = Join-Path $TestDrive 'BatchSpaceCache'
            $oldCatalog = New-Snapshot -Root (Join-Path $TestDrive 'BatchOld') -Version '1.0.0'
            $newCatalog = New-Snapshot -Root (Join-Path $TestDrive 'BatchNew') -Version '2.0.0'
            Sync-OSDAppCache -CatalogPath $oldCatalog -CachePath $cache -Confirm:$false | Out-Null
            $before = (Get-FileHash (Join-Path $cache 'CacheCatalog.json')).Hash
            Mock Get-OSDAppArchiveSpaceEstimate { 100MB }
            Mock Get-OSDAppAvailableDiskBytes { 200MB }
            { Sync-OSDAppCache -CatalogPath $newCatalog -CachePath $cache -Confirm:$false } | Should -Throw '*Insufficient free space*'
            (Get-FileHash (Join-Path $cache 'CacheCatalog.json')).Hash | Should -Be $before
            @((Get-ChildItem (Join-Path $cache '.staging') -Directory)).Count | Should -Be 0
        }
    }

    It 'preserves packages and catalog if free space drops before the second acquisition' {
        InModuleScope OSDApps {
            Mock Get-OSDAppAvailableDiskBytes { 100GB }
            $cache = Join-Path $TestDrive 'ShrinkingSpaceCache'
            $oldCatalog = New-Snapshot -Root (Join-Path $TestDrive 'ShrinkingOld') -Version '1.0.0'
            $newCatalog = New-Snapshot -Root (Join-Path $TestDrive 'ShrinkingNew') -Version '2.0.0'
            Sync-OSDAppCache -CatalogPath $oldCatalog -CachePath $cache -Confirm:$false | Out-Null
            $paths = @('CacheCatalog.json', 'Packages/AppA/Package.zip', 'Packages/AppB/Package.zip')
            $before = @($paths | ForEach-Object { (Get-FileHash (Join-Path $cache $_)).Hash })
            $script:spaceReads = 0
            Mock Get-OSDAppAvailableDiskBytes { $script:spaceReads++; if ($script:spaceReads -lt 3) { 100GB } else { 1MB } }
            { Sync-OSDAppCache -CatalogPath $newCatalog -CachePath $cache -Confirm:$false } | Should -Throw '*Insufficient free space*Previous cache preserved*'
            @($paths | ForEach-Object { (Get-FileHash (Join-Path $cache $_)).Hash }) | Should -Be $before
            @((Get-ChildItem (Join-Path $cache '.staging') -Directory)).Count | Should -Be 0
        }
    }

    It 'does not write any cache data in WhatIf mode' {
        InModuleScope OSDApps {
            Mock Get-OSDAppArchiveSpaceEstimate { throw 'WhatIf must not probe archive sizes' }
            Mock Get-OSDAppAvailableDiskBytes { throw 'WhatIf must not query free space' }
            $cache = Join-Path $TestDrive 'WhatIfCache'
            $source = New-Snapshot -Root (Join-Path $TestDrive 'WhatIfSource') -Version '1.0.0'
            Sync-OSDAppCache -CatalogPath $source -CachePath $cache -WhatIf | Out-Null
            (Test-Path -LiteralPath $cache) | Should -BeFalse
        }
    }
}
