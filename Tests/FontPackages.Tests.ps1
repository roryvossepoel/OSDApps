Describe 'Repository Font package contract' {
    BeforeAll {
        $script:root = Split-Path $PSScriptRoot -Parent
        Import-Module (Join-Path $script:root 'OSDStage.psd1') -Force
        . (Join-Path $script:root 'Runtime\OSDStageFont.ps1')
    }

    BeforeEach {
        Set-OSDStageConfiguration -EnableBuiltIns $true -EnableRepository $true
    }

    It 'builds and validates Font packages without Install.ps1' {
        $source = Join-Path $TestDrive 'FontSource'
        $nested = Join-Path $source 'Nested'
        New-Item -ItemType Directory -Path $nested -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $source 'Alpha.ttf') -Value 'font-alpha' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $nested 'Beta.otf') -Value 'font-beta' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $source 'readme.txt') -Value 'ignored support file' -Encoding ASCII

        $package = New-OSDStagePackage -Id OrgFonts -Version 1.0.0 -PackageType Font -SourcePath $source -OutputPath (Join-Path $TestDrive 'Build')
        $package.PackageType | Should -Be 'Font'

        $fontValidation = Test-OSDStagePackage -PackagePath $package.PackagePath -PackageType Font
        $fontValidation.Valid | Should -BeTrue
        $fontValidation.FontCount | Should -Be 2
        $fontValidation.InstallPs1Exists | Should -BeFalse

        (Test-OSDStagePackage -PackagePath $package.PackagePath -PackageType App).Valid | Should -BeFalse
    }

    It 'rejects a Font package source without TTF or OTF files' {
        $source = Join-Path $TestDrive 'NoFonts'
        New-Item -ItemType Directory -Path $source -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $source 'notes.txt') -Value 'not a font'
        { New-OSDStagePackage -Id NoFonts -Version 1.0.0 -PackageType Font -SourcePath $source -OutputPath (Join-Path $TestDrive 'BuildNoFonts') } |
            Should -Throw '*.ttf or .otf*'
    }

    It 'publishes Font metadata and validates the repository' {
        $source = Join-Path $TestDrive 'PublishSource'
        New-Item -ItemType Directory -Path $source -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $source 'Corporate.ttf') -Value 'corporate-font' -Encoding ASCII
        $package = New-OSDStagePackage -Id CorporateFonts -Version 2.0.0 -PackageType Font -SourcePath $source -OutputPath (Join-Path $TestDrive 'PublishBuild')
        $repository = Join-Path $TestDrive 'Repository'

        New-OSDStageRepository -Path $repository | Out-Null
        $published = Add-OSDStagePackage -Id CorporateFonts -DisplayName 'Corporate Fonts' -Vendor 'Example' -Version 2.0.0 -Architecture any -PackageType Font -PackagePath $package.PackagePath -RepositoryPath $repository
        $published.PackageType | Should -Be 'Font'

        $checks = @(Test-OSDStageRepository -RepositoryPath $repository)
        $checks.Count | Should -Be 1
        $checks[0].PackageType | Should -Be 'Font'
        $checks[0].PackageValid | Should -BeTrue
        $checks[0].Valid | Should -BeTrue

        $manifest = Get-Content -LiteralPath (Join-Path $repository 'Packages\CorporateFonts\2.0.0\any\manifest.json') -Raw | ConvertFrom-Json
        $manifest.PackageType | Should -Be 'Font'
    }

    It 'stages only repository packages classified as Font through Add-OSDStageFont' {
        InModuleScope OSDStage {
            Mock Get-OSDStage {
                [pscustomobject]@{ Id='CorporateFonts'; Source='Repository'; PackageType='Font' }
            }
            Mock Add-OSDStage {
                [pscustomobject]@{ Name='CorporateFonts'; Source='Repository'; PackageType='Font' }
            }

            $result = Add-OSDStageFont -Id CorporateFonts
            $result.PackageType | Should -Be 'Font'
            Should -Invoke Add-OSDStage -Exactly 1 -ParameterFilter { $Name -eq 'CorporateFonts' }
        }
    }

    It 'rejects using Add-OSDStageFont for a normal repository App' {
        InModuleScope OSDStage {
            Mock Get-OSDStage {
                [pscustomobject]@{ Id='NotAFont'; Source='Repository'; PackageType='App' }
            }
            Mock Add-OSDStage { throw 'must not stage' }

            { Add-OSDStageFont -Id NotAFont } | Should -Throw '*not Font*'
            Should -Invoke Add-OSDStage -Exactly 0
        }
    }

    It 'installs TTF and OTF machine registration idempotently and isolates filename conflicts' -Skip:($env:OS -ne 'Windows_NT') {
        $payload = Join-Path $TestDrive 'Payload'
        $fonts = Join-Path $TestDrive 'WindowsFonts'
        $resultPath = Join-Path $TestDrive 'Results\Font-CorporateFonts-Result.json'
        $registryPath = 'HKCU:\Software\OSDStage\Tests\Fonts-' + [guid]::NewGuid().ToString('N')
        New-Item -ItemType Directory -Path $payload -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $payload 'Alpha.ttf') -Value 'alpha-v1' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $payload 'Beta.otf') -Value 'beta-v1' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $payload 'readme.txt') -Value 'ignored' -Encoding ASCII

        try {
            $first = Invoke-OSDStageFontPackage -PayloadRoot $payload -PackageId CorporateFonts -DeploymentId ([guid]::NewGuid().Guid) -ResultPath $resultPath -FontsDirectory $fonts -RegistryPath $registryPath -SkipNativeActivation
            $first.ExitCode | Should -Be 0
            @($first.Items).Count | Should -Be 2
            @($first.Items | Where-Object Status -eq Installed).Count | Should -Be 2
            Test-Path -LiteralPath (Join-Path $fonts 'Alpha.ttf') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $fonts 'Beta.otf') | Should -BeTrue

            $second = Invoke-OSDStageFontPackage -PayloadRoot $payload -PackageId CorporateFonts -DeploymentId ([guid]::NewGuid().Guid) -ResultPath $resultPath -FontsDirectory $fonts -RegistryPath $registryPath -SkipNativeActivation
            $second.ExitCode | Should -Be 0
            @($second.Items | Where-Object Status -eq AlreadyPresent).Count | Should -Be 2

            Set-Content -LiteralPath (Join-Path $payload 'Alpha.ttf') -Value 'alpha-v2-conflict' -Encoding ASCII
            $third = Invoke-OSDStageFontPackage -PayloadRoot $payload -PackageId CorporateFonts -DeploymentId ([guid]::NewGuid().Guid) -ResultPath $resultPath -FontsDirectory $fonts -RegistryPath $registryPath -SkipNativeActivation
            $third.ExitCode | Should -Be 1
            @($third.Items | Where-Object { $_.FileName -eq 'Alpha.ttf' })[0].Outcome | Should -Be 'FileConflict'
            @($third.Items | Where-Object { $_.FileName -eq 'Beta.otf' })[0].Status | Should -Be 'AlreadyPresent'

            $record = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
            $record.Status | Should -Be 'Failed'
            $record.FailedCount | Should -Be 1
            $record.AlreadyPresentCount | Should -Be 1
        }
        finally {
            Remove-Item -LiteralPath $registryPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'labels Font packages separately in the read-only UI' {
        InModuleScope OSDStage {
            (Get-OSDStageUIPackageType -App ([pscustomobject]@{Source='Repository';PackageType='Font'})) | Should -Be 'Font'
        }
    }

    It 'routes Font packages before requiring Package Install.ps1 and stages the font runtime helper' {
        $runner = Get-Content -LiteralPath (Join-Path $script:root 'Runtime\Invoke-OSDStageRunner.ps1') -Raw
        $fontBranch = $runner.IndexOf('[string]$package.PackageType -eq ''Font''')
        $installRequirement = $runner.IndexOf("does not contain Package\Install.ps1")
        $fontBranch | Should -BeGreaterThan -1
        $installRequirement | Should -BeGreaterThan $fontBranch

        $setup = Get-Content -LiteralPath (Join-Path $script:root 'Private\Add-OSDStageSetupComplete.ps1') -Raw
        $setup | Should -Match 'OSDStageFont\.ps1'
    }
}
