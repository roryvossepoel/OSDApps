Describe 'Per-deployment acquisition reporting' {
    BeforeAll {
        $moduleRoot = Split-Path $PSScriptRoot -Parent
        $runtimePath = Join-Path $moduleRoot 'Runtime\Invoke-OSDAppPreInstall.ps1'
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($runtimePath, [ref]$tokens, [ref]$errors)
        if (@($errors).Count) { throw 'PreInstall parser errors.' }
        foreach ($definition in $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
            . ([scriptblock]::Create($definition.Extent.Text))
        }
        # Execute the actual production loop, including all catches, continue paths and finally records.
        # Only external acquisition, space and publisher boundaries are replaced by fixtures.
        $loop = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.ForEachStatementAst] -and $node.Condition.Extent.Text -eq '$builtInApps' }, $true)
        if (-not $loop) { throw 'PreInstall application loop not found.' }
        $script:preparationLoop = [scriptblock]::Create($loop.Extent.Text)
        . (Join-Path $moduleRoot 'Runtime\Assert-OSDAppTransactionSpace.ps1')
        $runnerAst = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $moduleRoot 'Runtime\Invoke-OSDAppRunner.ps1'), [ref]$tokens, [ref]$errors)
        foreach ($name in @('Get-RunnerCacheInfo','New-RunnerApplicationResult','Write-RunnerResult')) {
            $definition = $runnerAst.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
            . ([scriptblock]::Create($definition.Extent.Text))
        }
        Add-Type -AssemblyName System.IO.Compression
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        function New-TestArchive {
            param([string]$Path, [switch]$Teams)
            $zip = [IO.Compression.ZipFile]::Open($Path, [IO.Compression.ZipArchiveMode]::Create)
            try {
                $entry = $zip.CreateEntry($(if ($Teams) { 'AppxManifest.xml' } else { 'payload.txt' }))
                $writer = [IO.StreamWriter]::new($entry.Open())
                try { $writer.Write($(if ($Teams) { '<Package><Identity Version="1.0.0.0" /></Package>' } else { 'fixture' })) } finally { $writer.Dispose() }
            } finally { $zip.Dispose() }
        }
        function New-TestOfficePayload {
            param([string]$Root)
            $data = Join-Path $Root 'Office\Data'
            $version = Join-Path $data '1.0.0.0'
            New-Item -ItemType Directory -Path $version -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $version 'payload.dat') -Value fixture
            foreach ($cab in @('v64.cab','v64_1.0.0.0.cab')) { Set-Content -LiteralPath (Join-Path $data $cab) -Value fixture }
        }
    }

    BeforeEach {
        $ErrorActionPreference = 'Stop'
        $script:StagedPath = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $StagedPath -Force | Out-Null
        $script:usbRoot = $null
        $script:networkAvailable = $true
        $script:applicationResults = [System.Collections.Generic.List[object]]::new()
        $script:preInstallStopwatch = [Diagnostics.Stopwatch]::StartNew()
        $script:preInstallStartedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        $script:OfficeRefreshTimeoutMinutes = 1
        $script:manifest = [pscustomobject]@{ DeploymentId = 'reporting-test' }
        $script:preInstallResultPath = Join-Path $StagedPath 'Results\PreInstall.json'
        $script:logPath = Join-Path $StagedPath 'Logs\Runtime.log'
        $script:logDirectory = Split-Path $logPath -Parent
        $script:remoteMatches = $false
        $script:failDownload = $false
        Mock Assert-PreInstallSignedPayload { }
        Mock Assert-OSDAppTransactionSpace { }
        Mock Test-InternetEndpoint { $true }
        Mock Get-RemoteMetadata {
            [pscustomobject]@{ ETag=$(if ($script:remoteMatches) { 'old' } else { 'new' }); LastModified=$null; ContentLength=100; FinalUri='https://example.invalid/package' }
        }
        Mock Save-PreInstallDownload {
            if ($script:failDownload) { throw 'HTTP download timeout in fixture.' }
            if ($DestinationPath -match '\.zip$') { New-TestArchive -Path $DestinationPath }
            elseif ($DestinationPath -match '\.msix$') { New-TestArchive -Path $DestinationPath -Teams }
            else { Set-Content -LiteralPath $DestinationPath -Value 'new fixture payload' }
        }
        Mock Start-Process {
            New-TestOfficePayload -Root $WorkingDirectory
            [pscustomobject]@{ HasExited=$true; ExitCode=0 }
        }
        $script:builtInApps = @(
            [pscustomobject]@{ Id='Microsoft365Apps'; Relative='BuiltIn\Microsoft365Apps'; File='setup.exe' }
            [pscustomobject]@{ Id='MicrosoftTeams'; Relative='BuiltIn\MicrosoftTeams'; File='teams.msix' }
            [pscustomobject]@{ Id='AdobeAcrobatUnified'; Relative='BuiltIn\AdobeAcrobatUnified\x64'; File='Package.zip' }
            [pscustomobject]@{ Id='GoogleChromeEnterprise'; Relative='BuiltIn\GoogleChromeEnterprise\x64'; File='Package.msi' }
            [pscustomobject]@{ Id='MozillaFirefoxEnterprise'; Relative='BuiltIn\MozillaFirefoxEnterprise\Rapid\x64\en-US'; File='Package.msi' }
            [pscustomobject]@{ Id='CiscoWebex'; Relative='BuiltIn\CiscoWebex\x64'; File='Package.msi' }
        )
        foreach ($app in $builtInApps) {
            $app | Add-Member Architecture x64
            $app | Add-Member Source BuiltIn
            $app | Add-Member DisplayName $app.Id
            $root = Join-Path $StagedPath $app.Relative
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            $payload = Join-Path $root $app.File
            if ($app.Id -eq 'MicrosoftTeams') {
                New-TestArchive -Path $payload -Teams
                Set-Content -LiteralPath (Join-Path $root 'teamsbootstrapper.exe') -Value fixture
            } elseif ($app.Id -eq 'AdobeAcrobatUnified') { New-TestArchive -Path $payload }
            else { Set-Content -LiteralPath $payload -Value fixture }
            if ($app.Id -eq 'Microsoft365Apps') {
                New-TestOfficePayload -Root $root
                Set-Content -LiteralPath (Join-Path $root 'configuration.xml') -Value '<Configuration><Add OfficeClientEdition="64"><Product ID="O365ProPlusRetail"><Language ID="en-us" /></Product></Add></Configuration>'
            }
            @{ Id=$app.Id; Version='1.0.0.0'; Architecture='x64'; RemoteETag='old'; Updated=$true; Cached=$true } |
                ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'CacheInfo.json') -Encoding UTF8
        }
    }

    It 'reports a fresh acquisition for all six built-ins even when the Office version did not change' {
        . $script:preparationLoop
        $applicationResults.Count | Should -Be 6
        @($applicationResults | Where-Object Status -ne Succeeded).Count | Should -Be 0
        @($applicationResults | Where-Object AcquisitionOutcome -ne Downloaded).Count | Should -Be 0
        (Get-Content (Join-Path $StagedPath 'BuiltIn\Microsoft365Apps\CacheInfo.json') -Raw | ConvertFrom-Json).Updated | Should -BeFalse
        @($applicationResults | Where-Object { $_.RefreshError }).Count | Should -Be 0
    }

    It 'reports metadata-confirmed primary-payload reuse for all five HTTP built-ins' {
        $script:builtInApps = @($builtInApps | Where-Object Id -ne Microsoft365Apps)
        $script:remoteMatches = $true
        . $script:preparationLoop
        $applicationResults.Count | Should -Be 5
        @($applicationResults | Where-Object AcquisitionOutcome -ne CacheReused).Count | Should -Be 0
        Should -Invoke Save-PreInstallDownload -Exactly 1 -ParameterFilter { $Id -eq 'MicrosoftTeams' -and $Description -eq 'Microsoft Teams bootstrapper' }
        Should -Invoke Save-PreInstallDownload -Exactly 0 -ParameterFilter { $Description -ne 'Microsoft Teams bootstrapper' }
    }

    It 'reports offline use without inventing a refresh failure for any built-in' {
        $script:networkAvailable = $false
        . $script:preparationLoop
        @($applicationResults | Where-Object AcquisitionOutcome -ne OfflineCacheUsed).Count | Should -Be 0
        @($applicationResults | Where-Object { $_.RefreshError }).Count | Should -Be 0
        Should -Invoke Save-PreInstallDownload -Exactly 0
        Write-PreInstallResult -Status Succeeded
        $saved = Get-Content $preInstallResultPath -Raw | ConvertFrom-Json
        $saved.OfflineCacheApplicationCount | Should -Be 6
        $saved.FallbackApplicationCount | Should -Be 0
        $saved.HasAcquisitionWarnings | Should -BeTrue
    }

    It 'preserves refresh failure reasons for all six successful fallbacks in JSON and the log' {
        $script:failDownload = $true
        . $script:preparationLoop
        @($applicationResults | Where-Object Status -ne Succeeded).Count | Should -Be 0
        @($applicationResults | Where-Object AcquisitionOutcome -ne FallbackCacheUsed).Count | Should -Be 0
        @($applicationResults | Where-Object RefreshFailureType -ne Timeout).Count | Should -Be 0
        foreach ($result in $applicationResults) {
            $result.RefreshError | Should -Be 'HTTP download timeout in fixture.'
            $result.Error | Should -BeNullOrEmpty
        }
        Write-PreInstallResult -Status Succeeded
        $saved = Get-Content $preInstallResultPath -Raw | ConvertFrom-Json
        $saved.Status | Should -Be Succeeded
        $saved.FailedBuiltInApplicationCount | Should -Be 0
        $saved.FallbackApplicationCount | Should -Be 6
        $saved.HasAcquisitionWarnings | Should -BeTrue
        @(Get-Content $logPath | Select-String 'ApplicationAcquisitionComplete.*AcquisitionOutcome=FallbackCacheUsed').Count | Should -Be 6
    }

    It 'does not report successful fallback when the payload is absent and continues independent entries' {
        $script:builtInApps = @($builtInApps | Where-Object Id -in @('GoogleChromeEnterprise','CiscoWebex'))
        Remove-Item -LiteralPath (Join-Path $StagedPath 'BuiltIn\GoogleChromeEnterprise\x64\Package.msi')
        $script:failDownload = $true
        . $script:preparationLoop
        $applicationResults[0].Status | Should -Be Failed
        $applicationResults[0].AcquisitionOutcome | Should -Be Failed
        $applicationResults[0].Error | Should -Match 'no staged fallback'
        $applicationResults[1].AcquisitionOutcome | Should -Be FallbackCacheUsed
    }

    It 'does not label rejected fallback signatures as successful cache use' {
        $script:builtInApps = @($builtInApps | Where-Object Id -eq GoogleChromeEnterprise)
        $script:failDownload = $true
        Mock Assert-PreInstallSignedPayload { throw [Security.SecurityException]::new('Publisher rejected in fixture.') }
        { . $script:preparationLoop } | Should -Throw '*Publisher rejected*'
        $applicationResults[0].Status | Should -Be Failed
        $applicationResults[0].AcquisitionOutcome | Should -Be Failed
        $applicationResults[0].FailureType | Should -Be TrustValidationFailed
    }

    It 'carries fallback into both successful and failed installer results independently of stale cache metadata' {
        $script:builtInApps = @($builtInApps | Where-Object Id -eq GoogleChromeEnterprise)
        $script:failDownload = $true
        . $script:preparationLoop
        Write-PreInstallResult -Status Succeeded
        $preInstallResult = Get-Content $preInstallResultPath -Raw | ConvertFrom-Json
        $success = New-RunnerApplicationResult -App $builtInApps[0] -Status Succeeded -Execution ([pscustomobject]@{ ExitCode=0; Integrity='PublisherValidatedByPreInstall' })
        $success.Status | Should -Be Succeeded
        $success.AcquisitionOutcome | Should -Be FallbackCacheUsed
        $success.RefreshFailureType | Should -Be Timeout
        $failed = New-RunnerApplicationResult -App $builtInApps[0] -Status Failed -FailureType InstallerFailed -ErrorMessage 'Installer exit code 42.'
        $failed.AcquisitionOutcome | Should -Be FallbackCacheUsed
        $failed.FailureType | Should -Be InstallerFailed
        $failed.RefreshError | Should -Be 'HTTP download timeout in fixture.'
        $failed.Error | Should -Be 'Installer exit code 42.'
        $applicationResults.Clear(); $applicationResults.Add($success)
        $apps = $builtInApps; $cleanupMode = 'OnSuccess'
        $runnerStopwatch = [Diagnostics.Stopwatch]::StartNew(); $runnerStartedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        $resultPath = Join-Path $StagedPath 'Results\Latest.json'
        Write-RunnerResult -Status Succeeded
        $latest = Get-Content $resultPath -Raw | ConvertFrom-Json
        $latest.Status | Should -Be Succeeded
        $latest.PreInstall.FallbackApplicationCount | Should -Be 1
        $latest.Applications[0].AcquisitionOutcome | Should -Be FallbackCacheUsed
    }

    It 'keeps older PreInstall results readable and does not infer freshness from old CacheInfo' {
        $preInstallResult = [pscustomobject]@{ Applications=@([pscustomobject]@{ Id='MicrosoftTeams'; Status='Succeeded' }) }
        $result = New-RunnerApplicationResult -App $builtInApps[1] -Status Succeeded
        $result.AcquisitionOutcome | Should -Be Unknown
        $result.RefreshError | Should -BeNullOrEmpty
        $repositoryApp = [pscustomobject]@{ Id='CustomScript'; Source='Repository'; PackageType='Script' }
        (New-RunnerApplicationResult -App $repositoryApp -Status Succeeded).AcquisitionOutcome | Should -Be NotApplicable
    }
}
