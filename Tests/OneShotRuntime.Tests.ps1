Describe 'One-shot fault-tolerant runtime' {
    BeforeAll {
        $script:moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $script:runnerPath = Join-Path $script:moduleRoot 'Runtime\Invoke-OSDAppRunner.ps1'
        $script:preInstallPath = Join-Path $script:moduleRoot 'Runtime\Invoke-OSDAppPreInstall.ps1'
        Import-Module (Join-Path $script:moduleRoot 'OSDApps.psd1') -Force

        function ConvertTo-SingleQuotedPowerShellLiteral {
            param([Parameter(Mandatory)][string]$Value)
            "'$($Value.Replace("'", "''"))'"
        }

        function New-OneShotRepositoryPackage {
            param(
                [Parameter(Mandatory)][string]$Stage,
                [Parameter(Mandatory)][string]$Id,
                [Parameter(Mandatory)][string]$InstallScript,
                [ValidateSet('App','Script')][string]$PackageType = 'App'
            )

            $sourceRoot = Join-Path (Split-Path $Stage -Parent) ("Source-{0}-{1}" -f $Id, [guid]::NewGuid().ToString('N'))
            $payloadRoot = Join-Path $sourceRoot 'Package'
            $packageRoot = Join-Path $Stage (Join-Path 'Packages' $Id)
            New-Item -ItemType Directory -Path $payloadRoot,$packageRoot -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $payloadRoot 'Install.ps1') -Value $InstallScript -Encoding UTF8

            $archivePath = Join-Path $packageRoot 'Package.zip'
            Compress-Archive -Path $payloadRoot -DestinationPath $archivePath -Force
            $sha256 = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash

            [ordered]@{
                Id = $Id
                DisplayName = $Id
                Source = 'Repository'
                Type = 'RepositoryPackage'
                PackageType = $PackageType
                Version = '1.0.0'
                Architecture = 'x64'
                Archive = [ordered]@{ Sha256 = $sha256 }
                SuccessCodes = @(0,3010)
            }
        }

        function New-OneShotDeploymentFixture {
            param(
                [Parameter(Mandatory)][string]$Root,
                [Parameter(Mandatory)][object[]]$Apps,
                [ValidateSet('OnSuccess','Never')][string]$CleanupMode = 'OnSuccess'
            )

            $stage = Join-Path $Root 'Stage'
            $resultPath = Join-Path $Root 'Results\Latest.json'
            $logPath = Join-Path $Root 'Logs\Runtime.log'
            New-Item -ItemType Directory -Path $stage -Force | Out-Null
            $deploymentId = [guid]::NewGuid().Guid
            [ordered]@{
                SchemaVersion = 1
                DeploymentId = $deploymentId
                Runtime = [ordered]@{
                    CleanupMode = $CleanupMode
                    CacheVolumeLabel = 'OSDCloud'
                    LogPath = $logPath
                    ResultPath = $resultPath
                }
                Apps = @($Apps)
            } | ConvertTo-Json -Depth 20 |
                Set-Content -LiteralPath (Join-Path $stage 'DeviceManifest.json') -Encoding UTF8

            [pscustomobject]@{
                Root = $Root
                Stage = $stage
                ResultPath = $resultPath
                LogPath = $logPath
                DeploymentId = $deploymentId
            }
        }
    }

    It 'continues with independent apps after an installer exit-code failure' -Skip:(-not (Get-Command powershell.exe -ErrorAction SilentlyContinue)) {
        $root = Join-Path $TestDrive 'ContinueAfterInstallerFailure'
        $stage = Join-Path $root 'Stage'
        New-Item -ItemType Directory -Path $stage -Force | Out-Null
        $failedMarker = Join-Path $root 'failed-attempt.txt'
        $successMarker = Join-Path $root 'success-attempt.txt'
        $failedScript = "Set-Content -LiteralPath $(ConvertTo-SingleQuotedPowerShellLiteral $failedMarker) -Value 'attempted' -Encoding ASCII`r`nexit 42"
        $successScript = "Set-Content -LiteralPath $(ConvertTo-SingleQuotedPowerShellLiteral $successMarker) -Value 'attempted' -Encoding ASCII`r`nexit 0"
        $apps = @(
            New-OneShotRepositoryPackage -Stage $stage -Id 'BrokenInstaller' -InstallScript $failedScript -PackageType Script
            New-OneShotRepositoryPackage -Stage $stage -Id 'IndependentInstaller' -InstallScript $successScript
        )
        $fixture = New-OneShotDeploymentFixture -Root $root -Apps $apps

        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:runnerPath -StagedPath $fixture.Stage
        $LASTEXITCODE | Should -Be 1

        (Test-Path -LiteralPath $failedMarker -PathType Leaf) | Should -BeTrue
        (Test-Path -LiteralPath $successMarker -PathType Leaf) | Should -BeTrue
        (Test-Path -LiteralPath $fixture.Stage -PathType Container) | Should -BeTrue
        $result = Get-Content -LiteralPath $fixture.ResultPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $result.Status | Should -Be 'Failed'
        $result.FailureType | Should -Be 'AppFailures'
        $result.SuccessfulAppCount | Should -Be 1
        $result.FailedAppCount | Should -Be 1
        $result.SkippedAppCount | Should -Be 0
        @($result.Apps.Status) | Should -Be @('Failed','Succeeded')
        $result.Apps[0].ExitCode | Should -Be 42
        $result.Apps[0].FailureType | Should -Be 'InstallerFailed'
        $result.Apps[0].PackageType | Should -Be 'Script'
        $result.Apps[1].PackageType | Should -Be 'App'
        (Get-Content -LiteralPath $fixture.LogPath -Raw) | Should -Match '\[InstallCompletedWithErrors\]'
    }

    It 'skips a built-in that failed PreInstall and still runs an independent repository app' -Skip:(-not (Get-Command powershell.exe -ErrorAction SilentlyContinue)) {
        $root = Join-Path $TestDrive 'ContinueAfterPreInstallFailure'
        $stage = Join-Path $root 'Stage'
        New-Item -ItemType Directory -Path $stage -Force | Out-Null
        $successMarker = Join-Path $root 'repository-ran.txt'
        $successScript = "Set-Content -LiteralPath $(ConvertTo-SingleQuotedPowerShellLiteral $successMarker) -Value 'attempted' -Encoding ASCII`r`nexit 0"
        $repositoryApp = New-OneShotRepositoryPackage -Stage $stage -Id 'IndependentRepositoryApp' -InstallScript $successScript
        $builtInApp = [ordered]@{
            Id = 'AdobeAcrobatUnified'
            DisplayName = 'Adobe Acrobat Unified'
            Source = 'BuiltIn'
            Type = 'AdobeAcrobatUnifiedZip'
            Architecture = 'x64'
            Package = 'BuiltIn\AdobeAcrobatUnified\x64\Package.zip'
        }
        $fixture = New-OneShotDeploymentFixture -Root $root -Apps @($builtInApp,$repositoryApp)
        $preInstallPath = Join-Path (Split-Path $fixture.ResultPath -Parent) 'PreInstall.json'
        New-Item -ItemType Directory -Path (Split-Path $preInstallPath -Parent) -Force | Out-Null
        [ordered]@{
            SchemaVersion = '1.0'
            DeploymentId = $fixture.DeploymentId
            Phase = 'PreInstall'
            Status = 'CompletedWithErrors'
            Apps = @(
                [ordered]@{
                    Id = 'AdobeAcrobatUnified'
                    Status = 'Failed'
                    FailureType = 'RemoteAcquisition'
                    Error = 'Controlled acquisition failure.'
                }
            )
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $preInstallPath -Encoding UTF8

        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:runnerPath -StagedPath $fixture.Stage
        $LASTEXITCODE | Should -Be 1

        (Test-Path -LiteralPath $successMarker -PathType Leaf) | Should -BeTrue
        $result = Get-Content -LiteralPath $fixture.ResultPath -Raw -Encoding UTF8 | ConvertFrom-Json
        @($result.Apps.Status) | Should -Be @('Skipped','Succeeded')
        $result.SuccessfulAppCount | Should -Be 1
        $result.SkippedAppCount | Should -Be 1
        $result.Apps[0].FailureType | Should -Be 'RemoteAcquisition'
    }

    It 'aborts before every installer when repository integrity fails' -Skip:(-not (Get-Command powershell.exe -ErrorAction SilentlyContinue)) {
        $root = Join-Path $TestDrive 'AbortOnIntegrityFailure'
        $stage = Join-Path $root 'Stage'
        New-Item -ItemType Directory -Path $stage -Force | Out-Null
        $firstMarker = Join-Path $root 'first-ran.txt'
        $secondMarker = Join-Path $root 'second-ran.txt'
        $firstScript = "Set-Content -LiteralPath $(ConvertTo-SingleQuotedPowerShellLiteral $firstMarker) -Value 'attempted' -Encoding ASCII`r`nexit 0"
        $secondScript = "Set-Content -LiteralPath $(ConvertTo-SingleQuotedPowerShellLiteral $secondMarker) -Value 'attempted' -Encoding ASCII`r`nexit 0"
        $first = New-OneShotRepositoryPackage -Stage $stage -Id 'TamperedPackage' -InstallScript $firstScript
        $second = New-OneShotRepositoryPackage -Stage $stage -Id 'NeverAttemptedPackage' -InstallScript $secondScript
        $first.Archive.Sha256 = ('0' * 64)
        $fixture = New-OneShotDeploymentFixture -Root $root -Apps @($first,$second)

        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:runnerPath -StagedPath $fixture.Stage
        $LASTEXITCODE | Should -Be 1

        (Test-Path -LiteralPath $firstMarker) | Should -BeFalse
        (Test-Path -LiteralPath $secondMarker) | Should -BeFalse
        $result = Get-Content -LiteralPath $fixture.ResultPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $result.Status | Should -Be 'Failed'
        $result.FailureType | Should -Be 'HashMismatch'
        @($result.Apps.Status) | Should -Be @('Failed','Skipped')
        $result.FailedAppCount | Should -Be 1
        $result.SkippedAppCount | Should -Be 1
    }

    It 'records an ordinary built-in acquisition failure without requesting a retry' -Skip:(-not (Get-Command powershell.exe -ErrorAction SilentlyContinue)) {
        $root = Join-Path $TestDrive 'PreInstallAppFailure'
        $stage = Join-Path $root 'Stage'
        $resultPath = Join-Path $root 'Results\Latest.json'
        $logPath = Join-Path $root 'Logs\Runtime.log'
        New-Item -ItemType Directory -Path $stage -Force | Out-Null
        [ordered]@{
            SchemaVersion = 1
            DeploymentId = [guid]::NewGuid().Guid
            Runtime = [ordered]@{
                CleanupMode = 'OnSuccess'
                CacheVolumeLabel = 'OSDCloud'
                LogPath = $logPath
                ResultPath = $resultPath
            }
            Apps = @(
                [ordered]@{
                    Id = 'AdobeAcrobatUnified'
                    DisplayName = 'Adobe Acrobat Unified'
                    Source = 'BuiltIn'
                    Type = 'AdobeAcrobatUnifiedZip'
                    Architecture = 'x64'
                    Package = 'BuiltIn\AdobeAcrobatUnified\x64\Package.zip'
                    PackageUri = 'http://127.0.0.1:1/unavailable.zip'
                }
            )
        } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $stage 'DeviceManifest.json') -Encoding UTF8

        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:preInstallPath -StagedPath $stage
        $LASTEXITCODE | Should -Be 0

        $preInstallResultPath = Join-Path (Split-Path $resultPath -Parent) 'PreInstall.json'
        $result = Get-Content -LiteralPath $preInstallResultPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $result.Status | Should -Be 'CompletedWithErrors'
        $result.FailedBuiltInAppCount | Should -Be 1
        @($result.Apps).Count | Should -Be 1
        $result.Apps[0].Status | Should -Be 'Failed'
        $result.Error | Should -Match 'no automatic retry'
    }

    It 'keeps SetupComplete one-shot and does not install a persistence retry mechanism' {
        InModuleScope OSDApps {
            $windowsRoot = Join-Path $TestDrive 'OneShotSetupComplete'
            Add-OSDAppSetupComplete -WindowsPath $windowsRoot -Confirm:$false | Out-Null
        }
        $windowsRoot = Join-Path $TestDrive 'OneShotSetupComplete'
        $setupComplete = Get-Content -LiteralPath (Join-Path $windowsRoot 'Windows\Setup\Scripts\SetupComplete.cmd') -Raw
        $setupComplete | Should -Not -Match '(?i)Register-ScheduledTask|schtasks(?:\.exe)?|\\RunOnce\b|New-Service|sc(?:\.exe)?\s+create'
        ([regex]::Matches($setupComplete, '(?m)^powershell\.exe.*Invoke-OSDAppPreInstall\.ps1.*$')).Count | Should -Be 1
        ([regex]::Matches($setupComplete, '(?m)^powershell\.exe.*Invoke-OSDAppRunner\.ps1.*$')).Count | Should -Be 1
    }
}
