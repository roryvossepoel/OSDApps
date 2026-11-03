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

function Get-OSDStageReportComponent {
    param($Package, $Definition, $Result, [string]$Directory)
    # Fixed runtime report names only. Never follow a ResultPath supplied by a package.
    $builtIns = @{
        Certificates='CertificateScript'; Services='ServiceScript'; FileSystem='FileSystemScript'
        EnvironmentVariables='EnvironmentVariableScript'; DesktopSettings='DesktopSettingsScript'
        WindowsFeatures='WindowsFeatureScript'; WindowsCapabilities='WindowsCapabilityScript'
        DefaultAssociations='DefaultAssociationScript'; WiFiProfiles='WiFiProfileScript'
    }
    $kind = $null; $fileName = $null; $identityField = $null
    if ($Definition.Source -eq 'BuiltIn' -and $builtIns.ContainsKey([string]$Definition.Id) -and
        $Definition.Type -eq $builtIns[[string]$Definition.Id]) {
        $kind = [string]$Definition.Id; $fileName = $kind + '-Result.json'
    }
    elseif ($Definition.Source -eq 'Repository' -and $Definition.PackageType -in @('Font','Certificate','Driver')) {
        $kind = [string]$Definition.PackageType
        if ([string]$Definition.Id -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*$') { return $null }
        $fileName = '{0}-{1}-Result.json' -f $kind, $Definition.Id
        $identityField = if ($kind -eq 'Font') { 'Id' } else { 'PackageId' }
    }
    elseif ($Definition.Id -eq 'RegistrySettings' -and $Definition.Source -eq 'Repository' -and $Definition.RegistryStageSchema -eq 1) {
        $kind = 'Registry'; $fileName = 'Registry-Result.json'
    }
    if (-not $kind) { return $null }
    $fields = switch ($kind) {
        'Font' { @('FileName','RegistrationName','Status','Outcome') }
        { $_ -in @('Certificate','Certificates') } { @('Subject','Thumbprint','Store','Status','Outcome') }
        'Driver' { @('Inf','Status','DriverStoreStatus','DeviceInstallStatus','DeviceBindingConfirmed','RestartNeeded') }
        'Services' { @('Name','Status','Outcome','StartupTypeRequested','StateRequested','StartupTypeBefore','StartupTypeAfter','StateBefore','StateAfter') }
        'FileSystem' { @('Kind','Action','Path','Status','Outcome') }
        'Registry' { @('Path','Name','Action','Type','ResolvedView','Status','Outcome') }
        'EnvironmentVariables' { @('Name','Action','Status','Outcome','Changed','AddedPathEntryCount') }
        'DesktopSettings' { @('Kind','Status','Outcome','PinCount','ApplyOnce','Mode') }
        { $_ -in @('WindowsFeatures','WindowsCapabilities') } { @('Name','Action','Status','Outcome','StateBefore','StateAfter','RestartNeeded') }
        'DefaultAssociations' { @('Identifier','ProgId','AppName','Status','Outcome','UserDefaultsVerified') }
        'WiFiProfiles' { @('Name','Status','Outcome') }
    }
    $details = [pscustomobject]@{ Kind=$kind; Evidence='Unavailable'; Note='No matching component details are available for this execution.'; Fields=@($fields); Items=@() }
    if ($Package.Status -notin @('Succeeded','Failed')) {
        $details.Evidence = 'NotRun'; $details.Note = 'No component details imported for a package that did not run.'
        return $details
    }
    try {
        $file = Get-Item -LiteralPath (Join-Path $Directory $fileName) -ErrorAction Stop
        if ($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $file.Length -gt 10MB) { throw 'Invalid detail file.' }
        $start = ([datetime]$Result.StartedAtUtc).ToUniversalTime()
        $end = ([datetime]$Result.CompletedAtUtc).ToUniversalTime()
        # Legacy component reports have no attempt timestamp. Require a write within this runner execution.
        if ($end -lt $start -or $file.LastWriteTimeUtc -lt $start -or $file.LastWriteTimeUtc -gt $end) { throw 'Stale detail file.' }
        $source = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($source.SchemaVersion -ne 2 -or [string]$source.DeploymentId -ne [string]$Result.DeploymentId -or
            $source.Status -ne $Package.Status) { throw 'Component identity or outcome mismatch.' }
        if ($identityField -and $source.$identityField -ne $Definition.Id) { throw 'Package identity mismatch.' }
        if ($kind -eq 'DefaultAssociations') {
            $rows = @($source.Associations)
            if ($source.Associations -isnot [array] -or $source.RequestedCount -ne $rows.Count) { throw 'Invalid association details.' }
        }
        else {
            $rows = @($source.Items)
            $countField = if ($kind -eq 'Font') { 'FontCount' } elseif ($kind -eq 'Driver') { 'InfCount' } else { 'OperationCount' }
            if ($source.Items -isnot [array] -or $source.$countField -ne $rows.Count) { throw 'Invalid component counts.' }
            $allowedStates = if ($kind -eq 'Font') { @('Installed','AlreadyPresent','Failed','Ignored') } else { @('Succeeded','Failed') }
            if (@($rows | Where-Object { $_.Status -notin $allowedStates }).Count -gt 0 -or
                ($source.Status -eq 'Succeeded' -and (@($rows | Where-Object Status -eq 'Failed').Count -gt 0 -or $rows.Count -eq 0))) { throw 'Invalid component outcomes.' }
        }
        $details.Items = @(foreach ($row in $rows) {
            $values = [ordered]@{}
            foreach ($field in $fields) {
                $value = $row.$field
                if ($kind -eq 'Services' -and $field -match '^(StartupType|State)(Before|After)$') { $value = $row.($Matches[2]).($Matches[1]) }
                if ($kind -eq 'DesktopSettings' -and $field -in @('Outcome','PinCount','ApplyOnce','Mode')) { $value = $row.Detail.$field }
                if ($kind -eq 'DefaultAssociations' -and $field -in @('Status','Outcome','UserDefaultsVerified')) { $value = $source.$field }
                # Copy scalars only; arbitrary nested properties must never leak into JSON/HTML.
                if ($value -is [string]) { $value = ConvertTo-OSDStageReportText $value }
                elseif ($null -ne $value -and $value -isnot [bool] -and $value -isnot [ValueType]) { $value = $null }
                $values[$field] = $value
            }
            [pscustomobject]$values
        })
        $details.Evidence = 'Matched'
        $details.Note = switch ($kind) {
            'DefaultAssociations' { 'Recorded import for first sign-in; current user defaults are not verified.' }
            'DesktopSettings' { 'Recorded preparation for first sign-in; the rendered user layout is not verified.' }
            'Driver' { 'Driver Store and device-install outcomes are separate; successful import does not confirm an active device binding.' }
            'WiFiProfiles' { 'Profile import results; a working Wi-Fi connection is not verified.' }
            'EnvironmentVariables' { 'Machine environment changes; existing process environments are not verified.' }
            default { 'Recorded operations from this deployment execution.' }
        }
    }
    catch { $details.Evidence='Unavailable'; $details.Items=@() }
    return $details
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
    if ($Phase -eq 'SetupComplete' -and $identityValid) {
        foreach ($package in $packages) {
            $definitions = @($expected | Where-Object Id -eq $package.Id)
            if ($definitions.Count -ne 1 -or @($actual | Where-Object Id -eq $package.Id).Count -ne 1) { continue }
            $component = Get-OSDStageReportComponent -Package $package -Definition $definitions[0] -Result $Result -Directory $Directory
            if ($null -ne $component) {
                $package | Add-Member -NotePropertyName Details -NotePropertyValue $component
                if ($component.Evidence -ne 'NotRun') {
                    $checks.Add([pscustomobject]@{ Name=('ComponentEvidence:' + $package.Id); Passed=($component.Evidence -eq 'Matched'); Detail=$component.Note })
                }
            }
        }
    }
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
    $report = [pscustomobject][ordered]@{
        SchemaVersion='1.1'; ReportId=[guid]::NewGuid().Guid; GeneratedAtUtc=[datetime]::UtcNow.ToString('o')
        DeploymentId=$Result.DeploymentId; Phase=$Phase; Status=$state; ExecutionStatus=$Result.Status; Summary=$null
        StartedAtUtc=$Result.StartedAtUtc; CompletedAtUtc=$Result.CompletedAtUtc; DurationSeconds=$Result.DurationSeconds
        Module=[pscustomobject]@{ Name='OSDStage'; Version=$Manifest.Runtime.ModuleVersion; GalleryUrl='https://www.powershellgallery.com/packages/OSDStage'; GitHubUrl='https://github.com/roryvossepoel/OSDStage'; DocumentationUrl='https://roryvossepoel.github.io/OSDStage/' }
        Device=$device
        Counts=[pscustomobject]@{ Expected=$expected.Count; Succeeded=$succeeded; Failed=$failed; Skipped=$skipped; UnknownOrNotRun=@($packages | Where-Object { $_.Status -notin @('Succeeded','Failed','Skipped') }).Count }
        RebootRequired=$reboot; WindowsUpdate=$wu; Packages=@($packages); Checks=@($checks.ToArray())
        FailureType=(ConvertTo-OSDStageReportText $Result.FailureType); ErrorPresent=(-not [string]::IsNullOrWhiteSpace([string]$Result.Error))
        Scope='Execution evidence only. This report does not certify that Windows is fully patched or that Autopilot enrollment succeeded. Updates may become available after restart. Windows Update content is not cached by OSDStage.'
        Privacy='Registry/environment values, file content, Wi-Fi credentials, raw errors, command lines and source URLs are omitted. Device, component and certificate names and target paths remain; review before sharing. Consult local logs for diagnostics.'
    }
    $report.Summary = Get-OSDStageReportSummary -Report $report
    return $report
}

function Get-OSDStageReportSummary {
    param([Parameter(Mandatory)]$Report)
    if ($Report.Status -eq 'Failed') { return 'Deployment failed. Review package results and the local runtime log.' }
    if ($Report.Status -eq 'Succeeded') { return 'Recorded deployment execution succeeded.' }
    if ($Report.ExecutionStatus -ne 'Succeeded' -or @($Report.Checks | Where-Object Passed -eq $false).Count -gt 0 -or
        $Report.Counts.Skipped -gt 0 -or $Report.Counts.UnknownOrNotRun -gt 0) {
        return 'Review the package results and evidence checks below.'
    }
    if ($Report.RebootRequired -eq $true) {
        if ($Report.WindowsUpdate.FurtherScanRequired -eq $true) {
            return 'Execution succeeded; restart required. A follow-up update scan is recommended.'
        }
        return 'Execution succeeded; restart required.'
    }
    if ($Report.WindowsUpdate.ScanOnly -eq $true) { return 'Execution succeeded; Windows Update was scan-only.' }
    if ($Report.WindowsUpdate.FurtherScanRequired -eq $true) { return 'Execution succeeded; follow-up update scan recommended.' }
    return 'Execution succeeded; review the recorded follow-up requirements below.'
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
    $componentContent = (@(foreach ($package in $Report.Packages) {
        if ($null -eq $package.Details) { continue }
        $details = $package.Details
        '<details class="component-details"><summary>' + (Format-ReportValue $package.Id) + ' &middot; component details</summary><p class="muted">' +
            (Format-ReportValue $details.Note) + '</p>' +
            (Format-ReportTable @($details.Items) @($details.Fields)) + '</details>'
    })) -join ''
    $checkTable = Format-ReportTable @($Report.Checks) @('Name','Passed','Detail')
    $deviceTable = Format-ReportTable @($Report.Device) @('ComputerName','Manufacturer','Model','WindowsVersion','Build','Revision')
    $updateContent = '<p>No correlated Windows Update details are available for this execution. See the checks below.</p>'
    if ($null -ne $Report.WindowsUpdate) {
        $updateContent = (Format-ReportTable @($Report.WindowsUpdate) @('Status','Outcome','FoundCount','SelectedCount','InstalledCount','SkippedCount','RebootRequired','RebootRequested','InstallationBlockedByReboot','FurtherScanRequired')) +
            (Format-ReportTable @($Report.WindowsUpdate.Items) @('Title','DriverClass','Selected','SelectionReason','Status','InstallResultCode','InstallHResult'))
    }
    $headline = if ($Report.ExecutionStatus -eq 'Succeeded') { 'Deployment complete.' } else { 'Deployment report.' }
    $state = Format-ReportValue $Report.Status
    $brandMark = '<svg class="brand-mark" aria-hidden="true" focusable="false" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 40"><rect width="40" height="40" rx="10" fill="#17394b"/><path d="m10 15 10-5 10 5-10 5Zm0 6 10 5 10-5m-20 6 10 5 10-5" fill="none" stroke="#9cdbcd" stroke-width="2.5" stroke-linejoin="round"/></svg>'
    @"
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
<title>OSDStage delivery report</title>
<style>
/* Shared visual tokens and mark from the OSDStage website; everything stays inline/offline. */
:root{color-scheme:light;--ink:#182f3d;--soft:#60737f;--accent:#126854;--edge:#dce5e8;--paper:#fff;--wash:#f4f7f8}
*{box-sizing:border-box}body{margin:0;background:linear-gradient(145deg,#eaf5ef 0%,#f1f8f7 34%,#f7fafb 68%,#fff 100%);color:var(--ink);font:16px/1.65 ui-sans-serif,system-ui,-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif}
a{color:var(--accent);text-underline-offset:4px}a:focus-visible,summary:focus-visible,.scroll:focus-visible{outline:3px solid #12816b;outline-offset:4px}
.site-header{background:#ffffffed;border-top:3px solid #187b66;border-bottom:1px solid var(--edge)}.nav-wrap{max-width:1240px;margin:auto;min-height:88px;padding:12px 28px;display:flex;align-items:center;justify-content:space-between;gap:24px}.brand{display:inline-flex;align-items:center;gap:11px;color:var(--ink);font-size:1.35rem;font-weight:750;letter-spacing:-.04em;text-decoration:none;white-space:nowrap}.brand-mark{width:35px;height:35px;flex-shrink:0}.header-label{font-size:.8rem;color:var(--soft)}
main{max-width:1240px;margin:auto;padding:0 28px 48px}.report-hero{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr);gap:48px;align-items:center;padding:58px 0 40px}.eyebrow{display:inline-flex;align-items:center;gap:9px;margin:0 0 22px;padding:5px 12px;background:#ffffffc9;border:1px solid #e0ede6;border-radius:999px;font-size:.65rem;font-weight:750;letter-spacing:.12em;text-transform:uppercase;color:#22765b;box-shadow:0 2px 8px #1e695108}.eyebrow::before{content:'';width:6px;height:6px;border-radius:50%;background:#21a783;box-shadow:0 0 0 4px #ddf4eb}
h1,h2{margin:0;line-height:1.15;letter-spacing:-.035em}h1{font-size:clamp(2.4rem,4vw,3.5rem);font-weight:800;line-height:1.06;letter-spacing:-.055em;color:#132f2c}h1 span{display:block;color:#147d5e;background:linear-gradient(110deg,#16704e,#139d88);background-clip:text;-webkit-background-clip:text;-webkit-text-fill-color:transparent}h2{font-size:1.35rem;font-weight:700}p{max-width:90ch;color:var(--soft)}.lead{font-size:1.02rem;line-height:1.8;margin:22px 0 0}.execution-card{min-width:0;border:1px solid #dae7e1;border-radius:19px;background:#ffffffeb;box-shadow:0 24px 55px #1b54451a;overflow:hidden}.card-heading{padding:17px 22px;border-bottom:1px solid #e6eee9;display:flex;justify-content:space-between;align-items:center;gap:14px;font-size:.85rem;font-weight:700}.card-heading .brand{font-size:.9rem}.card-heading .brand-mark{width:25px;height:25px}.run-facts{margin:0;padding:12px 22px 20px}.run-facts>div{display:flex;justify-content:space-between;gap:18px;padding:10px 0;border-bottom:1px solid #edf2ef;font-size:.84rem}.run-facts>div:last-child{border:0}.run-facts dt{color:var(--soft)}.run-facts dd{margin:0;font-weight:650;text-align:right;overflow-wrap:anywhere}.badge{display:inline-flex;align-items:center;background:#eaf6ef;color:#176448;border:1px solid #cde8db;padding:5px 12px;border-radius:999px;font-size:.75rem;font-weight:750;white-space:nowrap}.Attention{background:#fff3d9;color:#76520e;border-color:#f0dca8}.Failed{background:#fbe6e4;color:#8b2823;border-color:#ecc3bf}
.metrics{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:16px;margin:0 0 26px}.metric{background:#ffffffd9;border:1px solid #dfe9e3;border-radius:17px;padding:20px 22px;box-shadow:0 8px 28px #1b483106;font-size:.78rem;color:var(--soft)}.metric strong{display:block;font-size:2rem;line-height:1.25;letter-spacing:-.04em;color:#173c30;margin-top:6px}
section.panel,details{min-width:0;background:#ffffffeb;border:1px solid #dfe9e3;border-radius:17px;padding:25px 26px;margin:18px 0;box-shadow:0 8px 28px #1b483106}summary{cursor:pointer;font-size:1.15rem;font-weight:700;letter-spacing:-.025em}summary::marker{color:#187358}.scroll{overflow:auto;margin-top:18px}table{border-collapse:collapse;width:100%;font-size:.8rem}th,td{text-align:left;padding:12px;border-bottom:1px solid #e2eae5;vertical-align:top;overflow-wrap:anywhere}th{background:#eff6f2;color:#345d50;font-size:.7rem;font-weight:750}tbody tr:last-child td{border-bottom:0}tbody tr:hover{background:#f7faf8}code{font-family:ui-monospace,Consolas,monospace;font-size:.82em;overflow-wrap:anywhere}.muted{font-size:.8rem;color:var(--soft)}.deployment-meta{padding:18px 0 4px;font-size:.78rem;color:var(--soft)}.deployment-meta p{margin:5px 0}.site-footer{border-top:1px solid #d9e7df;background:linear-gradient(110deg,#edf6f0,#edf4f8)}.footer-wrap{max-width:1240px;padding:30px 28px;margin:auto;display:flex;justify-content:space-between;gap:30px;align-items:center}.footer-wrap p{font-size:.78rem;margin:6px 0 0}.footer-links{display:flex;flex-wrap:wrap;gap:12px 24px;font-size:.8rem}.footer-links a{text-decoration:none}.footer-links a:hover{text-decoration:underline}
details.component-details{background:transparent;border:0;border-radius:0;box-shadow:none;padding:0;margin:16px 0 0}details.component-details>summary{padding:8px 0;font-size:1rem}
@media(max-width:850px){.report-hero{grid-template-columns:1fr;gap:26px;padding:36px 0 28px}.metrics{grid-template-columns:repeat(3,minmax(0,1fr))}.footer-wrap{align-items:flex-start;flex-direction:column}table{min-width:640px}}
@media(max-width:480px){main{padding:0 16px 28px}.nav-wrap{padding:12px 16px;min-height:76px;gap:12px}.header-label{font-size:.7rem}.metrics{grid-template-columns:repeat(2,minmax(0,1fr));gap:10px}.metric{padding:16px}section.panel,details{padding:20px 16px}.run-facts>div{flex-wrap:wrap;gap:4px 16px}.footer-wrap{padding:26px 16px}}
@media print{body{background:#fff}.site-header,.site-footer{background:#fff}.nav-wrap{min-height:60px}main{max-width:none;padding:0}.report-hero{padding:20px 0;gap:20px;grid-template-columns:1fr 1fr}h1{font-size:28px}h1 span{-webkit-text-fill-color:#147d5e;background:none}.execution-card,.metric,section.panel,details{box-shadow:none}.metrics{grid-template-columns:repeat(5,minmax(0,1fr));gap:8px}.metric{padding:12px}.metric strong{font-size:22px}details>*{display:block!important}.scroll{overflow:visible}table{min-width:0;font-size:9px}th{font-size:9px}th,td{padding:6px}header,.report-hero,.metrics{break-inside:avoid}a{color:inherit}.footer-wrap{padding:18px 0}.site-footer .brand-mark{width:24px;height:24px}}
</style></head><body>
<header class="site-header"><div class="nav-wrap"><a class="brand" href="https://roryvossepoel.github.io/OSDStage/">$brandMark<span>OSDStage</span></a><span class="header-label">Delivery report &middot; $(Format-ReportValue $Report.Module.Version)</span></div></header>
<main><div class="report-hero"><div><div class="eyebrow">Your deployment, recorded</div><h1>$headline<span>Your results.</span></h1><p class="lead">$(Format-ReportValue $Report.Summary)</p>
$(if ($Report.ErrorPresent -or $Report.FailureType) { '<p class="muted">Failure type: ' + (Format-ReportValue $Report.FailureType) + '. See the local runtime log for diagnostics.</p>' })
</div><div class="execution-card"><div class="card-heading"><span class="brand">$brandMark<span>Execution overview</span></span><span class="badge $state">$state</span></div>
<dl class="run-facts"><div><dt>Execution</dt><dd>$(Format-ReportValue $Report.ExecutionStatus)</dd></div><div><dt>Phase</dt><dd>$(Format-ReportValue $Report.Phase)</dd></div><div><dt>Restart required</dt><dd>$(Format-ReportValue $Report.RebootRequired)</dd></div><div><dt>Duration</dt><dd>$(Format-ReportValue $Report.DurationSeconds) seconds</dd></div></dl></div></div>
<div class="metrics"><div class="metric">Expected<strong>$(Format-ReportValue $Report.Counts.Expected)</strong></div><div class="metric">Succeeded<strong>$(Format-ReportValue $Report.Counts.Succeeded)</strong></div><div class="metric">Failed<strong>$(Format-ReportValue $Report.Counts.Failed)</strong></div><div class="metric">Skipped<strong>$(Format-ReportValue $Report.Counts.Skipped)</strong></div><div class="metric">Unknown / not run<strong>$(Format-ReportValue $Report.Counts.UnknownOrNotRun)</strong></div></div>
<section class="panel"><h2>Device</h2>$deviceTable</section><section class="panel"><h2>Apps and configuration</h2>$packageTable<p class="muted">Missing values are shown as Unknown. Raw error messages are retained in local runtime logs.</p>$componentContent</section>
<details open><summary>Windows Update</summary>$updateContent</details><details open><summary>Evidence checks</summary>$checkTable</details>
<section class="panel"><h2>Scope and follow-up</h2><p>$(Format-ReportValue $Report.Scope)</p><p>$(Format-ReportValue $Report.Privacy)</p></section>
<div class="deployment-meta"><p>Deployment <code>$(Format-ReportValue $Report.DeploymentId)</code></p><p>Started: $(Format-ReportValue $Report.StartedAtUtc) &middot; Completed: $(Format-ReportValue $Report.CompletedAtUtc)</p><p>Report <code>$(Format-ReportValue $Report.ReportId)</code> &middot; Generated: $(Format-ReportValue $Report.GeneratedAtUtc)</p></div>
</main><footer class="site-footer"><div class="footer-wrap"><div><span class="brand">$brandMark<span>OSDStage</span></span><p>Your choices. Ready before OOBE. &middot; $(Format-ReportValue $Report.Module.Version)</p></div><nav class="footer-links" aria-label="Project links"><a href="https://www.powershellgallery.com/packages/OSDStage">PowerShell Gallery &#8599;</a><a href="https://github.com/roryvossepoel/OSDStage">GitHub &#8599;</a><a href="https://roryvossepoel.github.io/OSDStage/">Documentation &#8599;</a></nav></div></footer>
</body></html>
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
