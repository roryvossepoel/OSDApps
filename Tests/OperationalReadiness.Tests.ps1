BeforeAll { . (Join-Path $PSScriptRoot 'Helpers/NativePayloadFixtures.ps1') }
Describe 'Operational readiness and deployment results' {
    BeforeAll {
        $script:moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $script:manifestPath = Join-Path $script:moduleRoot 'OSDStage.psd1'
        Remove-Module OSDStage -Force -ErrorAction SilentlyContinue
        Import-Module $script:manifestPath -Force
        . (Join-Path $script:moduleRoot 'Runtime/OSDStagePayloadFile.ps1')

        function New-OperationalDeploymentFixture {
            param(
                [Parameter(Mandatory)][string]$Root,
                [switch]$IncludeBuiltInPayload
            )

            $stage = Join-Path $Root 'Windows\Temp\OSDStage'
            $setupDirectory = Join-Path $Root 'Windows\Setup\Scripts'
            $packageDirectory = Join-Path $stage 'Packages\ExampleApp'
            New-Item -ItemType Directory -Path $stage,$setupDirectory,$packageDirectory -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $script:moduleRoot 'Runtime\Invoke-OSDStagePreInstall.ps1') -Destination $stage
            Copy-Item -LiteralPath (Join-Path $script:moduleRoot 'Runtime\Invoke-OSDStageRunner.ps1') -Destination $stage
            Copy-Item -LiteralPath (Join-Path $script:moduleRoot 'Runtime\Enter-OSDStageCacheLock.ps1') -Destination $stage
            Copy-Item -LiteralPath (Join-Path $script:moduleRoot 'Runtime\Assert-OSDStageTransactionSpace.ps1') -Destination $stage
            Copy-Item -LiteralPath (Join-Path $script:moduleRoot 'Runtime\Restore-OSDStageCacheGeneration.ps1') -Destination $stage
            Copy-Item -LiteralPath (Join-Path $script:moduleRoot 'Runtime\Test-OSDStageOfficeCacheCompatibility.ps1') -Destination $stage
            Copy-Item -LiteralPath (Join-Path $script:moduleRoot 'Runtime\OSDStageSleepPrevention.ps1') -Destination $stage
            Copy-Item -LiteralPath (Join-Path $script:moduleRoot 'Runtime\OSDStagePayloadFile.ps1') -Destination $stage
            Copy-Item -LiteralPath (Join-Path $script:moduleRoot 'Runtime\OSDStage7Zip.ps1') -Destination $stage
            Copy-Item -LiteralPath (Join-Path $script:moduleRoot 'Runtime\OSDStageVisualStudioCode.ps1') -Destination $stage
            Copy-Item -LiteralPath (Join-Path $script:moduleRoot 'Runtime\OSDStagePrerequisite.ps1') -Destination $stage
            Copy-Item -LiteralPath (Join-Path $script:moduleRoot 'Runtime\OSDStageFont.ps1') -Destination $stage
            Copy-Item -LiteralPath (Join-Path $script:moduleRoot 'Runtime\OSDStageCertificate.ps1') -Destination $stage
            Copy-Item -LiteralPath (Join-Path $script:moduleRoot 'Runtime\OSDStageDriver.ps1') -Destination $stage
            Copy-Item -LiteralPath (Join-Path $script:moduleRoot 'Runtime\Invoke-OSDStageBuiltInCacheTransaction.ps1') -Destination $stage

            $archive = Join-Path $packageDirectory 'Package.zip'
            Set-Content -LiteralPath $archive -Value 'known package bytes' -Encoding ASCII
            $sha256 = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
            $deploymentId = [guid]::NewGuid().Guid
            [ordered]@{
                SchemaVersion = 2
                DeploymentId = $deploymentId
                Runtime = [ordered]@{
                    CleanupMode = 'OnSuccess'
                    CacheVolumeLabel = 'OSDCloud'
                    LogPath = '%ProgramData%\OSDStage\Logs\Runtime.log'
                    ResultPath = '%ProgramData%\OSDStage\Results\Latest.json'
                }
                Packages = @(
                    [ordered]@{
                        Id = 'ExampleApp'; DisplayName = 'Example App'; Source = 'Repository'
                        Version = '1.0.0'; Architecture = 'x64'; Payload = @{ Sha256 = $sha256 }
                    },
                    [ordered]@{
                        Id = 'MicrosoftTeams'; DisplayName = 'Microsoft Teams'; Source = 'BuiltIn'
                        Type = 'MicrosoftTeamsBootstrapper'; Architecture = 'x64'
                        Setup = 'BuiltIn\MicrosoftTeams\teamsbootstrapper.exe'
                        OfflinePackage = $null
                        PayloadRoot = 'BuiltIn\MicrosoftTeams'; PayloadExtension = '.msix'; PayloadSha256 = $null
                    }
                )
            } | ConvertTo-Json -Depth 20 |
                Set-Content -LiteralPath (Join-Path $stage 'DeviceManifest.json') -Encoding UTF8

            @(
                '@echo off'
                ':: OSDStage PreInstall'
                'powershell.exe -File Invoke-OSDStagePreInstall.ps1'
                'set "OSDStage_PREINSTALL_EXITCODE=%ERRORLEVEL%"'
                'if not "%OSDStage_PREINSTALL_EXITCODE%"=="0" exit /b %OSDStage_PREINSTALL_EXITCODE%'
                ':: OSDStage Begin'
                'powershell.exe -File Invoke-OSDStageRunner.ps1'
                'set "OSDStage_EXITCODE=%ERRORLEVEL%"'
                'if not "%OSDStage_EXITCODE%"=="0" exit /b %OSDStage_EXITCODE%'
                ':: OSDStage End'
            ) | Set-Content -LiteralPath (Join-Path $setupDirectory 'SetupComplete.cmd') -Encoding ASCII

            if ($IncludeBuiltInPayload) {
                $teams = Join-Path $stage 'BuiltIn\MicrosoftTeams'
                New-Item -ItemType Directory -Path $teams -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $teams 'teamsbootstrapper.exe') -Value 'bootstrapper' -Encoding ASCII
                Set-Content -LiteralPath (Join-Path $teams 'MSTeams-x64.msix') -Value 'msix' -Encoding ASCII
                Set-OSDStageTestPayloadInfo -Path (Join-Path $teams 'MSTeams-x64.msix') -Id MicrosoftTeams
            }

            $manifestPath = Join-Path $stage 'DeviceManifest.json'
            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            Set-OSDStageManifestPayload -App $manifest.Packages[1] -StagedPath $stage -AllowPending
            $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

            [pscustomobject]@{
                Root = $Root
                Stage = $stage
                Payload = $archive
                DeploymentId = $deploymentId
            }
        }
    }

    It 'accepts an online-ready deployment and reports the missing built-in payload' {
        $fixture = New-OperationalDeploymentFixture -Root (Join-Path $TestDrive 'OnlineReady')
        $result = Test-OSDStageDeployment -WindowsPath $fixture.Root

        $result.Valid | Should -BeTrue
        $result.OfflineReady | Should -BeFalse
        $result.NetworkRequired | Should -BeTrue
        $result.DeploymentId | Should -Be $fixture.DeploymentId
        @($result.Packages).Count | Should -Be 2
        ($result.Packages | Where-Object Id -eq 'MicrosoftTeams').PayloadReady | Should -BeFalse
    }

    It 'accepts only a Boolean when optional PreventSleep is present' -TestCases @(
        @{ Value=$true; Expected=$true }
        @{ Value=$false; Expected=$true }
        @{ Value='false'; Expected=$false }
        @{ Value=$null; Expected=$false }
    ) {
        param($Value, $Expected)
        $fixture = New-OperationalDeploymentFixture -Root (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
        $manifestFile = Join-Path $fixture.Stage 'DeviceManifest.json'
        $manifest = Get-Content $manifestFile -Raw | ConvertFrom-Json
        $manifest.Runtime | Add-Member NoteProperty PreventSleep $Value
        $manifest | ConvertTo-Json -Depth 20 | Set-Content $manifestFile -Encoding UTF8
        $result = Test-OSDStageDeployment -WindowsPath $fixture.Root
        ($result.Checks | Where-Object Name -eq 'RuntimeConfiguration').Passed | Should -Be $Expected
    }

    It 'rejects missing or changed sleep prevention runtime content' {
        $fixture = New-OperationalDeploymentFixture -Root (Join-Path $TestDrive 'SleepHelper')
        $helper = Join-Path $fixture.Stage 'OSDStageSleepPrevention.ps1'
        Add-Content $helper '# Unexpected change'
        $result = Test-OSDStageDeployment -WindowsPath $fixture.Root
        ($result.Checks | Where-Object Name -eq 'RuntimeVersion').Passed | Should -BeFalse
        Remove-Item $helper
        $result = Test-OSDStageDeployment -WindowsPath $fixture.Root
        ($result.Checks | Where-Object Name -eq 'RuntimeScripts').Passed | Should -BeFalse
    }

    It 'enforces hard offline readiness when requested' {
        $fixture = New-OperationalDeploymentFixture -Root (Join-Path $TestDrive 'OfflineRequired')
        $result = Test-OSDStageDeployment -WindowsPath $fixture.Root -RequireOfflineReady

        $result.Valid | Should -BeFalse
        { Test-OSDStageDeployment -WindowsPath $fixture.Root -RequireOfflineReady -ThrowOnFailure } |
            Should -Throw '*MicrosoftTeams*'
    }

    It 'accepts a complete offline deployment' {
        $fixture = New-OperationalDeploymentFixture -Root (Join-Path $TestDrive 'OfflineReady') -IncludeBuiltInPayload
        $result = Test-OSDStageDeployment -WindowsPath $fixture.Root -RequireOfflineReady

        $result.Valid | Should -BeTrue
        $result.OfflineReady | Should -BeTrue
        $result.NetworkRequired | Should -BeFalse
    }

    It 'rejects a corrupted repository archive in every mode' {
        $fixture = New-OperationalDeploymentFixture -Root (Join-Path $TestDrive 'CorruptArchive')
        Set-Content -LiteralPath $fixture.Payload -Value 'tampered bytes' -Encoding ASCII

        $result = Test-OSDStageDeployment -WindowsPath $fixture.Root
        $result.Valid | Should -BeFalse
        ($result.Checks | Where-Object { $_.Name -eq 'AppDefinition' -and $_.AppId -eq 'ExampleApp' }).Passed |
            Should -BeFalse
    }

    It 'accepts exactly one <Source> app on Windows PowerShell and PowerShell' -TestCases @(
        @{ Source = 'Repository' }
        @{ Source = 'BuiltIn' }
    ) {
        param($Source)
        $fixture = New-OperationalDeploymentFixture -Root (Join-Path $TestDrive "Single-$Source") -IncludeBuiltInPayload
        $path = Join-Path $fixture.Stage 'DeviceManifest.json'
        $manifest = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $manifest.Packages = @($manifest.Packages | Where-Object Source -eq $Source)
        $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding UTF8

        $result = Test-OSDStageDeployment -WindowsPath $fixture.Root -RequireOfflineReady -ThrowOnFailure
        $result.Valid | Should -BeTrue
        $result.OfflineReady | Should -BeTrue
        $result.PackageCount | Should -Be 1
        ($result.Checks | Where-Object Name -eq 'AppQueue').Passed | Should -BeTrue
    }

    It 'rejects an empty or invalid queue: <Case>' -TestCases @(
        @{ Case = 'Empty' }
        @{ Case = 'Duplicate' }
        @{ Case = 'InvalidId' }
    ) {
        param($Case)
        $fixture = New-OperationalDeploymentFixture -Root (Join-Path $TestDrive "Queue-$Case") -IncludeBuiltInPayload
        $path = Join-Path $fixture.Stage 'DeviceManifest.json'
        $manifest = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        switch ($Case) {
            'Empty' { $manifest.Packages = @() }
            'Duplicate' { $manifest.Packages = @($manifest.Packages[1], $manifest.Packages[1]) }
            'InvalidId' { $manifest.Packages = @($manifest.Packages[1]); $manifest.Packages[0].Id = 'Invalid..Id' }
        }
        $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding UTF8

        $result = Test-OSDStageDeployment -WindowsPath $fixture.Root
        $result.Valid | Should -BeFalse
        ($result.Checks | Where-Object Name -eq 'AppQueue').Passed | Should -BeFalse
        { Test-OSDStageDeployment -WindowsPath $fixture.Root -ThrowOnFailure } | Should -Throw '*App queue*'
    }

    It 'rejects a staged runtime that differs from the loaded module' {
        $fixture = New-OperationalDeploymentFixture -Root (Join-Path $TestDrive 'RuntimeMismatch')
        Add-Content -LiteralPath (Join-Path $fixture.Stage 'Invoke-OSDStageRunner.ps1') -Value '# altered'

        $result = Test-OSDStageDeployment -WindowsPath $fixture.Root
        $result.Valid | Should -BeFalse
        ($result.Checks | Where-Object Name -eq 'RuntimeVersion').Passed | Should -BeFalse
    }

    It 'reads a valid machine-readable deployment result' {
        $path = Join-Path $TestDrive 'Latest.json'
        @{ SchemaVersion='2.0'; DeploymentId='test'; Status='Succeeded'; Packages=@() } |
            ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $path -Encoding UTF8

        $result = Get-OSDStageDeploymentResult -Path $path
        $result.Status | Should -Be 'Succeeded'
        $result.ResultPath | Should -Be $path
        $result.PSObject.TypeNames[0] | Should -Be 'OSDStage.DeploymentResult'
    }

    It 'rejects malformed or incomplete deployment results' {
        $malformed = Join-Path $TestDrive 'Malformed.json'
        $incomplete = Join-Path $TestDrive 'Incomplete.json'
        Set-Content -LiteralPath $malformed -Value '{ invalid' -Encoding UTF8
        @{ SchemaVersion='2.0' } | ConvertTo-Json | Set-Content -LiteralPath $incomplete -Encoding UTF8

        { Get-OSDStageDeploymentResult -Path $malformed } | Should -Throw '*not valid JSON*'
        { Get-OSDStageDeploymentResult -Path $incomplete } | Should -Throw '*missing required properties*'
    }

    It 'validates an explicit repository cache and detects tampering' {
        $cache = Join-Path $TestDrive 'Cache'
        $packageDirectory = Join-Path $cache 'Packages\ExampleApp'
        New-Item -ItemType Directory -Path $packageDirectory -Force | Out-Null
        $archive = Join-Path $packageDirectory 'Package.zip'
        Set-Content -LiteralPath $archive -Value 'cache bytes' -Encoding ASCII
        $sha256 = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
        @{
            SchemaVersion=2; GeneratedAt=(Get-Date).ToUniversalTime().ToString('o')
            Packages=@(@{Id='ExampleApp';DisplayName='Example App';Version='1.0';Architecture='x64';Payload=@{Sha256=$sha256}})
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $cache 'CacheCatalog.json') -Encoding UTF8

        $valid = Test-OSDStageCache -CachePath $cache -VerifySignatures
        $valid.Valid | Should -BeTrue
        $valid.EntryCount | Should -Be 1
        $valid.SignatureChecksComplete | Should -BeTrue

        Set-Content -LiteralPath $archive -Value 'tampered cache bytes' -Encoding ASCII
        $invalid = Test-OSDStageCache -CachePath $cache
        $invalid.Valid | Should -BeFalse
        $invalid.InvalidEntryCount | Should -Be 1
    }

    It 'returns a stable unavailable summary when no cache exists' {
        $result = Test-OSDStageCache -CachePath (Join-Path $TestDrive 'AbsentCache')
        $result.CacheAvailable | Should -BeFalse
        $result.Valid | Should -BeFalse
        $result.EntryCount | Should -Be 0
    }

    It 'executes both standalone runtime phases and writes a successful final result' -Skip:(-not (Get-Command powershell.exe -ErrorAction SilentlyContinue)) {
        $stage = Join-Path $TestDrive 'RunnerStage'
        $resultPath = Join-Path $TestDrive 'Results\Latest.json'
        $logPath = Join-Path $TestDrive 'Logs\Runtime.log'
        New-Item -ItemType Directory -Path $stage -Force | Out-Null
        $deploymentId = [guid]::NewGuid().Guid
        @{
            SchemaVersion=2; DeploymentId=$deploymentId; Packages=@()
            Runtime=@{CleanupMode='Never';CacheVolumeLabel='OSDCloud';LogPath=$logPath;ResultPath=$resultPath}
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $stage 'DeviceManifest.json') -Encoding UTF8

        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $script:moduleRoot 'Runtime\Invoke-OSDStagePreInstall.ps1') -StagedPath $stage
        $LASTEXITCODE | Should -Be 0
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $script:moduleRoot 'Runtime\Invoke-OSDStageRunner.ps1') -StagedPath $stage
        $LASTEXITCODE | Should -Be 0

        $result = Get-OSDStageDeploymentResult -Path $resultPath
        $result.Status | Should -Be 'Succeeded'
        $result.DeploymentId | Should -Be $deploymentId
        $result.ExpectedPackageCount | Should -Be 0
        $result.CleanupMode | Should -Be 'Never'
        $result.PreInstall.Status | Should -Be 'Succeeded'
        $result.PreInstall.DeploymentId | Should -Be $deploymentId
    }
}
