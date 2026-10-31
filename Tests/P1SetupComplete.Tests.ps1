Describe 'P1 SetupComplete coexistence and refresh' {
    BeforeAll {
        $moduleRoot = Split-Path -Parent $PSScriptRoot
        Import-Module (Join-Path $moduleRoot 'OSDStage.psd1') -Force
    }

    It 'preserves third-party commands between OSDStage blocks during repeated staging' {
        InModuleScope OSDStage {
            $winRoot = Join-Path $TestDrive 'OfflineWindows'
            $scripts = Join-Path $winRoot 'Windows\Setup\Scripts'
            New-Item -ItemType Directory -Path $scripts -Force | Out-Null
            $setupPath = Join-Path $scripts 'SetupComplete.cmd'
            @('@echo off','echo existing-before','echo after-script') |
                Set-Content -LiteralPath $setupPath -Encoding ASCII

            Add-OSDStageSetupComplete -WindowsPath $winRoot -Confirm:$false | Out-Null

            $original = [IO.File]::ReadAllText($setupPath)
            $withThirdParty = $original.Replace(
                ':: OSDStage Begin',
                "echo third-party-between-blocks$([Environment]::NewLine):: OSDStage Begin"
            )
            [IO.File]::WriteAllText($setupPath, $withThirdParty, [Text.Encoding]::ASCII)

            Add-OSDStageSetupComplete -WindowsPath $winRoot -Confirm:$false | Out-Null
            Add-OSDStageSetupComplete -WindowsPath $winRoot -Confirm:$false | Out-Null

            $final = [IO.File]::ReadAllText($setupPath)
            $final | Should -Match 'echo existing-before'
            $final | Should -Match 'echo after-script'
            $final | Should -Match 'echo third-party-between-blocks'
            ([regex]::Matches($final, '(?m)^:: OSDStage PreInstall\r?$')).Count | Should -Be 1
            ([regex]::Matches($final, '(?m)^:: OSDStage Begin\r?$')).Count | Should -Be 1
            ([regex]::Matches($final, '(?m)^:: OSDStage End\r?$')).Count | Should -Be 1
        }
    }

    It 'rejects an incomplete OSDStage block instead of adding duplicates' {
        InModuleScope OSDStage {
            $winRoot = Join-Path $TestDrive 'BrokenWindows'
            $scripts = Join-Path $winRoot 'Windows\Setup\Scripts'
            New-Item -ItemType Directory -Path $scripts -Force | Out-Null
            $setupPath = Join-Path $scripts 'SetupComplete.cmd'
            $initial = "@echo off$([Environment]::NewLine):: OSDStage PreInstall$([Environment]::NewLine)echo something"
            [IO.File]::WriteAllText($setupPath, $initial, [Text.Encoding]::ASCII)

            { Add-OSDStageSetupComplete -WindowsPath $winRoot -Confirm:$false } |
                Should -Throw '*without a runner block*'
            [IO.File]::ReadAllText($setupPath) | Should -Be $initial
        }
    }

    It 'does not create directories or scripts when called with WhatIf' {
        InModuleScope OSDStage {
            $winRoot = Join-Path $TestDrive 'WhatIfWindows'
            Add-OSDStageSetupComplete -WindowsPath $winRoot -WhatIf | Out-Null
            (Test-Path -LiteralPath $winRoot) | Should -BeFalse
        }
    }
}
