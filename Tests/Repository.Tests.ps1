Describe 'Repository authoring and validation' {
    BeforeAll {
        $script:moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $script:manifestPath = Join-Path $script:moduleRoot 'OSDStage.psd1'
        Remove-Module OSDStage -Force -ErrorAction SilentlyContinue
        Import-Module $script:manifestPath -Force
    }

    BeforeEach {
        $script:testRoot = Join-Path $TestDrive 'RepositoryTest'
        $script:source = Join-Path $script:testRoot 'Source'
        $script:build = Join-Path $script:testRoot 'Build'
        $script:repository = Join-Path $script:testRoot 'Repository'
        New-Item -ItemType Directory -Path $script:source -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:source 'Install.ps1') -Value 'exit 0' -Encoding UTF8
    }

    It 'creates a valid repository package end to end' {
        New-OSDStageRepository -Path $script:repository | Out-Null
        $package = New-OSDStagePackage -Id ExampleApp -Version 1.0.0 -SourcePath $script:source -OutputPath $script:build
        Add-OSDStagePackage -Id ExampleApp -DisplayName 'Example App' -Version 1.0.0 -Architecture x64 -PackagePath $package.PackagePath -RepositoryPath $script:repository | Out-Null

        $result = @(Test-OSDStageRepository -RepositoryPath $script:repository)

        $result.Count | Should -Be 1
        $result[0].Valid | Should -BeTrue
        $result[0].HashValid | Should -BeTrue
        $result[0].PackageValid | Should -BeTrue
        $result[0].SuccessCodesValid | Should -BeTrue
        $result[0].PackageType | Should -Be 'App'
        $result[0].PackageTypeValid | Should -BeTrue
        $result[0].PayloadDefinitionValid | Should -BeTrue
        $result[0].Orphaned | Should -BeFalse
    }

    It 'rejects an unsupported package type' {
        New-OSDStageRepository -Path $script:repository | Out-Null
        $package = New-OSDStagePackage -Id ExampleApp -Version 1.0.0 -SourcePath $script:source -OutputPath $script:build
        Add-OSDStagePackage -Id ExampleApp -DisplayName 'Example App' -Version 1.0.0 -Architecture x64 -PackagePath $package.PackagePath -RepositoryPath $script:repository | Out-Null
        $manifestPath = Join-Path $script:repository 'Packages\ExampleApp\1.0.0\x64\manifest.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $manifest.PackageType = 'Registry'
        $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

        $result = @(Test-OSDStageRepository -RepositoryPath $script:repository)
        $result[0].PackageType | Should -Be 'Registry'
        $result[0].PackageTypeValid | Should -BeFalse
        $result[0].Valid | Should -BeFalse
        $catalogPath = Join-Path $script:repository 'catalog.json'
        InModuleScope OSDStage -Parameters @{ CatalogPath = $catalogPath } {
            { Get-OSDStageCatalogPackages -CatalogPath $CatalogPath } |
                Should -Throw '*unsupported PackageType*'
        }
    }

    It 'preserves an existing script type when republishing without PackageType' {
        New-OSDStageRepository -Path $script:repository | Out-Null
        $package = New-OSDStagePackage -Id ExampleScript -Version 1.0.0 -SourcePath $script:source -OutputPath $script:build
        $publishParameters = @{
            Id             = 'ExampleScript'
            DisplayName    = 'Example Script'
            Version        = '1.0.0'
            Architecture   = 'x64'
            PackagePath    = $package.PackagePath
            RepositoryPath = $script:repository
            PackageType    = 'Script'
        }
        Add-OSDStagePackage @publishParameters | Out-Null
        $publishParameters.Remove('PackageType')
        Add-OSDStagePackage @publishParameters | Out-Null

        $manifestPath = Join-Path $script:repository 'Packages\ExampleScript\1.0.0\x64\manifest.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $manifest.PackageType | Should -Be 'Script'
    }

    It 'detects an orphaned manifest' {
        New-OSDStageRepository -Path $script:repository | Out-Null
        $orphan = Join-Path $script:repository 'Packages\Orphan\1.0.0\x64'
        New-Item -ItemType Directory -Path $orphan -Force | Out-Null
        @{
            SchemaVersion = 2
            Id = 'Orphan'
            DisplayName = 'Orphan'
            Version = '1.0.0'
            Architecture = 'x64'
            SuccessCodes = @(0)
            Payload = @{ FileName='Package.zip'; Sha256=('0' * 64) }
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $orphan 'manifest.json') -Encoding UTF8

        $result = @(Test-OSDStageRepository -RepositoryPath $script:repository)
        @($result | Where-Object Orphaned).Count | Should -Be 1
    }
}
