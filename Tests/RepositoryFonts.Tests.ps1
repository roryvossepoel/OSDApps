Describe 'Repository Font packages' {
    BeforeAll {
        $script:root = Split-Path $PSScriptRoot -Parent
        Import-Module (Join-Path $script:root 'OSDApps.psd1') -Force
    }

    BeforeEach {
        $script:source = Join-Path $TestDrive 'FontSource'
        $script:build = Join-Path $TestDrive 'FontBuild'
        $script:repo = Join-Path $TestDrive 'Repository'
        New-Item -ItemType Directory -Path (Join-Path $script:source 'Fonts') -Force | Out-Null
        [IO.File]::WriteAllBytes((Join-Path $script:source 'Fonts\Example-Regular.ttf'),[byte[]](0,1,2,3))
        [IO.File]::WriteAllBytes((Join-Path $script:source 'Fonts\Example-Bold.otf'),[byte[]](4,5,6,7))
    }

    It 'builds and validates a Font package without Install.ps1' {
        $package = New-OSDAppPackage -Id OrganisationFonts -Version 1.0.0 -PackageType Font -SourcePath $script:source -OutputPath $script:build
        $package.PackageType | Should -Be 'Font'
        $validation = Test-OSDAppPackage -PackagePath $package.PackagePath -PackageType Font
        $validation.Valid | Should -BeTrue
        $validation.InstallPs1Exists | Should -BeFalse
        $validation.FontFileCount | Should -Be 2
    }

    It 'does not relax App or Script package requirements' {
        { New-OSDAppPackage -Id BadApp -Version 1.0.0 -PackageType App -SourcePath $script:source -OutputPath $script:build } | Should -Throw '*Install.ps1*'
        { New-OSDAppPackage -Id BadScript -Version 1.0.0 -PackageType Script -SourcePath $script:source -OutputPath $script:build } | Should -Throw '*Install.ps1*'
    }

    It 'rejects a Font package with only unsupported font formats' {
        Remove-Item -LiteralPath (Join-Path $script:source 'Fonts') -Recurse -Force
        New-Item -ItemType Directory -Path (Join-Path $script:source 'Fonts') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:source 'Fonts\Legacy.ttc') -Value 'unsupported' -Encoding ASCII
        { New-OSDAppPackage -Id LegacyFonts -Version 1.0.0 -PackageType Font -SourcePath $script:source -OutputPath $script:build } | Should -Throw '*.ttf or .otf*'
    }

    It 'publishes, validates and resolves PackageType Font end to end' {
        New-OSDAppRepository -Path $script:repo | Out-Null
        $package = New-OSDAppPackage -Id OrganisationFonts -Version 1.0.0 -PackageType Font -SourcePath $script:source -OutputPath $script:build
        Add-OSDAppPackage -Id OrganisationFonts -DisplayName 'Organisation Fonts' -Version 1.0.0 -Architecture any -PackageType Font -PackagePath $package.PackagePath -RepositoryPath $script:repo | Out-Null
        $validation = @(Test-OSDAppRepository -RepositoryPath $script:repo)
        $validation.Count | Should -Be 1
        $validation[0].Valid | Should -BeTrue
        $validation[0].PackageType | Should -Be 'Font'
        $validation[0].PackageValid | Should -BeTrue
        InModuleScope OSDApps -Parameters @{ Catalog=(Join-Path $script:repo 'catalog.json') } {
            $resolved = @(Get-OSDAppCatalogPackages -CatalogPath $Catalog)
            $resolved.Count | Should -Be 1
            $resolved[0].PackageType | Should -Be 'Font'
        }
    }

    It 'preserves an existing Font type when republishing without PackageType' {
        New-OSDAppRepository -Path $script:repo | Out-Null
        $package = New-OSDAppPackage -Id OrganisationFonts -Version 1.0.0 -PackageType Font -SourcePath $script:source -OutputPath $script:build
        $parameters = @{Id='OrganisationFonts';DisplayName='Organisation Fonts';Version='1.0.0';Architecture='any';PackageType='Font';PackagePath=$package.PackagePath;RepositoryPath=$script:repo}
        Add-OSDAppPackage @parameters | Out-Null
        $parameters.Remove('PackageType')
        Add-OSDAppPackage @parameters | Out-Null
        $manifest = Get-Content (Join-Path $script:repo 'Apps\OrganisationFonts\1.0.0\any\manifest.json') -Raw | ConvertFrom-Json
        $manifest.PackageType | Should -Be 'Font'
    }

    It 'Add-OSDAppFont accepts only Repository Font packages and delegates staging' {
        InModuleScope OSDApps {
            Mock Assert-OSDAppSourceEnabled {}
            Mock Get-OSDApp { [pscustomobject]@{Id='OrganisationFonts';Source='Repository';PackageType='Font'} }
            Mock Add-OSDApp { [pscustomobject]@{Name='OrganisationFonts';Source='Repository';PackageType='Font'} }
            $result = Add-OSDAppFont -Id OrganisationFonts -WindowsPath 'C:\' -SkipCacheRefresh
            $result.PackageType | Should -Be 'Font'
            Should -Invoke Add-OSDApp -Exactly 1 -ParameterFilter { $Name -contains 'OrganisationFonts' -and $WindowsPath -eq 'C:\' -and $SkipCacheRefresh }
        }
    }

    It 'Add-OSDAppFont rejects a non-Font repository package' {
        InModuleScope OSDApps {
            Mock Assert-OSDAppSourceEnabled {}
            Mock Get-OSDApp { [pscustomobject]@{Id='ExampleApp';Source='Repository';PackageType='App'} }
            Mock Add-OSDApp { throw 'must not stage' }
            { Add-OSDAppFont -Id ExampleApp } | Should -Throw '*not Font*'
            Should -Invoke Add-OSDApp -Exactly 0
        }
    }

    It 'Runner owns Font installation and never requires Install.ps1 for Font packages' {
        $source = Get-Content (Join-Path $script:root 'Runtime\Invoke-OSDAppRunner.ps1') -Raw
        $source | Should -Match "PackageType -eq 'Font'"
        $source | Should -Match "Extension\.ToLowerInvariant\(\) -in @\('\.ttf','\.otf'\)"
        $source | Should -Match "Join-Path \$env:SystemRoot 'Fonts'"
        $source | Should -Match 'CurrentVersion\\Fonts'
        $source | Should -Match 'AddFontResourceW'
        $source | Should -Match 'WM_FONTCHANGE'
        $source | Should -Match "Outcome = 'AlreadyPresent'"
        $source | Should -Match 'Duplicate font filename'
        $source | Should -Match 'different content'
    }

    It 'Viewer reports Font separately from App and Script' {
        InModuleScope OSDApps {
            (Get-OSDAppUIPackageType -App ([pscustomobject]@{PackageType='Font'})) | Should -Be 'Font'
            (Get-OSDAppUIPackageType -App ([pscustomobject]@{PackageType='Script'})) | Should -Be 'Script'
            (Get-OSDAppUIPackageType -App ([pscustomobject]@{})) | Should -Be 'App'
        }
    }
}
