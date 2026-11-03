# Standalone reporting: no module import, network requests, installers or reboot actions.
function ConvertTo-OSDStageReportText {
    param([AllowNull()]$Value)
    if ($null -eq $Value) { return $null }
    $text = [string]$Value
    # Do not carry source URLs (including query tokens) or credential assignments into exports.
    $text = $text -replace '(?i)\b(?:https?|ftp)://\S+', '[URL omitted]'
    $text = $text -replace '(?i)\b(password|passwd|token|secret|apikey|api_key)\s*[:=]\s*\S+', '$1=[omitted]'
    if ($text.Length -gt 2048) { $text = $text.Substring(0, 2048) + '...' }
    return $text
}

function Select-OSDStageReportField {
    param($InputObject, [string[]]$Fields)
    $record = [ordered]@{}
    foreach ($field in $Fields) {
        $value = $null
        if ($null -ne $InputObject -and $InputObject.PSObject.Properties[$field]) { $value = $InputObject.$field }
        if ($value -is [string]) { $value = ConvertTo-OSDStageReportText $value }
        $record[$field] = $value
    }
    [pscustomobject]$record
}

function Get-OSDStageReportDevice {
    $device = [ordered]@{ ComputerName=$env:COMPUTERNAME; Manufacturer=$null; Model=$null; WindowsVersion=$null; Build=$null; Revision=$null; CollectionStatus='Unavailable' }
    try {
        $system = Get-CimInstance -ClassName Win32_ComputerSystem -OperationTimeoutSec 5 -ErrorAction Stop
        $device.Manufacturer = ConvertTo-OSDStageReportText $system.Manufacturer
        $device.Model = ConvertTo-OSDStageReportText $system.Model
        $windows = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
        $device.WindowsVersion = $windows.DisplayVersion
        $device.Build = $windows.CurrentBuildNumber
        $device.Revision = $windows.UBR
        $device.CollectionStatus = 'Available'
    }
    catch { $device.CollectionStatus = 'Unavailable' } # Metadata is best effort.
    [pscustomobject]$device
}

