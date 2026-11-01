Describe 'Transactional desired-state cache reconciliation' {
    BeforeAll {
        $script:moduleRoot = Split-Path -Parent $PSScriptRoot
        Remove-Module OSDStage -Force -ErrorAction SilentlyContinue
        Import-Module (Join-Path $script:moduleRoot 'OSDStage.psd1') -Force

        function global:New-ReconciliationCatalog {
            param(
                [Parameter(Mandatory)][string]$Root,
                [Parameter(Mandatory)][object[]]$Definitions
            )

            $catalogApps = @()
            foreach ($definition in $Definitions) {
                $id = [string]$definition.Id
                $version = [string]$definition.Version
                $packageRoot = Join-Path $Root "Packages\$id\$version\x64"
                New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null
                $archivePath = Join-Path $packageRoot 'Package.zip'
                Set-Content -LiteralPath $archivePath -Value "archive-$id-$version" -Encoding ASCII
                $sha256 = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
                @{
                    SchemaVersion=2; Id=$id; DisplayName=$id; Version=$version
                    Architecture='x64'; SuccessCodes=@(0,3010)
                    Payload=@{FileName='Package.zip';Sha256=$sha256}
                } | ConvertTo-Json -Depth 10 |
                    Set-Content -LiteralPath (Join-Path $packageRoot 'manifest.json') -Encoding UTF8
                $app = [ordered]@{
                    Id=$id
                    Architectures=@(@{Architecture='x64';Manifest="Packages/$id/$version/x64/manifest.json"})
                }
                if ($definition.PSObject.Properties.Name -contains 'Aliases') {
                    $app['Aliases'] = @($definition.Aliases)
                }
                $catalogApps += [pscustomobject]$app
            }

            $catalogPath = Join-Path $Root 'catalog.json'
            @{
                SchemaVersion=2
                GeneratedAt='2026-10-13T00:00:00Z'
                Packages=$catalogApps
            } | ConvertTo-Json -Depth 20 |
                Set-Content -LiteralPath $catalogPath -Encoding UTF8
            $catalogPath
        }
    }

    AfterAll {
        Remove-Item Function:\New-ReconciliationCatalog -ErrorAction SilentlyContinue
    }

    It 'replaces aliases, prunes obsolete and orphaned folders, and retains a valid pin' {
        InModuleScope OSDStage {
            $cache = Join-Path $TestDrive 'ReconciledCache'
            $oldCatalog = New-ReconciliationCatalog -Root (Join-Path $TestDrive 'OldRepository') -Definitions @(
                [pscustomobject]@{Id='OldApp';Version='1.0.0'},
                [pscustomobject]@{Id='GoneApp';Version='1.0.0'},
                [pscustomobject]@{Id='PinnedApp';Version='1.0.0'}
            )
            $desiredCatalog = New-ReconciliationCatalog -Root (Join-Path $TestDrive 'NewRepository') -Definitions @(
                [pscustomobject]@{Id='NewApp';Version='2.0.0';Aliases=@('OldApp')}
            )
            Sync-OSDStageCache -CatalogPath $oldCatalog -CachePath $cache -Confirm:$false | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $cache 'Packages\LooseFolder') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $cache 'Packages\LooseFolder\Package.zip') -Value 'orphan' -Encoding ASCII

            Sync-OSDStageCache -CatalogPath $desiredCatalog -CachePath $cache -Prune -PinnedId PinnedApp -Confirm:$false | Out-Null

            @((Get-ChildItem -LiteralPath (Join-Path $cache 'Packages') -Directory).Name | Sort-Object) |
                Should -Be @('NewApp','PinnedApp')
            $cacheCatalog = Get-Content -LiteralPath (Join-Path $cache 'CacheCatalog.json') -Raw | ConvertFrom-Json
            @($cacheCatalog.Packages.Id | Sort-Object) | Should -Be @('NewApp','PinnedApp')
            @($cacheCatalog.Packages | Where-Object Id -eq 'NewApp')[0].Aliases | Should -Contain 'OldApp'
            (Test-Path -LiteralPath (Join-Path $cache 'Packages\OldApp')) | Should -BeFalse
            (Test-Path -LiteralPath (Join-Path $cache 'Packages\GoneApp')) | Should -BeFalse
            (Test-Path -LiteralPath (Join-Path $cache 'Packages\LooseFolder')) | Should -BeFalse
            @((Get-ChildItem -LiteralPath (Join-Path $cache '.staging') -Directory -ErrorAction SilentlyContinue)).Count | Should -Be 0

            $health = Get-OSDStageCacheHealth -CachePath $cache -CatalogPath $desiredCatalog -PinnedId PinnedApp
            $health.Healthy | Should -BeTrue
            $health.ActiveCount | Should -Be 1
            $health.PinnedCount | Should -Be 1
        }
    }

    It 'restores removed folders and the prior catalog when the commit fails' {
        InModuleScope OSDStage {
            $cache = Join-Path $TestDrive 'RollbackCache'
            $oldCatalog = New-ReconciliationCatalog -Root (Join-Path $TestDrive 'RollbackOld') -Definitions @(
                [pscustomobject]@{Id='OldApp';Version='1.0.0'},
                [pscustomobject]@{Id='GoneApp';Version='1.0.0'}
            )
            $desiredCatalog = New-ReconciliationCatalog -Root (Join-Path $TestDrive 'RollbackNew') -Definitions @(
                [pscustomobject]@{Id='NewApp';Version='2.0.0';Aliases=@('OldApp')}
            )
            Sync-OSDStageCache -CatalogPath $oldCatalog -CachePath $cache -Confirm:$false | Out-Null
            $catalogBefore = [IO.File]::ReadAllText((Join-Path $cache 'CacheCatalog.json'))
            $hashesBefore = @{}
            foreach ($id in @('OldApp','GoneApp')) {
                $hashesBefore[$id] = (Get-FileHash -LiteralPath (Join-Path $cache "Packages\$id\Package.zip") -Algorithm SHA256).Hash
            }
            Mock Publish-OSDStageCacheCatalog { throw 'Simulated reconciliation commit failure' }

            { Sync-OSDStageCache -CatalogPath $desiredCatalog -CachePath $cache -Prune -Confirm:$false } |
                Should -Throw '*Simulated reconciliation commit failure*'

            [IO.File]::ReadAllText((Join-Path $cache 'CacheCatalog.json')) | Should -Be $catalogBefore
            foreach ($id in @('OldApp','GoneApp')) {
                (Get-FileHash -LiteralPath (Join-Path $cache "Packages\$id\Package.zip") -Algorithm SHA256).Hash |
                    Should -Be $hashesBefore[$id]
            }
            (Test-Path -LiteralPath (Join-Path $cache 'Packages\NewApp')) | Should -BeFalse
            @((Get-ChildItem -LiteralPath (Join-Path $cache '.staging') -Directory -ErrorAction SilentlyContinue)).Count | Should -Be 0
        }
    }

    It 'does not change files while previewing a prune operation' {
        InModuleScope OSDStage {
            $cache = Join-Path $TestDrive 'PreviewCache'
            $oldCatalog = New-ReconciliationCatalog -Root (Join-Path $TestDrive 'PreviewOld') -Definitions @(
                [pscustomobject]@{Id='OldApp';Version='1.0.0'}
            )
            $desiredCatalog = New-ReconciliationCatalog -Root (Join-Path $TestDrive 'PreviewNew') -Definitions @(
                [pscustomobject]@{Id='NewApp';Version='2.0.0';Aliases=@('OldApp')}
            )
            Sync-OSDStageCache -CatalogPath $oldCatalog -CachePath $cache -Confirm:$false | Out-Null
            $catalogBefore = (Get-FileHash -LiteralPath (Join-Path $cache 'CacheCatalog.json') -Algorithm SHA256).Hash
            $packageBefore = (Get-FileHash -LiteralPath (Join-Path $cache 'Packages\OldApp\Package.zip') -Algorithm SHA256).Hash

            Sync-OSDStageCache -CatalogPath $desiredCatalog -CachePath $cache -Prune -WhatIf | Out-Null

            (Get-FileHash -LiteralPath (Join-Path $cache 'CacheCatalog.json') -Algorithm SHA256).Hash | Should -Be $catalogBefore
            (Get-FileHash -LiteralPath (Join-Path $cache 'Packages\OldApp\Package.zip') -Algorithm SHA256).Hash | Should -Be $packageBefore
            (Test-Path -LiteralPath (Join-Path $cache 'Packages\NewApp')) | Should -BeFalse
        }
    }

    It 'keeps merge-only files non-destructively while retiring ambiguous alias metadata' {
        InModuleScope OSDStage {
            $cache = Join-Path $TestDrive 'MergeOnlyRenameCache'
            $oldCatalog = New-ReconciliationCatalog -Root (Join-Path $TestDrive 'MergeOnlyRenameOld') -Definitions @(
                [pscustomobject]@{Id='OldApp';Version='1.0.0'}
            )
            $desiredCatalog = New-ReconciliationCatalog -Root (Join-Path $TestDrive 'MergeOnlyRenameNew') -Definitions @(
                [pscustomobject]@{Id='NewApp';Version='2.0.0';Aliases=@('OldApp')}
            )
            Sync-OSDStageCache -CatalogPath $oldCatalog -CachePath $cache -Confirm:$false | Out-Null

            Sync-OSDStageCache -CatalogPath $desiredCatalog -CachePath $cache -Name OldApp -Confirm:$false | Out-Null

            (Test-Path -LiteralPath (Join-Path $cache 'Packages\OldApp\Package.zip') -PathType Leaf) | Should -BeTrue
            (Test-Path -LiteralPath (Join-Path $cache 'Packages\NewApp\Package.zip') -PathType Leaf) | Should -BeTrue
            $cacheCatalog = Get-Content -LiteralPath (Join-Path $cache 'CacheCatalog.json') -Raw | ConvertFrom-Json
            @($cacheCatalog.Packages.Id) | Should -Be @('NewApp')
            @(Resolve-OSDStageCachedPackageId -CachePath $cache -Name OldApp) | Should -Be @('NewApp')

            $health = Get-OSDStageCacheHealth -CachePath $cache -CatalogPath $desiredCatalog
            @($health.Entries | Where-Object { $_.Id -eq 'OldApp' -and $_.State -eq 'Renamed' }).Count | Should -Be 1
        }
    }

    It 'rejects selective pruning and refuses invalid pinned content' {
        InModuleScope OSDStage {
            { Sync-OSDStageCache -CatalogPath 'missing.json' -CachePath (Join-Path $TestDrive 'NeverTouched') -Name AppA -Prune -Confirm:$false } |
                Should -Throw '*complete catalog synchronization*'

            $cache = Join-Path $TestDrive 'InvalidPinCache'
            $oldCatalog = New-ReconciliationCatalog -Root (Join-Path $TestDrive 'InvalidPinOld') -Definitions @(
                [pscustomobject]@{Id='PinnedApp';Version='1.0.0'}
            )
            $desiredCatalog = New-ReconciliationCatalog -Root (Join-Path $TestDrive 'InvalidPinNew') -Definitions @(
                [pscustomobject]@{Id='DesiredApp';Version='2.0.0'}
            )
            Sync-OSDStageCache -CatalogPath $oldCatalog -CachePath $cache -Confirm:$false | Out-Null
            Set-Content -LiteralPath (Join-Path $cache 'Packages\PinnedApp\Package.zip') -Value 'tampered' -Encoding ASCII

            { Sync-OSDStageCache -CatalogPath $desiredCatalog -CachePath $cache -Prune -PinnedId PinnedApp -Confirm:$false } |
                Should -Throw '*missing or corrupt*'
            (Test-Path -LiteralPath (Join-Path $cache 'Packages\PinnedApp\Package.zip')) | Should -BeTrue
            (Test-Path -LiteralPath (Join-Path $cache 'Packages\DesiredApp')) | Should -BeFalse
        }
    }

    It 'rejects alias and unknown pins before creating cache content' {
        InModuleScope OSDStage {
            $desiredCatalog = New-ReconciliationCatalog -Root (Join-Path $TestDrive 'RejectedPinRepository') -Definitions @(
                [pscustomobject]@{Id='NewApp';Version='2.0.0';Aliases=@('OldApp')}
            )
            $aliasCache = Join-Path $TestDrive 'RejectedAliasPinCache'
            $unknownCache = Join-Path $TestDrive 'RejectedUnknownPinCache'

            { Sync-OSDStageCache -CatalogPath $desiredCatalog -CachePath $aliasCache -Prune -PinnedId OldApp -Confirm:$false } |
                Should -Throw '*declared alias*canonical Id*'
            { Sync-OSDStageCache -CatalogPath $desiredCatalog -CachePath $unknownCache -Prune -PinnedId MissingApp -Confirm:$false } |
                Should -Throw '*not present in desired or existing cache state*'

            (Test-Path -LiteralPath $aliasCache) | Should -BeFalse
            (Test-Path -LiteralPath $unknownCache) | Should -BeFalse
        }
    }

    It 'rejects ambiguous compatible architecture variants' {
        InModuleScope OSDStage {
            $variants = @(
                [pscustomobject]@{Id='AppA';Architecture='x64';Version='1.0.0'},
                [pscustomobject]@{Id='AppA';Architecture='x64';Version='2.0.0'}
            )

            { Resolve-OSDStageCatalogPackageVariant -Package $variants -Architecture x64 } |
                Should -Throw '*more than one*x64*variant*'
        }
    }

    It 'can reconcile to an intentionally empty desired repository' {
        InModuleScope OSDStage {
            $cache = Join-Path $TestDrive 'EmptyDesiredCache'
            $oldCatalog = New-ReconciliationCatalog -Root (Join-Path $TestDrive 'EmptyDesiredOld') -Definitions @(
                [pscustomobject]@{Id='RetiredApp';Version='1.0.0'}
            )
            $emptyRoot = Join-Path $TestDrive 'EmptyDesiredRepository'
            New-Item -ItemType Directory -Path $emptyRoot -Force | Out-Null
            $emptyCatalog = Join-Path $emptyRoot 'catalog.json'
            @{SchemaVersion=2;GeneratedAt='2026-10-13T00:00:00Z';Packages=@()} |
                ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $emptyCatalog -Encoding UTF8
            Sync-OSDStageCache -CatalogPath $oldCatalog -CachePath $cache -Confirm:$false | Out-Null

            Sync-OSDStageCache -CatalogPath $emptyCatalog -CachePath $cache -Prune -Confirm:$false | Out-Null

            @((Get-ChildItem -LiteralPath (Join-Path $cache 'Packages') -Directory -ErrorAction SilentlyContinue)).Count | Should -Be 0
            $catalog = Get-Content -LiteralPath (Join-Path $cache 'CacheCatalog.json') -Raw | ConvertFrom-Json
            @($catalog.Packages).Count | Should -Be 0
        }
    }

    It 'honors WhatIf at the public repository synchronization boundary' {
        InModuleScope OSDStage {
            $cache = Join-Path $TestDrive 'PublicPreviewCache'
            Mock Get-OSDStageConfiguration { [pscustomobject]@{CatalogUri=[uri]'https://example.org/catalog.json'} }
            Mock Get-OSDStageCachePath { $cache }
            Mock Sync-OSDStageCache { throw 'Internal synchronization must not run during preview.' }

            Sync-OSDStageRepository -Prune -WhatIf | Out-Null

            Should -Invoke Sync-OSDStageCache -Exactly 0
            (Test-Path -LiteralPath $cache) | Should -BeFalse
        }
    }
}

