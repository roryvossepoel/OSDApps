#Requires -Version 5.1
<#
.SYNOPSIS
Maintenance checks and diagnostic export for OSDStage.
.DESCRIPTION
Run checks on the preparation PC or export diagnostics on the deployed PC.
Diagnostics writes a local ZIP with results and logs; source files are only read.
This standalone repository tool does not update modules,
change cache content, publish packages, install apps or rerun SetupComplete.
.EXAMPLE
.\Test-OSDStageMaintenance.ps1 -Mode Usb -ExpectedVersion 0.42.0
.EXAMPLE
.\Test-OSDStageMaintenance.ps1 -Mode Release -ExpectedVersion 0.42.0
.EXAMPLE
.\Test-OSDStageMaintenance.ps1 -Mode Result -ResultPath C:\Temp\Latest.json
.EXAMPLE
.\Test-OSDStageMaintenance.ps1 -Mode Diagnostics -OutputPath C:\Temp\OSDStage-Diagnostics.zip
#>
[CmdletBinding()]
param(
    [ValidateSet('Usb','Release','Result','Diagnostics')][string]$Mode = 'Usb',
    [string]$UsbRoot,
    [version]$ExpectedVersion,
    [string]$ResultPath,
    [string]$DeploymentId,
    [string]$OutputPath,
    [string]$LogPath,
    [string[]]$InstallerLogDirectory,
    [string[]]$AdditionalLogPath,
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
        Accept='application/vnd.github+json'; 'User-Agent'='OSDStage-Maintenance'
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

function Export-MaintenanceDiagnosticBundle {
    param([string]$ResultFile, [string]$Destination, [string]$ExpectedDeployment,
        [string]$RuntimeLog, [string[]]$InstallerDirectories, [string[]]$ExtraLogs)

    if (-not $Destination -or [IO.Path]::GetExtension($Destination) -ne '.zip') { throw 'Specify -OutputPath with a new .zip filename.' }
    $Destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Destination)
    if (Test-Path -LiteralPath $Destination) { throw 'The output file already exists; choose another name.' }
    $parent = Split-Path $Destination -Parent
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { throw 'The output directory must already exist.' }
    $files = [Collections.Generic.List[object]]::new()
    $seen = @{}
    $state = @{ Bytes=0L; Copied=0 }
    $bundleRoot = Join-Path ([IO.Path]::GetTempPath()) ('OSDStage-Diagnostics-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $bundleRoot | Out-Null

    function Assert-DiagnosticPath {
        param([string]$Path)
        if ($Path -match '^[\\/]{2}') { throw 'Network paths are not collected.' }
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if ($item.PSProvider.Name -ne 'FileSystem') { throw 'Only filesystem paths are collected.' }
        $ancestor = $item
        while ($null -ne $ancestor) {
            if (($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Linked paths are not collected.' }
            $ancestor = if ($ancestor -is [IO.DirectoryInfo]) { $ancestor.Parent } else { $ancestor.Directory }
        }
        return $item
    }
    function Copy-DiagnosticFile {
        param([string]$Path, [string]$Kind)
        if ([string]::IsNullOrWhiteSpace($Path) -or $seen.ContainsKey($Path)) { return }
        $seen[$Path] = $true
        $entry = [ordered]@{ Source=$Path; Kind=$Kind; Status='Skipped'; ArchivePath=$null; Bytes=0; Sha256=$null; Reason=$null }
        $inputStream=$null; $outputStream=$null; $target=$null
        try {
            $item = Assert-DiagnosticPath $Path
            if ($item.PSIsContainer) { throw 'Expected a file.' }
            if ($state.Copied -ge 100) { throw 'The 100-file bundle limit was reached.' }
            $inputStream = [IO.File]::Open($item.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
            $length = $inputStream.Length
            if ($length -gt 20MB -or ($state.Bytes + $length) -gt 100MB) { throw 'The 20 MB per-file or 100 MB bundle limit would be exceeded.' }
            $leaf = '{0:D3}-{1}' -f $state.Copied, $item.Name
            $target = Join-Path $bundleRoot $leaf
            $outputStream = [IO.File]::Open($target,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
            $buffer = New-Object byte[] 65536
            $remaining = $length
            while ($remaining -gt 0) {
                $read = $inputStream.Read($buffer,0,[int][math]::Min($buffer.Length,$remaining))
                if ($read -eq 0) { throw 'Source became shorter during collection.' }
                $outputStream.Write($buffer,0,$read)
                $remaining -= $read
            }
            $outputStream.Dispose(); $outputStream=$null
            $entry.Status='Copied'; $entry.ArchivePath=$leaf; $entry.Bytes=$length
            $entry.Sha256=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
            $state.Bytes += $length; $state.Copied++
        }
        catch {
            $entry.Reason=$_.Exception.Message
            Add-MaintenanceCheck DiagnosticFile Warning "$Path : $($entry.Reason)"
        }
        finally {
            if ($outputStream) { $outputStream.Dispose() }
            if ($inputStream) { $inputStream.Dispose() }
            if ($target -and $entry.Status -ne 'Copied') { Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue }
            $files.Add([pscustomobject]$entry)
        }
    }
    try {
        if (-not $ResultFile) { $ResultFile = [Environment]::ExpandEnvironmentVariables('%ProgramData%\OSDStage\Results\Latest.json') }
        $ResultFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ResultFile)
        Copy-DiagnosticFile $ResultFile Result
        $resultEntry = @($files | Where-Object { $_.Kind -eq 'Result' -and $_.Status -eq 'Copied' })
        $result=$null
        if ($resultEntry.Count -eq 1) {
            try { $result = Get-Content -LiteralPath (Join-Path $bundleRoot $resultEntry[0].ArchivePath) -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop }
            catch { Add-MaintenanceCheck DiagnosticResult Warning "Result JSON could not be read: $($_.Exception.Message)" }
        }
        $actualId = [string](Get-MaintenanceValue $result DeploymentId)
        $pre = Get-MaintenanceValue $result PreInstall
        $prePath = Join-Path (Split-Path $ResultFile -Parent) 'PreInstall.json'
        if (Test-Path -LiteralPath $prePath -PathType Leaf) {
            # Keep the embedded, correlated PreInstall record in Latest.json. Do not silently mix a later standalone run.
            try {
                $preItem=Assert-DiagnosticPath $prePath
                if ($preItem.Length -gt 20MB) { throw 'PreInstall result exceeds 20 MB.' }
                $separate = Get-Content -LiteralPath $prePath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
                if (-not $result -and -not $actualId) {
                    $actualId = [string](Get-MaintenanceValue $separate DeploymentId)
                    $pre = $separate
                }
                if ($actualId -and [string](Get-MaintenanceValue $separate DeploymentId) -eq $actualId) { Copy-DiagnosticFile $prePath PreInstall }
                else { Add-MaintenanceCheck DiagnosticPreInstall Warning 'Standalone PreInstall.json was omitted because its deployment identity could not be correlated.' }
            }
            catch { Add-MaintenanceCheck DiagnosticPreInstall Warning $_.Exception.Message }
        }
        if ($ExpectedDeployment -and $actualId -ne $ExpectedDeployment) { throw 'Result is missing or belongs to another deployment; no bundle was exported.' }
        if (-not $RuntimeLog) { $RuntimeLog = [string](Get-MaintenanceValue $result LogPath) }
        if (-not $RuntimeLog) { $RuntimeLog = [Environment]::ExpandEnvironmentVariables('%ProgramData%\OSDStage\Logs\Runtime.log') }
        $RuntimeLog = [Environment]::ExpandEnvironmentVariables($RuntimeLog)
        Copy-DiagnosticFile $RuntimeLog RuntimeLog
        foreach ($suffix in @('.1','.2','.3')) {
            if (Test-Path -LiteralPath "$RuntimeLog$suffix" -PathType Leaf) { Copy-DiagnosticFile "$RuntimeLog$suffix" RotatedRuntimeLog }
        }
        foreach ($path in $ExtraLogs) { Copy-DiagnosticFile $path ExplicitLog }
        $startText = [string](Get-MaintenanceValue $pre StartedAtUtc (Get-MaintenanceValue $result StartedAtUtc))
        $endText = [string](Get-MaintenanceValue $result CompletedAtUtc (Get-MaintenanceValue $pre CompletedAtUtc))
        $start=[datetimeoffset]::MinValue; $end=[datetimeoffset]::MinValue
        $hasWindow = [datetimeoffset]::TryParse($startText,[ref]$start) -and [datetimeoffset]::TryParse($endText,[ref]$end) -and $end -ge $start
        if ($hasWindow) {
            $from=$start.UtcDateTime.AddMinutes(-5); $until=$end.UtcDateTime.AddMinutes(5)
            if (-not $InstallerDirectories) {
                $InstallerDirectories = @([IO.Path]::GetTempPath())
                if ($env:windir) {
                    $InstallerDirectories += @((Join-Path $env:windir 'Temp'),(Join-Path $env:windir 'SystemTemp'),(Join-Path $env:windir 'System32\config\systemprofile\AppData\Local\Temp'))
                }
            }
            foreach ($directory in @($InstallerDirectories | Select-Object -Unique)) {
                if (-not (Test-Path -LiteralPath $directory -PathType Container)) { continue }
                try {
                    $null=Assert-DiagnosticPath $directory
                    # Top-level only. Office ODT machine/date logs plus known vendor installer names.
                    $candidates = @(Get-ChildItem -LiteralPath $directory -File -Force -ErrorAction Stop | Where-Object {
                        $_.Name -match '^(?:.+-\d{8}-\d{4}\.log|teamsprovision\..+\.log|chrome_installer\.log|dd_vcredist[^\\/]*\.log|AdobePDFPrinterInstall\.log|adobegc\.log)$' -and
                        $_.LastWriteTimeUtc -ge $from -and $_.LastWriteTimeUtc -le $until
                    } | Sort-Object LastWriteTimeUtc -Descending)
                    if ($candidates.Count -gt 100) { Add-MaintenanceCheck DiagnosticLimit Warning "More than 100 installer candidates in $directory; only the newest 100 were considered." }
                    foreach ($candidate in @($candidates | Select-Object -First 100)) { Copy-DiagnosticFile $candidate.FullName InstallerLogCandidate }
                }
                catch { Add-MaintenanceCheck DiagnosticSearch Warning "$directory : $($_.Exception.Message)" }
            }
        }
        else { Add-MaintenanceCheck DiagnosticWindow Warning 'No valid completed deployment time window; automatic installer-log discovery was skipped. Use -AdditionalLogPath for explicit files.' }
        if ($state.Copied -eq 0) { throw 'No diagnostic files could be collected.' }
        $summary = [ordered]@{
            SchemaVersion='2.0'; CollectedAtUtc=(Get-Date).ToUniversalTime().ToString('o'); DeploymentId=$actualId
            RecordedStatus=(Get-MaintenanceValue $result Status); Files=@($files.ToArray()); Checks=@($checks.ToArray())
            Notes='Read-only source collection. Logs are not an atomic snapshot and may contain other deployments. Installer candidates match filename and time, not proven deployment identity. Contents are not redacted. Review before sharing. No installers, scripts or Office configuration XML are collected automatically.'
        }
        $summary | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $bundleRoot 'Bundle.json') -Encoding UTF8
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        # ZipFile uses CreateNew: never replace an existing destination, including a competing export.
        [IO.Compression.ZipFile]::CreateFromDirectory($bundleRoot,$Destination)
        $details.Bundle = [pscustomobject]@{ Path=$Destination; DeploymentId=$actualId; FileCount=$state.Copied; SourceBytes=$state.Bytes; Sha256=(Get-FileHash -LiteralPath $Destination).Hash }
        Add-MaintenanceCheck DiagnosticBundle Passed "Collected $($state.Copied) files: $Destination. Bundle creation does not establish deployment success."
    }
    finally { Remove-Item -LiteralPath $bundleRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

switch ($Mode) {
    'Diagnostics' {
        try { Export-MaintenanceDiagnosticBundle -ResultFile $ResultPath -Destination $OutputPath -ExpectedDeployment $DeploymentId -RuntimeLog $LogPath -InstallerDirectories $InstallerLogDirectory -ExtraLogs $AdditionalLogPath }
        catch { Add-MaintenanceCheck Diagnostics Failed $_.Exception.Message }
    }
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
            $moduleParent = Join-Path $UsbRoot 'Modules\OSDStage'
            $versions = @(Get-ChildItem -LiteralPath $moduleParent -Directory -ErrorAction Stop |
                Where-Object { $_.Name -match '^\d+\.\d+\.\d+(\.\d+)?$' } | Sort-Object { [version]$_.Name } -Descending)
            if ($versions.Count -eq 0) { throw "No versioned OSDStage module found in $moduleParent." }
            $moduleRoot = $versions[0].FullName
            $manifestPath = Join-Path $moduleRoot 'OSDStage.psd1'
            $manifest = Test-ModuleManifest -Path $manifestPath -ErrorAction Stop
            if ($manifest.Version -ne [version]$versions[0].Name) { throw 'Module manifest version differs from its directory name.' }
            if ($ExpectedVersion -and $manifest.Version -ne $ExpectedVersion) {
                throw "Newest USB module is $($manifest.Version); expected $ExpectedVersion."
            }
            foreach ($file in @('Invoke-OSDStagePreInstall.ps1','Invoke-OSDStageRunner.ps1','Restore-OSDStageCacheGeneration.ps1','Assert-OSDStageTransactionSpace.ps1','Enter-OSDStageCacheLock.ps1')) {
                if (-not (Test-Path -LiteralPath (Join-Path $moduleRoot "Runtime\$file") -PathType Leaf)) { throw "Missing runtime file: $file" }
            }
            $loaded = @(Import-Module -Name $manifestPath -Force -PassThru -ErrorAction Stop | Where-Object Name -eq OSDStage)
            if ($loaded.Count -ne 1 -or $loaded[0].ModuleBase -ne $moduleRoot -or $loaded[0].Version -ne $manifest.Version) { throw 'Imported module does not match the selected USB module.' }
            $expectedCommands = @($manifest.ExportedFunctions.Keys | Sort-Object)
            $actualCommands = @($loaded[0].ExportedFunctions.Keys | Sort-Object)
            if ($expectedCommands.Count -eq 0 -or @(Compare-Object $expectedCommands $actualCommands).Count -ne 0) { throw 'Exported commands do not match the module manifest.' }
            $details.Module = [pscustomobject]@{ Version=$loaded[0].Version.ToString(); Path=$moduleRoot; ExportedCommandCount=$actualCommands.Count }
            $details.ModuleVersions = @($versions.Name)
            Add-MaintenanceCheck Module Passed "OSDStage $($manifest.Version), $($actualCommands.Count) exported functions, required runtime files present."

            $cachePath = Join-Path $UsbRoot 'OSDStage'
            $health = & $loaded[0] { param($Path) Get-OSDStageCacheHealth -CachePath $Path -Offline } $cachePath
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
                $package = Find-Module -Name OSDStage -RequiredVersion $ExpectedVersion.ToString() -Repository PSGallery -ErrorAction Stop
                if (-not $package -or [version]$package.Version -ne $ExpectedVersion) { throw 'Gallery did not return the exact requested version.' }
                $details.GalleryVersion = [string]$package.Version
                Add-MaintenanceCheck GalleryVersion Passed "Gallery lists OSDStage $ExpectedVersion. Package bytes were not downloaded or compared."
            }
            catch { Add-MaintenanceCheck GalleryVersion Warning "Exact Gallery version could not be confirmed: $($_.Exception.Message)" }
        }
    }
    'Result' {
        try {
            if (-not $ResultPath) { throw 'Specify -ResultPath with a saved Latest.json file.' }
            $result = Get-Content -LiteralPath $ResultPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
            foreach ($field in @('SchemaVersion','Status','DeploymentId','ExpectedPackageCount','SuccessfulPackageCount','FailedPackageCount','SkippedPackageCount','Packages')) {
                if ($null -eq $result -or $result.PSObject.Properties.Name -notcontains $field) { throw "Result is missing required field: $field" }
            }
            if ([string]$result.SchemaVersion -ne '2.0') { throw "Unsupported result schema: $($result.SchemaVersion)" }
            if ([string]$result.Status -notin @('Running','Succeeded','Failed')) { throw "Unsupported result status: $($result.Status)" }
            if ([string]::IsNullOrWhiteSpace([string]$result.DeploymentId)) { throw 'Result has no deployment identity.' }
            if ($DeploymentId -and [string]$result.DeploymentId -ne $DeploymentId) { throw 'Result belongs to another deployment.' }
            foreach ($field in @('ExpectedPackageCount','SuccessfulPackageCount','FailedPackageCount','SkippedPackageCount')) {
                if ([string]$result.$field -notmatch '^\d+$') { throw "Invalid result count: $field" }
            }
            $apps = @($result.Packages)
            $ids = @($apps | ForEach-Object { [string](Get-MaintenanceValue $_ Id) })
            if (@($ids | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0 -or @($ids | Select-Object -Unique).Count -ne $ids.Count) { throw 'Result contains missing or duplicate app identities.' }
            foreach ($state in @('Succeeded','Failed','Skipped')) {
                $field = switch ($state) { Succeeded { 'SuccessfulPackageCount' } Failed { 'FailedPackageCount' } Skipped { 'SkippedPackageCount' } }
                $count = @($apps | Where-Object { (Get-MaintenanceValue $_ Status) -eq $state }).Count
                if ($count -ne [int]$result.$field) { throw "App entries do not match $field." }
            }
            if (@($apps | Where-Object { (Get-MaintenanceValue $_ Status) -notin @('Succeeded','Failed','Skipped') }).Count -gt 0) { throw 'An app has an unsupported status.' }
            if ($apps.Count -gt [int]$result.ExpectedPackageCount) { throw 'Result contains more entries than expected.' }
            $details.Result = $result
            $details.ResultPath = (Get-Item -LiteralPath $ResultPath).FullName
            $preInstall = Get-MaintenanceValue $result PreInstall
            if ($result.Status -eq 'Failed') { Add-MaintenanceCheck Deployment Failed 'Deployment failed. Inspect Details.Result, including failed and skipped entries.' }
            elseif ($result.Status -eq 'Running') { Add-MaintenanceCheck Deployment Warning 'Result is not final: deployment is still recorded as Running.' }
            elseif ($apps.Count -ne [int]$result.ExpectedPackageCount -or [int]$result.FailedPackageCount -gt 0 -or [int]$result.SkippedPackageCount -gt 0 -or (Get-MaintenanceValue $preInstall Status) -in @('Failed','CompletedWithErrors')) {
                throw 'Succeeded result contradicts its app or PreInstall outcomes.'
            }
            elseif ($apps.Count -eq 0) { Add-MaintenanceCheck Deployment Warning 'Successful result contains no app executions.' }
            else { Add-MaintenanceCheck Deployment Passed "$($apps.Count) successful app entries. DeploymentId=$($result.DeploymentId). This is recorded installer evidence, not a fresh device health test." }
            $preApps = @(Get-MaintenanceValue $preInstall Packages -Default @())
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
if ($ThrowOnFailure -and -not $report.Passed) { throw "OSDStage $Mode maintenance did not pass: $status" }
