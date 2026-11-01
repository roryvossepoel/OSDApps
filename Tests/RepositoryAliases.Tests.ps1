Describe 'Repository canonical Id and alias contract' {
    BeforeAll {
        $script:moduleRoot = Split-Path -Parent $PSScriptRoot
        Remove-Module OSDStage -Force -ErrorAction SilentlyContinue
        Import-Module (Join-Path $script:moduleRoot 'OSDStage.psd1') -Force

        function global:New-AliasCatalogFixture {
            param(
                [Parameter(Mandatory)][string]$Root,
                [Parameter(Mandatory)][object[]]$Definitions
            )

            $apps = @()
            foreach ($definition in $Definitions) {
                $id = [string]$definition.Id
                $packageRoot = Join-Path $Root "Packages\$id\1.0.0\x64"
                New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null
                $archive = Join-Path $packageRoot 'Package.zip'
                Set-Content -LiteralPath $archive -Value $id -Encoding ASCII
                @{
                    SchemaVersion=2;Id=$id;DisplayName=$id;Version='1.0.0';Architecture='x64';SuccessCodes=@(0)
                    Payload=@{FileName='Package.zip';Sha256=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash}
                } | ConvertTo-Json -Depth 10 |
                    Set-Content -LiteralPath (Join-Path $packageRoot 'manifest.json') -Encoding UTF8
                $app = [ordered]@{
                    Id=$id
                    Architectures=@(@{Architecture='x64';Manifest="Packages/$id/1.0.0/x64/manifest.json"})
                }
                if ($definition.PSObject.Properties.Name -contains 'Aliases') { $app['Aliases'] = @($definition.Aliases) }
                $apps += [pscustomobject]$app
            }
            $catalogPath = Join-Path $Root 'catalog.json'
            @{SchemaVersion=2;GeneratedAt='2026-10-13T00:00:00Z';Packages=$apps} |
                ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $catalogPath -Encoding UTF8
            $catalogPath
        }
    }

    AfterAll {
        Remove-Item Function:\New-AliasCatalogFixture -ErrorAction SilentlyContinue
    }

    It 'resolves a requested alias to one canonical package' {
        InModuleScope OSDStage {
            $catalogPath = New-AliasCatalogFixture -Root (Join-Path $TestDrive 'AliasCatalog') -Definitions @(
                [pscustomobject]@{Id='NewApp';Aliases=@('OldApp')}
            )

            $catalog = Get-OSDStageCatalogPackages -CatalogPath $catalogPath -Name OldApp

            @($catalog.Packages).Count | Should -Be 1
            $catalog.Packages[0].Id | Should -Be 'NewApp'
            @($catalog.Packages[0].Aliases) | Should -Be @('OldApp')
        }
    }

    It 'rejects aliases that collide with canonical Ids or have multiple owners' {
        InModuleScope OSDStage {
            $canonicalConflict = New-AliasCatalogFixture -Root (Join-Path $TestDrive 'CanonicalConflict') -Definitions @(
                [pscustomobject]@{Id='AppA';Aliases=@('AppB')},
                [pscustomobject]@{Id='AppB'}
            )
            { Get-OSDStageCatalogPackages -CatalogPath $canonicalConflict } |
                Should -Throw '*conflicts with a canonical app Id*'

            $ownerConflict = New-AliasCatalogFixture -Root (Join-Path $TestDrive 'OwnerConflict') -Definitions @(
                [pscustomobject]@{Id='AppA';Aliases=@('OldApp')},
                [pscustomobject]@{Id='AppB';Aliases=@('OldApp')}
            )
            { Get-OSDStageCatalogPackages -CatalogPath $ownerConflict } |
                Should -Throw '*assigned to both*'
        }
    }

    It 'publishes aliases, preserves omission and removes an explicitly empty Alias' {
        $source = Join-Path $TestDrive 'AliasSource'
        $buildOne = Join-Path $TestDrive 'AliasBuildOne'
        $buildTwo = Join-Path $TestDrive 'AliasBuildTwo'
        $buildThree = Join-Path $TestDrive 'AliasBuildThree'
        $repository = Join-Path $TestDrive 'AliasRepository'
        New-Item -ItemType Directory -Path $source -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $source 'Install.ps1') -Value 'exit 0' -Encoding UTF8

        $first = New-OSDStagePackage -Id NewApp -Version 1.0.0 -SourcePath $source -OutputPath $buildOne -Confirm:$false
        Add-OSDStagePackage -Id NewApp -DisplayName 'New App' -Version 1.0.0 -PackagePath $first.PackagePath `
            -RepositoryPath $repository -Alias OldApp -Confirm:$false | Out-Null
        $second = New-OSDStagePackage -Id NewApp -Version 2.0.0 -SourcePath $source -OutputPath $buildTwo -Confirm:$false
        Add-OSDStagePackage -Id NewApp -DisplayName 'New App' -Version 2.0.0 -PackagePath $second.PackagePath `
            -RepositoryPath $repository -Confirm:$false | Out-Null

        $catalog = Get-Content -LiteralPath (Join-Path $repository 'catalog.json') -Raw | ConvertFrom-Json
        @($catalog.Packages).Count | Should -Be 1
        @($catalog.Packages[0].Aliases) | Should -Be @('OldApp')
        $catalog.Packages[0].Architectures[0].Manifest | Should -Be 'Packages/NewApp/2.0.0/x64/manifest.json'

        $third = New-OSDStagePackage -Id NewApp -Version 3.0.0 -SourcePath $source -OutputPath $buildThree -Confirm:$false
        Add-OSDStagePackage -Id NewApp -DisplayName 'New App' -Version 3.0.0 -PackagePath $third.PackagePath `
            -RepositoryPath $repository -Alias @() -Confirm:$false | Out-Null

        $catalog = Get-Content -LiteralPath (Join-Path $repository 'catalog.json') -Raw | ConvertFrom-Json
        $catalog.Packages[0].PSObject.Properties.Name | Should -Not -Contain 'Aliases'
        $catalog.Packages[0].Architectures[0].Manifest | Should -Be 'Packages/NewApp/3.0.0/x64/manifest.json'
    }

    It 'discovers a canonical cached app through its retired alias' {
        InModuleScope OSDStage {
            $cache = Join-Path $TestDrive 'AliasDiscoveryCache'
            $packageRoot = Join-Path $cache 'Packages\NewApp'
            New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null
            $archive = Join-Path $packageRoot 'Package.zip'
            Set-Content -LiteralPath $archive -Value 'package' -Encoding ASCII
            @{
                SchemaVersion=2;GeneratedAt='2026-10-13T00:00:00Z'
                Packages=@(@{
                    Id='NewApp';Aliases=@('OldApp');DisplayName='New App';Version='2.0.0';Architecture='x64'
                    Payload=@{FileName='Package.zip';Sha256=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash}
                })
            } | ConvertTo-Json -Depth 10 |
                Set-Content -LiteralPath (Join-Path $cache 'CacheCatalog.json') -Encoding UTF8
            Mock Get-OSDStageCachePath { $cache }

            $apps = @(Get-OSDStage -Offline -Name OldApp)

            $apps.Count | Should -Be 1
            $apps[0].Id | Should -Be 'NewApp'
            @($apps[0].Aliases) | Should -Be @('OldApp')
        }
    }

    It 'rejects an authoring alias already owned by another app without changing the catalog' {
        $source = Join-Path $TestDrive 'ConflictSource'
        $repository = Join-Path $TestDrive 'ConflictRepository'
        New-Item -ItemType Directory -Path $source -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $source 'Install.ps1') -Value 'exit 0' -Encoding UTF8
        $appA = New-OSDStagePackage -Id AppA -Version 1.0.0 -SourcePath $source -OutputPath (Join-Path $TestDrive 'ConflictBuildA') -Confirm:$false
        $appB = New-OSDStagePackage -Id AppB -Version 1.0.0 -SourcePath $source -OutputPath (Join-Path $TestDrive 'ConflictBuildB') -Confirm:$false
        Add-OSDStagePackage -Id AppA -DisplayName 'App A' -Version 1.0.0 -PackagePath $appA.PackagePath `
            -RepositoryPath $repository -Alias OldApp -Confirm:$false | Out-Null
        $before = (Get-FileHash -LiteralPath (Join-Path $repository 'catalog.json') -Algorithm SHA256).Hash

        { Add-OSDStagePackage -Id AppB -DisplayName 'App B' -Version 1.0.0 -PackagePath $appB.PackagePath `
            -RepositoryPath $repository -Alias OldApp -Confirm:$false } |
            Should -Throw '*already assigned*'

        (Get-FileHash -LiteralPath (Join-Path $repository 'catalog.json') -Algorithm SHA256).Hash | Should -Be $before
        (Test-Path -LiteralPath (Join-Path $repository 'Packages\AppB')) | Should -BeFalse
    }
}