function New-OSDStageDeliveryReport {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification='Builds an in-memory report object; no external state changes.')]
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Result, $Manifest, [Parameter(Mandatory)][string]$Directory,
        [ValidateSet('SetupComplete','PreInstall')][string]$Phase = 'SetupComplete')
    $checks = [Collections.Generic.List[object]]::new()
    $packages = @()
    $expected = @($Manifest.Packages | Where-Object { $null -ne $_ })
    $actual = @($Result.Packages | Where-Object { $null -ne $_ })
    $validId = [guid]::Empty
    $identityValid = [guid]::TryParse([string]$Result.DeploymentId, [ref]$validId) -and
        $validId -ne [guid]::Empty -and [string]$Result.DeploymentId -eq [string]$Manifest.DeploymentId
    $checks.Add([pscustomobject]@{ Name='DeploymentIdentity'; Passed=$identityValid; Detail='Result and staged manifest identify the same deployment.' })
    if ($Phase -eq 'PreInstall') {
        $packages = @(foreach ($app in $expected) {
            [pscustomobject]@{ Id=(ConvertTo-OSDStageReportText $app.Id); DisplayName=(ConvertTo-OSDStageReportText $app.DisplayName); Status='NotRun'; FailureType='PreInstallFailed' }
        })
    }
    else {
        $packages = @(foreach ($app in $actual) {
            $item = Select-OSDStageReportField $app @('Id','DisplayName','Source','Type','PackageType','Version','Architecture','Status','ExitCode','RebootRequired','DurationSeconds','AcquisitionOutcome','CacheUsed','PackageUpdated','FailureType','WindowsUpdateStatus','WindowsUpdateOutcome')
            $item | Add-Member -NotePropertyName ErrorPresent -NotePropertyValue (-not [string]::IsNullOrWhiteSpace([string]$app.Error))
            $item
        })
        foreach ($app in $expected) {
            if (@($actual | Where-Object Id -eq $app.Id).Count -eq 0) {
                $packages += [pscustomobject]@{ Id=(ConvertTo-OSDStageReportText $app.Id); DisplayName=(ConvertTo-OSDStageReportText $app.DisplayName); Status='Unknown'; FailureType='MissingResult' }
            }
        }
    }
    $complete = $Phase -eq 'SetupComplete' -and $null -ne $Manifest -and
        $actual.Count -eq $expected.Count -and $Result.ExpectedPackageCount -eq $expected.Count -and
        @($expected | Where-Object { $id=$_.Id; @($actual | Where-Object Id -eq $id).Count -ne 1 }).Count -eq 0
    $checks.Add([pscustomobject]@{ Name='PackageResultsComplete'; Passed=$complete; Detail='Exactly one result is present for every staged package.' })
    $knownStates = @($packages | Where-Object { $_.Status -notin @('Succeeded','Failed','Skipped') }).Count -eq 0
    $checks.Add([pscustomobject]@{ Name='PackageStatesKnown'; Passed=$knownStates; Detail='Every execution result has a recognized terminal state.' })
    $wu = $null
    $wuPackages = @($actual | Where-Object Id -eq 'WindowsUpdate')
    if ($Phase -eq 'SetupComplete' -and @($expected | Where-Object Id -eq 'WindowsUpdate').Count -gt 0) {
        $wuValid = $false
        try {
            # Only the fixed sibling file is read, never a package-supplied path or URL.
            $wuPath = Join-Path $Directory 'WindowsUpdate-Result.json'
            $source = Get-Content -LiteralPath $wuPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            $wuValid = $identityValid -and $wuPackages.Count -eq 1 -and
                $source.DeploymentId -eq $Result.DeploymentId -and $source.Phase -eq 'LastWithinSetupComplete' -and
                ([datetime]$source.StartedAtUtc).ToUniversalTime() -ge ([datetime]$Result.StartedAtUtc).ToUniversalTime() -and
                ([datetime]$source.CompletedAtUtc).ToUniversalTime() -le ([datetime]$Result.CompletedAtUtc).ToUniversalTime() -and
                ([datetime]$source.CompletedAtUtc).ToUniversalTime() -ge ([datetime]$source.StartedAtUtc).ToUniversalTime() -and
                $wuPackages[0].WindowsUpdateStatus -eq $source.Status -and
                $wuPackages[0].WindowsUpdateOutcome -eq $source.Outcome -and
                $source.FoundCount -eq @($source.Items).Count -and
                $source.SelectedCount -eq @($source.Items | Where-Object Selected -eq $true).Count -and
                $source.InstalledCount -eq @($source.Items | Where-Object Status -eq 'Installed').Count
            if ($wuValid) {
                $wu = Select-OSDStageReportField $source @('Status','Outcome','Phase','ScanOnly','IncludeDrivers','FoundCount','SelectedCount','InstalledCount','RebootRequired','RebootStateKnown','InstallationBlockedByReboot','RebootRequested','FurtherScanRequired','DurationSeconds','ReleaseUnchanged')
                $wu | Add-Member -NotePropertyName DriverClass -NotePropertyValue @($source.DriverClass | ForEach-Object { ConvertTo-OSDStageReportText $_ })
                $wu | Add-Member -NotePropertyName Items -NotePropertyValue @(foreach ($update in $source.Items) {
                    Select-OSDStageReportField $update @('UpdateId','Revision','Title','Type','DriverClass','Selected','SelectionReason','Status','DownloadResultCode','DownloadHResult','InstallResultCode','InstallHResult','RebootRequired')
                })
                $wu | Add-Member -NotePropertyName SkippedCount -NotePropertyValue @($wu.Items | Where-Object Status -eq 'Skipped').Count
            }
        }
        catch { $wuValid = $false }
        $checks.Add([pscustomobject]@{ Name='WindowsUpdateEvidence'; Passed=$wuValid; Detail='Windows Update details match this execution, its timestamps and package outcome; missing or stale details are not imported.' })
    }
    $failed = @($packages | Where-Object Status -eq 'Failed').Count
    $succeeded = @($packages | Where-Object Status -eq 'Succeeded').Count
    $skipped = @($packages | Where-Object Status -eq 'Skipped').Count
    $reboot = $Result.RebootRequired
    if ($null -ne $wu) {
        $checks.Add([pscustomobject]@{ Name='RestartEvidence'; Passed=($wu.RebootRequired -ne $true -or $Result.RebootRequired -eq $true); Detail='A restart required by Windows Update is reflected in the deployment result.' })
        if ($wu.RebootRequired -eq $true) { $reboot = $true }
    }
    $checks.Add([pscustomobject]@{ Name='ModuleMetadata'; Passed=(-not [string]::IsNullOrWhiteSpace([string]$Manifest.Runtime.ModuleVersion)); Detail='The staging module version was recorded in the manifest.' })
    $checks.Add([pscustomobject]@{ Name='CacheCurrency'; Passed=(@($packages | Where-Object { $_.AcquisitionOutcome -in @('FallbackCacheUsed','OfflineCacheUsed') }).Count -eq 0); Detail='Fallback/offline cache use requires review; successful installation alone does not confirm current content.' })
    $state = 'Attention'
    if ($Result.Status -eq 'Failed' -or $failed -gt 0) { $state = 'Failed' }
    elseif ($Result.Status -eq 'Succeeded' -and $complete -and $knownStates -and $skipped -eq 0 -and
        @($checks | Where-Object Passed -eq $false).Count -eq 0 -and $reboot -eq $false -and
        ($null -eq $wu -or ($wu.FurtherScanRequired -eq $false -and $wu.ScanOnly -eq $false))) { $state = 'Succeeded' }
    $device = Get-OSDStageReportDevice
    if ($device.CollectionStatus -ne 'Available') {
        $checks.Add([pscustomobject]@{ Name='DeviceMetadata'; Passed=$false; Detail='Some device metadata could not be collected.' })
        if ($state -eq 'Succeeded') { $state = 'Attention' }
    }
    $message = switch ($state) {
        'Failed' { 'Deployment failed. Review package results and the local runtime log.' }
        'Succeeded' { 'Recorded deployment execution succeeded.' }
        default { 'Review restart requirements, incomplete evidence and follow-up updates below.' }
    }
    [pscustomobject][ordered]@{
        SchemaVersion='1.0'; ReportId=[guid]::NewGuid().Guid; GeneratedAtUtc=[datetime]::UtcNow.ToString('o')
        DeploymentId=$Result.DeploymentId; Phase=$Phase; Status=$state; ExecutionStatus=$Result.Status; Summary=$message
        StartedAtUtc=$Result.StartedAtUtc; CompletedAtUtc=$Result.CompletedAtUtc; DurationSeconds=$Result.DurationSeconds
        Module=[pscustomobject]@{ Name='OSDStage'; Version=$Manifest.Runtime.ModuleVersion; GalleryUrl='https://www.powershellgallery.com/packages/OSDStage'; GitHubUrl='https://github.com/roryvossepoel/OSDStage'; DocumentationUrl='https://roryvossepoel.github.io/OSDStage/' }
        Device=$device
        Counts=[pscustomobject]@{ Expected=$expected.Count; Succeeded=$succeeded; Failed=$failed; Skipped=$skipped; UnknownOrNotRun=@($packages | Where-Object { $_.Status -notin @('Succeeded','Failed','Skipped') }).Count }
        RebootRequired=$reboot; WindowsUpdate=$wu; Packages=@($packages); Checks=@($checks.ToArray())
        FailureType=(ConvertTo-OSDStageReportText $Result.FailureType); ErrorPresent=(-not [string]::IsNullOrWhiteSpace([string]$Result.Error))
        Scope='Execution evidence only. This report does not certify that Windows is fully patched or that Autopilot enrollment succeeded. Updates may become available after restart. Windows Update content is not cached by OSDStage.'
        Privacy='Configuration values, raw errors, command lines and source URLs are omitted. Device and package names remain; review before sharing. Consult local logs for diagnostics.'
    }
}

