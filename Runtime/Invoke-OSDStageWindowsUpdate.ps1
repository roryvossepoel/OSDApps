[CmdletBinding()]
param([string]$ConfigPath)
$script:OSDStageWindowsUpdateLogPath=$null

function Assert-OSDStageWindowsUpdateConfiguration {
    param([Parameter(Mandatory)]$Configuration)
    $id=[guid]::Empty
    if ($Configuration.SchemaVersion -ne 2 -or
        -not [guid]::TryParse([string]$Configuration.DeploymentId,[ref]$id) -or
        [string]::IsNullOrWhiteSpace([string]$Configuration.ResultPath) -or
        $Configuration.IncludeDrivers -isnot [bool] -or $Configuration.ScanOnly -isnot [bool] -or
        ($Configuration.TimeoutMinutes -isnot [int] -and $Configuration.TimeoutMinutes -isnot [long]) -or
        $Configuration.TimeoutMinutes -lt 5 -or $Configuration.TimeoutMinutes -gt 180) {
        throw 'Invalid Windows Update configuration.'
    }
    if ($Configuration.PSObject.Properties.Name -contains 'DriverClass') {
        $classes=@($Configuration.DriverClass)
        if (($classes.Count -gt 0 -and -not $Configuration.IncludeDrivers) -or
            @($classes | Where-Object { $_ -isnot [string] -or [string]::IsNullOrWhiteSpace($_) -or $_ -match '[*?\[\]]' }).Count -gt 0) {
            throw 'DriverClass must contain exact, nonempty WUA class names and requires IncludeDrivers.'
        }
    }
}

