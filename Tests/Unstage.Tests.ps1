Describe 'Remove-OSDStageStaging CLI safety' {
    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module (Join-Path $moduleRoot 'OSDStage.psd1') -Force

        function global:New-OSDStageStagingFixture {
            param([string]$Root)
            $stage = Join-Path $Root 'Windows\Temp\OSDStage'
            $scripts = Join-Path $Root 'Windows\Setup\Scripts'
            New-Item -ItemType Directory -Path $stage,$scripts -Force | Out-Null
            $pkgA = Join-Path $stage 'Packages\NotepadPlusPlus'
            $pkgB = Join-Path $stage 'BuiltIn\MicrosoftTeams'
            New-Item -ItemType Directory -Path $pkgA,$pkgB -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $pkgA 'Package.zip') -Value 'package' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $pkgB 'teamsbootstrapper.exe') -Value 'teams' -Encoding ASCII
            @{
                SchemaVersion='2.0'
                StagedAt='2026-10-10T10:00:00Z'
                Runtime=@{CleanupMode='Never'}
                Packages=@(
                    @{Id='MicrosoftTeams';Source='BuiltIn';Type='MicrosoftTeamsBootstrapper'},
                    @{Id='NotepadPlusPlus';Source='Repository';Type='RepositoryPackage'}
                )
            } | ConvertTo-Json -Depth 10 |
                Set-Content -LiteralPath (Join-Path $stage 'DeviceManifest.json') -Encoding UTF8
            # Canonical SetupComplete block fixture; the helper is global, while
            # Add-OSDStageSetupComplete is an intentionally private module command.
            $relative='Windows\Temp\OSDStage'
            @(
                '@echo off'
                ':: OSDStage PreInstall'
                ('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SystemDrive%\{0}\Invoke-OSDStagePreInstall.ps1" -StagedPath "%SystemDrive%\{0}"' -f $relative)
                'set "OSDStage_PREINSTALL_EXITCODE=%ERRORLEVEL%"'
                'if not "%OSDStage_PREINSTALL_EXITCODE%"=="0" exit /b %OSDStage_PREINSTALL_EXITCODE%'
                ':: OSDStage Begin'
                ('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SystemDrive%\{0}\Invoke-OSDStageRunner.ps1" -StagedPath "%SystemDrive%\{0}"' -f $relative)
                'set "OSDStage_EXITCODE=%ERRORLEVEL%"'
                'if not "%OSDStage_EXITCODE%"=="0" exit /b %OSDStage_EXITCODE%'
                ':: OSDStage End'
            ) | Set-Content -LiteralPath (Join-Path $scripts 'SetupComplete.cmd') -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $stage 'Invoke-OSDStageRunner.ps1') -Value '# runner' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $stage 'Invoke-OSDStagePreInstall.ps1') -Value '# preinstall' -Encoding ASCII
            return [pscustomobject]@{
                Manifest=Join-Path $stage 'DeviceManifest.json'
                Setup=Join-Path $scripts 'SetupComplete.cmd'
                Stage=$stage
            }
        }
    }
    AfterAll {
        Remove-Item Function:\New-OSDStageStagingFixture -ErrorAction SilentlyContinue
    }

    It 'removes Teams staging while keeping Notepad++, manifest and USB cache' {
        InModuleScope OSDStage {
            $root=Join-Path $TestDrive 'SafeWindows'
            $fixture=New-OSDStageStagingFixture -Root $root
            $cache=Join-Path $TestDrive 'USB\OSDStage'
            New-Item -Path (Join-Path $cache 'BuiltIn\MicrosoftTeams') -ItemType Directory -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $cache 'BuiltIn\MicrosoftTeams\teams.msix') -Value 'cache' -Encoding ASCII
            Mock Test-OSDStageWinPE {$false}
            Mock Get-OSDStageUITestWindowsPath {$root}

            $result=Remove-OSDStageStaging -Name MicrosoftTeams -TestMode -Confirm:$false
            @($result.Removed) | Should -Be @('MicrosoftTeams')
            $manifest=Get-Content -LiteralPath $fixture.Manifest -Raw | ConvertFrom-Json
            @($manifest.Packages.Id) | Should -Be @('NotepadPlusPlus')
            (Test-Path (Join-Path $fixture.Stage 'BuiltIn\MicrosoftTeams')) | Should -BeFalse
            (Test-Path (Join-Path $fixture.Stage 'Packages\NotepadPlusPlus\Package.zip')) | Should -BeTrue
            (Test-Path (Join-Path $cache 'BuiltIn\MicrosoftTeams\teams.msix')) | Should -BeTrue
            (Get-Content -LiteralPath $fixture.Setup -Raw) | Should -Match ':: OSDStage Begin'
        }
    }

    It 'removes the last app and only OSDStage commands from SetupComplete' {
        InModuleScope OSDStage {
            $root=Join-Path $TestDrive 'WindowsWithThirdPartySetup'
            $fixture=New-OSDStageStagingFixture -Root $root
            $original=Get-Content -LiteralPath $fixture.Setup -Raw
            $external= $original.Replace(':: OSDStage Begin',("echo external-between-blocks" + [Environment]::NewLine + ':: OSDStage Begin'))
            [IO.File]::WriteAllText($fixture.Setup,$external,[Text.Encoding]::ASCII)
            Mock Test-OSDStageWinPE {$false}
            Mock Get-OSDStageUITestWindowsPath {$root}

            Remove-OSDStageStaging -Name @('MicrosoftTeams','NotepadPlusPlus') -TestMode -Confirm:$false | Out-Null

            (Test-Path -LiteralPath $fixture.Manifest) | Should -BeFalse
            (Test-Path (Join-Path $fixture.Stage 'Packages\NotepadPlusPlus')) | Should -BeFalse
            (Test-Path (Join-Path $fixture.Stage 'BuiltIn\MicrosoftTeams')) | Should -BeFalse
            (Test-Path (Join-Path $fixture.Stage 'Invoke-OSDStageRunner.ps1')) | Should -BeFalse
            (Test-Path (Join-Path $fixture.Stage 'Invoke-OSDStagePreInstall.ps1')) | Should -BeFalse
            $setup=Get-Content -LiteralPath $fixture.Setup -Raw
            $setup | Should -Match 'echo external-between-blocks'
            $setup | Should -Not -Match ':: OSDStage Begin'
            $setup | Should -Not -Match ':: OSDStage PreInstall'
            $setup | Should -Not -Match ':: OSDStage End'
        }
    }

    It 'does not touch files in -WhatIf mode' {
        InModuleScope OSDStage {
            $root=Join-Path $TestDrive 'WhatIfRoot'
            $fixture=New-OSDStageStagingFixture -Root $root
            $original=Get-Content -LiteralPath $fixture.Manifest -Raw
            Mock Test-OSDStageWinPE {$false}
            Mock Get-OSDStageUITestWindowsPath {$root}

            Remove-OSDStageStaging -Name @('MicrosoftTeams','NotepadPlusPlus') -TestMode -WhatIf | Out-Null
            (Get-Content -LiteralPath $fixture.Manifest -Raw) | Should -Be $original
            (Test-Path (Join-Path $fixture.Stage 'BuiltIn\MicrosoftTeams')) | Should -BeTrue
            (Get-Content -LiteralPath $fixture.Setup -Raw) | Should -Match ':: OSDStage End'
        }
    }

    It 'blocks full-Windows unstaging without TestMode and rejects traversal' {
        InModuleScope OSDStage {
            Mock Test-OSDStageWinPE {$false}
            {Remove-OSDStageStaging -Name MicrosoftTeams -WindowsPath 'C:\' -Confirm:$false} |
                Should -Throw '*requires -TestMode*'
            $root=Join-Path $TestDrive 'InvalidId'
            $fixture=New-OSDStageStagingFixture -Root $root
            Mock Get-OSDStageUITestWindowsPath {$root}
            {Remove-OSDStageStaging -Name '../Windows' -TestMode -Confirm:$false} |
                Should -Throw '*Invalid app ID*'
            (Test-Path $fixture.Manifest) | Should -BeTrue
        }
    }

    It 'preserves the queue if SetupComplete is malformed on last-app removal' {
        InModuleScope OSDStage {
            $root=Join-Path $TestDrive 'BrokenSetup'
            $fixture=New-OSDStageStagingFixture -Root $root
            [IO.File]::WriteAllText($fixture.Setup,':: OSDStage Begin',[Text.Encoding]::ASCII)
            Mock Test-OSDStageWinPE {$false}
            Mock Get-OSDStageUITestWindowsPath {$root}
            {Remove-OSDStageStaging -Name @('MicrosoftTeams','NotepadPlusPlus') -TestMode -Confirm:$false} |
                Should -Throw '*missing or duplicate OSDStage markers*'
            (Test-Path -LiteralPath $fixture.Manifest) | Should -BeTrue
        }
    }

    It 'preserves non-ASCII bytes in unrelated SetupComplete commands when emptying queue' {
        InModuleScope OSDStage {
            $root=Join-Path $TestDrive 'AnsiSetupRoot'
            $fixture=New-OSDStageStagingFixture -Root $root
            $originalBytes=[IO.File]::ReadAllBytes($fixture.Setup)
            $prefix=[Text.Encoding]::GetEncoding(28591).GetBytes("echo Cafe"+[char]233+[Environment]::NewLine)
            $newBytes=New-Object byte[] ($prefix.Length+$originalBytes.Length)
            [Array]::Copy($prefix,0,$newBytes,0,$prefix.Length)
            [Array]::Copy($originalBytes,0,$newBytes,$prefix.Length,$originalBytes.Length)
            [IO.File]::WriteAllBytes($fixture.Setup,$newBytes)

            Mock Test-OSDStageWinPE {$false}
            Mock Get-OSDStageUITestWindowsPath {$root}
            Remove-OSDStageStaging -Name @('MicrosoftTeams','NotepadPlusPlus') -TestMode -Confirm:$false | Out-Null

            $remaining=[IO.File]::ReadAllBytes($fixture.Setup)
            @($remaining).Count | Should -BeGreaterThan 0
            @($remaining | Where-Object {$_ -eq 233}).Count | Should -Be 1
            [Text.Encoding]::GetEncoding(28591).GetString($remaining) | Should -Match 'echo Cafe'
        }
    }

}
