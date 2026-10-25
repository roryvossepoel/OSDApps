Describe 'Standalone prerequisite runner bootstrap' {
    BeforeAll {
        $script:runnerPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'Runtime\Invoke-OSDAppRunner.ps1'
        $script:enginePath = (Get-Process -Id $PID).Path
    }

    # Run the complete production entrypoint in a fresh process. A module import
    # or dot-sourced helper in the Pester session must not hide bootstrap defects.
    # Deliberately corrupt content prevents real installers from being started.
    It 'reaches real payload validation for <Id> without a preloaded module' -Skip:($env:OS -ne 'Windows_NT') -TestCases @(
        @{
            Id = 'VisualCRedist-x64'; Family = 'VisualCRedist'
            RuntimeType = 'Runtime'; Channel = '14'
            RelativeRoot = 'BuiltIn\VisualCRedist\x64'; FileName = 'VC_redist.x64.exe'
        }
        @{
            Id = 'DotNetRuntime-Desktop-10.0-x64'; Family = 'DotNetRuntime'
            RuntimeType = 'Desktop'; Channel = '10.0'
            RelativeRoot = 'BuiltIn\DotNetRuntime\Desktop\10.0\x64'
            FileName = 'windowsdesktop-runtime-10.0.0-win-x64.exe'
        }
    ) {
        param($Id, $Family, $RuntimeType, $Channel, $RelativeRoot, $FileName)

        $root = Join-Path $TestDrive $Id
        $stage = Join-Path $root 'Stage'
        $payloadRoot = Join-Path $stage $RelativeRoot
        $resultPath = Join-Path $root 'Results\Latest.json'
        $logPath = Join-Path $root 'Logs\Runtime.log'
        New-Item -ItemType Directory -Path $payloadRoot -Force | Out-Null
        $payloadPath = Join-Path $payloadRoot $FileName
        [IO.File]::WriteAllText($payloadPath, 'original test fixture', [Text.Encoding]::ASCII)
        $hash = (Get-FileHash -LiteralPath $payloadPath -Algorithm SHA256).Hash
        $size = (Get-Item -LiteralPath $payloadPath).Length
        @{
            Id = $Family; Architecture = 'x64'; PayloadFileName = $FileName
            Sha256 = $hash; Size = $size
        } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $payloadRoot 'CacheInfo.json') -Encoding UTF8

        $app = [ordered]@{
            Id = $Id; DisplayName = $Id; Source = 'BuiltIn'; Type = 'PrerequisiteExe'
            PackageType = 'App'; Family = $Family; Architecture = 'x64'
            RuntimeType = $RuntimeType; Channel = $Channel
            PayloadRoot = $RelativeRoot; PayloadExtension = '.exe'; PayloadSha256 = $hash
            Package = Join-Path $RelativeRoot $FileName
        }
        [ordered]@{
            SchemaVersion = 1
            DeploymentId = [guid]::NewGuid().Guid
            Runtime = @{
                CleanupMode = 'Never'; PreventSleep = $false
                LogPath = $logPath; ResultPath = $resultPath
            }
            Apps = @($app)
        } | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath (Join-Path $stage 'DeviceManifest.json') -Encoding UTF8

        [IO.File]::WriteAllText($payloadPath, 'tampered fixture, not an executable', [Text.Encoding]::ASCII)
        $arguments = @(
            '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File'
            ('"{0}"' -f $script:runnerPath), '-StagedPath', ('"{0}"' -f $stage)
        )
        $child = Start-Process -FilePath $script:enginePath -ArgumentList $arguments -PassThru `
            -RedirectStandardOutput (Join-Path $root 'stdout.txt') `
            -RedirectStandardError (Join-Path $root 'stderr.txt')
        try {
            if (-not $child.WaitForExit(30000)) {
                Stop-Process -Id $child.Id -Force -ErrorAction SilentlyContinue
                throw "Standalone runner timed out for $Id."
            }
            $child.WaitForExit()
            $child.ExitCode | Should -Be 1
        }
        finally { $child.Dispose() }

        Test-Path -LiteralPath $resultPath -PathType Leaf | Should -BeTrue
        $result = Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $result.Status | Should -Be 'Failed'
        $result.ExpectedAppCount | Should -Be 1
        $result.SuccessfulAppCount | Should -Be 0
        $result.FailedAppCount | Should -Be 1
        $result.SkippedAppCount | Should -Be 0
        @($result.Apps).Count | Should -Be 1
        $result.Apps[0].Id | Should -Be $Id
        # Before the bootstrap fix this is AppError: the spec helper is absent.
        $result.Apps[0].FailureType | Should -Be 'HashMismatch'
        $result.Apps[0].Error | Should -Match 'Vendor payload SHA-256 or size mismatch'
        $result.Apps[0].Error | Should -Not -Match 'Get-OSDAppPrerequisiteSpec'
        (Get-Content -LiteralPath $logPath -Raw) | Should -Not -Match '\[BuiltInInstallStart\]'
    }
}