function Write-OSDStageWindowsUpdateMessage {
    param([string]$Message,[ValidateSet('INFO','WARN','ERROR')][string]$Level='INFO')
    $color=switch ($Level) { 'WARN' {'Yellow'} 'ERROR' {'Red'} default {'Cyan'} }
    $line='[{0}] [{1}] Windows Update: {2}' -f (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'),$Level,$Message
    Write-Host $line -ForegroundColor $color
    if ($script:OSDStageWindowsUpdateLogPath) { Add-Content -LiteralPath $script:OSDStageWindowsUpdateLogPath -Value $line -Encoding UTF8 -ErrorAction Stop }
}

function Get-OSDStageWindowsUpdateRelease {
    $cv=Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
    [pscustomobject]@{DisplayVersion=[string]$cv.DisplayVersion;Build=[string]$cv.CurrentBuildNumber;Revision=$cv.UBR;InstallationType=[string]$cv.InstallationType}
}

function Assert-OSDStageWindowsUpdateContext {
    param([switch]$OobeTest)
    if ((Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT') -or
        -not [Environment]::Is64BitProcess) {
        throw 'Windows Update runtime requires native 64-bit PowerShell as SYSTEM during SetupComplete.'
    }
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    $principal=[Security.Principal.WindowsPrincipal]::new($identity)
    if ($identity.User.Value -ne 'S-1-5-18' -and
        -not ($OobeTest -and $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) {
        throw 'Use native 64-bit PowerShell as SYSTEM for SetupComplete, or an elevated console for the explicit OOBE test.'
    }
    $release=Get-OSDStageWindowsUpdateRelease
    if ($release.InstallationType -ne 'Client' -or [int]$release.Build -lt 26200) {
        throw 'Windows Update requires Windows 11 25H2 or later (client build 26200+).'
    }
}

function Get-OSDStageWindowsUpdateSelection {
    param([Parameter(Mandatory)]$Update,[bool]$IncludeDrivers=$false,[int]$Depth=0,
        [string[]]$ParentSoftwareClassifications=@(),[string[]]$DriverClass=@())
    # Category IDs are language independent. Root updates require their own
    # classification. Unclassified software members can use a checked software
    # parent's classification; explicit disallowed metadata is never overridden.
    # Regular quality servicing includes Updates and Update Rollups (for example
    # .NET servicing and MSRT). Upgrades/Feature Packs remain excluded; root
    # software also requires automatic, non-browse-only selection and title checks.
    $safe=@('0fa1201d-4330-4fa8-8ae9-b877473b6441', # Security Updates
        'e6cf1350-c01b-414d-a61f-263d14d133b4', # Critical Updates
        'e0789628-ce08-4437-be74-2495b842f43b', # Definition Updates
        '28bc880e-0592-4cbf-8f95-c79b17911d5f', # Update Rollups
        'cd5ffd1e-e932-4e3a-bf74-18bf0b1bbd83') # Updates
    $reason='MissingOrUnsupportedMetadata';$selected=$false
    $categories=@();$effectiveCategories=@();$classificationSource='None'
    $bundleDecisions=[Collections.Generic.List[object]]::new()
    try {
        if ($Depth -gt 16) { throw 'BundleDepthExceeded' }
        if ($Update.IsInstalled -ne $false -or $Update.IsHidden -ne $false) { throw 'NotApplicable' }
        if ([int]$Update.Type -eq 2 -and -not $IncludeDrivers) { throw 'DriversDisabled' }
        if ($Depth -eq 0 -and [int]$Update.Type -ne 2) {
            if ($Update.BrowseOnly -ne $false -or $Update.AutoSelectOnWebSites -ne $true) { throw 'NotAutomatic' }
        }
        # RebootBehavior=1 means a restart is required AFTER installation, not
        # that WUA should initiate it. Cumulative updates must remain eligible.
        $behavior=$Update.InstallationBehavior
        if ($null -eq $behavior) { throw 'InstallationBehaviorMissing' }
        if ($behavior.CanRequestUserInput -isnot [bool]) { throw 'InteractionMetadataUnknown' }
        if ($null -eq $behavior.RebootBehavior -or
            [int]$behavior.RebootBehavior -notin @(0,1,2)) { throw 'RebootBehaviorUnknown' }
        # Explicitly opted-in drivers may advertise UI capability. Installation
        # still MUST use ForceQuiet, with no interactive fallback. WUA rejects
        # updates that cannot honor it; the runtime records failure and stops.
        if ($behavior.CanRequestUserInput -and
            -not ([int]$Update.Type -eq 2 -and $IncludeDrivers)) { throw 'InteractiveSoftwareUpdate' }
        if ([string]$Update.Title -match '(?i)preview|voorvertoning|vorschau|aper\u00e7u|enablement|feature\s+update|functie.update') { throw 'ExcludedTitle' }
        if ($null -eq $Update.Categories) { throw 'ClassificationMetadataMissing' }
        $categories=@($Update.Categories | Where-Object Type -eq 'UpdateClassification' | ForEach-Object { [string]$_.CategoryID })
        $effectiveCategories=$categories
        if ($categories.Count -gt 0) { $classificationSource='Own' }
        if ([int]$Update.Type -eq 1) {
            if ([string]$Update.Title -match '(?i)firmware|\bBIOS\b|\bUEFI\b') { throw 'ExcludedTitle' }
            if ($categories.Count -eq 0 -and $Depth -gt 0 -and
                $ParentSoftwareClassifications.Count -gt 0 -and
                @($ParentSoftwareClassifications | Where-Object { $_ -notin $safe }).Count -eq 0) {
                $effectiveCategories=@($ParentSoftwareClassifications)
                $classificationSource='ParentBundle'
            }
            if ($effectiveCategories.Count -eq 0 -or @($effectiveCategories | Where-Object { $_ -notin $safe }).Count -gt 0) { throw 'ClassificationNotAllowed' }
        }
        elseif ([int]$Update.Type -eq 2) {
            # Explicit opt-in includes ALL WUA driver classes, including firmware.
            # An optional exact-name allowlist narrows root and member offers.
            # Hardware IDs and titles are evidence, not a home-grown PnP ranker.
            if ([string]::IsNullOrWhiteSpace([string]$Update.DriverClass)) { throw 'DriverClassMissing' }
            if ($DriverClass.Count -gt 0 -and [string]$Update.DriverClass -notin $DriverClass) { throw 'DriverClassNotIncluded' }
            if ($categories.Count -eq 0 -or @($categories | Where-Object { $_ -ne 'ebfc1fc5-71a4-4f7b-9aca-3b9a503104a0' }).Count -gt 0) { throw 'DriverClassificationNotAllowed' }
        }
        else { throw 'UpdateTypeNotAllowed' }
        if ($null -eq $Update.BundledUpdates) { throw 'BundleMetadataMissing' }
        $childClassifications=@()
        if ([int]$Update.Type -eq 1) { $childClassifications=@($effectiveCategories) }
        $bundleRejection=$null
        foreach ($child in $Update.BundledUpdates) {
            $decision=Get-OSDStageWindowsUpdateSelection -Update $child -IncludeDrivers $IncludeDrivers -Depth ($Depth+1) -ParentSoftwareClassifications $childClassifications -DriverClass $DriverClass
            $bundleDecisions.Add([pscustomobject]@{
                UpdateId=[string]$child.Identity.UpdateID;Title=[string]$child.Title;Type=[int]$child.Type
                DriverClass=$(if ([int]$child.Type -eq 2) { [string]$child.DriverClass } else { $null })
                DriverHardwareId=$(if ([int]$child.Type -eq 2) { [string]$child.DriverHardwareID } else { $null })
                Selected=$decision.Selected;Reason=$decision.Reason
                ClassificationIds=$decision.ClassificationIds;EffectiveClassificationIds=$decision.EffectiveClassificationIds
                ClassificationSource=$decision.ClassificationSource;Children=$decision.BundleDecisions
            })
            if (-not $decision.Selected -and -not $bundleRejection) { $bundleRejection='BundleRejected: ' + $decision.Reason }
        }
        if ($bundleRejection) { throw $bundleRejection }
        $selected=$true;$reason=if ([int]$Update.Type -eq 2) {'OptedInHardwareDriver'} else {'AllowedQualityClassification'}
    }
    catch { $reason=$_.Exception.Message }
    [pscustomobject]@{
        Selected=$selected;Reason=$reason;ClassificationIds=@($categories)
        EffectiveClassificationIds=@($effectiveCategories);ClassificationSource=$classificationSource
        BundleDecisions=@($bundleDecisions.ToArray())
    }
}

function Get-OSDStageWindowsUpdateSelections {
    param([AllowEmptyCollection()][object[]]$Updates,[bool]$IncludeDrivers=$false,[string[]]$DriverClass=@())
    # Do not discard distinct updates just because their hardware IDs match.
    # Keep WUA identities and delegate installation to WUA; no version/title sorting.
    foreach ($update in $Updates) {
        [pscustomobject]@{Update=$update;Decision=(Get-OSDStageWindowsUpdateSelection -Update $update -IncludeDrivers $IncludeDrivers -DriverClass $DriverClass)}
    }
}

function New-OSDStageWindowsUpdateComObject {
    param([Parameter(Mandatory)][string]$ProgId)
    New-Object -ComObject $ProgId -ErrorAction Stop
}

function Test-OSDStageWindowsUpdateRebootPrerequisite {
    param([Parameter(Mandatory)]$Installer)
    $required=$Installer.RebootRequiredBeforeInstallation
    if ($required -isnot [bool]) {
        throw 'WUA did not return a Boolean reboot prerequisite; installation was not attempted.'
    }
    $required
}

function New-OSDStageWindowsUpdateCallback {
    # WUA supports an Automation callback with DISPID 0. The managed callback
    # never enters a PowerShell runspace on a COM worker thread. The caller polls.
    if (-not ('OSDStage.WuaCallback' -as [type])) {
        Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
namespace OSDStage {
    [ComVisible(true), InterfaceType(ComInterfaceType.InterfaceIsIDispatch)]
    public interface IWuaCallback {
        [DispId(0)] void Invoke(object job, object args);
    }
    [ComVisible(true), ClassInterface(ClassInterfaceType.None)]
    public sealed class WuaCallback : IWuaCallback {
        public void Invoke(object job, object args) { }
    }
}
'@ -ErrorAction Stop
    }
    New-Object OSDStage.WuaCallback
}

function Invoke-OSDStageWindowsUpdateAsync {
    param([Parameter(Mandatory)]$Agent,[ValidateSet('Search','Download','Install')][string]$Phase,
        [int]$TimeoutMinutes,[string]$Criteria="IsInstalled=0 and IsHidden=0")
    $callback=New-OSDStageWindowsUpdateCallback
    $job=$null;$timedOut=$false;$watch=[Diagnostics.Stopwatch]::StartNew();$nextHeartbeat=15
    try {
        $job=switch ($Phase) {
            'Search' { $Agent.BeginSearch($Criteria,$callback,$null) }
            'Download' { $Agent.BeginDownload($callback,$callback,$null) }
            'Install' { $Agent.BeginInstall($callback,$callback,$null) }
        }
        while (-not $job.IsCompleted) {
            if (-not $timedOut -and $watch.Elapsed.TotalMinutes -ge $TimeoutMinutes) {
                $timedOut=$true
                Write-OSDStageWindowsUpdateMessage "$Phase exceeded $TimeoutMinutes minutes; requesting cancellation and waiting for WUA to finish safely." WARN
                $job.RequestAbort()
            }
            if ($watch.Elapsed.TotalSeconds -ge $nextHeartbeat) {
                Write-OSDStageWindowsUpdateMessage ("{0} running ({1}s); cancellation requested: {2}." -f $Phase,[int]$watch.Elapsed.TotalSeconds,$timedOut)
                $nextHeartbeat+=15
            }
            Start-Sleep -Milliseconds 500
        }
        $result=switch ($Phase) {
            'Search' { $Agent.EndSearch($job) }
            'Download' { $Agent.EndDownload($job) }
            'Install' { $Agent.EndInstall($job) }
        }
        [pscustomobject]@{Result=$result;TimedOut=$timedOut;DurationSeconds=[math]::Round($watch.Elapsed.TotalSeconds,1)}
    }
    finally {
        # CleanUp waits for quiescence, including when a COM call throws. Never
        # kill servicing or leave an installer running behind the wrapper.
        if ($null -ne $job) { $job.CleanUp() }
        $watch.Stop()
    }
}

function Save-OSDStageWindowsUpdateReport {
    param([Parameter(Mandatory)]$Report,[Parameter(Mandatory)][string]$Path)
    $resolved=[Environment]::ExpandEnvironmentVariables($Path)
    New-Item -ItemType Directory -Path (Split-Path $resolved -Parent) -Force | Out-Null
    $temp=$resolved+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try {
        $Report | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $temp -Encoding UTF8 -ErrorAction Stop
        Move-Item -LiteralPath $temp -Destination $resolved -Force -ErrorAction Stop
    }
    finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force } }
}

function Invoke-OSDStageWindowsUpdateConfiguration {
    param([Parameter(Mandatory)]$Configuration,[switch]$OobeTest)
    Assert-OSDStageWindowsUpdateConfiguration $Configuration
    $driverClasses=@()
    if ($Configuration.PSObject.Properties.Name -contains 'DriverClass') { $driverClasses=@($Configuration.DriverClass) }
    $previousLogPath=$script:OSDStageWindowsUpdateLogPath
    $resolvedResult=[Environment]::ExpandEnvironmentVariables([string]$Configuration.ResultPath)
    $script:OSDStageWindowsUpdateLogPath=[IO.Path]::ChangeExtension($resolvedResult,'.log')
    New-Item -ItemType Directory -Path (Split-Path $resolvedResult -Parent) -Force | Out-Null
    Set-Content -LiteralPath $script:OSDStageWindowsUpdateLogPath -Value '' -NoNewline -Encoding UTF8 -ErrorAction Stop
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $report=[ordered]@{
        SchemaVersion=2;DeploymentId=[string]$Configuration.DeploymentId
        Phase=$(if ($OobeTest) {'ManualOobeTest'} else {'LastWithinSetupComplete'});Status='Running';Outcome='Running';ScanOnly=$Configuration.ScanOnly
        IncludeDrivers=$Configuration.IncludeDrivers;DriverClass=$driverClasses;Source='PolicyDefault';SelectionPolicy='QualityAndDriversV5'
        StartedAtUtc=[DateTime]::UtcNow.ToString('o');CompletedAtUtc=$null;DurationSeconds=0
        LogPath=$script:OSDStageWindowsUpdateLogPath
        ReleaseBefore=$null;ReleaseAfter=$null;ReleaseUnchanged=$null
        SearchResultCode=$null;FoundCount=0;SelectedCount=0;InstalledCount=0
        RebootRequired=$false;RebootStateKnown=$false;RebootRequested=$false;TimedOut=$false;FurtherScanRequired=$true
        ExecutionPolicy='ContinueUntilRebootPrerequisiteV1';InstallationBlockedByReboot=$false
        Items=@();Error=$null
    }
    try {
        Assert-OSDStageWindowsUpdateContext -OobeTest:$OobeTest
        $report.ReleaseBefore=Get-OSDStageWindowsUpdateRelease
        Save-OSDStageWindowsUpdateReport $report $Configuration.ResultPath
        $session=New-OSDStageWindowsUpdateComObject 'Microsoft.Update.Session'
        $session.ClientApplicationID='OSDStage'
        $searcher=$session.CreateUpdateSearcher()
        # Leave ServerSelection, ServiceID and all update policies unchanged.
        Write-OSDStageWindowsUpdateMessage 'Searching the configured update source.'
        $search=Invoke-OSDStageWindowsUpdateAsync -Agent $searcher -Phase Search -TimeoutMinutes $Configuration.TimeoutMinutes
        $report.SearchResultCode=[int]$search.Result.ResultCode;$report.TimedOut=$search.TimedOut
        if ($search.TimedOut -or $report.SearchResultCode -ne 2) { throw 'Update search did not complete successfully; no updates were installed.' }
        $candidates=@($search.Result.Updates)
        $report.FoundCount=$candidates.Count
        $selected=[Collections.Generic.List[object]]::new()
        $items=[Collections.Generic.List[object]]::new()
        foreach ($candidate in @(Get-OSDStageWindowsUpdateSelections -Updates $candidates -IncludeDrivers $Configuration.IncludeDrivers -DriverClass $driverClasses)) {
            $update=$candidate.Update;$decision=$candidate.Decision
            $item=[pscustomobject]@{
                UpdateId=[string]$update.Identity.UpdateID;Revision=$update.Identity.RevisionNumber
                Title=[string]$update.Title;Type=[int]$update.Type
                BrowseOnly=$update.BrowseOnly;AutoSelectOnWebSites=$update.AutoSelectOnWebSites
                CanRequestUserInput=$update.InstallationBehavior.CanRequestUserInput
                RebootBehavior=$update.InstallationBehavior.RebootBehavior
                DriverClass=$(if ([int]$update.Type -eq 2) { [string]$update.DriverClass } else { $null })
                DriverHardwareId=$(if ([int]$update.Type -eq 2) { [string]$update.DriverHardwareID } else { $null })
                KBArticleIDs=@($update.KBArticleIDs);BundleDecisions=$decision.BundleDecisions
                Categories=@($update.Categories | ForEach-Object { [pscustomobject]@{Id=[string]$_.CategoryID;Type=[string]$_.Type;Name=[string]$_.Name} })
                Selected=$decision.Selected;SelectionReason=$decision.Reason
                Status=if ($decision.Selected) {'Selected'} else {'Skipped'}
                DownloadResultCode=$null;DownloadHResult=$null;InstallResultCode=$null;InstallHResult=$null;RebootRequired=$false
            }
            $items.Add($item)
            if ($decision.Selected) { $selected.Add([pscustomobject]@{Update=$update;Item=$item}) }
            Write-OSDStageWindowsUpdateMessage ("{0}: {1} ({2})." -f $item.Status,$item.Title,$decision.Reason)
        }
        $report.Items=@($items.ToArray());$report.SelectedCount=$selected.Count
        Save-OSDStageWindowsUpdateReport $report $Configuration.ResultPath
        if ($Configuration.ScanOnly) { $report.Status='Succeeded';$report.Outcome='ScanOnly' }
        elseif ($selected.Count -eq 0) { $report.Status='Succeeded';$report.Outcome='NoEligibleUpdates';$report.FurtherScanRequired=$false }
        else {
            $installer=$session.CreateUpdateInstaller()
            $installer.AllowSourcePrompts=$false;$installer.ForceQuiet=$true
            if ($installer.IsBusy) { throw 'Windows Update installer is busy; no concurrent installation was started.' }
            if (Test-OSDStageWindowsUpdateRebootPrerequisite -Installer $installer) {
                $report.InstallationBlockedByReboot=$true
                $report.RebootRequired=$true;$report.Status='Deferred';$report.Outcome='RebootRequiredBeforeInstallation'
                foreach ($entry in $selected) { $entry.Item.Status='Deferred' }
            }
            else {
                $downloads=New-OSDStageWindowsUpdateComObject 'Microsoft.Update.UpdateColl'
                foreach ($entry in $selected) {
                    if (-not $entry.Update.EulaAccepted) { $entry.Update.AcceptEula() }
                    [void]$downloads.Add($entry.Update)
                }
                $downloader=$session.CreateUpdateDownloader();$downloader.Updates=$downloads
                foreach ($entry in $selected) { $entry.Item.Status='Downloading' }
                Save-OSDStageWindowsUpdateReport $report $Configuration.ResultPath
                Write-OSDStageWindowsUpdateMessage ("Downloading {0} selected update(s) before any driver changes." -f $selected.Count)
                $download=Invoke-OSDStageWindowsUpdateAsync -Agent $downloader -Phase Download -TimeoutMinutes $Configuration.TimeoutMinutes
                $report.TimedOut=$download.TimedOut
                for ($i=0;$i -lt $selected.Count;$i++) {
                    $dr=$download.Result.GetUpdateResult($i)
                    $selected[$i].Item.DownloadResultCode=[int]$dr.ResultCode;$selected[$i].Item.DownloadHResult=[int]$dr.HResult
                    $selected[$i].Item.Status=if ([int]$dr.ResultCode -eq 2 -and $selected[$i].Update.IsDownloaded) {'Downloaded'} else {'DownloadFailed'}
                }
                Save-OSDStageWindowsUpdateReport $report $Configuration.ResultPath
                if ($download.TimedOut -or [int]$download.Result.ResultCode -ne 2 -or @($selected | Where-Object {$_.Item.Status -ne 'Downloaded'}).Count -gt 0) {
                    throw 'Download incomplete; no installations were started.'
                }
                # Software before drivers. Install individually for accurate results,
                # exclusive installers and a reboot prerequisite check between updates.
                # Sort-Object is not stable on Windows PowerShell 5.1. Preserve
                # discovery order within each type when partitioning the queue.
                $installQueue=@($selected | Where-Object { [int]$_.Update.Type -eq 1 }) +
                    @($selected | Where-Object { [int]$_.Update.Type -eq 2 })
                foreach ($entry in $installQueue) {
                    if ($report.InstallationBlockedByReboot) { $entry.Item.Status='Deferred';continue }
                    if ($installer.IsBusy) { throw 'Windows Update installer became busy; no concurrent installation was started.' }
                    $single=New-OSDStageWindowsUpdateComObject 'Microsoft.Update.UpdateColl'
                    [void]$single.Add($entry.Update);$installer.Updates=$single
                    # A successful update may need a restart to finish without
                    # blocking further installation. Keep the aggregate flag,
                    # but defer only when WUA says a restart is a prerequisite.
                    if (Test-OSDStageWindowsUpdateRebootPrerequisite -Installer $installer) {
                        $report.InstallationBlockedByReboot=$true
                        $report.RebootRequired=$true;$entry.Item.Status='Deferred'
                        Write-OSDStageWindowsUpdateMessage 'WUA requires a restart before further installation; remaining updates are deferred. No restart requested.' WARN
                        continue
                    }
                    $entry.Item.Status='Installing';Save-OSDStageWindowsUpdateReport $report $Configuration.ResultPath
                    Write-OSDStageWindowsUpdateMessage ('Installing '+$entry.Item.Title)
                    $install=Invoke-OSDStageWindowsUpdateAsync -Agent $installer -Phase Install -TimeoutMinutes $Configuration.TimeoutMinutes
                    $ir=$install.Result.GetUpdateResult(0)
                    $entry.Item.InstallResultCode=[int]$ir.ResultCode;$entry.Item.InstallHResult=[int]$ir.HResult
                    $entry.Item.RebootRequired=([bool]$ir.RebootRequired -or [bool]$install.Result.RebootRequired)
                    $report.RebootRequired=$report.RebootRequired -or $entry.Item.RebootRequired
                    $entry.Item.Status=if ([int]$ir.ResultCode -eq 2) {'Installed'} else {'InstallFailed'}
                    if ($entry.Item.Status -eq 'Installed') { $report.InstalledCount++ }
                    $report.TimedOut=$install.TimedOut
                    Save-OSDStageWindowsUpdateReport $report $Configuration.ResultPath
                    if ($install.TimedOut -or [int]$ir.ResultCode -ne 2 -or [int]$install.Result.ResultCode -ne 2) { throw 'Installation did not complete successfully; remaining updates were not attempted.' }
                    if ($entry.Item.RebootRequired) {
                        Write-OSDStageWindowsUpdateMessage 'Installed update requires a later restart. Checking WUA prerequisites before the next update; no restart requested.'
                    }
                }
                $report.Status=if (@($selected | Where-Object {$_.Item.Status -eq 'Deferred'}).Count -gt 0) {'Deferred'} else {'Succeeded'}
                $report.Outcome=if ($report.RebootRequired) {'RebootRequired'} else {'SelectedUpdatesInstalled'}
            }
        }
    }
    catch { $report.Status='Failed';$report.Outcome='Failed';$report.Error=$_.Exception.Message;Write-OSDStageWindowsUpdateMessage $report.Error ERROR }
    finally {
        if ($null -ne $report.ReleaseBefore) {
            try {
                # Preserve a reboot requirement even if EndInstall throws after
                # servicing changed the machine, or it already existed at scan time.
                $systemInfo=New-OSDStageWindowsUpdateComObject 'Microsoft.Update.SystemInfo'
                $pendingReboot=$systemInfo.RebootRequired
                if ($pendingReboot -isnot [bool]) { throw 'WUA did not return a Boolean reboot state.' }
                $report.RebootRequired=$report.RebootRequired -or $pendingReboot
                $report.RebootStateKnown=$true
            }
            catch { Write-OSDStageWindowsUpdateMessage ('Unable to query final reboot state: '+$_.Exception.Message) WARN }
            try {
                $report.ReleaseAfter=Get-OSDStageWindowsUpdateRelease
                $report.ReleaseUnchanged=($report.ReleaseBefore.DisplayVersion -eq $report.ReleaseAfter.DisplayVersion -and $report.ReleaseBefore.Build -eq $report.ReleaseAfter.Build)
                if (-not $report.ReleaseUnchanged) { $report.Status='Failed';$report.Outcome='ReleaseChanged';$report.Error='Windows release/build changed during the update pass.' }
            }
            catch { $report.Status='Failed';$report.Error=$_.Exception.Message }
        }
        foreach ($item in $report.Items) {
            if ($item.Status -eq 'Installing') { $item.Status='InstallOutcomeUnknown' }
            elseif ($item.Status -eq 'Downloading') { $item.Status='DownloadOutcomeUnknown' }
            elseif ($item.Status -eq 'Downloaded' -or ($item.Status -eq 'Selected' -and -not $Configuration.ScanOnly)) { $item.Status='NotAttempted' }
        }
        $watch.Stop();$report.DurationSeconds=[math]::Round($watch.Elapsed.TotalSeconds,1);$report.CompletedAtUtc=[DateTime]::UtcNow.ToString('o')
        Save-OSDStageWindowsUpdateReport $report $Configuration.ResultPath
    }
    Write-OSDStageWindowsUpdateMessage ("{0}: {1}/{2} installed; reboot required: {3}; {4}s. No reboot requested." -f $report.Outcome,$report.InstalledCount,$report.SelectedCount,$report.RebootRequired,$report.DurationSeconds)
    $script:OSDStageWindowsUpdateLogPath=$previousLogPath
    [pscustomobject]$report
}

if ($MyInvocation.InvocationName -ne '.' -and $ConfigPath) {
    $ErrorActionPreference='Stop'
    try {
        $configuration=Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        $result=Invoke-OSDStageWindowsUpdateConfiguration $configuration
        if ($result.Status -eq 'Failed') { exit 1 }
        if ($result.RebootRequired) { exit 3010 }
        exit 0
    }
    catch { Write-Error -ErrorRecord $_;exit 1 }
}
