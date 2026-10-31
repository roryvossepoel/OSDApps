Describe 'Inventory and client logging analyzer cleanup' {
    BeforeAll {
        $script:moduleRoot = Split-Path $PSScriptRoot -Parent
        Import-Module (Join-Path $script:moduleRoot 'OSDStage.psd1') -Force
    }

    It 'writes byte-identical CMTrace records using Event and EventName' {
        InModuleScope OSDStage {
            Mock Get-Date { [datetime]::SpecifyKind([datetime]'2026-01-02T03:04:05', [DateTimeKind]::Utc) }
            $legacyPath = Join-Path $TestDrive 'legacy.log'
            $namedPath = Join-Path $TestDrive 'named.log'
            $parameters = @{
                Component = 'Cache'
                Level = 'Warning'
                Message = 'Cache inspection'
                Data = @{ Z = @(1,2); A = 'first' }
            }
            @(Write-OSDStageLog -LogPath $legacyPath -Event 'CacheInspected' @parameters).Count | Should -Be 0
            @(Write-OSDStageLog -LogPath $namedPath -EventName 'CacheInspected' @parameters).Count | Should -Be 0
            (Get-FileHash -LiteralPath $legacyPath).Hash | Should -Be (Get-FileHash -LiteralPath $namedPath).Hash
            $row = ConvertFrom-OSDStageUILogLine -Line (Get-Content -LiteralPath $legacyPath)
            $row.Event | Should -Be 'CacheInspected'
            $row.Component | Should -Be 'Cache'
            $row.Level | Should -Be 'Warning'
            $row.Message | Should -Be 'Cache inspection | A=first; Z=1,2'
        }
    }

    It 'accepts legacy Event splatting and preserves single-line escaping' {
        InModuleScope OSDStage {
            $path = Join-Path $TestDrive 'splat.log'
            $parameters = @{
                LogPath = $path; Component = 'Client'; Event = 'Inspect'
                Message = "first`nsecond ]LOG]!> text"
            }
            Write-OSDStageLog @parameters
            $lines = @(Get-Content -LiteralPath $path)
            $lines.Count | Should -Be 1
            $row = ConvertFrom-OSDStageUILogLine -Line $lines[0]
            $row.Event | Should -Be 'Inspect'
            $row.Message | Should -Be 'first second ]LOG]! > text'
        }
    }

    It 'keeps an event-only record readable by the Viewer parser' {
        InModuleScope OSDStage {
            $path = Join-Path $TestDrive 'event-only.log'
            Write-OSDStageLog -LogPath $path -Component 'Client' -Event 'Ready'
            $row = ConvertFrom-OSDStageUILogLine -Line (Get-Content -LiteralPath $path)
            $row.Event | Should -Be 'Ready'
            $row.Message | Should -BeNullOrEmpty
        }
    }

    It 'selects the explicit architecture and channel without changing input inventory' {
        InModuleScope OSDStage {
            $app = [pscustomobject]@{ Id='MozillaFirefoxEnterprise'; Architecture='x64'; Channel='Rapid' }
            $entries = @(
                [pscustomobject]@{Id=$app.Id; Architecture='x86'; Channel='Rapid'; Version='1.0'; Valid=$true},
                [pscustomobject]@{Id=$app.Id; Architecture='x64'; Channel='ESR'; Version='2.0'; Valid=$true},
                [pscustomobject]@{Id=$app.Id; Architecture='x64'; Channel='Rapid'; Version='3.0'; Valid=$false},
                [pscustomobject]@{Id=$app.Id; Architecture='x64'; Channel='Rapid'; Version='4.0'; Valid=$true}
            )
            $before = ConvertTo-Json -InputObject $entries -Depth 5 -Compress
            Get-OSDStageUICachedVersion -App $app -CacheEntries $entries | Should -Be '4.0'
            (ConvertTo-Json -InputObject $entries -Depth 5 -Compress) | Should -Be $before
        }
    }

    It 'does not pick an arbitrary version from ambiguous architectures' {
        InModuleScope OSDStage {
            $app = [pscustomobject]@{Id='GoogleChromeEnterprise'; Architecture='Auto'}
            $entries = @(
                [pscustomobject]@{Id=$app.Id; Architecture='x86'; Version='1.0'; Valid=$true},
                [pscustomobject]@{Id=$app.Id; Architecture='x64'; Version='2.0'; Valid=$true}
            )
            Get-OSDStageUICachedVersion -App $app -CacheEntries $entries | Should -Be '-'
        }
    }

    It 'preserves missing and Current-only cached version labels' {
        InModuleScope OSDStage {
            $app = [pscustomobject]@{Id='GoogleChromeEnterprise'; Architecture='x64'}
            Get-OSDStageUICachedVersion -App $app -CacheEntries @() | Should -Be '-'
            $entry = [pscustomobject]@{Id=$app.Id; Architecture='x64'; Version='Current'; Valid=$true}
            Get-OSDStageUICachedVersion -App $app -CacheEntries @($entry) | Should -Be 'Not recorded'
        }
    }

    It 'retains the existing display-only legacy Teams match without mutating the entry' {
        InModuleScope OSDStage {
            $app = [pscustomobject]@{Id='MicrosoftTeams'; Architecture='x64'}
            $entry = [pscustomobject]@{Id='Teams'; Architecture='x64'; Version='1.2.3.4'; Valid=$true}
            Get-OSDStageUICachedVersion -App $app -CacheEntries @($entry) | Should -Be '1.2.3.4'
            $entry.Id | Should -Be 'Teams'
        }
    }

    It 'retains one trimmed MSI version and reports a failed view close only on the verbose stream' {
        InModuleScope OSDStage {
            $file = Join-Path $TestDrive 'cleanup.msi'
            Set-Content -LiteralPath $file -Value 'sentinel, not an installer' -Encoding ASCII
            $before = (Get-FileHash -LiteralPath $file).Hash
            Mock Test-OSDStageWinPE { $false }
            Mock New-Object {
                $record = [pscustomobject]@{}
                $record | Add-Member ScriptMethod StringData { param([int]$column) ' 123.4.5 ' }
                $view = [pscustomobject]@{Record=$record}
                $view | Add-Member ScriptMethod Execute { '' }
                $view | Add-Member ScriptMethod Fetch { $this.Record }
                $view | Add-Member ScriptMethod Close { throw 'simulated close failure' }
                $database = [pscustomobject]@{View=$view}
                $database | Add-Member ScriptMethod OpenView { param([string]$sql) $this.View }
                $installer = [pscustomobject]@{Database=$database}
                $installer | Add-Member ScriptMethod OpenDatabase {
                    param([string]$path,[int]$mode)
                    if ($mode -ne 0) { throw 'Only read-only database access is permitted.' }
                    $this.Database
                }
                $installer
            } -ParameterFilter { $ComObject -eq 'WindowsInstaller.Installer' }

            $normal = @(Get-OSDStageMsiProductVersion -Path $file -Verbose:$false)
            $normal.Count | Should -Be 1
            $normal[0] | Should -Be '123.4.5'
            $withDiagnostics = @(Get-OSDStageMsiProductVersion -Path $file -Verbose 4>&1)
            @($withDiagnostics | Where-Object { $_ -is [string] }).Count | Should -Be 1
            @($withDiagnostics | Where-Object {
                $_ -is [System.Management.Automation.VerboseRecord] -and
                $_.Message -like '*MSI view cleanup failed*simulated close failure*'
            }).Count | Should -Be 1
            (Get-FileHash -LiteralPath $file).Hash | Should -Be $before
        }
    }

    It 'does not regress the specific analyzer rules addressed in the four reviewed files' {
        $rules = @(
            'PSAvoidAssignmentToAutomaticVariable',
            'PSAvoidUsingEmptyCatchBlock',
            'PSPossibleIncorrectComparisonWithNull'
        )
        foreach ($relative in @(
            'Private/Write-OSDStageLog.ps1',
            'Private/OSDStageUIFormatting.ps1',
            'Private/Get-OSDStageCachedPackageVersion.ps1',
            'Public/Test-OSDStageRepository.ps1'
        )) {
            $findings = @(Invoke-ScriptAnalyzer -Path (Join-Path $script:moduleRoot $relative) -IncludeRule $rules)
            $findings.Count | Should -Be 0 -Because "$relative must retain the reviewed cleanup"
        }
    }
}
