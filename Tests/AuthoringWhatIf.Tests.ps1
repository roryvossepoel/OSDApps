Describe 'Repository authoring -WhatIf safety (#17)' {
    BeforeAll {
        $root = Split-Path $PSScriptRoot -Parent
        Import-Module (Join-Path $root 'OSDApps.psd1') -Force
    }

    BeforeEach {
        $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:source = Join-Path $script:root 'Source'
        $script:build = Join-Path $script:root 'Build'
        $script:repo = Join-Path $script:root 'Repository'
        New-Item -ItemType Directory -Path $script:source -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:source 'Install.ps1') -Value 'exit 0' -Encoding UTF8
    }

    It 'does not create an archive or output directory when previewing a new package' {
        $outcome = @(New-OSDAppPackage -Id ExampleApp -Version 1.0.0 -SourcePath $script:source -OutputPath $script:build -WhatIf)
        Test-Path -LiteralPath $script:build | Should -BeFalse
        $outcome.Count | Should -Be 0
    }

    It 'does not alter an existing package archive or advertise a newly built package under WhatIf' {
        New-Item -ItemType Directory -Path $script:build -Force | Out-Null
        $archive = Join-Path $script:build 'Package.zip'
        [IO.File]::WriteAllBytes($archive, [byte[]](1,2,3,4,5))
        $before = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
        $outcome = @(New-OSDAppPackage -Id ExampleApp -Version 2.0.0 -SourcePath $script:source -OutputPath $script:build -WhatIf)
        (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash | Should -Be $before
        $outcome.Count | Should -Be 0
    }

    It 'does not create a repository or a catalog when previewing a new package publication' {
        $package = New-OSDAppPackage -Id ExampleApp -Version 1.0.0 -SourcePath $script:source -OutputPath $script:build
        $outcome = @(Add-OSDAppPackage -Id ExampleApp -DisplayName 'Example' -Version 1.0.0 -PackagePath $package.PackagePath -RepositoryPath $script:repo -WhatIf)
        Test-Path -LiteralPath $script:repo | Should -BeFalse
        $outcome.Count | Should -Be 0
    }

    It 'preserves an existing repository and its catalog when previewing another version' {
        $package = New-OSDAppPackage -Id ExampleApp -Version 1.0.0 -SourcePath $script:source -OutputPath $script:build
        New-OSDAppRepository -Path $script:repo | Out-Null
        Add-OSDAppPackage -Id ExampleApp -DisplayName 'Example' -Version 1.0.0 -PackagePath $package.PackagePath -RepositoryPath $script:repo | Out-Null
        $catalog = Join-Path $script:repo 'catalog.json'
        $original = (Get-FileHash -LiteralPath $catalog -Algorithm SHA256).Hash
        $published = Join-Path $script:repo 'Apps\ExampleApp\1.0.0\x64\Package.zip'
        $originalZip = (Get-FileHash -LiteralPath $published -Algorithm SHA256).Hash

        $outcome = @(Add-OSDAppPackage -Id ExampleApp -DisplayName 'Changed' -Version 2.0.0 -PackagePath $package.PackagePath -RepositoryPath $script:repo -WhatIf)

        (Get-FileHash -LiteralPath $catalog -Algorithm SHA256).Hash | Should -Be $original
        (Get-FileHash -LiteralPath $published -Algorithm SHA256).Hash | Should -Be $originalZip
        Test-Path -LiteralPath (Join-Path $script:repo 'Apps\ExampleApp\2.0.0') | Should -BeFalse
        $outcome.Count | Should -Be 0
    }
}
