Describe 'Module package contents' {
    BeforeAll {
        $root = Split-Path $PSScriptRoot -Parent
        $output = Join-Path $TestDrive 'package'
        $script:builtModule = & (Join-Path $root 'build\Build-Module.ps1') -OutputPath $output
    }

    It 'ships the runtime built-in metadata used by the Viewer' {
        Test-Path -LiteralPath (Join-Path $script:builtModule.Path 'metadata\builtins.json') -PathType Leaf |
            Should -BeTrue
    }

    It 'does not ship website SVG assets in the PowerShell module' {
        Test-Path -LiteralPath (Join-Path $script:builtModule.Path 'metadata\icons') |
            Should -BeFalse
        @(Get-ChildItem -LiteralPath $script:builtModule.Path -Recurse -File -Filter '*.svg').Count |
            Should -Be 0
    }

    It 'keeps repository-only release history out of the installed module' {
        Test-Path -LiteralPath (Join-Path $script:builtModule.Path 'CHANGELOG.md') |
            Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:builtModule.Path 'README.md') |
            Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:builtModule.Path 'LICENSE') |
            Should -BeTrue
    }

    It 'keeps metadata packaging explicitly limited to runtime files' {
        $metadataFiles = @(
            Get-ChildItem -LiteralPath (Join-Path $script:builtModule.Path 'metadata') -Recurse -File |
                ForEach-Object { $_.Name }
        )
        $metadataFiles | Should -Be @('builtins.json')
    }
}