function ConvertTo-OSDStageReportHtml {
    param([Parameter(Mandatory)]$Report)
    function Format-ReportValue {
        param($Value)
        if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return 'Unknown' }
        if ($Value -is [bool]) { if ($Value) { return 'Yes' } else { return 'No' } }
        [System.Net.WebUtility]::HtmlEncode([string]$Value)
    }
    function Format-ReportTable {
        param([object[]]$Rows, [string[]]$Fields)
        $header = ($Fields | ForEach-Object { '<th scope="col">' + (Format-ReportValue ($_ -creplace '([a-z])([A-Z])', '$1 $2')) + '</th>' }) -join ''
        $body = ($Rows | ForEach-Object {
            $row = $_
            '<tr>' + (($Fields | ForEach-Object { '<td>' + (Format-ReportValue $row.$_) + '</td>' }) -join '') + '</tr>'
        }) -join ''
        if (-not $body) { return '<p>No recorded items.</p>' }
        '<div class="scroll" tabindex="0"><table><thead><tr>' + $header + '</tr></thead><tbody>' + $body + '</tbody></table></div>'
    }
    $packageTable = Format-ReportTable @($Report.Packages) @('Id','Status','Version','ExitCode','DurationSeconds','AcquisitionOutcome','RebootRequired','FailureType','ErrorPresent')
    $checkTable = Format-ReportTable @($Report.Checks) @('Name','Passed','Detail')
    $deviceTable = Format-ReportTable @($Report.Device) @('ComputerName','Manufacturer','Model','WindowsVersion','Build','Revision')
    $updateContent = '<p>No correlated Windows Update details are available for this execution. See the checks below.</p>'
    if ($null -ne $Report.WindowsUpdate) {
        $updateContent = (Format-ReportTable @($Report.WindowsUpdate) @('Status','Outcome','FoundCount','SelectedCount','InstalledCount','SkippedCount','RebootRequired','RebootRequested','InstallationBlockedByReboot','FurtherScanRequired')) +
            (Format-ReportTable @($Report.WindowsUpdate.Items) @('Title','DriverClass','Selected','SelectionReason','Status','InstallResultCode','InstallHResult'))
    }
    $state = Format-ReportValue $Report.Status
    @"
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
<title>OSDStage delivery report</title>
<style>
:root{color-scheme:light;--ink:#183a35;--green:#20765e;--line:#d4e3dd}*{box-sizing:border-box}body{margin:0;background:#f0f6f3;color:var(--ink);font:16px/1.55 system-ui,Segoe UI,sans-serif}main{max-width:1180px;margin:auto;padding:40px 24px}header{border-top:5px solid var(--green);padding:28px;background:#fff;border-radius:12px}h1{font-size:32px;line-height:1.2;margin:8px 0}h2{font-size:20px}p{max-width:90ch}.eyebrow{font-weight:700;color:var(--green);letter-spacing:.08em}.badge{display:inline-block;background:#dcefe4;padding:6px 14px;border-radius:20px;font-weight:700}.Attention{background:#fff0ce;color:#6c4700}.Failed{background:#fbe1df;color:#8b2823}.metrics{display:grid;grid-template-columns:repeat(auto-fit,minmax(130px,1fr));gap:12px;margin:22px 0}.metric,section,details{background:white;border:1px solid var(--line);border-radius:12px;padding:20px}.metric strong{display:block;font-size:28px}section,details{margin:16px 0}summary{cursor:pointer;font-weight:700}table{border-collapse:collapse;width:100%;font-size:14px}th,td{text-align:left;padding:10px;border-bottom:1px solid var(--line);vertical-align:top;overflow-wrap:anywhere}th{background:#edf5f1}.scroll{overflow:auto;margin-top:12px}a{color:#17684f}footer{font-size:14px;padding:16px 0}code{overflow-wrap:anywhere}.muted{color:#526960}@media print{body{background:#fff}main{max-width:none;padding:0}details{break-inside:auto}details>*{display:block!important}.scroll{overflow:visible}table{font-size:9px}header{break-inside:avoid}a{color:inherit}}
</style></head><body><main>
<header><div class="eyebrow">OSDSTAGE &middot; DELIVERY REPORT</div><h1>Deployment execution</h1><span class="badge $state">$state</span><p>$(Format-ReportValue $Report.Summary)</p>
<p class="muted">Execution: $(Format-ReportValue $Report.ExecutionStatus) &middot; Phase: $(Format-ReportValue $Report.Phase) &middot; Restart required: $(Format-ReportValue $Report.RebootRequired)</p>
$(if ($Report.ErrorPresent -or $Report.FailureType) { '<p>Failure type: ' + (Format-ReportValue $Report.FailureType) + '. See the local runtime log for diagnostics.</p>' })
<p>Deployment <code>$(Format-ReportValue $Report.DeploymentId)</code><br>Started: $(Format-ReportValue $Report.StartedAtUtc)<br>Completed: $(Format-ReportValue $Report.CompletedAtUtc) &middot; Duration: $(Format-ReportValue $Report.DurationSeconds) seconds</p></header>
<div class="metrics"><div class="metric">Expected<strong>$(Format-ReportValue $Report.Counts.Expected)</strong></div><div class="metric">Succeeded<strong>$(Format-ReportValue $Report.Counts.Succeeded)</strong></div><div class="metric">Failed<strong>$(Format-ReportValue $Report.Counts.Failed)</strong></div><div class="metric">Skipped<strong>$(Format-ReportValue $Report.Counts.Skipped)</strong></div><div class="metric">Unknown / not run<strong>$(Format-ReportValue $Report.Counts.UnknownOrNotRun)</strong></div></div>
<section><h2>Device</h2>$deviceTable</section><section><h2>Apps and configuration</h2>$packageTable<p class="muted">Missing values are shown as Unknown. Raw error messages are retained in local runtime logs.</p></section>
<details open><summary>Windows Update</summary>$updateContent</details><details open><summary>Evidence checks</summary>$checkTable</details>
<section><h2>Scope and follow-up</h2><p>$(Format-ReportValue $Report.Scope)</p><p>$(Format-ReportValue $Report.Privacy)</p></section>
<footer>OSDStage $(Format-ReportValue $Report.Module.Version) &middot; <a href="https://www.powershellgallery.com/packages/OSDStage">PowerShell Gallery</a> &middot; <a href="https://github.com/roryvossepoel/OSDStage">GitHub</a> &middot; <a href="https://roryvossepoel.github.io/OSDStage/">Documentation</a><br>Report $(Format-ReportValue $Report.ReportId) &middot; Generated $(Format-ReportValue $Report.GeneratedAtUtc)</footer>
</main></body></html>
"@
}

