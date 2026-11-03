# Read-only acceptance checks after SetupComplete. Does not install or restart.
[CmdletBinding()]
param(
    [string]$ResultsPath = "$env:ProgramData\OSDStage\Results",
    [string]$RecordPath = "$env:ProgramData\OSDStage\Tests\DeliveryReport-Staging.json"
)
$ErrorActionPreference = 'Stop'
$record = Get-Content -LiteralPath $RecordPath -Raw | ConvertFrom-Json
$result = Get-Content -LiteralPath (Join-Path $ResultsPath 'Latest.json') -Raw | ConvertFrom-Json
$report = Get-Content -LiteralPath (Join-Path $ResultsPath 'DeliveryReport.json') -Raw | ConvertFrom-Json
$html = Get-Content -LiteralPath (Join-Path $ResultsPath 'DeliveryReport.html') -Raw
$wu = Get-Content -LiteralPath (Join-Path $ResultsPath 'WindowsUpdate-Result.json') -Raw | ConvertFrom-Json
$expected = @($record.ExpectedIds)
if ($expected.Count -ne 19 -or @($expected | Sort-Object -Unique).Count -ne 19) { throw 'Invalid test selection record.' }
$marker = Join-Path $env:ProgramData 'OSDStageAcceptance\FullReportTest.txt'
$checks = [ordered]@{
    SameDeployment = ($record.DeploymentId -eq $result.DeploymentId -and $result.DeploymentId -eq $report.DeploymentId -and $report.DeploymentId -eq $wu.DeploymentId)
    SameHtmlReport = ($report.ReportId -and $html.Contains([string]$report.ReportId))
    ExpectedRunnerPackages = (@($result.Packages).Count -eq 19 -and @(Compare-Object ($expected | Sort-Object) (@($result.Packages.Id) | Sort-Object)).Count -eq 0)
    ExpectedReportPackages = (@($report.Packages).Count -eq 19 -and @(Compare-Object ($expected | Sort-Object) (@($report.Packages.Id) | Sort-Object)).Count -eq 0)
    AllPackagesSucceeded = ($result.Status -eq 'Succeeded' -and @($result.Packages | Where-Object Status -ne 'Succeeded').Count -eq 0)
    ReportEvidencePassed = (@($report.Checks).Count -gt 0 -and @($report.Checks | Where-Object { $_.Passed -ne $true }).Count -eq 0)
    BuiltInAppsShown = $html.Contains('<h3>Built-in apps</h3>')
    RepositoryAppsShown = $html.Contains('<h3>Repository apps</h3>')
    WindowsUpdateLast = (@($result.Packages)[-1].Id -eq 'WindowsUpdate')
    ActualSetupComplete = ($wu.Phase -eq 'LastWithinSetupComplete')
    NoRestartRequested = ($wu.RebootRequested -eq $false)
    MarkerPresent = (Test-Path -LiteralPath $marker)
}
[pscustomobject]$checks | Format-List
$report | Format-List Status,ExecutionStatus,Summary,RebootRequired
$report.Packages | Select-Object Id,Source,PackageType,Status,ExitCode,RebootRequired | Format-Table -AutoSize
$report.Checks | Format-Table Name,Passed,Detail -Wrap
$wu | Format-List Status,Outcome,FoundCount,SelectedCount,InstalledCount,RebootRequired,FurtherScanRequired
if (@($checks.Values | Where-Object { $_ -ne $true }).Count -gt 0) {
    throw 'One or more acceptance checks failed. Preserve all reports and runtime logs for investigation.'
}
Write-Host 'Recorded execution and report checks passed. Inspect the actual fonts, certificate, apps and user settings separately.' -ForegroundColor Green
Write-Host 'Attention is expected when a restart or follow-up update scan is recorded. This does not prove all Windows updates are complete.'
