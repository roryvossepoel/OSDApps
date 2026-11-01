Describe 'Optional repository Vendor metadata' {
    BeforeAll {
        $script:root = Split-Path $PSScriptRoot -Parent
        Import-Module (Join-Path $script:root 'OSDStage.psd1') -Force
    }

    It 'publishes Vendor and preserves it through catalog, USB cache and device manifest' {
        InModuleScope OSDStage {
            $payload = Join-Path $TestDrive 'Payload\Package'
            $build = Join-Path $TestDrive 'Build'
            $repo = Join-Path $TestDrive 'Repository'
            $cache = Join-Path $TestDrive 'Cache'
            $target = Join-Path $TestDrive 'Target'
            New-Item -ItemType Directory -Force -Path $payload,$build,$repo,$cache,$target | Out-Null
            Set-Content -LiteralPath (Join-Path $payload 'Install.ps1') -Value 'exit 0' -Encoding UTF8
            $zip = Join-Path $build 'Package.zip'
            Compress-Archive -Path $payload -DestinationPath $zip -Force
            $originalHash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash

            $published = Add-OSDStagePackage -Id SampleApp -DisplayName 'Sample App' -Vendor 'Example Publisher' -Version '1.2.3' -PackagePath $zip -RepositoryPath $repo -Architecture x64 -PackageType Script -Confirm:$false
            $published.Vendor | Should -Be 'Example Publisher'
            $published.PackageType | Should -Be 'Script'
            $manifest = Get-Content -LiteralPath (Join-Path $repo 'Packages\SampleApp\1.2.3\x64\manifest.json') -Raw | ConvertFrom-Json
            $manifest.Vendor | Should -Be 'Example Publisher'
            $manifest.PackageType | Should -Be 'Script'
            $manifest.Payload.Sha256 | Should -Be $originalHash

            $catalog = Get-OSDStageCatalogPackages -CatalogPath (Join-Path $repo 'catalog.json')
            @($catalog.Packages).Count | Should -Be 1
            $catalog.Packages[0].Vendor | Should -Be 'Example Publisher'
            $catalog.Packages[0].PackageType | Should -Be 'Script'

            Mock Get-OSDStageHostArchitecture { 'x64' }
            Sync-OSDStageCache -CatalogPath (Join-Path $repo 'catalog.json') -CachePath $cache -Confirm:$false | Out-Null
            $cachedCatalog = Get-Content -LiteralPath (Join-Path $cache 'CacheCatalog.json') -Raw | ConvertFrom-Json
            $cachedCatalog.Packages[0].Vendor | Should -Be 'Example Publisher'
            $cachedCatalog.Packages[0].PackageType | Should -Be 'Script'

            $script:VendorTestCacheRoot = $cache
            Mock Get-OSDStageCachePath { $script:VendorTestCacheRoot }
            $entry = @(Get-OSDStageCache -Name SampleApp)
            $entry.Count | Should -Be 1
            $entry[0].Vendor | Should -Be 'Example Publisher'
            $entry[0].DisplayName | Should -Be 'Sample App'
            $entry[0].PackageType | Should -Be 'Script'
            $entry[0].Valid | Should -BeTrue

            Copy-OSDStageContent -Name @('SampleApp') -CachePath $cache -WindowsPath $target -Confirm:$false | Out-Null
            $device = Get-Content -LiteralPath (Join-Path $target 'Windows\Temp\OSDStage\DeviceManifest.json') -Raw | ConvertFrom-Json
            @($device.Packages).Count | Should -Be 1
            $device.Packages[0].Vendor | Should -Be 'Example Publisher'
            $device.Packages[0].DisplayName | Should -Be 'Sample App'
            $device.Packages[0].PackageType | Should -Be 'Script'
            (Get-FileHash -LiteralPath (Join-Path $cache 'Packages\SampleApp\Package.zip') -Algorithm SHA256).Hash | Should -Be $originalHash
        }
    }

    It 'keeps older packages without Vendor compatible' {
        InModuleScope OSDStage {
            $payload = Join-Path $TestDrive 'LegacyPayload\Package'
            $build = Join-Path $TestDrive 'LegacyBuild'
            $repo = Join-Path $TestDrive 'LegacyRepo'
            New-Item -ItemType Directory -Force -Path $payload,$build,$repo | Out-Null
            Set-Content -LiteralPath (Join-Path $payload 'Install.ps1') -Value 'exit 0' -Encoding UTF8
            $zip = Join-Path $build 'Package.zip'
            Compress-Archive -Path $payload -DestinationPath $zip -Force

            Add-OSDStagePackage -Id LegacyApp -DisplayName 'Legacy App' -Version '1.0.0' -PackagePath $zip -RepositoryPath $repo -Architecture x64 -Confirm:$false | Out-Null
            $manifest = Get-Content -LiteralPath (Join-Path $repo 'Packages\LegacyApp\1.0.0\x64\manifest.json') -Raw | ConvertFrom-Json
            $manifest.PSObject.Properties.Name | Should -Not -Contain 'Vendor'
            $catalog = Get-OSDStageCatalogPackages -CatalogPath (Join-Path $repo 'catalog.json')
            $catalog.Packages[0].Vendor | Should -BeNullOrEmpty
            $catalog.Packages[0].PackageType | Should -Be 'App'
        }
    }
}