Describe 'Named cache clearing' {
    BeforeAll {
        $script:moduleRoot = Split-Path -Parent $PSScriptRoot
        Import-Module (Join-Path $script:moduleRoot 'OSDStage.psd1') -Force
    }

    It 'clears matching retired built-in and repository identities without a hard-coded list' {
        InModuleScope OSDStage {
            $cache = Join-Path $TestDrive 'NamedClearCache'
            $builtIn = Join-Path $cache 'BuiltIn\RetiredApp'
            $repository = Join-Path $cache 'Packages\RetiredApp'
            New-Item -ItemType Directory -Path $builtIn,$repository -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $builtIn 'payload.bin') -Value 'built-in' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $repository 'Package.zip') -Value 'repository' -Encoding ASCII
            @{
                SchemaVersion=2;GeneratedAt='2026-10-13T00:00:00Z'
                Packages=@(@{Id='RetiredApp';Version='1.0.0';Architecture='x64';Payload=@{FileName='Package.zip';Sha256=('0' * 64)}})
            } | ConvertTo-Json -Depth 10 |
                Set-Content -LiteralPath (Join-Path $cache 'CacheCatalog.json') -Encoding UTF8
            Mock Get-OSDStageCachePath { $cache }

            Clear-OSDStageCache -Name RetiredApp -Confirm:$false | Out-Null

            (Test-Path -LiteralPath $builtIn) | Should -BeFalse
            (Test-Path -LiteralPath $repository) | Should -BeFalse
            $catalog = Get-Content -LiteralPath (Join-Path $cache 'CacheCatalog.json') -Raw | ConvertFrom-Json
            @($catalog.Packages).Count | Should -Be 0
        }
    }
}
