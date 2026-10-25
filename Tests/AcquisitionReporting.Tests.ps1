BeforeAll { . (Join-Path $PSScriptRoot 'Helpers/NativePayloadFixtures.ps1') }
Describe 'Per-deployment acquisition reporting' {
    BeforeAll {
        . (Join-Path (Split-Path $PSScriptRoot -Parent) 'Runtime/OSDAppPayloadFile.ps1')
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
        if (-not $loop) { throw 'PreInstall app loop not found.' }
        $script:preparationLoop = [scriptblock]::Create($loop.Extent.Text)
        . (Join-Path $moduleRoot 'Runtime\Assert-OSDAppTransactionSpace.ps1')
        . (Join-Path $moduleRoot 'Runtime\Restore-OSDAppCacheGeneration.ps1')
        . (Join-Path $moduleRoot 'Runtime\Invoke-OSDAppBuiltInCacheTransaction.ps1')
        . (Join-Path $moduleRoot 'Runtime\Test-OSDAppOfficeCacheCompatibility.ps1')
        $runnerAst = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $moduleRoot 'Runtime\Invoke-OSDAppRunner.ps1'), [ref]$tokens, [ref]$errors)
        foreach ($name in @('Get-RunnerCacheInfo','New-RunnerAppResult','Write-RunnerResult')) {
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
        Mock Invoke-WebRequest { Set-Content -LiteralPath $OutFile -Value 'changed CDN descriptor' }
        $script:advertisedOfficeBuild = '2.0.0.0'
        Mock Expand-OSDAppOfficeDescriptor {
            $path = Join-Path $DestinationPath 'VersionDescriptor.xml'
            '<Version><Available I640Version="{0}" /><DeliveryMechanism FFNRoot="492350f6-3a01-4f97-b9c0-c7c6ddf67d60" /></Version>' -f $script:advertisedOfficeBuild | Set-Content $path
            $path
        }
        $ErrorActionPreference = 'Stop'
        $script:StagedPath = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $StagedPath -Force | Out-Null
        $script:usbRoot = $null
        $script:networkAvailable = $true
        $script:appResults = [System.Collections.Generic.List[object]]::new()
        $script:preInstallStopwatch = [Diagnostics.Stopwatch]::StartNew()
        $script:preInstallStartedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        $script:OfficeRefreshTimeoutMinutes = 1
        $script:manifest = [pscustomobject]@{ DeploymentId = [guid]::NewGuid().Guid }
        $script:preInstallResult = $null
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
            if ($DestinationDirectory) { $DestinationPath = Join-Path $DestinationDirectory ('vendor-' + $Id + $ExpectedExtension) }
            if ($DestinationPath -match '\.zip$') { New-TestArchive -Path $DestinationPath }
            elseif ($DestinationPath -match '\.msix$') { New-TestArchive -Path $DestinationPath -Teams }
            else { Set-Content -LiteralPath $DestinationPath -Value 'new fixture payload' }
            Get-Item -LiteralPath $DestinationPath
        }
        Mock Start-Process {
            New-TestOfficePayload -Root $WorkingDirectory
            [pscustomobject]@{ HasExited=$true; ExitCode=0 }
        }
        $script:builtInApps = @(
            [pscustomobject]@{ Id='Microsoft365Apps'; Type='OfficeDeploymentTool'; Relative='BuiltIn\Microsoft365Apps'; File='setup.exe' }
            [pscustomobject]@{ Id='MicrosoftTeams'; Type='MicrosoftTeamsBootstrapper'; Relative='BuiltIn\MicrosoftTeams'; File='MSTeams-x64.msix' }
            [pscustomobject]@{ Id='AdobeAcrobatUnified'; Type='AdobeAcrobatUnifiedZip'; Relative='BuiltIn\AdobeAcrobatUnified\x64'; File='Acrobat_DC_Web_x64_WWMUI.zip' }
            [pscustomobject]@{ Id='GoogleChromeEnterprise'; Type='VendorMsi'; Relative='BuiltIn\GoogleChromeEnterprise\x64'; File='googlechromestandaloneenterprise64.msi' }
            [pscustomobject]@{ Id='MozillaFirefoxEnterprise'; Type='VendorMsi'; Relative='BuiltIn\MozillaFirefoxEnterprise\Rapid\x64\en-US'; File='Firefox Setup 145.0.msi'; Channel='Rapid'; Language='en-US' }
            [pscustomobject]@{ Id='ZoomWorkplace'; Type='VendorMsi'; Relative='BuiltIn\ZoomWorkplace\x64'; File='ZoomInstallerFull.msi' }
            [pscustomobject]@{ Id='CiscoWebex'; Type='VendorMsi'; Relative='BuiltIn\CiscoWebex\x64'; File='Webex_en.msi' }
        )
        foreach ($app in $builtInApps) {
            $app | Add-Member Architecture x64
            $app | Add-Member Source BuiltIn
            $app | Add-Member DisplayName $app.Id
            $app | Add-Member PackageUri ('https://example.invalid/' + [uri]::EscapeDataString($app.File))
            if ($app.Id -eq 'MicrosoftTeams') {
                $app | Add-Member MsixUri $app.PackageUri
                $app | Add-Member BootstrapperUri 'https://example.invalid/teamsbootstrapper.exe'
            }
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
                Set-Content -LiteralPath (Join-Path $root 'configuration.xml') -Value '<Configuration><Add OfficeClientEdition="64" Channel="Current"><Product ID="O365ProPlusRetail"><Language ID="en-us" /></Product></Add></Configuration>'
            }
            $cacheInfo = @{ Id=$app.Id; Version='1.0.0.0'; Architecture='x64'; RemoteETag='old'; Updated=$true; Cached=$true; PackageUri=$app.PackageUri }
            if ($app.Id -eq 'Microsoft365Apps') {
                $cacheInfo.PayloadProfile = Get-OSDAppOfficePayloadProfile -Path (Join-Path $root 'configuration.xml')
            }
            if ($app.Id -ne 'Microsoft365Apps') {
                $cacheInfo.PayloadFileName = $app.File
                $cacheInfo.Sha256 = (Get-FileHash -LiteralPath $payload).Hash
                $cacheInfo.Size = (Get-Item -LiteralPath $payload).Length
            }
            $cacheInfo | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $root 'CacheInfo.json') -Encoding UTF8
            Set-OSDAppManifestPayload -App $app -StagedPath $StagedPath -AllowPending
        }
    }

    It 'keeps vendor filenames through USB acquisition, staging and warm reuse for all six HTTP payloads' {
        $script:builtInApps = @($builtInApps | Where-Object Id -ne Microsoft365Apps)
        $script:usbRoot = Join-Path $TestDrive 'NativeUsb'
        Mock Restore-PreInstallBuiltInCache { }
        Mock Save-PreInstallDownload {
            if ($DestinationDirectory) { $DestinationPath = Join-Path $DestinationDirectory ('vendor-' + $Id + $ExpectedExtension) }
            if ($DestinationPath -match '\.zip$') { New-TestArchive -Path $DestinationPath }
            elseif ($DestinationPath -match '\.msix$') { New-TestArchive -Path $DestinationPath -Teams }
            else { Set-Content -LiteralPath $DestinationPath -Value 'native fixture payload' }
            Get-Item -LiteralPath $DestinationPath
        }
        . $script:preparationLoop
        @($appResults | Where-Object AcquisitionOutcome -ne Downloaded).Count | Should -Be 0
        foreach ($row in $appResults) { $row.PackageUpdated | Should -BeTrue }
        foreach ($app in $builtInApps) {
            $name = 'vendor-' + $app.Id + [IO.Path]::GetExtension($app.File)
            $cached = Join-Path (Join-Path $usbRoot $app.Relative) $name
            $staged = Join-Path (Join-Path $StagedPath $app.Relative) $name
            (Get-FileHash $staged).Hash | Should -Be (Get-FileHash $cached).Hash
            Test-Path (Join-Path (Join-Path $StagedPath $app.Relative) $app.File) | Should -BeFalse
        }
        # The recorded new ETag still matches the same remote ETag.
        $appResults.Clear()
        Mock Save-PreInstallDownload {
            if ((Split-Path $DestinationPath -Leaf) -ne 'teamsbootstrapper.exe') { throw 'Primary payload must be reused.' }
            Set-Content -LiteralPath $DestinationPath -Value 'bootstrapper fixture'
            Get-Item -LiteralPath $DestinationPath
        }
        . $script:preparationLoop
        @($appResults | Where-Object AcquisitionOutcome -ne CacheReused).Count | Should -Be 0
        foreach ($row in $appResults) { $row.PackageUpdated | Should -BeFalse }
    }

    It 'reports a fresh acquisition for all seven built-ins even when the Office version did not change' {
        . $script:preparationLoop
        $appResults.Count | Should -Be 7
        @($appResults | Where-Object Status -ne Succeeded).Count | Should -Be 0
        @($appResults | Where-Object AcquisitionOutcome -ne Downloaded).Count | Should -Be 0
        foreach ($row in $appResults) { $row.PackageUpdated | Should -BeTrue }
        (Get-Content (Join-Path $StagedPath 'BuiltIn\Microsoft365Apps\CacheInfo.json') -Raw | ConvertFrom-Json).Updated | Should -BeFalse
        @($appResults | Where-Object { $_.RefreshError }).Count | Should -Be 0
        ($appResults | Where-Object Id -eq Microsoft365Apps).CacheDecisionReason | Should -Match 'does not match.*build'
        foreach ($result in @($appResults | Where-Object Id -ne Microsoft365Apps)) {
            $result.CacheDecisionReason | Should -Match 'HTTP metadata differs'
        }
    }

    It 'reuses current Office without starting ODT, downloading setup, or changing staged payloads' {
        $script:builtInApps = @($builtInApps | Where-Object Id -eq Microsoft365Apps)
        $script:advertisedOfficeBuild = '1.0.0.0'
        $root = Join-Path $StagedPath 'BuiltIn\Microsoft365Apps'
        $before = @(Get-ChildItem $root -File -Recurse | Get-FileHash | Sort-Object Path | ForEach-Object { $_.Path + ':' + $_.Hash })
        . $script:preparationLoop
        $appResults[0].Status | Should -Be Succeeded
        $appResults[0].AcquisitionOutcome | Should -Be CacheReused
        $appResults[0].PackageUpdated | Should -BeFalse
        $appResults[0].RefreshError | Should -BeNullOrEmpty
        $appResults[0].CacheDecisionReason | Should -Match 'cached build matches'
        Should -Invoke Start-Process -Exactly 0
        Should -Invoke Save-PreInstallDownload -Exactly 0
        Should -Invoke Assert-OSDAppTransactionSpace -Exactly 0
        Should -Invoke Assert-PreInstallSignedPayload -Exactly 1
        $after = @(Get-ChildItem $root -File -Recurse | Get-FileHash | Sort-Object Path | ForEach-Object { $_.Path + ':' + $_.Hash })
        Compare-Object $before $after | Should -BeNullOrEmpty
    }

    It 'restages and reuses a current USB Office generation without mutating the USB cache' {
        $script:builtInApps = @($builtInApps | Where-Object Id -eq Microsoft365Apps)
        $script:advertisedOfficeBuild = '1.0.0.0'
        Mock Restore-PreInstallBuiltInCache { }
        $script:usbRoot = Join-Path $TestDrive 'UsbCache'
        $local = Join-Path $StagedPath 'BuiltIn\Microsoft365Apps'
        $usbOffice = Join-Path $usbRoot 'BuiltIn\Microsoft365Apps'
        New-Item (Split-Path $usbOffice -Parent) -ItemType Directory -Force | Out-Null
        Copy-Item $local $usbOffice -Recurse
        $before = @(Get-ChildItem $usbOffice -File -Recurse | Get-FileHash | Sort-Object Path | ForEach-Object { $_.Path + ':' + $_.Hash })
        Remove-Item (Join-Path $local 'Office') -Recurse -Force
        Remove-Item (Join-Path $local 'CacheInfo.json'),(Join-Path $local 'setup.exe') -Force
        . $script:preparationLoop
        $appResults[0].Status | Should -Be Succeeded
        $appResults[0].AcquisitionOutcome | Should -Be CacheReused
        $appResults[0].PackageUpdated | Should -BeFalse
        Should -Invoke Start-Process -Exactly 0
        Should -Invoke Save-PreInstallDownload -Exactly 0
        $after = @(Get-ChildItem $usbOffice -File -Recurse | Get-FileHash | Sort-Object Path | ForEach-Object { $_.Path + ':' + $_.Hash })
        Compare-Object $before $after | Should -BeNullOrEmpty
        Test-LocalOfficeSource -Root $local -ConfigurationPath (Join-Path $local 'configuration.xml') | Should -BeTrue
    }

    It 'downloads when Office configuration changed even if the CDN descriptor would match' {
        $script:builtInApps = @($builtInApps | Where-Object Id -eq Microsoft365Apps)
        $script:advertisedOfficeBuild = '1.0.0.0'
        $config = Join-Path $StagedPath 'BuiltIn\Microsoft365Apps\configuration.xml'
        (Get-Content $config -Raw).Replace('en-us','nl-nl') | Set-Content $config
        . $script:preparationLoop
        $appResults[0].AcquisitionOutcome | Should -Be Downloaded
        $appResults[0].CacheDecisionReason | Should -Match 'incompatible.*configuration'
        Should -Invoke Start-Process -Exactly 1
        Should -Invoke Invoke-WebRequest -Exactly 0
    }

    It 'downloads when the staged generation is inconsistent instead of treating metadata as sufficient' {
        $script:builtInApps = @($builtInApps | Where-Object Id -eq Microsoft365Apps)
        Set-Content (Join-Path $StagedPath 'BuiltIn\Microsoft365Apps\Office\Data\v64.cab') 'inconsistent'
        Mock Invoke-WebRequest { Set-Content -LiteralPath $OutFile -Value inconsistent }
        . $script:preparationLoop
        $appResults[0].AcquisitionOutcome | Should -Be Downloaded
        $appResults[0].CacheDecisionReason | Should -Match 'Office generation validation failed'
        Should -Invoke Start-Process -Exactly 1
        Should -Invoke Invoke-WebRequest -Exactly 0
    }

    It 'records a freshness-check failure as fallback, never as confirmed reuse' {
        $script:builtInApps = @($builtInApps | Where-Object Id -eq Microsoft365Apps)
        Mock Invoke-WebRequest { throw 'Office metadata request timeout.' }
        . $script:preparationLoop
        $appResults[0].Status | Should -Be Succeeded
        $appResults[0].AcquisitionOutcome | Should -Be FallbackCacheUsed
        $appResults[0].RefreshError | Should -Be 'Office metadata request timeout.'
        $appResults[0].CacheDecisionReason | Should -Match 'Refresh failed.*Office metadata request timeout'
        Should -Invoke Start-Process -Exactly 0
        Should -Invoke Save-PreInstallDownload -Exactly 0
    }

    It 'reports metadata-confirmed primary-payload reuse for all six HTTP built-ins' {
        $script:builtInApps = @($builtInApps | Where-Object Id -ne Microsoft365Apps)
        $script:remoteMatches = $true
        . $script:preparationLoop
        $appResults.Count | Should -Be 6
        foreach ($result in $appResults) { $result.CacheDecisionReason | Should -Match 'matches the vendor HTTP metadata' }
        ($appResults | Where-Object Id -eq MicrosoftTeams).CacheDecisionReason | Should -Match 'bootstrapper is downloaded separately'
        @($appResults | Where-Object AcquisitionOutcome -ne CacheReused).Count | Should -Be 0
        foreach ($row in $appResults) { $row.PackageUpdated | Should -BeFalse }
        Should -Invoke Save-PreInstallDownload -Exactly 1 -ParameterFilter { $Id -eq 'MicrosoftTeams' -and $Description -eq 'Microsoft Teams bootstrapper' }
        Should -Invoke Save-PreInstallDownload -Exactly 0 -ParameterFilter { $Description -ne 'Microsoft Teams bootstrapper' }
    }

    It 'reports offline use without inventing a refresh failure for any built-in' {
        $script:networkAvailable = $false
        . $script:preparationLoop
        @($appResults | Where-Object AcquisitionOutcome -ne OfflineCacheUsed).Count | Should -Be 0
        foreach ($row in $appResults) { $row.PackageUpdated | Should -BeFalse }
        @($appResults | Where-Object { $_.RefreshError }).Count | Should -Be 0
        Should -Invoke Save-PreInstallDownload -Exactly 0
        Write-PreInstallResult -Status Succeeded
        $saved = Get-Content $preInstallResultPath -Raw | ConvertFrom-Json
        $saved.OfflineCacheAppCount | Should -Be 7
        foreach ($result in $saved.Apps) { $result.CacheDecisionReason | Should -Match 'No network.*Currency was not checked' }
        $saved.FallbackAppCount | Should -Be 0
        $saved.HasAcquisitionWarnings | Should -BeTrue
    }

    It 'preserves refresh failure reasons for all seven successful fallbacks in JSON and the log' {
        $script:failDownload = $true
        . $script:preparationLoop
        @($appResults | Where-Object Status -ne Succeeded).Count | Should -Be 0
        @($appResults | Where-Object AcquisitionOutcome -ne FallbackCacheUsed).Count | Should -Be 0
        foreach ($row in $appResults) { $row.PackageUpdated | Should -BeFalse }
        @($appResults | Where-Object RefreshFailureType -ne Timeout).Count | Should -Be 0
        foreach ($result in $appResults) {
            $result.RefreshError | Should -Be 'HTTP download timeout in fixture.'
            $result.CacheDecisionReason | Should -Match 'Refresh failed.*HTTP download timeout'
            $result.Error | Should -BeNullOrEmpty
        }
        Write-PreInstallResult -Status Succeeded
        $saved = Get-Content $preInstallResultPath -Raw | ConvertFrom-Json
        $saved.Status | Should -Be Succeeded
        $saved.FailedBuiltInAppCount | Should -Be 0
        $saved.FallbackAppCount | Should -Be 7
        $saved.HasAcquisitionWarnings | Should -BeTrue
        foreach ($result in $saved.Apps) { $result.CacheDecisionReason | Should -Match 'Refresh failed.*HTTP download timeout' }
        @(Get-Content $logPath | Select-String 'AppAcquisitionComplete.*CacheDecisionReason=Refresh failed').Count | Should -Be 7
        @(Get-Content $logPath | Select-String 'AppAcquisitionComplete.*AcquisitionOutcome=FallbackCacheUsed').Count | Should -Be 7
    }

    It 'does not report successful fallback when the payload is absent and continues independent entries' {
        $script:builtInApps = @($builtInApps | Where-Object Id -in @('GoogleChromeEnterprise','CiscoWebex'))
        Remove-Item -LiteralPath (Join-Path $StagedPath 'BuiltIn\GoogleChromeEnterprise\x64\googlechromestandaloneenterprise64.msi')
        $script:failDownload = $true
        . $script:preparationLoop
        $appResults[0].Status | Should -Be Failed
        $appResults[0].AcquisitionOutcome | Should -Be Failed
        $appResults[0].PackageUpdated | Should -BeNullOrEmpty
        $appResults[0].Error | Should -Match 'no staged fallback'
        $appResults[0].CacheDecisionReason | Should -Match '^Acquisition failed.*no staged fallback'
        $appResults[1].AcquisitionOutcome | Should -Be FallbackCacheUsed
    }

    It 'does not label rejected fallback signatures as successful cache use' {
        $script:builtInApps = @($builtInApps | Where-Object Id -eq GoogleChromeEnterprise)
        $script:failDownload = $true
        Mock Assert-PreInstallSignedPayload { throw [Security.SecurityException]::new('Publisher rejected in fixture.') }
        { . $script:preparationLoop } | Should -Throw '*Publisher rejected*'
        $appResults[0].Status | Should -Be Failed
        $appResults[0].AcquisitionOutcome | Should -Be Failed
        $appResults[0].PackageUpdated | Should -BeNullOrEmpty
        $appResults[0].FailureType | Should -Be TrustValidationFailed
        $appResults[0].CacheDecisionReason | Should -Match '^Acquisition failed.*Publisher rejected'
    }

    It 'carries fallback into both successful and failed installer results independently of stale cache metadata' {
        $script:builtInApps = @($builtInApps | Where-Object Id -eq GoogleChromeEnterprise)
        $script:failDownload = $true
        . $script:preparationLoop
        Write-PreInstallResult -Status Succeeded
        $preInstallResult = Get-Content $preInstallResultPath -Raw | ConvertFrom-Json
        $success = New-RunnerAppResult -App $builtInApps[0] -Status Succeeded -Execution ([pscustomobject]@{ ExitCode=0; Integrity='PublisherValidatedByPreInstall' })
        $success.Status | Should -Be Succeeded
        $success.PackageUpdated | Should -BeFalse
        $success.CacheUsed | Should -BeFalse
        $success.AcquisitionOutcome | Should -Be FallbackCacheUsed
        $success.RefreshFailureType | Should -Be Timeout
        $failed = New-RunnerAppResult -App $builtInApps[0] -Status Failed -FailureType InstallerFailed -ErrorMessage 'Installer exit code 42.'
        $failed.AcquisitionOutcome | Should -Be FallbackCacheUsed
        $failed.FailureType | Should -Be InstallerFailed
        $failed.PackageUpdated | Should -BeFalse
        $failed.RefreshError | Should -Be 'HTTP download timeout in fixture.'
        $failed.Error | Should -Be 'Installer exit code 42.'
        $failed.CacheDecisionReason | Should -Be $success.CacheDecisionReason
        $success.CacheDecisionReason | Should -Match 'Refresh failed.*HTTP download timeout'
        $appResults.Clear(); $appResults.Add($success)
        $apps = $builtInApps; $cleanupMode = 'OnSuccess'
        $runnerStopwatch = [Diagnostics.Stopwatch]::StartNew(); $runnerStartedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        $resultPath = Join-Path $StagedPath 'Results\Latest.json'
        Write-RunnerResult -Status Succeeded
        $latest = Get-Content $resultPath -Raw | ConvertFrom-Json
        $latest.Status | Should -Be Succeeded
        $latest.PreInstall.FallbackAppCount | Should -Be 1
        $latest.Apps[0].AcquisitionOutcome | Should -Be FallbackCacheUsed
        $latest.Apps[0].PackageUpdated | Should -BeFalse
        $latest.PreInstall.Apps[0].PackageUpdated | Should -BeFalse
        $latest.Apps[0].CacheDecisionReason | Should -Be $success.CacheDecisionReason
    }


    It 'explains missing payload and insufficient freshness metadata without accepting malformed cache records' {
        $script:builtInApps = @($builtInApps | Where-Object Id -eq GoogleChromeEnterprise)
        $root = Join-Path $StagedPath 'BuiltIn\GoogleChromeEnterprise\x64'
        $infoPath = Join-Path $root 'CacheInfo.json'
        $script:remoteMatches = $true
        Remove-Item -LiteralPath (Join-Path $root 'googlechromestandaloneenterprise64.msi')
        . $script:preparationLoop
        $appResults[0].AcquisitionOutcome | Should -Be Downloaded
        $appResults[0].CacheDecisionReason | Should -Match 'primary payload is missing'

        $appResults.Clear()
        $appResults.Clear()
        Mock Get-RemoteMetadata { [pscustomobject]@{ ETag=$null; LastModified=$null; ContentLength=100; FinalUri='https://example.test/package' } }
        . $script:preparationLoop
        $appResults[0].AcquisitionOutcome | Should -Be Downloaded
        $appResults[0].CacheDecisionReason | Should -Match 'Comparable.*metadata is unavailable'
    }

    It 'rejects malformed metadata rather than inventing a vendor filename or reusing orphaned bytes' {
        $script:builtInApps = @($builtInApps | Where-Object Id -eq GoogleChromeEnterprise)
        $root = Join-Path $StagedPath 'BuiltIn\GoogleChromeEnterprise\x64'
        Set-Content -LiteralPath (Join-Path $root 'CacheInfo.json') 'invalid JSON'
        . $script:preparationLoop
        $appResults[0].Status | Should -Be Failed
        $appResults[0].AcquisitionOutcome | Should -Be Failed
        $appResults[0].PackageUpdated | Should -BeNullOrEmpty
        Should -Invoke Save-PreInstallDownload -Times 0 -Exactly
        Test-Path -LiteralPath (Join-Path $root 'googlechromestandaloneenterprise64.msi') | Should -BeTrue
    }

    It 'explains last-modified and length comparisons when ETags are absent' {
        $script:builtInApps = @($builtInApps | Where-Object Id -eq GoogleChromeEnterprise)
        $path = Join-Path $StagedPath 'BuiltIn\GoogleChromeEnterprise\x64\CacheInfo.json'
        $info = Get-Content $path -Raw | ConvertFrom-Json
        $info | Add-Member -NotePropertyName RemoteETag -NotePropertyValue $null -Force
        $info | Add-Member -NotePropertyName RemoteLastModified -NotePropertyValue '2026-01-01' -Force
        $info | Add-Member -NotePropertyName RemoteContentLength -NotePropertyValue 100 -Force
        $info | ConvertTo-Json | Set-Content $path
        Mock Get-RemoteMetadata { [pscustomobject]@{ ETag=$null; LastModified='2026-01-01'; ContentLength=100; FinalUri='https://example.test/package' } }
        . $script:preparationLoop
        $appResults[0].AcquisitionOutcome | Should -Be CacheReused
        $appResults[0].PackageUpdated | Should -BeFalse
        $appResults[0].CacheDecisionReason | Should -Match 'matches the vendor HTTP metadata'
        $appResults.Clear()
        Mock Get-RemoteMetadata { [pscustomobject]@{ ETag=$null; LastModified='2026-01-02'; ContentLength=101; FinalUri='https://example.test/package' } }
        . $script:preparationLoop
        $appResults[0].AcquisitionOutcome | Should -Be Downloaded
        $appResults[0].CacheDecisionReason | Should -Match 'HTTP metadata differs'
    }

    It 'retains the incompatible USB Office assessment when only intent was staged locally' {
        $script:builtInApps = @($builtInApps | Where-Object Id -eq Microsoft365Apps)
        Mock Restore-PreInstallBuiltInCache { }
        $script:usbRoot = Join-Path $TestDrive 'UsbCache'
        $local = Join-Path $StagedPath 'BuiltIn\Microsoft365Apps'
        $usbOffice = Join-Path $usbRoot 'BuiltIn\Microsoft365Apps'
        New-Item (Split-Path $usbOffice -Parent) -ItemType Directory -Force | Out-Null
        Copy-Item $local $usbOffice -Recurse
        Remove-Item (Join-Path $local 'Office') -Recurse -Force
        Remove-Item (Join-Path $local 'CacheInfo.json'),(Join-Path $local 'setup.exe') -Force
        $config = Join-Path $local 'configuration.xml'
        (Get-Content $config -Raw).Replace('en-us','nl-nl') | Set-Content $config
        . $script:preparationLoop
        $appResults[0].Status | Should -Be Succeeded
        $appResults[0].AcquisitionOutcome | Should -Be Downloaded
        $appResults[0].CacheDecisionReason | Should -Match 'USB cache assessment:.*incompatible'
    }

    It 'reports Unknown when the current result has no acquisition evidence' {
        $preInstallResult = [pscustomobject]@{ Apps=@([pscustomobject]@{ Id='MicrosoftTeams'; Status='Succeeded' }) }
        $result = New-RunnerAppResult -App $builtInApps[1] -Status Succeeded
        $result.AcquisitionOutcome | Should -Be Unknown
        $result.RefreshError | Should -BeNullOrEmpty
        $result.CacheDecisionReason | Should -BeNullOrEmpty
        $repositoryApp = [pscustomobject]@{ Id='CustomScript'; Source='Repository'; PackageType='Script' }
        $repositoryResult = New-RunnerAppResult -App $repositoryApp -Status Succeeded
        $repositoryResult.AcquisitionOutcome | Should -Be NotApplicable
        $repositoryResult.CacheDecisionReason | Should -BeNullOrEmpty
    }
}
