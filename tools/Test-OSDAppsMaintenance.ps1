#Requires -Version 5.1
<#
.SYNOPSIS
Read-only maintenance checks for an OSDApps USB, release or saved deployment result.
.DESCRIPTION
Run on the preparation PC. This standalone repository tool does not update modules,
change cache content, publish packages, install apps or rerun SetupComplete.
.EXAMPLE
.\Test-OSDAppsMaintenance.ps1 -Mode Usb -ExpectedVersion 0.42.0
.EXAMPLE
.\Test-OSDAppsMaintenance.ps1 -Mode Release -ExpectedVersion 0.42.0
.EXAMPLE
.\Test-OSDAppsMaintenance.ps1 -Mode Result -ResultPath C:\Temp\Latest.json
#>
[CmdletBinding()]
param(
    [ValidateSet('Usb','Release','Result')][string]$Mode = 'Usb',
    [string]$UsbRoot,
    [version]$ExpectedVersion,
    [string]$ResultPath,
    [string]$DeploymentId,
    [switch]$ThrowOnFailure
)

$ErrorActionPreference = 'Stop'
$checks = [System.Collections.Generic.List[object]]::new()
$details = [ordered]@{}

function Add-MaintenanceCheck {
    param([string]$Name, [ValidateSet('Passed','Warning','Failed')][string]$Status, [string]$Message)
    $checks.Add([pscustomobject]@{ Name=$Name; Status=$Status; Message=$Message })
}

function Get-MaintenanceValue {
    param($Object, [string]$Name, $Default = $null)
    if ($null -ne $Object -and $Object.PSObject.Properties.Name -contains $Name) { return $Object.$Name }
    return $Default
}

function Get-MaintenanceGitHub {
    param([string]$Resource)
    Invoke-RestMethod -Uri "https://api.github.com/repos/roryvossepoel/OSDApps/$Resource" -Headers @{
        Accept='application/vnd.github+json'; 'User-Agent'='OSDApps-Maintenance'
    } -TimeoutSec 30 -ErrorAction Stop
}

function Add-MaintenanceWorkflowCheck {
    param([string]$Name, [string]$Workflow, [string]$Commit, [switch]$Publication)
    try {
        $response = Get-MaintenanceGitHub -Resource "actions/workflows/$Workflow/runs?head_sha=$Commit&per_page=1"
        $runs = @(Get-MaintenanceValue -Object $response -Name workflow_runs -Default @())
        if ($runs.Count -eq 0) { Add-MaintenanceCheck $Name Warning 'No workflow run was found for this release commit.'; return }
        $run = $runs[0]
        $details[$Name] = $run
        if ($run.status -ne 'completed') { Add-MaintenanceCheck $Name Warning "Workflow is $($run.status): $($run.html_url)" }
        elseif ($run.conclusion -eq 'success') { Add-MaintenanceCheck $Name Passed "Workflow succeeded: $($run.html_url)" }
        else {
            $state = if ($Publication) { 'Warning' } else { 'Failed' }
            Add-MaintenanceCheck $Name $state "Workflow concluded '$($run.conclusion)'. Investigate this run; Gallery visibility alone does not verify package content. $($run.html_url)"
        }
    }
    catch { Add-MaintenanceCheck $Name Warning "Could not query workflow state: $($_.Exception.Message)" }
}