function Write-OSDStageDeliveryReport {
    param([Parameter(Mandatory)]$Result, $Manifest, [Parameter(Mandatory)][string]$Directory,
        [ValidateSet('SetupComplete','PreInstall')][string]$Phase = 'SetupComplete')
    $jsonPath = Join-Path $Directory 'DeliveryReport.json'
    $htmlPath = Join-Path $Directory 'DeliveryReport.html'
    $suffix = '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        # Invalidate the old pair first: failure must never leave an older green report as current.
        foreach ($path in @($jsonPath, $htmlPath)) {
            if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path -Force -ErrorAction Stop }
        }
        $report = New-OSDStageDeliveryReport -Result $Result -Manifest $Manifest -Directory $Directory -Phase $Phase
        $json = $report | ConvertTo-Json -Depth 16
        # Render the serialized schema, so HTML and JSON describe precisely the same report.
        $html = ConvertTo-OSDStageReportHtml -Report ($json | ConvertFrom-Json)
        [IO.File]::WriteAllText($jsonPath + $suffix, $json, [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText($htmlPath + $suffix, $html, [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath ($jsonPath + $suffix) -Destination $jsonPath -Force -ErrorAction Stop
        Move-Item -LiteralPath ($htmlPath + $suffix) -Destination $htmlPath -Force -ErrorAction Stop
    }
    finally {
        foreach ($path in @($jsonPath + $suffix, $htmlPath + $suffix)) {
            if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
        }
    }
}
