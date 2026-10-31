Describe 'Repository validation diagnostics and scalar success-code checks' {
    BeforeAll {
        $root = Split-Path $PSScriptRoot -Parent
        Import-Module (Join-Path $root 'OSDStage.psd1') -Force
    }

    BeforeEach {
        $script:caseRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $source = Join-Path $script:caseRoot 'Source'
        $script:repository = Join-Path $script:caseRoot 'Repository'
        New-Item -ItemType Directory -Path $source -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $source 'Install.ps1') -Value "throw 'This fixture must never be executed.'" -Encoding UTF8
        $package = New-OSDStagePackage -Id ExampleApp -Version 1.0.0 -SourcePath $source -OutputPath (Join-Path $script:caseRoot 'Build')
        Add-OSDStagePackage -Id ExampleApp -DisplayName 'Example App' -Version 1.0.0 -PackagePath $package.PackagePath -RepositoryPath $script:repository | Out-Null
        $script:packageManifest = Join-Path $script:repository 'Packages\ExampleApp\1.0.0\x64\manifest.json'
    }

    It 'retains scalar success-code validation for <Label>' -TestCases @(
        @{Label='zero'; Codes=@(0); Expected=$true},
        @{Label='normal installer codes'; Codes=@(0,3010); Expected=$true},
        @{Label='integer strings'; Codes=@('0','3010'); Expected=$true},
        @{Label='empty list'; Codes=@(); Expected=$false},
        @{Label='non-numeric entry'; Codes=@(0,'not-an-exit-code'); Expected=$false},
        @{Label='out-of-range integer'; Codes=@('9999999999999999999999'); Expected=$false}
    ) {
        param($Label,$Codes,$Expected)
        $manifest = Get-Content -LiteralPath $script:packageManifest -Raw | ConvertFrom-Json
        $manifest.SuccessCodes = @($Codes)
        $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $script:packageManifest -Encoding UTF8
        $result = @(Test-OSDStageRepository -RepositoryPath $script:repository)
        $result.Count | Should -Be 1
        $result[0].SuccessCodesValid | Should -Be $Expected
        $result[0].Valid | Should -Be $Expected
    }

    It 'keeps a valid package valid when optional free-space reporting fails' {
        Mock Get-PSDrive { throw 'simulated capacity query failure' } -ModuleName OSDStage
        $before = (Get-FileHash -LiteralPath $script:packageManifest).Hash
        $normal = @(Test-OSDStageRepository -RepositoryPath $script:repository -Verbose:$false)
        $normal.Count | Should -Be 1
        $normal[0].Valid | Should -BeTrue
        $normal[0].RepositoryFreeSpaceGB | Should -BeNullOrEmpty

        $diagnosticOutput = @(Test-OSDStageRepository -RepositoryPath $script:repository -Verbose 4>&1)
        $rows = @($diagnosticOutput | Where-Object { $_.PSTypeNames -contains 'OSDStage.RepositoryValidation' })
        $rows.Count | Should -Be 1
        $rows[0].Valid | Should -BeTrue
        @($diagnosticOutput | Where-Object {
            $_ -is [System.Management.Automation.VerboseRecord] -and
            $_.Message -like '*Repository free space could not be determined*simulated capacity query failure*'
        }).Count | Should -Be 1
        (Get-FileHash -LiteralPath $script:packageManifest).Hash | Should -Be $before
    }

    It 'reports malformed orphan JSON as invalid without altering repository files' {
        $orphan = Join-Path $script:repository 'Packages\Orphan\1.0.0\x64'
        New-Item -ItemType Directory -Path $orphan -Force | Out-Null
        $orphanManifest = Join-Path $orphan 'manifest.json'
        Set-Content -LiteralPath $orphanManifest -Value '{ invalid JSON' -Encoding UTF8
        $before = @(Get-ChildItem -LiteralPath $script:repository -Recurse -File | Sort-Object FullName | ForEach-Object {
            $_.FullName + '|' + (Get-FileHash -LiteralPath $_.FullName).Hash
        }) -join "`n"
        $output = @(Test-OSDStageRepository -RepositoryPath $script:repository -Verbose -ErrorAction Stop 4>&1)
        $rows = @($output | Where-Object { $_.PSTypeNames -contains 'OSDStage.RepositoryValidation' })
        $rows.Count | Should -Be 2
        @($rows | Where-Object Valid).Count | Should -Be 1
        $invalid = @($rows | Where-Object Orphaned)
        $invalid.Count | Should -Be 1
        $invalid[0].Valid | Should -BeFalse
        $invalid[0].Id | Should -BeNullOrEmpty
        @($output | Where-Object {
            $_ -is [System.Management.Automation.VerboseRecord] -and
            $_.Message -like '*Orphan manifest could not be read*'
        }).Count | Should -Be 1
        $after = @(Get-ChildItem -LiteralPath $script:repository -Recurse -File | Sort-Object FullName | ForEach-Object {
            $_.FullName + '|' + (Get-FileHash -LiteralPath $_.FullName).Hash
        }) -join "`n"
        $after | Should -Be $before
    }
}
