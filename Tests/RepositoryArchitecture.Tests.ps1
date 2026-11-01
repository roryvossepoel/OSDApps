Describe 'Repository target architecture' {
    BeforeAll {
        $root = Split-Path $PSScriptRoot -Parent
        Remove-Module OSDStage -Force -ErrorAction SilentlyContinue
        Import-Module (Join-Path $root 'OSDStage.psd1') -Force
    }
    BeforeEach {
        InModuleScope OSDStage {
            $script:architectureTestRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            $script:architectureTestSource = Join-Path $architectureTestRoot 'Repository'
            $script:architectureTestCache = Join-Path $architectureTestRoot 'Cache'
            $script:architectureTestCatalog = Join-Path $architectureTestSource 'catalog.json'
            $apps = @()
            foreach ($id in @('AppA','NeutralScript')) {
                $variants = if ($id -eq 'AppA') { @('x64','arm64','any') } else { @('any') }
                $references = @()
                foreach ($variant in $variants) {
                    $relative = "Packages/$id/1.0.0/$variant"
                    $packageRoot = Join-Path $architectureTestSource $relative
                    New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null
                    $archive = Join-Path $packageRoot 'Package.zip'
                    Set-Content -LiteralPath $archive -Value "payload-$id-$variant" -Encoding ASCII
                    @{
                        SchemaVersion=2; Id=$id; DisplayName=$id; Version='1.0.0'; Architecture=$variant
                        PackageType=$(if ($id -eq 'NeutralScript') { 'Script' } else { 'App' }); SuccessCodes=@(0)
                        Payload=@{FileName='Package.zip';Sha256=(Get-FileHash $archive -Algorithm SHA256).Hash}
                    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $packageRoot 'manifest.json') -Encoding UTF8
                    $references += @{Architecture=$variant;Manifest="$relative/manifest.json"}
                }
                $apps += @{Id=$id;Architectures=$references}
            }
            @{SchemaVersion=2;GeneratedAt='2026-10-16T00:00:00Z';Packages=$apps} | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $architectureTestCatalog -Encoding UTF8
            Mock Get-OSDStageHostArchitecture { 'arm64' }
        }
    }
    It 'prepares exact x64 and neutral script variants on an ARM64 host and checks matching desired state' {
        InModuleScope OSDStage {
            Sync-OSDStageCache -CatalogPath $architectureTestCatalog -CachePath $architectureTestCache -Architecture x64 -Confirm:$false | Out-Null
            $catalog = Get-Content (Join-Path $architectureTestCache 'CacheCatalog.json') -Raw | ConvertFrom-Json
            ($catalog.Packages | Where-Object Id -eq AppA).Architecture | Should -Be x64
            ($catalog.Packages | Where-Object Id -eq NeutralScript).Architecture | Should -Be any
            ($catalog.Packages | Where-Object Id -eq NeutralScript).PackageType | Should -Be Script
            (Get-Content (Join-Path $architectureTestCache 'Packages/AppA/Package.zip') -Raw).Trim() | Should -Be payload-AppA-x64
            (Get-OSDStageCacheHealth -CachePath $architectureTestCache -CatalogPath $architectureTestCatalog -Architecture x64).Healthy | Should -BeTrue
            (Get-OSDStageCacheHealth -CachePath $architectureTestCache -CatalogPath $architectureTestCatalog).Healthy | Should -BeFalse
            (Get-OSDStageCacheHealth -CachePath $architectureTestCache -Offline).Healthy | Should -BeTrue
        }
    }
    It 'preserves host defaults and replaces only the requested Id when switching architecture' {
        InModuleScope OSDStage {
            Sync-OSDStageCache -CatalogPath $architectureTestCatalog -CachePath $architectureTestCache -Confirm:$false | Out-Null
            $catalog = Get-Content (Join-Path $architectureTestCache 'CacheCatalog.json') -Raw | ConvertFrom-Json
            ($catalog.Packages | Where-Object Id -eq AppA).Architecture | Should -Be arm64
            $neutral = Join-Path $architectureTestCache 'Packages/NeutralScript/Package.zip'
            $before = (Get-FileHash $neutral).Hash
            Sync-OSDStageCache -CatalogPath $architectureTestCatalog -CachePath $architectureTestCache -Name AppA -Architecture x64 -Confirm:$false | Out-Null
            $catalog = Get-Content (Join-Path $architectureTestCache 'CacheCatalog.json') -Raw | ConvertFrom-Json
            @($catalog.Packages).Count | Should -Be 2
            ($catalog.Packages | Where-Object Id -eq AppA).Architecture | Should -Be x64
            (Get-FileHash $neutral).Hash | Should -Be $before
            @(Get-ChildItem (Join-Path $architectureTestCache '.staging') -Force).Count | Should -Be 0
        }
    }
    It 'preserves the complete existing cache when the requested variant is missing' {
        InModuleScope OSDStage {
            Sync-OSDStageCache -CatalogPath $architectureTestCatalog -CachePath $architectureTestCache -Confirm:$false | Out-Null
            $source = Get-Content $architectureTestCatalog -Raw | ConvertFrom-Json
            $source.Packages[0].Architectures = @($source.Packages[0].Architectures | Where-Object Architecture -eq arm64)
            $source | ConvertTo-Json -Depth 15 | Set-Content $architectureTestCatalog -Encoding UTF8
            $before = @(Get-ChildItem $architectureTestCache -File -Recurse | Get-FileHash | ForEach-Object { "$($_.Path):$($_.Hash)" } | Sort-Object)
            { Sync-OSDStageCache -CatalogPath $architectureTestCatalog -CachePath $architectureTestCache -Architecture x64 -Confirm:$false } | Should -Throw '*No compatible package variant*'
            $after = @(Get-ChildItem $architectureTestCache -File -Recurse | Get-FileHash | ForEach-Object { "$($_.Path):$($_.Hash)" } | Sort-Object)
            @(Compare-Object $before $after).Count | Should -Be 0
        }
    }
    It 'preserves the previous architecture when a replacement fails hash validation' {
        InModuleScope OSDStage {
            Sync-OSDStageCache -CatalogPath $architectureTestCatalog -CachePath $architectureTestCache -Confirm:$false | Out-Null
            $cacheCatalog = Join-Path $architectureTestCache 'CacheCatalog.json'
            $cachedArchive = Join-Path $architectureTestCache 'Packages/AppA/Package.zip'
            $beforeCatalog = (Get-FileHash $cacheCatalog).Hash
            $beforeArchive = (Get-FileHash $cachedArchive).Hash
            Set-Content (Join-Path $architectureTestSource 'Packages/AppA/1.0.0/x64/Package.zip') 'corrupt replacement'
            { Sync-OSDStageCache -CatalogPath $architectureTestCatalog -CachePath $architectureTestCache -Architecture x64 -Confirm:$false } | Should -Throw '*SHA-256 validation failed*'
            (Get-FileHash $cacheCatalog).Hash | Should -Be $beforeCatalog
            (Get-FileHash $cachedArchive).Hash | Should -Be $beforeArchive
            @(Get-ChildItem (Join-Path $architectureTestCache '.staging') -Force).Count | Should -Be 0
        }
    }
    It 'keeps WhatIf read-only and prunes against the explicitly selected architecture' {
        InModuleScope OSDStage {
            Sync-OSDStageCache -CatalogPath $architectureTestCatalog -CachePath $architectureTestCache -Confirm:$false | Out-Null
            $source = Get-Content $architectureTestCatalog -Raw | ConvertFrom-Json
            $source.Packages = @($source.Packages | Where-Object Id -eq AppA)
            $source | ConvertTo-Json -Depth 15 | Set-Content $architectureTestCatalog -Encoding UTF8
            $before = @(Get-ChildItem $architectureTestCache -File -Recurse | Get-FileHash | ForEach-Object { "$($_.Path):$($_.Hash)" } | Sort-Object)
            Sync-OSDStageCache -CatalogPath $architectureTestCatalog -CachePath $architectureTestCache -Architecture x64 -Prune -WhatIf | Out-Null
            $after = @(Get-ChildItem $architectureTestCache -File -Recurse | Get-FileHash | ForEach-Object { "$($_.Path):$($_.Hash)" } | Sort-Object)
            @(Compare-Object $before $after).Count | Should -Be 0
            Sync-OSDStageCache -CatalogPath $architectureTestCatalog -CachePath $architectureTestCache -Architecture x64 -Prune -Confirm:$false | Out-Null
            Test-Path (Join-Path $architectureTestCache 'Packages/NeutralScript') | Should -BeFalse
            $health = Get-OSDStageCacheHealth -CachePath $architectureTestCache -CatalogPath $architectureTestCatalog -Architecture x64
            $health.Healthy | Should -BeTrue
            $health.EntryCount | Should -Be 1
        }
    }
    It 'forwards the optional public target without making it a persistent setting' {
        InModuleScope OSDStage {
            Mock Get-OSDStageConfiguration { [pscustomobject]@{CatalogUri=[uri]'https://example.test/catalog.json'} }
            Mock Get-OSDStageCachePath { $architectureTestCache }
            Mock Sync-OSDStageCache { }
            Sync-OSDStageRepository -Name AppA -Architecture x64 -Confirm:$false
            Sync-OSDStageRepository -Name AppA -Architecture arm64 -Confirm:$false
            Sync-OSDStageRepository -Name AppA -Confirm:$false
            Should -Invoke Sync-OSDStageCache -Times 1 -Exactly -ParameterFilter { $Architecture -eq 'x64' }
            Should -Invoke Sync-OSDStageCache -Times 1 -Exactly -ParameterFilter { $Architecture -eq 'arm64' }
            Should -Invoke Sync-OSDStageCache -Times 1 -Exactly -ParameterFilter { -not $Architecture }
            Sync-OSDStageRepository -Architecture x64 -WhatIf
            Should -Invoke Sync-OSDStageCache -Times 3 -Exactly
            { Sync-OSDStageRepository -Architecture any -Confirm:$false } | Should -Throw
            { Get-OSDStageCacheHealth -Architecture x86 } | Should -Throw
        }
    }
}
