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
}