switch ($Mode) {
    'Usb' {
        try {
            if ($env:OS -eq 'Windows_NT' -and (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT')) {
                throw 'Run USB maintenance on the Windows preparation PC, not in WinPE.'
            }
            if (-not $UsbRoot) {
                $volumes = @(Get-Volume -ErrorAction Stop | Where-Object { $_.FileSystemLabel -eq 'OSDCloud' -and $_.DriveLetter })
                if ($volumes.Count -ne 1) { throw "Expected one OSDCloud volume; found $($volumes.Count). Specify -UsbRoot explicitly if needed." }
                $UsbRoot = '{0}:\' -f $volumes[0].DriveLetter
            }
            $UsbRoot = (Get-Item -LiteralPath $UsbRoot -ErrorAction Stop).FullName
            $details.UsbRoot = $UsbRoot
            $moduleParent = Join-Path $UsbRoot 'Modules\OSDApps'
            $versions = @(Get-ChildItem -LiteralPath $moduleParent -Directory -ErrorAction Stop |
                Where-Object { $_.Name -match '^\d+\.\d+\.\d+(\.\d+)?$' } | Sort-Object { [version]$_.Name } -Descending)
            if ($versions.Count -eq 0) { throw "No versioned OSDApps module found in $moduleParent." }
            $moduleRoot = $versions[0].FullName
            $manifestPath = Join-Path $moduleRoot 'OSDApps.psd1'
            $manifest = Test-ModuleManifest -Path $manifestPath -ErrorAction Stop
            if ($manifest.Version -ne [version]$versions[0].Name) { throw 'Module manifest version differs from its directory name.' }
            if ($ExpectedVersion -and $manifest.Version -ne $ExpectedVersion) {
                throw "Newest USB module is $($manifest.Version); expected $ExpectedVersion."
            }
            foreach ($file in @('Invoke-OSDAppPreInstall.ps1','Invoke-OSDAppRunner.ps1','Restore-OSDAppCacheGeneration.ps1','Assert-OSDAppTransactionSpace.ps1','Enter-OSDAppCacheLock.ps1')) {
                if (-not (Test-Path -LiteralPath (Join-Path $moduleRoot "Runtime\$file") -PathType Leaf)) { throw "Missing runtime file: $file" }
            }
            $loaded = @(Import-Module -Name $manifestPath -Force -PassThru -ErrorAction Stop | Where-Object Name -eq OSDApps)
            if ($loaded.Count -ne 1 -or $loaded[0].ModuleBase -ne $moduleRoot -or $loaded[0].Version -ne $manifest.Version) { throw 'Imported module does not match the selected USB module.' }
            $expectedCommands = @($manifest.ExportedFunctions.Keys | Sort-Object)
            $actualCommands = @($loaded[0].ExportedFunctions.Keys | Sort-Object)
            if ($expectedCommands.Count -eq 0 -or @(Compare-Object $expectedCommands $actualCommands).Count -ne 0) { throw 'Exported commands do not match the module manifest.' }
            $details.Module = [pscustomobject]@{ Version=$loaded[0].Version.ToString(); Path=$moduleRoot; ExportedCommandCount=$actualCommands.Count }
            $details.ModuleVersions = @($versions.Name)
            Add-MaintenanceCheck Module Passed "OSDApps $($manifest.Version), $($actualCommands.Count) exported functions, required runtime files present."

            $cachePath = Join-Path $UsbRoot 'OSDApps'
            $health = & $loaded[0] { param($Path) Get-OSDAppCacheHealth -CachePath $Path -Offline } $cachePath
            $details.CacheHealth = $health
            if (-not $health.CacheAvailable) { Add-MaintenanceCheck Cache Failed "Cache is not available: $cachePath" }
            elseif (-not $health.Healthy -or $health.CacheCatalogError) { Add-MaintenanceCheck Cache Failed 'Cache health checks failed. Inspect Details.CacheHealth and its entries.' }
            elseif ($health.EntryCount -eq 0) { Add-MaintenanceCheck Cache Warning 'Cache exists but contains no package entries.' }
            else { Add-MaintenanceCheck Cache Passed "$($health.EntryCount) cached entries passed offline health checks; online freshness was not checked." }
            if (($health.ObsoleteCount + $health.OrphanedCount + $health.RenamedCount) -gt 0) {
                Add-MaintenanceCheck CacheMaintenance Warning 'Obsolete, orphaned or renamed entries need review. Nothing was removed.'
            }
        }
        catch { Add-MaintenanceCheck Usb Failed $_.Exception.Message }
    }
    'Release' {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $releaseCommit = $null
        try {
            $resource = if ($ExpectedVersion) { "releases/tags/v$ExpectedVersion" } else { 'releases/latest' }
            $release = Get-MaintenanceGitHub -Resource $resource
            $tag = [string]$release.tag_name
            if ($tag -notmatch '^v\d+\.\d+\.\d+(\.\d+)?$' -or $release.draft -or $release.prerelease) { throw 'Expected a published stable versioned release.' }
            $releaseVersion = [version]$tag.Substring(1)
            if ($ExpectedVersion -and $releaseVersion -ne $ExpectedVersion) { throw 'GitHub release does not match the requested version.' }
            $ExpectedVersion = $releaseVersion
            $details.Release = $release
            $details.Version = $releaseVersion.ToString()
            Add-MaintenanceCheck GitHubRelease Passed "Published release ${tag}: $($release.html_url)"
            $commit = Get-MaintenanceGitHub -Resource "commits/$tag"
            $releaseCommit = [string]$commit.sha
            if ($releaseCommit -notmatch '^[a-fA-F0-9]{40}$') { throw 'Release tag did not resolve to a commit SHA.' }
            $details.ReleaseCommit = $releaseCommit
        }
        catch { Add-MaintenanceCheck GitHubRelease Warning "Release or tag could not be confirmed: $($_.Exception.Message)" }
        if ($releaseCommit -and $releaseCommit -match '^[a-fA-F0-9]{40}$') {
            Add-MaintenanceWorkflowCheck -Name ReleaseCI -Workflow ci.yml -Commit $releaseCommit
            Add-MaintenanceWorkflowCheck -Name GalleryWorkflow -Workflow publish.yml -Commit $releaseCommit -Publication
        }
        if ($ExpectedVersion) {
            try {
                $package = Find-Module -Name OSDApps -RequiredVersion $ExpectedVersion.ToString() -Repository PSGallery -ErrorAction Stop
                if (-not $package -or [version]$package.Version -ne $ExpectedVersion) { throw 'Gallery did not return the exact requested version.' }
                $details.GalleryVersion = [string]$package.Version
                Add-MaintenanceCheck GalleryVersion Passed "Gallery lists OSDApps $ExpectedVersion. Package bytes were not downloaded or compared."
            }
            catch { Add-MaintenanceCheck GalleryVersion Warning "Exact Gallery version could not be confirmed: $($_.Exception.Message)" }
        }
    }
    'Result' {
        try {
            if (-not $ResultPath) { throw 'Specify -ResultPath with a saved Latest.json file.' }
            $result = Get-Content -LiteralPath $ResultPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
            foreach ($field in @('SchemaVersion','Status','DeploymentId','ExpectedApplicationCount','SuccessfulApplicationCount','FailedApplicationCount','SkippedApplicationCount','Applications')) {
                if ($null -eq $result -or $result.PSObject.Properties.Name -notcontains $field) { throw "Result is missing required field: $field" }
            }
            if ([string]$result.SchemaVersion -ne '1.0') { throw "Unsupported result schema: $($result.SchemaVersion)" }
            if ([string]$result.Status -notin @('Running','Succeeded','Failed')) { throw "Unsupported result status: $($result.Status)" }
            if ([string]::IsNullOrWhiteSpace([string]$result.DeploymentId)) { throw 'Result has no deployment identity.' }
            if ($DeploymentId -and [string]$result.DeploymentId -ne $DeploymentId) { throw 'Result belongs to another deployment.' }
            foreach ($field in @('ExpectedApplicationCount','SuccessfulApplicationCount','FailedApplicationCount','SkippedApplicationCount')) {
                if ([string]$result.$field -notmatch '^\d+$') { throw "Invalid result count: $field" }
            }
            $apps = @($result.Applications)
            $ids = @($apps | ForEach-Object { [string](Get-MaintenanceValue $_ Id) })
            if (@($ids | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0 -or @($ids | Select-Object -Unique).Count -ne $ids.Count) { throw 'Result contains missing or duplicate application identities.' }
            foreach ($state in @('Succeeded','Failed','Skipped')) {
                $field = switch ($state) { Succeeded { 'SuccessfulApplicationCount' } Failed { 'FailedApplicationCount' } Skipped { 'SkippedApplicationCount' } }
                $count = @($apps | Where-Object { (Get-MaintenanceValue $_ Status) -eq $state }).Count
                if ($count -ne [int]$result.$field) { throw "Application entries do not match $field." }
            }
            if (@($apps | Where-Object { (Get-MaintenanceValue $_ Status) -notin @('Succeeded','Failed','Skipped') }).Count -gt 0) { throw 'An application has an unsupported status.' }
            if ($apps.Count -gt [int]$result.ExpectedApplicationCount) { throw 'Result contains more entries than expected.' }
            $details.Result = $result
            $details.ResultPath = (Get-Item -LiteralPath $ResultPath).FullName
            $preInstall = Get-MaintenanceValue $result PreInstall
            if ($result.Status -eq 'Failed') { Add-MaintenanceCheck Deployment Failed 'Deployment failed. Inspect Details.Result, including failed and skipped entries.' }
            elseif ($result.Status -eq 'Running') { Add-MaintenanceCheck Deployment Warning 'Result is not final: deployment is still recorded as Running.' }
            elseif ($apps.Count -ne [int]$result.ExpectedApplicationCount -or [int]$result.FailedApplicationCount -gt 0 -or [int]$result.SkippedApplicationCount -gt 0 -or (Get-MaintenanceValue $preInstall Status) -in @('Failed','CompletedWithErrors')) {
                throw 'Succeeded result contradicts its application or PreInstall outcomes.'
            }
            elseif ($apps.Count -eq 0) { Add-MaintenanceCheck Deployment Warning 'Successful result contains no application executions.' }
            else { Add-MaintenanceCheck Deployment Passed "$($apps.Count) successful application entries. DeploymentId=$($result.DeploymentId). This is recorded installer evidence, not a fresh device health test." }
            $preApps = @(Get-MaintenanceValue $preInstall Applications -Default @())
            $acquisitionWarnings = @(@($apps) + @($preApps) | Where-Object { (Get-MaintenanceValue $_ AcquisitionOutcome) -in @('FallbackCacheUsed','OfflineCacheUsed') })
            if ((Get-MaintenanceValue $preInstall HasAcquisitionWarnings -Default $false) -or $acquisitionWarnings.Count -gt 0) {
                Add-MaintenanceCheck Acquisition Warning 'Offline cache use or fallback was recorded. Installation can still have succeeded; inspect acquisition outcomes and refresh errors.'
            }
        }
        catch { Add-MaintenanceCheck Result Failed $_.Exception.Message }
    }
}

$status = if (@($checks | Where-Object Status -eq Failed).Count) { 'Failed' } elseif (@($checks | Where-Object Status -eq Warning).Count) { 'ReviewRequired' } else { 'Passed' }
$report = [pscustomobject]@{
    Mode=$Mode; Status=$status; Passed=($status -eq 'Passed')
    CheckedAtUtc=(Get-Date).ToUniversalTime().ToString('o')
    Checks=@($checks | ForEach-Object { $_ }); Details=[pscustomobject]$details
}
foreach ($check in $checks) {
    $color = switch ($check.Status) { Passed { 'Green' } Warning { 'Yellow' } Failed { 'Red' } }
    Write-Host "[$($check.Status)] $($check.Name): $($check.Message)" -ForegroundColor $color
}
$report
if ($ThrowOnFailure -and -not $report.Passed) { throw "OSDApps $Mode maintenance did not pass: $status" }
