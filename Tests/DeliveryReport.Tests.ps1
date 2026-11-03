Describe 'Standalone delivery report' {
    BeforeAll {
        $script:root = Split-Path $PSScriptRoot -Parent
        . (Join-Path $script:root 'Runtime/OSDStageDeliveryReport.ps1')
    }
    BeforeEach {
        $script:directory = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        New-Item -ItemType Directory $script:directory | Out-Null
        $script:manifest = [pscustomobject]@{
            DeploymentId=[guid]::NewGuid().Guid
            Runtime=[pscustomobject]@{ModuleVersion='1.0.0-rc3'}
            Packages=@([pscustomobject]@{Id='7Zip';DisplayName='7-Zip'})
        }
        $script:result = [pscustomobject]@{
            DeploymentId=$script:manifest.DeploymentId; Status='Succeeded'; ExpectedPackageCount=1
            StartedAtUtc='2026-11-03T07:00:00Z'; CompletedAtUtc='2026-11-03T07:10:00Z'; DurationSeconds=600
            RebootRequired=$false; Packages=@([pscustomobject]@{Id='7Zip';Status='Succeeded';ExitCode=0;Version='26.05';AcquisitionOutcome='CacheReused'})
        }
        Mock Get-OSDStageReportDevice { [pscustomobject]@{ComputerName='PC1';Manufacturer='Dell';Model='Test';WindowsVersion='26H2';Build='26300';Revision=9711;CollectionStatus='Available'} }
    }
    It 'writes matching offline JSON and HTML without changing the source result' {
        Write-OSDStageDeliveryReport -Result $result -Manifest $manifest -Directory $directory
        $report = Get-Content (Join-Path $directory 'DeliveryReport.json') -Raw | ConvertFrom-Json
        $html = Get-Content (Join-Path $directory 'DeliveryReport.html') -Raw
        $report.Status | Should -Be 'Succeeded'
        $report.Module.Version | Should -Be '1.0.0-rc3'
        $report.Counts.Succeeded | Should -Be 1
        $report.Packages[0].AcquisitionOutcome | Should -Be 'CacheReused'
        $html | Should -Match $report.ReportId
        $html | Should -Not -Match '<script|<link|<img'
        $result.Status | Should -Be 'Succeeded'
    }
    It 'groups apps by recorded source in one card without guessing unknown sources' {
        $report = New-OSDStageDeliveryReport -Result $result -Manifest $manifest -Directory $directory
        $report.Packages = @(
            [pscustomobject]@{Id='BuiltInExample';PackageType='App';Source='BuiltIn';Status='Succeeded'},
            [pscustomobject]@{Id='RepositoryExample';PackageType='App';Source='Repository';Status='Succeeded'},
            [pscustomobject]@{Id='MissingSource';PackageType='App';Status='Succeeded'},
            [pscustomobject]@{Id='UnrecognizedSource';PackageType='App';Source='Other';Status='Succeeded'}
        )
        $html = ConvertTo-OSDStageReportHtml $report
        ([regex]::Matches($html, 'class="panel apps-card"')).Count | Should -Be 1
        $html | Should -Match '(?s)<h3>Built-in apps</h3>.*?BuiltInExample.*?<h3>Repository apps</h3>.*?RepositoryExample.*?<h3>Apps with unknown source</h3>.*?MissingSource.*?UnrecognizedSource'
        $report.Packages[1].Source | Should -Be 'Repository'
        $report.Packages = @($report.Packages[0])
        $html = ConvertTo-OSDStageReportHtml $report
        $html | Should -Match '<h3>Built-in apps</h3>'
        $html | Should -Not -Match '<h3>Repository apps</h3>|<h3>Apps with unknown source</h3>'
    }
    It 'formats HTML durations as minutes and seconds without changing JSON precision' {
        $result.DurationSeconds = 2460.5
        $result.Packages[0] | Add-Member DurationSeconds 213.5
        $manifest.Packages[0] | Add-Member PackageType App
        Write-OSDStageDeliveryReport -Result $result -Manifest $manifest -Directory $directory
        $report = Get-Content (Join-Path $directory 'DeliveryReport.json') -Raw | ConvertFrom-Json
        $html = Get-Content (Join-Path $directory 'DeliveryReport.html') -Raw
        $html | Should -Match '<dt>Duration</dt><dd>41 min 01 sec</dd>'
        $html | Should -Match '<td>3 min 34 sec</td>'
        $html | Should -Match '<th scope="col">Duration</th>'
        $html | Should -Not -Match 'Duration Seconds|2460\.5 seconds'
        $report.DurationSeconds | Should -Be 2460.5
        $report.Packages[0].DurationSeconds | Should -Be 213.5
        $result.DurationSeconds | Should -Be 2460.5
    }
    It 'handles duration boundaries and missing values: <Seconds> becomes <Expected>' -ForEach @(
        @{Seconds=0; Expected='0 min 00 sec'},
        @{Seconds=2.6; Expected='0 min 03 sec'},
        @{Seconds=59.5; Expected='1 min 00 sec'},
        @{Seconds=3601; Expected='60 min 01 sec'},
        @{Seconds=$null; Expected='Unknown'},
        @{Seconds=-1; Expected='Unknown'},
        @{Seconds='invalid'; Expected='Unknown'}
    ) {
        $report = New-OSDStageDeliveryReport -Result $result -Manifest $manifest -Directory $directory
        $report.DurationSeconds = $Seconds
        $report.Packages = @([pscustomobject]@{Id='FileSystem';PackageType='Script';DurationSeconds=$Seconds;Status='Succeeded'})
        $html = ConvertTo-OSDStageReportHtml $report
        $html | Should -Match "<dt>Duration</dt><dd>$Expected</dd>"
        $html | Should -Match "<td>$Expected</td>"
    }
    It 'does not call a successful run with a pending restart fully complete' {
        $result.RebootRequired = $true
        $report = New-OSDStageDeliveryReport -Result $result -Manifest $manifest -Directory $directory
        $report.Status | Should -Be 'Attention'
        $report.ExecutionStatus | Should -Be 'Succeeded'
        $report.RebootRequired | Should -BeTrue
    }
    It 'marks missing and duplicate package results as incomplete' {
        $result.Packages = @()
        $report = New-OSDStageDeliveryReport -Result $result -Manifest $manifest -Directory $directory
        $report.Status | Should -Be 'Attention'
        $report.Packages[0].Status | Should -Be 'Unknown'
        $result.Packages = @([pscustomobject]@{Id='7Zip';Status='Succeeded'},[pscustomobject]@{Id='7Zip';Status='Succeeded'})
        (New-OSDStageDeliveryReport -Result $result -Manifest $manifest -Directory $directory).Status | Should -Be 'Attention'
    }
    It 'reports failures and omits raw diagnostic data and configuration secrets' {
        $result.Status = 'Failed'
        $result.Packages[0].Status = 'Failed'
        $result.Packages[0] | Add-Member Error 'https://source.example/payload?token=supersecret failed; password=hunter2'
        $manifest.Packages[0] | Add-Member Configuration @{Password='unexportable'}
        $report = New-OSDStageDeliveryReport -Result $result -Manifest $manifest -Directory $directory
        $report.Status | Should -Be 'Failed'
        $report.Packages[0].ErrorPresent | Should -BeTrue
        $report | ConvertTo-Json -Depth 16 | Should -Not -Match 'supersecret|hunter2|unexportable|source.example'
    }
    It 'escapes markup in displayed names and redacts URLs' {
        $result.Packages[0].Id = '<script>alert(1)</script> https://example.test/?token=secret'
        $report = New-OSDStageDeliveryReport -Result $result -Manifest $manifest -Directory $directory
        $html = ConvertTo-OSDStageReportHtml $report
        $html | Should -Match '&lt;script&gt;'
        $html | Should -Not -Match '<script>|token=secret'
    }
    It 'does not describe successful acquisition as successful installation after PreInstall fails' {
        $result.Status = 'Failed'
        $report = New-OSDStageDeliveryReport -Result $result -Manifest $manifest -Directory $directory -Phase PreInstall
        $report.Status | Should -Be 'Failed'
        $report.Counts.Succeeded | Should -Be 0
        $report.Packages[0].Status | Should -Be 'NotRun'
    }
    It 'tolerates a missing manifest and unavailable device metadata' {
        Mock Get-OSDStageReportDevice { [pscustomobject]@{CollectionStatus='Unavailable'} }
        $result.Status = 'Failed'
        $report = New-OSDStageDeliveryReport -Result $result -Manifest $null -Directory $directory
        $report.Status | Should -Be 'Failed'
        $report.Device.CollectionStatus | Should -Be 'Unavailable'
    }
    Context 'Windows Update evidence' {
        BeforeEach {
            $manifest.Packages += [pscustomobject]@{Id='WindowsUpdate'}
            $result.ExpectedPackageCount = 2
            $result.Packages += [pscustomobject]@{Id='WindowsUpdate';Status='Succeeded';WindowsUpdateStatus='Succeeded';WindowsUpdateOutcome='RebootRequired'}
            $script:wu = [pscustomobject]@{
                DeploymentId=$result.DeploymentId;Phase='LastWithinSetupComplete';Status='Succeeded';Outcome='RebootRequired'
                StartedAtUtc='2026-11-03T07:02:00Z';CompletedAtUtc='2026-11-03T07:09:00Z';FoundCount=2;SelectedCount=1;InstalledCount=1
                RebootRequired=$true;RebootRequested=$false;FurtherScanRequired=$true;ScanOnly=$false
                Items=@([pscustomobject]@{Title='Driver';Selected=$true;Status='Installed';InstallResultCode=2;InstallHResult=0},[pscustomobject]@{Title='Preview';Selected=$false;Status='Skipped';SelectionReason='ExcludedTitle'})
            }
        }
        It 'includes correlated counters, skipped reasons and reboot flags' {
            $wu | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $directory 'WindowsUpdate-Result.json')
            $report = New-OSDStageDeliveryReport -Result $result -Manifest $manifest -Directory $directory
            $report.WindowsUpdate.InstalledCount | Should -Be 1
            $report.WindowsUpdate.SkippedCount | Should -Be 1
            $report.WindowsUpdate.Items[1].SelectionReason | Should -Be 'ExcludedTitle'
            $report.WindowsUpdate.RebootRequested | Should -BeFalse
            $report.Status | Should -Be 'Attention'
        }
        It 'rejects a previous deployment or a previous execution within the same deployment' {
            $wu.DeploymentId = [guid]::NewGuid().Guid
            $wu | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $directory 'WindowsUpdate-Result.json')
            (New-OSDStageDeliveryReport -Result $result -Manifest $manifest -Directory $directory).WindowsUpdate | Should -BeNullOrEmpty
            $wu.DeploymentId = $result.DeploymentId
            $wu.StartedAtUtc = '2026-11-02T07:02:00Z'
            $wu | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $directory 'WindowsUpdate-Result.json')
            (New-OSDStageDeliveryReport -Result $result -Manifest $manifest -Directory $directory).WindowsUpdate | Should -BeNullOrEmpty
        }
    }
    It 'explains only recorded follow-up reasons: <Case>' -TestCases @(
        @{Case='FollowUpOnly'; Restart=$false; Missing=$false; Expected='Execution succeeded; follow-up update scan recommended.'}
        @{Case='RestartAndFollowUp'; Restart=$true; Missing=$false; Expected='Execution succeeded; restart required. A follow-up update scan is recommended.'}
        @{Case='MissingEvidence'; Restart=$false; Missing=$true; Expected='Review the package results and evidence checks below.'}
    ) {
        param($Restart, $Missing, $Expected)
        $report = [pscustomobject]@{
            Status='Attention';ExecutionStatus='Succeeded';RebootRequired=$Restart
            Checks=@([pscustomobject]@{Passed=(-not $Missing)})
            Counts=[pscustomobject]@{Skipped=0;UnknownOrNotRun=0}
            WindowsUpdate=[pscustomobject]@{FurtherScanRequired=$true;ScanOnly=$false}
        }
        Get-OSDStageReportSummary $report | Should -Be $Expected
    }
    It 'does not present failed execution as a completed deployment in the headline' {
        $result.Status = 'Failed'
        $report = New-OSDStageDeliveryReport -Result $result -Manifest $manifest -Directory $directory
        $html = ConvertTo-OSDStageReportHtml $report
        $html | Should -Match '<h1>Deployment report[.]'
        $html | Should -Not -Match 'Deployment complete[.]'
    }
    It 'does not leave a previous green report when rendering fails' {
        Write-OSDStageDeliveryReport -Result $result -Manifest $manifest -Directory $directory
        Mock ConvertTo-OSDStageReportHtml { throw 'render failure' }
        { Write-OSDStageDeliveryReport -Result $result -Manifest $manifest -Directory $directory } | Should -Throw
        Test-Path (Join-Path $directory 'DeliveryReport.html') | Should -BeFalse
        Test-Path (Join-Path $directory 'DeliveryReport.json') | Should -BeFalse
    }
    It 'isolates report failures from final runner result writes' {
        # Exercise the actual result-writing function, not a duplicate reporting wrapper.
        $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'Runtime/Invoke-OSDStageRunner.ps1'),[ref]$null,[ref]$null)
        $fn = $ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Write-RunnerResult'},$true)
        . ([scriptblock]::Create($fn.Extent.Text))
        $resultPath = Join-Path $directory 'Latest.json'
        $runnerStartedAtUtc = $result.StartedAtUtc
        $runnerStopwatch = [Diagnostics.Stopwatch]::StartNew()
        $appResults = $result.Packages; $apps=$manifest.Packages
        # The dot-source location in this extracted function has no helper: bootstrap failure must be isolated.
        { Write-RunnerResult -Status Succeeded -WarningAction SilentlyContinue } | Should -Not -Throw
        (Get-Content $resultPath -Raw | ConvertFrom-Json).Status | Should -Be 'Succeeded'
    }
    It 'imports recorded component rows with allowlisted fields: <Kind>' -TestCases @(
        @{Kind='Font'; Id='TestFonts'; Source='Repository'; Type='RepositoryPackage'; PackageType='Font'; File='Font-TestFonts-Result.json'; Count='FontCount'; Identity='Id'; Row=@{FileName='Example.ttf';RegistrationName='Example';Status='Installed';Outcome='Installed'}; Field='FileName'; Value='Example.ttf'}
        @{Kind='Certificate'; Id='TestCA'; Source='Repository'; Type='RepositoryPackage'; PackageType='Certificate'; File='Certificate-TestCA-Result.json'; Count='OperationCount'; Identity='PackageId'; Row=@{Subject='CN=Example CA';Thumbprint='ABCD';Store='LocalMachine\Root';Status='Succeeded';Outcome='Imported'}; Field='Store'; Value='LocalMachine\Root'}
        @{Kind='Driver'; Id='TestDrivers'; Source='Repository'; Type='RepositoryPackage'; PackageType='Driver'; File='Driver-TestDrivers-Result.json'; Count='InfCount'; Identity='PackageId'; Row=@{Inf='example.inf';Status='Succeeded';DriverStoreStatus='AddedOrAlreadyPresent';DeviceInstallStatus='NoMatchingDeviceOrBetterDriver';DeviceBindingConfirmed=$null}; Field='DeviceInstallStatus'; Value='NoMatchingDeviceOrBetterDriver'}
        @{Kind='Certificates'; Id='Certificates'; Source='BuiltIn'; Type='CertificateScript'; PackageType='Script'; File='Certificates-Result.json'; Count='OperationCount'; Row=@{Subject='CN=Example CA';Thumbprint='ABCD';Store='LocalMachine\CA';Status='Succeeded';Outcome='AlreadyPresent'}; Field='Outcome'; Value='AlreadyPresent'}
        @{Kind='Services'; Id='Services'; Source='BuiltIn'; Type='ServiceScript'; PackageType='Script'; File='Services-Result.json'; Count='OperationCount'; Row=@{Name='Example';Status='Succeeded';Outcome='Applied';Before=@{StartupType='Manual';State='Stopped'};After=@{StartupType='Automatic';State='Running'}}; Field='StartupTypeAfter'; Value='Automatic'}
        @{Kind='FileSystem'; Id='FileSystem'; Source='BuiltIn'; Type='FileSystemScript'; PackageType='Script'; File='FileSystem-Result.json'; Count='OperationCount'; Row=@{Kind='File';Action='Copy';Path='C:\Example.txt';Status='Succeeded';Outcome='Copied'}; Field='Path'; Value='C:\Example.txt'}
        @{Kind='Registry'; Id='RegistrySettings'; Source='Repository'; Type='RepositoryPackage'; PackageType='Script'; File='Registry-Result.json'; Count='OperationCount'; Row=@{Path='HKLM:\Software\Example';Name='Setting';Action='SetValue';Status='Succeeded';Outcome='Set'}; Field='Action'; Value='SetValue'}
        @{Kind='EnvironmentVariables'; Id='EnvironmentVariables'; Source='BuiltIn'; Type='EnvironmentVariableScript'; PackageType='Script'; File='EnvironmentVariables-Result.json'; Count='OperationCount'; Row=@{Name='Example';Action='Set';Status='Succeeded';Outcome='Set'}; Field='Name'; Value='Example'}
        @{Kind='DesktopSettings'; Id='DesktopSettings'; Source='BuiltIn'; Type='DesktopSettingsScript'; PackageType='Script'; File='DesktopSettings-Result.json'; Count='OperationCount'; Row=@{Kind='StartPins';Status='Succeeded';Detail=@{Outcome='ConfiguredForFirstSignIn';PinCount=2;ApplyOnce=$true;Secret='do-not-export'}}; Field='Outcome'; Value='ConfiguredForFirstSignIn'}
        @{Kind='WindowsFeatures'; Id='WindowsFeatures'; Source='BuiltIn'; Type='WindowsFeatureScript'; PackageType='Script'; File='WindowsFeatures-Result.json'; Count='OperationCount'; Row=@{Name='TelnetClient';Action='Enable';Status='Succeeded';Outcome='Enabled';StateBefore='Disabled';StateAfter='Enabled'}; Field='StateAfter'; Value='Enabled'}
        @{Kind='WindowsCapabilities'; Id='WindowsCapabilities'; Source='BuiltIn'; Type='WindowsCapabilityScript'; PackageType='Script'; File='WindowsCapabilities-Result.json'; Count='OperationCount'; Row=@{Name='Example';Action='Add';Status='Succeeded';Outcome='PendingRestart';RestartNeeded=$true}; Field='Outcome'; Value='PendingRestart'}
        @{Kind='DefaultAssociations'; Id='DefaultAssociations'; Source='BuiltIn'; Type='DefaultAssociationScript'; PackageType='Script'; File='DefaultAssociations-Result.json'; Count='RequestedCount'; Row=@{Identifier='.pdf';ProgId='Example.Pdf';AppName='Example'}; Field='Outcome'; Value='ImportedForFirstSignIn'}
        @{Kind='WiFiProfiles'; Id='WiFiProfiles'; Source='BuiltIn'; Type='WiFiProfileScript'; PackageType='Script'; File='WiFiProfiles-Result.json'; Count='OperationCount'; Row=@{Name='Example';Status='Succeeded';Outcome='Imported';Xml='<keyMaterial>do-not-export</keyMaterial>'}; Field='Outcome'; Value='Imported'}
    ) {
        param($Kind,$Id,$Source,$Type,$PackageType,$File,$Count,$Identity,$Row,$Field,$Value)
        $manifest.Packages=@([pscustomobject]@{Id=$Id;Source=$Source;Type=$Type;PackageType=$PackageType;RegistryStageSchema=1})
        $result.Packages=@([pscustomobject]@{Id=$Id;Status='Succeeded';ExitCode=0})
        $record=@{SchemaVersion=2;DeploymentId=$result.DeploymentId;Status='Succeeded';$Count=1;Error='do-not-export';CommandLine='do-not-export'}
        if ($Identity) { $record[$Identity]=$Id }
        $Row['Data']='do-not-export';$Row['Content']='do-not-export';$Row['Value']='do-not-export'
        if ($Kind -eq 'DefaultAssociations') { $record.Associations=@($Row);$record.Outcome='ImportedForFirstSignIn';$record.UserDefaultsVerified=$false }
        else { $record.Items=@($Row) }
        $path=Join-Path $directory $File
        $record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path
        (Get-Item $path).LastWriteTimeUtc=[datetime]'2026-11-03T07:05:00Z'
        Write-OSDStageDeliveryReport -Result $result -Manifest $manifest -Directory $directory
        $report=Get-Content (Join-Path $directory 'DeliveryReport.json') -Raw | ConvertFrom-Json
        $report.Packages[0].Details.Evidence | Should -Be 'Matched'
        $report.Packages[0].Details.Items.Count | Should -Be 1
        $report.Packages[0].Details.Items[0].$Field | Should -Be $Value
        $report.Status | Should -Be 'Succeeded'
        $report | ConvertTo-Json -Depth 16 | Should -Not -Match 'do-not-export'
        $html=Get-Content (Join-Path $directory 'DeliveryReport.html') -Raw
        $html | Should -Match 'component details'
        $html | Should -Match ([regex]::Escape([Net.WebUtility]::HtmlEncode([string]$Value)))
        $html | Should -Not -Match 'do-not-export'
    }
    It 'excludes unusable component evidence without changing package outcomes: <Case>' -TestCases @(
        @{Case='Missing'};@{Case='WrongDeployment'};@{Case='OldSameDeployment'};@{Case='Future'}
        @{Case='WrongPackage'};@{Case='WrongStatus'};@{Case='WrongCount'};@{Case='FailedChild'}
        @{Case='Malformed'};@{Case='UnknownSchema'};@{Case='UnknownChildStatus'}
    ) {
        param($Case)
        $manifest.Packages=@([pscustomobject]@{Id='Fonts';Source='Repository';Type='RepositoryPackage';PackageType='Font'})
        $result.Packages=@([pscustomobject]@{Id='Fonts';Status='Succeeded';ExitCode=0})
        $record=@{SchemaVersion=2;DeploymentId=$result.DeploymentId;Id='Fonts';Status='Succeeded';FontCount=1;Items=@(@{FileName='do-not-import.ttf';Status='Installed'})}
        switch ($Case) {
            WrongDeployment {$record.DeploymentId=[guid]::NewGuid().Guid}
            WrongPackage {$record.Id='OtherFonts'}
            WrongStatus {$record.Status='Failed'}
            WrongCount {$record.FontCount=2}
            FailedChild {$record.Items[0].Status='Failed'}
            UnknownChildStatus {$record.Items[0].Status='Perhaps'}
            UnknownSchema {$record.SchemaVersion=99}
        }
        $path=Join-Path $directory 'Font-Fonts-Result.json'
        if ($Case -ne 'Missing') {
            $record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path
            if ($Case -eq 'Malformed') { '{broken' | Set-Content $path }
            (Get-Item $path).LastWriteTimeUtc = switch ($Case) {
                OldSameDeployment { [datetime]'2026-11-03T06:00:00Z' }
                Future { [datetime]'2026-11-03T08:00:00Z' }
                default { [datetime]'2026-11-03T07:05:00Z' }
            }
        }
        $report=New-OSDStageDeliveryReport -Result $result -Manifest $manifest -Directory $directory
        $report.Status | Should -Be 'Attention'
        $report.Packages[0].Status | Should -Be 'Succeeded'
        $report.Packages[0].Details.Evidence | Should -Be 'Unavailable'
        $report.Packages[0].Details.Items.Count | Should -Be 0
        $report | ConvertTo-Json -Depth 16 | Should -Not -Match 'do-not-import'
    }
    It 'does not import component details for skipped packages or PreInstall failures' {
        $manifest.Packages=@([pscustomobject]@{Id='Fonts';Source='Repository';PackageType='Font'})
        $result.Packages=@([pscustomobject]@{Id='Fonts';Status='Skipped'})
        $report=New-OSDStageDeliveryReport -Result $result -Manifest $manifest -Directory $directory
        $report.Packages[0].Details.Evidence | Should -Be 'NotRun'
        $result.Status='Failed'
        $report=New-OSDStageDeliveryReport -Result $result -Manifest $manifest -Directory $directory -Phase PreInstall
        $report.Packages[0].Details | Should -BeNullOrEmpty
    }
    It 'does not follow component paths for arbitrary packages or unsafe package identifiers' {
        Mock Get-Content { throw 'Must not read arbitrary component paths' }
        foreach ($definition in @(
            [pscustomobject]@{Id='../escape';Source='Repository';PackageType='Font'},
            [pscustomobject]@{Id='Services';Source='Repository';PackageType='Script';Type='ServiceScript'},
            [pscustomobject]@{Id='RegistrySettings';Source='Repository';PackageType='Script'}
        )) {
            Get-OSDStageReportComponent -Definition $definition -Package $result.Packages[0] -Result $result -Directory $directory | Should -BeNullOrEmpty
        }
        Should -Invoke Get-Content -Times 0
    }
    It 'preserves mixed font outcomes and escapes component names without exporting raw errors' {
        $definition=[pscustomobject]@{Id='Fonts';Source='Repository';PackageType='Font'}
        $manifest.Packages=@($definition);$result.Status='Failed'
        $result.Packages=@([pscustomobject]@{Id='Fonts';Status='Failed'})
        $record=@{SchemaVersion=2;DeploymentId=$result.DeploymentId;Id='Fonts';Status='Failed';FontCount=3;Items=@(
            @{FileName='<script>font</script>.ttf';Status='Installed';Outcome='Installed'},
            @{FileName='existing.ttf';Status='AlreadyPresent';Outcome='AlreadyPresent'},
            @{FileName='bad.ttf';Status='Failed';Outcome='FileConflict';Error='secret-error'}
        )}
        $path=Join-Path $directory 'Font-Fonts-Result.json'
        $record | ConvertTo-Json -Depth 8 | Set-Content $path
        (Get-Item $path).LastWriteTimeUtc=[datetime]'2026-11-03T07:05:00Z'
        $report=New-OSDStageDeliveryReport -Result $result -Manifest $manifest -Directory $directory
        $report.Status | Should -Be 'Failed'
        $report.Packages[0].Details.Items[1].Outcome | Should -Be 'AlreadyPresent'
        $report.Packages[0].Details.Items[2].Outcome | Should -Be 'FileConflict'
        $html=ConvertTo-OSDStageReportHtml $report
        $html | Should -Match '&lt;script&gt;font&lt;/script&gt;'
        $html | Should -Not -Match '<script>|secret-error'
    }

}
