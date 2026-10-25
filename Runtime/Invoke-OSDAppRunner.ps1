[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$StagedPath,
    [string[]]$Name
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'OSDAppPayloadFile.ps1')
$sleepRequest = $null
$sleepLog = $null
$manifestPath = Join-Path $StagedPath 'DeviceManifest.json'
$workRoot = Join-Path $StagedPath 'Work'
$runnerStartedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
$resultPath = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables('%ProgramData%\OSDApps\Results\Latest.json'))
$preInstallResult = $null
$manifest = $null
$apps = @()
$cleanupMode = $null
$logPath = $null
$appResults = [System.Collections.Generic.List[object]]::new()
$validatedRepositoryHashes = @{}

function Initialize-RunnerLog {
    param(
        [Parameter(Mandatory)]
        [string]$ConfiguredPath
    )

    $resolvedPath = [Environment]::ExpandEnvironmentVariables($ConfiguredPath)
    $logDirectory = Split-Path -Path $resolvedPath -Parent
    New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    $resolvedPath
}

function Write-RunnerLog {
    param(
        [Parameter(Mandatory)][string]$LogPath,
        [Parameter(Mandatory)][string]$Event,
        [ValidateSet('Info','Warning','Error')][string]$Level = 'Info',
        [string]$Message,
        [hashtable]$Data,
        [int]$MaxSizeMB = 1,
        [int]$RetainFiles = 3
    )

    if (Test-Path -LiteralPath $LogPath -PathType Leaf) {
        $maxBytes = $MaxSizeMB * 1MB
        if ((Get-Item -LiteralPath $LogPath).Length -ge $maxBytes) {
            for ($i = $RetainFiles - 1; $i -ge 1; $i--) {
                $source = "$LogPath.$i"
                $target = "$LogPath.$($i + 1)"
                if (Test-Path -LiteralPath $source) {
                    Move-Item -LiteralPath $source -Destination $target -Force
                }
            }

            Move-Item -LiteralPath $LogPath -Destination "$LogPath.1" -Force
            $oldest = "$LogPath.$($RetainFiles + 1)"
            if (Test-Path -LiteralPath $oldest) {
                Remove-Item -LiteralPath $oldest -Force
            }
        }
    }

    $type = switch ($Level) {
        'Warning' { 2 }
        'Error'   { 3 }
        default   { 1 }
    }

    $details = @()
    if ($Data) {
        foreach ($key in @($Data.Keys | Sort-Object)) {
            $value = $Data[$key]
            if ($value -is [System.Collections.IEnumerable] -and $value -isnot [string]) {
                $value = @($value) -join ','
            }
            $details += ('{0}={1}' -f $key, $value)
        }
    }

    $logMessage = if ($Message) { "[$Event] $Message" } else { "[$Event]" }
    if ($details.Count -gt 0) {
        $logMessage += ' | ' + ($details -join '; ')
    }
    $logMessage = $logMessage -replace '\]LOG\]!>', ']LOG]! >'
    $logMessage = $logMessage -replace '[\r\n\x00-\x1F]+', ' '

    $now = (Get-Date).ToUniversalTime()
    $time = $now.ToString('HH:mm:ss.fff') + '+000'
    $date = $now.ToString('MM-dd-yyyy')
    $thread = [System.Threading.Thread]::CurrentThread.ManagedThreadId

    $line = '<![LOG[{0}]LOG]!><time="{1}" date="{2}" component="Install" context="" type="{3}" thread="{4}" file="">' -f $logMessage, $time, $date, $type, $thread
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
}

function Start-RunnerCleanup {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$LogPath
    )

    $cleanupScript = Join-Path $env:TEMP ("OSDApps-Cleanup-{0}.cmd" -f ([guid]::NewGuid().ToString('N')))
    $cleanupContent = @(
        '@echo off'
        'timeout /t 2 /nobreak >nul'
        ('rd /s /q "{0}"' -f $Path)
        'del /f /q "%~f0"'
    )

    Set-Content -LiteralPath $cleanupScript -Value $cleanupContent -Encoding ASCII

    Write-RunnerLog -LogPath $LogPath -Event 'CleanupScheduled' -Message 'Runtime source cleanup was scheduled.' -Data @{ Path = $Path; CleanupScript = $cleanupScript }

    Start-Process -FilePath $env:ComSpec -ArgumentList @('/d','/c',('"{0}"' -f $cleanupScript)) -WindowStyle Hidden | Out-Null
}

function Get-RunnerCacheInfo {
    param([Parameter(Mandatory)]$App)

    if ([string]$App.Source -ne 'BuiltIn') { return $null }
    $root = Join-Path $StagedPath (Join-Path 'BuiltIn' ([string]$App.Id))
    if ($App.PSObject.Properties['Type'] -and $App.Type -eq 'PrerequisiteExe') {
        $root = Split-Path (Join-Path $StagedPath $App.Package) -Parent
    }
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { return $null }
    $file = Get-ChildItem -LiteralPath $root -Filter 'CacheInfo.json' -File -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $file) { return $null }
    try {
        Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-RunnerLog -LogPath $logPath -Event 'ResultMetadataReadFailed' -Level Warning -Message $_.Exception.Message -Data @{ Id=$App.Id; Path=$file.FullName }
        $null
    }
}

function New-RunnerFailureException {
    param(
        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][string]$FailureType,
        [string]$AppId,
        [switch]$Fatal
    )

    $exception = [System.InvalidOperationException]::new($Message)
    $exception.Data['OSDAppsFailureType'] = $FailureType
    $exception.Data['OSDAppsFatal'] = [bool]$Fatal
    if ($AppId) {
        $exception.Data['OSDAppsAppId'] = $AppId
    }
    $exception
}

function Get-RunnerFailureInfo {
    param(
        [Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$ErrorRecord,
        [string]$AppId
    )

    $exception = $ErrorRecord.Exception
    $message = $exception.Message
    $failureType = $null
    $fatal = $false

    if ($exception.Data -and $exception.Data.Contains('OSDAppsFailureType')) {
        $failureType = [string]$exception.Data['OSDAppsFailureType']
        $fatal = [bool]$exception.Data['OSDAppsFatal']
        if ($exception.Data.Contains('OSDAppsAppId')) {
            $AppId = [string]$exception.Data['OSDAppsAppId']
        }
    }
    elseif ($message -match 'SHA-256') {
        $failureType = 'HashMismatch'
        $fatal = $true
    }
    elseif ($message -match 'timeout|exceeded') {
        $failureType = 'Timeout'
    }
    elseif ($message -match 'exit code') {
        $failureType = 'InstallerFailed'
    }
    elseif ($message -match 'not found|does not contain|missing') {
        $failureType = 'SourceMissing'
    }
    elseif ($message -match 'unsupported .*app|invalid .*manifest|duplicate .*Id') {
        $failureType = 'ManifestInvalid'
        $fatal = $true
    }
    elseif ($AppId) {
        $failureType = 'AppError'
    }
    else {
        $failureType = 'RuntimeError'
        $fatal = $true
    }

    [pscustomobject]@{
        FailureType  = $failureType
        Fatal        = $fatal
        AppId= $AppId
        Message      = $message
    }
}

function New-RunnerAppResult {
    param(
        [Parameter(Mandatory)]$App,
        [Parameter(Mandatory)][ValidateSet('Succeeded','Failed','Skipped')][string]$Status,
        [double]$DurationSeconds = 0,
        $Execution,
        [string]$FailureType,
        [string]$ErrorMessage
    )

    $cacheInfo = Get-RunnerCacheInfo -App $App
    # Freshness belongs to this deployment's PreInstall result, never to an older CacheInfo.json.
    $acquisitionOutcome = if ([string]$App.Source -eq 'BuiltIn') { 'Unknown' } else { 'NotApplicable' }
    $cacheDecisionReason = $null
    $refreshFailureType = $null
    $refreshError = $null
    if ([string]$App.Source -eq 'BuiltIn' -and $preInstallResult) {
        $preparation = @($preInstallResult.Apps | Where-Object { [string]$_.Id -eq [string]$App.Id } | Select-Object -First 1)
        if ($preparation.Count -gt 0 -and $preparation[0].PSObject.Properties.Name -contains 'AcquisitionOutcome') {
            $acquisitionOutcome = [string]$preparation[0].AcquisitionOutcome
            if ($preparation[0].PSObject.Properties.Name -contains 'CacheDecisionReason') { $cacheDecisionReason = $preparation[0].CacheDecisionReason }
            if ($preparation[0].PSObject.Properties.Name -contains 'RefreshFailureType') { $refreshFailureType = $preparation[0].RefreshFailureType }
            if ($preparation[0].PSObject.Properties.Name -contains 'RefreshError') { $refreshError = $preparation[0].RefreshError }
        }
    }
    [pscustomobject]@{
        Id              = [string]$App.Id
        DisplayName     = if ($App.DisplayName) { [string]$App.DisplayName } else { [string]$App.Id }
        Source          = [string]$App.Source
        Type            = if ($App.Type) { [string]$App.Type } else { $null }
        PackageType     = if ($App.PackageType) { [string]$App.PackageType } else { 'App' }
        Version         = if ($App.Version) { [string]$App.Version } elseif ($cacheInfo -and $cacheInfo.Version) { [string]$cacheInfo.Version } else { $null }
        Architecture    = if ($App.Architecture) { [string]$App.Architecture } elseif ($cacheInfo -and $cacheInfo.Architecture) { [string]$cacheInfo.Architecture } else { $null }
        Status          = $Status
        ExitCode        = if ($Execution -and $null -ne $Execution.ExitCode) { [int]$Execution.ExitCode } else { $null }
        DurationSeconds = [math]::Round($DurationSeconds, 1)
        Integrity       = if ($Execution -and $Execution.Integrity) { [string]$Execution.Integrity } else { $null }
        CacheUsed       = if ($cacheInfo -and $null -ne $cacheInfo.Cached) { [bool]$cacheInfo.Cached } else { $null }
        PackageUpdated  = if ($cacheInfo -and $null -ne $cacheInfo.Updated) { [bool]$cacheInfo.Updated } else { $null }
        AcquisitionOutcome = $acquisitionOutcome
        CacheDecisionReason = $cacheDecisionReason
        RefreshFailureType = $refreshFailureType
        RefreshError    = $refreshError
        FailureType     = $FailureType
        Error           = $ErrorMessage
    }
}

function Complete-RunnerAbortedResults {
    param([Parameter(Mandatory)]$Failure)

    $recordedIds = @($appResults | ForEach-Object { [string]$_.Id })
    foreach ($app in $apps) {
        $id = [string]$app.Id
        if ($id -in $recordedIds) { continue }

        $isFailureSource = (
            $Failure.AppId -and
            [string]::Equals($id, [string]$Failure.AppId, [StringComparison]::OrdinalIgnoreCase)
        )
        $status = if ($isFailureSource) { 'Failed' } else { 'Skipped' }
        $type = if ($isFailureSource) { [string]$Failure.FailureType } else { 'ExecutionAborted' }
        $message = if ($isFailureSource) {
            [string]$Failure.Message
        }
        else {
            "Not attempted because execution stopped after a critical $($Failure.FailureType) failure."
        }
        $appResults.Add((New-RunnerAppResult -App $app -Status $status -FailureType $type -ErrorMessage $message))
        $recordedIds += $id
    }
}

function Write-RunnerResult {
    param(
        [Parameter(Mandatory)][ValidateSet('Running','Succeeded','Failed')][string]$Status,
        [string]$FailureType,
        [string]$ErrorMessage
    )

    $directory = Split-Path -Path $resultPath -Parent
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $temporaryPath = "$resultPath.$([guid]::NewGuid().ToString('N')).tmp"
    $completed = @($appResults | Where-Object { $_.Status -eq 'Succeeded' }).Count
    $failed = @($appResults | Where-Object { $_.Status -eq 'Failed' }).Count
    $skipped = @($appResults | Where-Object { $_.Status -eq 'Skipped' }).Count
    $record = [ordered]@{
        SchemaVersion              = '1.0'
        DeploymentId              = if ($manifest -and $manifest.DeploymentId) { [string]$manifest.DeploymentId } else { $null }
        Status                    = $Status
        StartedAtUtc              = $runnerStartedAtUtc
        CompletedAtUtc            = if ($Status -eq 'Running') { $null } else { (Get-Date).ToUniversalTime().ToString('o') }
        DurationSeconds           = [math]::Round($runnerStopwatch.Elapsed.TotalSeconds, 1)
        StagedPath                = $StagedPath
        LogPath                   = $logPath
        CleanupMode               = $cleanupMode
        ExpectedAppCount  = @($apps).Count
        SuccessfulAppCount= $completed
        FailedAppCount    = $failed
        SkippedAppCount   = $skipped
        UnsuccessfulAppCount = ($failed + $skipped)
        PreInstall                = $preInstallResult
        Apps              = @($appResults | ForEach-Object { $_ })
        FailureType               = $FailureType
        Error                     = $ErrorMessage
    }

    try {
        $record | ConvertTo-Json -Depth 20 |
            Set-Content -LiteralPath $temporaryPath -Encoding UTF8 -ErrorAction Stop
        Move-Item -LiteralPath $temporaryPath -Destination $resultPath -Force -ErrorAction Stop
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Save-RunnerResult {
    param(
        [Parameter(Mandatory)][ValidateSet('Running','Succeeded','Failed')][string]$Status,
        [string]$FailureType,
        [string]$ErrorMessage
    )

    try {
        Write-RunnerResult -Status $Status -FailureType $FailureType -ErrorMessage $ErrorMessage
    }
    catch {
        if ($logPath) {
            Write-RunnerLog -LogPath $logPath -Event 'ResultWriteFailed' -Level Warning -Message $_.Exception.Message -Data @{ ResultPath=$resultPath; Status=$Status }
        }
    }
}

$runnerStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

try {
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        throw "Device manifest not found: $manifestPath"
    }

    . (Join-Path $PSScriptRoot 'OSDAppSleepPrevention.ps1')
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $manifest.Runtime) { throw 'Device manifest Runtime configuration is missing.' }
    if ($manifest.Runtime.ResultPath) {
        $resultPath = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables([string]$manifest.Runtime.ResultPath))
    }
    if (-not $manifest.Runtime.CleanupMode) { throw 'Device manifest Runtime.CleanupMode is missing.' }
    if (-not $manifest.Runtime.LogPath) { throw 'Device manifest Runtime.LogPath is missing.' }

    $cleanupMode = [string]$manifest.Runtime.CleanupMode
    if ($cleanupMode -notin @('OnSuccess','Never')) {
        throw "Unsupported CleanupMode '$cleanupMode'."
    }

    $logPath = Initialize-RunnerLog -ConfiguredPath ([string]$manifest.Runtime.LogPath)
    $preventSleep = Get-OSDAppPreventSleep -Runtime $manifest.Runtime
    $sleepLog = {
        param($EventName, $Level, $Message)
        Write-RunnerLog -LogPath $logPath -Event $EventName -Level $Level -Message $Message
    }
    $sleepRequest = Start-OSDAppSleepPrevention -Enabled $preventSleep -Reason 'OSDApps Runner is installing apps and running scripts.' -Log $sleepLog

    $preInstallResultPath = Join-Path (Split-Path -Path $resultPath -Parent) 'PreInstall.json'
    if (Test-Path -LiteralPath $preInstallResultPath -PathType Leaf) {
        try {
            $candidatePreInstallResult = Get-Content -LiteralPath $preInstallResultPath -Raw -Encoding UTF8 |
                ConvertFrom-Json -ErrorAction Stop
            if ($candidatePreInstallResult.DeploymentId -and $manifest.DeploymentId -and
                [string]$candidatePreInstallResult.DeploymentId -ne [string]$manifest.DeploymentId) {
                Write-RunnerLog -LogPath $logPath -Event 'PreInstallResultIgnored' -Level Warning -Message 'PreInstall result belongs to another deployment.' -Data @{ Path=$preInstallResultPath; ExpectedDeploymentId=$manifest.DeploymentId; ActualDeploymentId=$candidatePreInstallResult.DeploymentId }
            }
            else {
                $preInstallResult = $candidatePreInstallResult
            }
        }
        catch {
            Write-RunnerLog -LogPath $logPath -Event 'PreInstallResultReadFailed' -Level Warning -Message $_.Exception.Message -Data @{ Path=$preInstallResultPath }
        }
    }
    Write-RunnerLog -LogPath $logPath -Event 'InstallStart' -Message 'OSD App Runner started.' -Data @{ StagedPath = $StagedPath }

    $apps = if ($manifest.PSObject.Properties.Name -contains 'Apps') { @($manifest.Apps) } else { @() }
    if ($Name) { $apps = @($apps | Where-Object { $_.Id -in $Name }) }

    $deploymentId = [guid]::Empty
    if (-not [guid]::TryParse([string]$manifest.DeploymentId, [ref]$deploymentId)) {
        throw (New-RunnerFailureException -Message 'Device manifest DeploymentId is missing or invalid.' -FailureType 'ManifestInvalid' -Fatal)
    }

    $appIds = @($apps | ForEach-Object { [string]$_.Id })
    $invalidIds = @($appIds | Where-Object {
        $_ -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or $_ -match '\.\.'
    })
    if ($invalidIds.Count -gt 0 -or @($appIds | Select-Object -Unique).Count -ne $appIds.Count) {
        throw (New-RunnerFailureException -Message 'Device manifest contains an invalid or duplicate app Id.' -FailureType 'ManifestInvalid' -Fatal)
    }

    $supportedBuiltInTypes = @('OfficeDeploymentTool','MicrosoftTeamsBootstrapper','AdobeAcrobatUnifiedZip','VendorMsi','7ZipExe','VisualStudioCodeExe','PrerequisiteExe','WindowsInboxCleanupScript','CompanyPortalAppxBundle')
    foreach ($app in $apps) {
        $id = [string]$app.Id
        $source = [string]$app.Source
        if ($source -notin @('Repository','BuiltIn')) {
            throw (New-RunnerFailureException -Message "Unsupported app source '$source' for '$id'." -FailureType 'ManifestInvalid' -AppId $id -Fatal)
        }
        # A built-in cleanup may only run its fixed packaged script and config paths.
        if ($source -eq 'BuiltIn' -and
            ([string]$app.Type -eq 'WindowsInboxCleanupScript' -or $id -eq 'WindowsInboxCleanup')) {
            if ($id -ne 'WindowsInboxCleanup' -or [string]$app.Type -ne 'WindowsInboxCleanupScript' -or
                [string]$app.PackageType -ne 'Script' -or
                [string]$app.Script -ne 'BuiltIn\WindowsInboxCleanup\Install.ps1' -or
                [string]$app.Configuration -ne 'BuiltIn\WindowsInboxCleanup\config.json' -or
                [string]$app.ScriptSha256 -notmatch '^[A-Fa-f0-9]{64}$' -or
                [string]$app.ConfigurationSha256 -notmatch '^[A-Fa-f0-9]{64}$') {
                throw (New-RunnerFailureException -Message 'Invalid Windows Inbox Cleanup built-in manifest.' -FailureType 'ManifestInvalid' -AppId $id -Fatal)
            }
        }
        if ($source -eq 'BuiltIn' -and [string]$app.Type -eq 'CompanyPortalAppxBundle' -and
            -not (Test-OSDAppCompanyPortalDefinition -App $app)) {
            throw (New-RunnerFailureException -Message 'Invalid Company Portal built-in manifest.' -FailureType 'ManifestInvalid' -AppId $id -Fatal)
        }
        if ($source -eq 'BuiltIn' -and [string]$app.Type -notin $supportedBuiltInTypes) {
            throw (New-RunnerFailureException -Message "Unsupported built-in app type '$($app.Type)' for '$id'." -FailureType 'ManifestInvalid' -AppId $id -Fatal)
        }
        if ($source -eq 'Repository' -and
            (-not $app.Archive -or [string]$app.Archive.Sha256 -notmatch '^[A-Fa-f0-9]{64}$')) {
            throw (New-RunnerFailureException -Message "Repository package '$id' has no valid SHA-256 in the device manifest." -FailureType 'ManifestInvalid' -AppId $id -Fatal)
        }
    }

    if ($preInstallResult -and [string]$preInstallResult.Status -eq 'Failed') {
        $failedPreInstallApp = @($preInstallResult.Apps | Where-Object { [string]$_.Status -eq 'Failed' } | Select-Object -First 1)
        $message = if ($preInstallResult.Error) {
            "PreInstall failed: $($preInstallResult.Error)"
        }
        else {
            'PreInstall failed before app installation could start.'
        }
        $failedPreInstallId = if ($failedPreInstallApp.Count -gt 0) { [string]$failedPreInstallApp[0].Id } else { $null }
        throw (New-RunnerFailureException -Message $message -FailureType 'PreInstallFailed' -AppId $failedPreInstallId -Fatal)
    }

    Save-RunnerResult -Status Running

    # Validate every available repository archive before starting the first
    # installer. A trust failure aborts the queue; a missing archive remains an
    # app-local source failure so independent apps can run.
    foreach ($app in @($apps | Where-Object { [string]$_.Source -eq 'Repository' })) {
        $archivePath = Join-Path $StagedPath (Join-Path 'Packages' (Join-Path ([string]$app.Id) 'Package.zip'))
        if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) { continue }

        $actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
        if ($actualHash -ne [string]$app.Archive.Sha256) {
            Write-RunnerLog -LogPath $logPath -Event 'PackageIntegrityFailed' -Level 'Error' -Message 'Staged package SHA-256 validation failed before app execution.' -Data @{ Id=$app.Id; ExpectedSha256=$app.Archive.Sha256; ActualSha256=$actualHash; Archive=$archivePath }
            throw (New-RunnerFailureException -Message "SHA-256 validation failed for staged package '$($app.Id)'." -FailureType 'HashMismatch' -AppId ([string]$app.Id) -Fatal)
        }

        $validatedRepositoryHashes[[string]$app.Id] = $actualHash
        Write-RunnerLog -LogPath $logPath -Event 'PackageIntegrityValidated' -Message 'Staged package SHA-256 validation succeeded before app execution.' -Data @{ Id=$app.Id; Sha256=$actualHash; Archive=$archivePath }
    }

    # Verify the bundled script and config before processing the queue.
    foreach ($app in @($apps | Where-Object { [string]$_.Source -eq 'BuiltIn' -and [string]$_.Type -eq 'WindowsInboxCleanupScript' })) {
        foreach ($entry in @(
            @{ Relative='BuiltIn\WindowsInboxCleanup\Install.ps1'; Hash=[string]$app.ScriptSha256 },
            @{ Relative='BuiltIn\WindowsInboxCleanup\config.json'; Hash=[string]$app.ConfigurationSha256 }
        )) {
            $file = Join-Path $StagedPath $entry.Relative
            if (-not (Test-Path -LiteralPath $file -PathType Leaf) -or
                (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $entry.Hash) {
                throw (New-RunnerFailureException -Message ('Bundled cleanup integrity failed for {0}.' -f $entry.Relative) -FailureType 'HashMismatch' -AppId ([string]$app.Id) -Fatal)
            }
        }
        Write-RunnerLog -LogPath $logPath -Event 'BuiltInScriptIntegrityValidated' -Message 'Bundled script and config SHA-256 validated.' -Data @{ Id=$app.Id }
    }

    foreach ($app in @($apps | Where-Object { [string]$_.Source -eq 'BuiltIn' -and [string]$_.Type -eq 'CompanyPortalAppxBundle' })) {
        try { Assert-OSDAppCompanyPortalFiles -App $app -StagedPath $StagedPath }
        catch { throw (New-RunnerFailureException -Message $_.Exception.Message -FailureType 'HashMismatch' -AppId ([string]$app.Id) -Fatal) }
        Write-RunnerLog -LogPath $logPath -Event 'BuiltInAppxIntegrityValidated' -Message 'Company Portal vendor bundle, license and dependencies validated.' -Data @{Id=$app.Id}
    }

    # CMTrace Open is pre-cached on full Windows; validate again before invoking MSI.
    foreach ($app in @($apps | Where-Object { [string]$_.Source -eq 'BuiltIn' -and [string]$_.Id -eq 'CMTraceOpen' })) {
        $expectedFile = 'CMTrace-Open_{0}_{1}.msi' -f [string]$app.Version,[string]$app.Architecture
        $relative = 'BuiltIn\CMTraceOpen\' + [string]$app.Architecture + '\' + $expectedFile
        if ([string]$app.Version -notmatch '^\d+\.\d+\.\d+$' -or
            [string]$app.Type -ne 'VendorMsi' -or [string]$app.Package -ne $relative -or
            [string]$app.Architecture -notin @('x64','arm64') -or
            [string]$app.ExpectedSha256 -notmatch '^[A-Fa-f0-9]{64}$') {
            throw (New-RunnerFailureException -Message 'Invalid CMTrace Open built-in manifest.' -FailureType 'ManifestInvalid' -AppId 'CMTraceOpen' -Fatal)
        }
        $path = Join-Path $StagedPath $relative
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
            (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne [string]$app.ExpectedSha256) {
            throw (New-RunnerFailureException -Message 'CMTrace Open staged MSI hash mismatch.' -FailureType 'HashMismatch' -AppId 'CMTraceOpen' -Fatal)
        }
        $signature = Get-AuthenticodeSignature -FilePath $path
        if ($signature.Status -ne 'Valid') {
            throw (New-RunnerFailureException -Message 'CMTrace Open MSI signature invalid.' -FailureType 'SignatureInvalid' -AppId 'CMTraceOpen' -Fatal)
        }
        Write-RunnerLog -LogPath $logPath -Event 'BuiltInMsiIntegrityValidated' -Message 'CMTrace Open SHA-256 and Authenticode validation succeeded.' -Data @{ Id=$app.Id }
    }

    New-Item -ItemType Directory -Path $workRoot -Force | Out-Null

    function Invoke-RepositoryPackage {
        param([Parameter(Mandatory)]$package)
        $packageRoot = Join-Path $StagedPath (Join-Path 'Packages' $package.Id)
        $archivePath = Join-Path $packageRoot 'Package.zip'

        if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
            throw "Package.zip not found for '$($package.Id)': $archivePath"
        }

        if (-not $validatedRepositoryHashes.ContainsKey([string]$package.Id)) {
            $actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
            if ($actualHash -ne $package.Archive.Sha256) {
                Write-RunnerLog -LogPath $logPath -Event 'PackageIntegrityFailed' -Level 'Error' -Message 'Staged package SHA-256 validation failed.' -Data @{ Id = $package.Id; ExpectedSha256 = $package.Archive.Sha256; ActualSha256 = $actualHash; Archive = $archivePath }
                throw (New-RunnerFailureException -Message "SHA-256 validation failed for staged package '$($package.Id)'." -FailureType 'HashMismatch' -AppId ([string]$package.Id) -Fatal)
            }

            $validatedRepositoryHashes[[string]$package.Id] = $actualHash
            Write-RunnerLog -LogPath $logPath -Event 'PackageIntegrityValidated' -Message 'Staged package SHA-256 validation succeeded.' -Data @{ Id = $package.Id; Sha256 = $actualHash; Archive = $archivePath }
        }

        $packageWork = Join-Path $workRoot $package.Id
        if (Test-Path -LiteralPath $packageWork) {
            Remove-Item -LiteralPath $packageWork -Recurse -Force
        }
        New-Item -ItemType Directory -Path $packageWork -Force | Out-Null

        Write-RunnerLog -LogPath $logPath -Event 'PackageExtractStart' -Message 'Extracting package archive.' -Data @{ Id = $package.Id; Version = $package.Version; Archive = $archivePath }
        Expand-Archive -LiteralPath $archivePath -DestinationPath $packageWork -Force

        $payloadRoot = Join-Path $packageWork 'Package'
        $installScript = Join-Path $payloadRoot 'Install.ps1'
        if (-not (Test-Path -LiteralPath $installScript -PathType Leaf)) {
            throw "Package '$($package.Id)' does not contain Package\Install.ps1."
        }

        Write-RunnerLog -LogPath $logPath -Event 'PackageInstallStart' -Message 'Starting package installation.' -Data @{ Id = $package.Id; Version = $package.Version }

        $process = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$installScript) -WorkingDirectory $payloadRoot -Wait -PassThru

        $successCodes = @(0,3010)
        if ($package.SuccessCodes) {
            $successCodes = @($package.SuccessCodes | ForEach-Object { [int]$_ })
        }

        if ($process.ExitCode -notin $successCodes) {
            throw "Installation of '$($package.Id)' failed with exit code $($process.ExitCode)."
        }

        Write-RunnerLog -LogPath $logPath -Event 'PackageInstallComplete' -Message 'Package installation completed.' -Data @{ Id = $package.Id; Version = $package.Version; ExitCode = $process.ExitCode }
        [pscustomobject]@{
            ExitCode  = $process.ExitCode
            Integrity = if ($package.Archive -and $package.Archive.Sha256) { 'Sha256Validated' } else { 'NotConfigured' }
        }
    }

    function Invoke-BuiltInApp {
        param([Parameter(Mandatory)]$app)
        switch ($app.Type) {
            'CompanyPortalAppxBundle' {
                $bundle = Join-Path $StagedPath ([string]$app.Package)
                $license = Join-Path $StagedPath ([string]$app.License)
                $dependencies = @($app.Dependencies | ForEach-Object { Join-Path $StagedPath ([string]$_) })
                $existing = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop |
                    Where-Object { $_.DisplayName -eq 'Microsoft.CompanyPortal' })
                if (@($existing | Where-Object { [version]$_.Version -ge [version]$app.Version }).Count -gt 0) {
                    Write-RunnerLog -LogPath $logPath -Event 'BuiltInInstallSkipped' -Message 'Company Portal is already provisioned at the requested or a newer version.' -Data @{ Id=$app.Id }
                    [pscustomobject]@{ExitCode=0;Integrity='Sha256Validated'}
                    break
                }
                Write-RunnerLog -LogPath $logPath -Event 'BuiltInAppxProvisionStart' -Message 'Provisioning Microsoft Company Portal for future users.' -Data @{ Id=$app.Id;Version=$app.Version;Architecture=$app.Architecture }
                Add-AppxProvisionedPackage -Online -PackagePath $bundle -LicensePath $license -DependencyPackagePath $dependencies -Regions all -ErrorAction Stop | Out-Null
                $installed = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop |
                    Where-Object { $_.DisplayName -eq 'Microsoft.CompanyPortal' })
                if ($installed.Count -eq 0) { throw 'Company Portal provisioning returned without a provisioned package.' }
                Write-RunnerLog -LogPath $logPath -Event 'BuiltInAppxProvisionComplete' -Message 'Company Portal provisioning complete.' -Data @{ Id=$app.Id;Version=$app.Version }
                [pscustomobject]@{ExitCode=0;Integrity='Sha256Validated'}
                break
            }
            'WindowsInboxCleanupScript' {
                $root = Join-Path $StagedPath 'BuiltIn\WindowsInboxCleanup'
                $scriptFile = Join-Path $root 'Install.ps1'
                $arguments = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$scriptFile)
                if ($app.DiagnoseOnly -eq $true) { $arguments += '-DiagnoseOnly' }
                Write-RunnerLog -LogPath $logPath -Event 'BuiltInScriptStart' -Message 'Running Windows Inbox Cleanup under SetupComplete.' -Data @{ Id=$app.Id; DiagnoseOnly=[bool]$app.DiagnoseOnly }
                $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WorkingDirectory $root -Wait -PassThru
                if ($process.ExitCode -ne 0) {
                    throw ('Windows Inbox Cleanup failed with exit code {0}.' -f $process.ExitCode)
                }
                Write-RunnerLog -LogPath $logPath -Event 'BuiltInScriptComplete' -Message 'Windows Inbox Cleanup completed.' -Data @{ Id=$app.Id; ExitCode=$process.ExitCode }
                [pscustomobject]@{ ExitCode=$process.ExitCode; Integrity='Sha256Validated' }
            }
            'OfficeDeploymentTool' {
                $setupPath = Join-Path $StagedPath $app.Setup
                $configurationPath = Join-Path $StagedPath $app.Configuration
                $workingDirectory = Split-Path $setupPath -Parent

                if (-not (Test-Path -LiteralPath $setupPath -PathType Leaf)) {
                    throw "Office setup executable not found: $setupPath"
                }
                if (-not (Test-Path -LiteralPath $configurationPath -PathType Leaf)) {
                    throw "Office configuration XML not found: $configurationPath"
                }

                $officeDataPath = Join-Path $workingDirectory 'Office\Data'
                $offlineOffice = Test-Path -LiteralPath $officeDataPath -PathType Container

                Write-RunnerLog -LogPath $logPath -Event 'BuiltInInstallStart' -Message 'Starting built-in Microsoft 365 Apps installation.' -Data @{ Id = $app.Id; Setup = $setupPath; Configuration = $configurationPath; Offline = $offlineOffice }

                $process = Start-Process -FilePath $setupPath -ArgumentList @('/configure', $configurationPath) -WorkingDirectory $workingDirectory -Wait -PassThru
                if ($process.ExitCode -notin @(0,3010)) {
                    throw "Installation of '$($app.Id)' failed with exit code $($process.ExitCode)."
                }

                Write-RunnerLog -LogPath $logPath -Event 'BuiltInInstallComplete' -Message 'Built-in Microsoft 365 Apps installation completed.' -Data @{ Id = $app.Id; ExitCode = $process.ExitCode }
                [pscustomobject]@{ ExitCode=$process.ExitCode; Integrity='PublisherValidatedByPreInstall' }
            }
            'MicrosoftTeamsBootstrapper' {
                Assert-OSDAppManifestPayload -App $app -StagedPath $StagedPath | Out-Null
                $setupPath = Join-Path $StagedPath $app.Setup
                $workingDirectory = Split-Path $setupPath -Parent

                if (-not (Test-Path -LiteralPath $setupPath -PathType Leaf)) {
                    throw "Teams bootstrapper not found: $setupPath"
                }

                $arguments = @('-p')

                if ($app.OfflinePackage) {
                    $offlinePackagePath = Assert-OSDAppManifestPayload -App $app -StagedPath $StagedPath
                    if (-not (Test-Path -LiteralPath $offlinePackagePath -PathType Leaf)) {
                        throw "Teams offline MSIX not found: $offlinePackagePath"
                    }

                    $arguments += '-o'
                    $arguments += $offlinePackagePath
                }

                if ($app.InstallMeetingAddin -eq $true) {
                    $arguments += '--installTMA'
                }

                Write-RunnerLog -LogPath $logPath -Event 'BuiltInInstallStart' -Message 'Starting built-in Microsoft Teams provisioning.' -Data @{ Id = $app.Id; Setup = $setupPath; Arguments = ($arguments -join ' '); Offline = [bool]$app.OfflinePackage }

                $process = Start-Process -FilePath $setupPath -ArgumentList $arguments -WorkingDirectory $workingDirectory -Wait -PassThru
                if ($process.ExitCode -ne 0) {
                    throw "Installation of '$($app.Id)' failed with exit code $($process.ExitCode)."
                }

                Write-RunnerLog -LogPath $logPath -Event 'BuiltInInstallComplete' -Message 'Built-in Microsoft Teams provisioning completed.' -Data @{ Id = $app.Id; ExitCode = $process.ExitCode }
                [pscustomobject]@{ ExitCode=$process.ExitCode; Integrity='PublisherValidatedByPreInstall' }
            }
            'AdobeAcrobatUnifiedZip' {
                $packagePath = Assert-OSDAppManifestPayload -App $app -StagedPath $StagedPath
                if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
                    throw "Adobe Acrobat Unified package not found: $packagePath"
                }

                $adobeWork = Join-Path $workRoot 'AdobeAcrobatUnified'
                if (Test-Path -LiteralPath $adobeWork) {
                    Remove-Item -LiteralPath $adobeWork -Recurse -Force
                }
                New-Item -ItemType Directory -Path $adobeWork -Force | Out-Null

                Write-RunnerLog -LogPath $logPath -Event 'BuiltInExtractStart' -Message 'Extracting Adobe Acrobat Unified package.' -Data @{ Id=$app.Id; Archive=$packagePath; Destination=$adobeWork }
                Expand-Archive -LiteralPath $packagePath -DestinationPath $adobeWork -Force

                $setupPath = Get-ChildItem -LiteralPath $adobeWork -Filter 'Setup.exe' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
                if (-not $setupPath) {
                    throw "Adobe Acrobat Unified Setup.exe was not found after extracting '$packagePath'."
                }

                $arguments = if ($app.InstallArguments) { [string]$app.InstallArguments } else { '/sAll /msi ADDLOCAL=ALL' }
                $workingDirectory = Split-Path $setupPath -Parent

                $timeoutMinutes = if ($app.InstallTimeoutMinutes) { [int]$app.InstallTimeoutMinutes } else { 15 }

                Write-RunnerLog -LogPath $logPath -Event 'BuiltInInstallStart' -Message 'Starting built-in Adobe Acrobat Unified installation.' -Data @{ Id=$app.Id; Setup=$setupPath; Arguments=$arguments; Offline=$true; TimeoutMinutes=$timeoutMinutes }

                $process = Start-Process -FilePath $setupPath -ArgumentList $arguments -WorkingDirectory $workingDirectory -PassThru
                $installStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                $nextHeartbeat = [TimeSpan]::FromMinutes(1)

                while (-not $process.HasExited) {
                    if ($installStopwatch.Elapsed.TotalMinutes -ge $timeoutMinutes) {
                        Write-RunnerLog -LogPath $logPath -Event 'BuiltInInstallTimeout' -Level 'Error' -Message 'Adobe Acrobat Unified installation exceeded its timeout.' -Data @{ Id=$app.Id; ProcessId=$process.Id; ElapsedSeconds=[math]::Round($installStopwatch.Elapsed.TotalSeconds); TimeoutMinutes=$timeoutMinutes }

                        try {
                            Start-Process -FilePath 'taskkill.exe' -ArgumentList @('/PID',[string]$process.Id,'/T','/F') -WindowStyle Hidden -Wait | Out-Null
                        }
                        catch { }

                        throw "Installation of '$($app.Id)' exceeded the $timeoutMinutes minute timeout."
                    }

                    if ($installStopwatch.Elapsed -ge $nextHeartbeat) {
                        Write-RunnerLog -LogPath $logPath -Event 'BuiltInInstallWaiting' -Message 'Adobe Acrobat Unified installation is still running.' -Data @{ Id=$app.Id; ProcessId=$process.Id; ElapsedSeconds=[math]::Round($installStopwatch.Elapsed.TotalSeconds) }
                        $nextHeartbeat = $nextHeartbeat.Add([TimeSpan]::FromMinutes(1))
                    }

                    Start-Sleep -Seconds 2
                    $process.Refresh()
                }

                $installStopwatch.Stop()

                if ($process.ExitCode -notin @(0,3010)) {
                    throw "Installation of '$($app.Id)' failed with exit code $($process.ExitCode)."
                }

                Write-RunnerLog -LogPath $logPath -Event 'BuiltInInstallComplete' -Message 'Built-in Adobe Acrobat Unified installation completed.' -Data @{ Id=$app.Id; ExitCode=$process.ExitCode; DurationSeconds=[math]::Round($installStopwatch.Elapsed.TotalSeconds) }
                [pscustomobject]@{ ExitCode=$process.ExitCode; Integrity='NotAssessed' }
            }
            'PrerequisiteExe' {
                $packagePath = Assert-OSDAppManifestPayload -App $app -StagedPath $StagedPath
                if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
                    throw "EXE package not found for '$($app.Id)': $packagePath"
                }

                $displayName = if ($app.DisplayName) { [string]$app.DisplayName } else { [string]$app.Id }
                $timeoutMinutes = if ($app.InstallTimeoutMinutes) { [int]$app.InstallTimeoutMinutes } else { 10 }
                . (Join-Path $PSScriptRoot 'OSDAppPrerequisite.ps1')
                $spec = Get-OSDAppPrerequisiteSpec -Family $app.Family -Architecture $app.Architecture -RuntimeType $app.RuntimeType -Channel $app.Channel
                if ($app.Id -ne $spec.Id -or $app.PayloadRoot -ne $spec.RelativeRoot) { throw 'Invalid runtime deployment identity or path.' }
                $info = Assert-OSDAppPrerequisiteGeneration -Root (Split-Path $packagePath -Parent) -Spec $spec -VerifyPublisher
                $installed = Get-OSDAppInstalledPrerequisiteVersion -Spec $spec
                if ($installed -and $installed -ge [version]$info.Version) {
                    Write-RunnerLog -LogPath $logPath -Event 'BuiltInInstallComplete' -Message 'A suitable runtime is already installed; no downgrade or repair requested.' -Data @{Id=$app.Id;Version=$installed;ExitCode=0}
                    return [pscustomobject]@{ExitCode=0;Integrity='HashAndPublisherValidated'}
                }
                $arguments = @('/install','/quiet','/norestart')

                Write-RunnerLog -LogPath $logPath -Event 'BuiltInInstallStart' -Message "Starting built-in $displayName EXE installation." -Data @{ Id=$app.Id; Package=$packagePath; Arguments=($arguments -join ' '); Offline=$true; TimeoutMinutes=$timeoutMinutes }

                $process = Start-Process -FilePath $packagePath -ArgumentList $arguments -PassThru
                $installStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                $nextHeartbeat = [TimeSpan]::FromMinutes(1)

                while (-not $process.HasExited) {
                    if ($installStopwatch.Elapsed.TotalMinutes -ge $timeoutMinutes) {
                        Write-RunnerLog -LogPath $logPath -Event 'BuiltInInstallTimeout' -Level 'Error' -Message "$displayName installation exceeded its timeout." -Data @{ Id=$app.Id; ProcessId=$process.Id; ElapsedSeconds=[math]::Round($installStopwatch.Elapsed.TotalSeconds); TimeoutMinutes=$timeoutMinutes }

                        try {
                            Start-Process -FilePath 'taskkill.exe' -ArgumentList @('/PID',[string]$process.Id,'/T','/F') -WindowStyle Hidden -Wait | Out-Null
                        }
                        catch { }

                        throw "Installation of '$($app.Id)' exceeded the $timeoutMinutes minute timeout."
                    }

                    if ($installStopwatch.Elapsed -ge $nextHeartbeat) {
                        Write-RunnerLog -LogPath $logPath -Event 'BuiltInInstallWaiting' -Message "$displayName installation is still running." -Data @{ Id=$app.Id; ProcessId=$process.Id; ElapsedSeconds=[math]::Round($installStopwatch.Elapsed.TotalSeconds) }
                        $nextHeartbeat = $nextHeartbeat.Add([TimeSpan]::FromMinutes(1))
                    }

                    Start-Sleep -Seconds 2
                    $process.Refresh()
                }

                $installStopwatch.Stop()

                if ($process.ExitCode -notin @(0,3010)) {
                    throw "Installation of '$($app.Id)' failed with exit code $($process.ExitCode)."
                }

                $installed = Get-OSDAppInstalledPrerequisiteVersion -Spec $spec
                if (-not $installed -or $installed -lt [version]$info.Version) { throw 'Runtime installer exited successfully, but the required installed version was not detected.' }
                Write-RunnerLog -LogPath $logPath -Event 'BuiltInInstallComplete' -Message "Built-in $displayName installation completed." -Data @{ Id=$app.Id; ExitCode=$process.ExitCode; DurationSeconds=[math]::Round($installStopwatch.Elapsed.TotalSeconds) }
                [pscustomobject]@{ ExitCode=$process.ExitCode; Integrity='HashAndPublisherValidated' }
            }
            'VisualStudioCodeExe' {
                $packagePath = Assert-OSDAppManifestPayload -App $app -StagedPath $StagedPath
                if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
                    throw "EXE package not found for '$($app.Id)': $packagePath"
                }

                $displayName = if ($app.DisplayName) { [string]$app.DisplayName } else { [string]$app.Id }
                $timeoutMinutes = if ($app.InstallTimeoutMinutes) { [int]$app.InstallTimeoutMinutes } else { 10 }
                if ([string]$app.Id -ne 'VisualStudioCode') { throw 'VisualStudioCodeExe requires the VisualStudioCode app Id.' }
                . (Join-Path $PSScriptRoot 'OSDAppVisualStudioCode.ps1')
                Assert-OSDAppVisualStudioCodeGeneration -Root (Split-Path $packagePath -Parent) -Architecture ([string]$app.Architecture) -VerifyPublisher | Out-Null
                $arguments = @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-','/MERGETASKS=!runcode','/RESTARTEXITCODE=3010')

                Write-RunnerLog -LogPath $logPath -Event 'BuiltInInstallStart' -Message "Starting built-in $displayName EXE installation." -Data @{ Id=$app.Id; Package=$packagePath; Arguments=($arguments -join ' '); Offline=$true; TimeoutMinutes=$timeoutMinutes }

                $process = Start-Process -FilePath $packagePath -ArgumentList $arguments -PassThru
                $installStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                $nextHeartbeat = [TimeSpan]::FromMinutes(1)

                while (-not $process.HasExited) {
                    if ($installStopwatch.Elapsed.TotalMinutes -ge $timeoutMinutes) {
                        Write-RunnerLog -LogPath $logPath -Event 'BuiltInInstallTimeout' -Level 'Error' -Message "$displayName installation exceeded its timeout." -Data @{ Id=$app.Id; ProcessId=$process.Id; ElapsedSeconds=[math]::Round($installStopwatch.Elapsed.TotalSeconds); TimeoutMinutes=$timeoutMinutes }

                        try {
                            Start-Process -FilePath 'taskkill.exe' -ArgumentList @('/PID',[string]$process.Id,'/T','/F') -WindowStyle Hidden -Wait | Out-Null
                        }
                        catch { }

                        throw "Installation of '$($app.Id)' exceeded the $timeoutMinutes minute timeout."
                    }

                    if ($installStopwatch.Elapsed -ge $nextHeartbeat) {
                        Write-RunnerLog -LogPath $logPath -Event 'BuiltInInstallWaiting' -Message "$displayName installation is still running." -Data @{ Id=$app.Id; ProcessId=$process.Id; ElapsedSeconds=[math]::Round($installStopwatch.Elapsed.TotalSeconds) }
                        $nextHeartbeat = $nextHeartbeat.Add([TimeSpan]::FromMinutes(1))
                    }

                    Start-Sleep -Seconds 2
                    $process.Refresh()
                }

                $installStopwatch.Stop()

                if ($process.ExitCode -notin @(0,3010)) {
                    throw "Installation of '$($app.Id)' failed with exit code $($process.ExitCode)."
                }

                Write-RunnerLog -LogPath $logPath -Event 'BuiltInInstallComplete' -Message "Built-in $displayName installation completed." -Data @{ Id=$app.Id; ExitCode=$process.ExitCode; DurationSeconds=[math]::Round($installStopwatch.Elapsed.TotalSeconds) }
                [pscustomobject]@{ ExitCode=$process.ExitCode; Integrity='ReleaseSha256AndPublisherValidated' }
            }
            '7ZipExe' {
                $packagePath = Assert-OSDAppManifestPayload -App $app -StagedPath $StagedPath
                if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
                    throw "EXE package not found for '$($app.Id)': $packagePath"
                }

                $displayName = if ($app.DisplayName) { [string]$app.DisplayName } else { [string]$app.Id }
                $timeoutMinutes = if ($app.InstallTimeoutMinutes) { [int]$app.InstallTimeoutMinutes } else { 10 }
                if ([string]$app.Id -ne '7Zip') { throw '7ZipExe requires the 7Zip app Id.' }
                . (Join-Path $PSScriptRoot 'OSDApp7Zip.ps1')
                Assert-OSDApp7ZipGeneration -Root (Split-Path $packagePath -Parent) -Architecture ([string]$app.Architecture) | Out-Null
                $arguments = @('/S')

                Write-RunnerLog -LogPath $logPath -Event 'BuiltInInstallStart' -Message "Starting built-in $displayName EXE installation." -Data @{ Id=$app.Id; Package=$packagePath; Arguments=($arguments -join ' '); Offline=$true; TimeoutMinutes=$timeoutMinutes }

                $process = Start-Process -FilePath $packagePath -ArgumentList $arguments -PassThru
                $installStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                $nextHeartbeat = [TimeSpan]::FromMinutes(1)

                while (-not $process.HasExited) {
                    if ($installStopwatch.Elapsed.TotalMinutes -ge $timeoutMinutes) {
                        Write-RunnerLog -LogPath $logPath -Event 'BuiltInInstallTimeout' -Level 'Error' -Message "$displayName installation exceeded its timeout." -Data @{ Id=$app.Id; ProcessId=$process.Id; ElapsedSeconds=[math]::Round($installStopwatch.Elapsed.TotalSeconds); TimeoutMinutes=$timeoutMinutes }

                        try {
                            Start-Process -FilePath 'taskkill.exe' -ArgumentList @('/PID',[string]$process.Id,'/T','/F') -WindowStyle Hidden -Wait | Out-Null
                        }
                        catch { }

                        throw "Installation of '$($app.Id)' exceeded the $timeoutMinutes minute timeout."
                    }

                    if ($installStopwatch.Elapsed -ge $nextHeartbeat) {
                        Write-RunnerLog -LogPath $logPath -Event 'BuiltInInstallWaiting' -Message "$displayName installation is still running." -Data @{ Id=$app.Id; ProcessId=$process.Id; ElapsedSeconds=[math]::Round($installStopwatch.Elapsed.TotalSeconds) }
                        $nextHeartbeat = $nextHeartbeat.Add([TimeSpan]::FromMinutes(1))
                    }

                    Start-Sleep -Seconds 2
                    $process.Refresh()
                }

                $installStopwatch.Stop()

                if ($process.ExitCode -notin @(0,3010)) {
                    throw "Installation of '$($app.Id)' failed with exit code $($process.ExitCode)."
                }

                Write-RunnerLog -LogPath $logPath -Event 'BuiltInInstallComplete' -Message "Built-in $displayName installation completed." -Data @{ Id=$app.Id; ExitCode=$process.ExitCode; DurationSeconds=[math]::Round($installStopwatch.Elapsed.TotalSeconds) }
                [pscustomobject]@{ ExitCode=$process.ExitCode; Integrity='ReleaseSha256Validated' }
            }
            'VendorMsi' {
                $packagePath = if ([string]$app.Id -eq 'CMTraceOpen') { Join-Path $StagedPath ([string]$app.Package) }
                    else { Assert-OSDAppManifestPayload -App $app -StagedPath $StagedPath }
                if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
                    throw "MSI package not found for '$($app.Id)': $packagePath"
                }

                $displayName = if ($app.DisplayName) { [string]$app.DisplayName } else { [string]$app.Id }
                $timeoutMinutes = if ($app.InstallTimeoutMinutes) { [int]$app.InstallTimeoutMinutes } else { 10 }
                $arguments = @('/i', ('"{0}"' -f $packagePath), '/qn', '/norestart')
                if ($app.PSObject.Properties.Name -contains 'MsiProperties' -and $app.MsiProperties) {
                    $arguments += @($app.MsiProperties)
                }

                Write-RunnerLog -LogPath $logPath -Event 'BuiltInInstallStart' -Message "Starting built-in $displayName MSI installation." -Data @{ Id=$app.Id; Package=$packagePath; Arguments=($arguments -join ' '); Offline=$true; TimeoutMinutes=$timeoutMinutes }

                $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $arguments -PassThru
                $installStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                $nextHeartbeat = [TimeSpan]::FromMinutes(1)

                while (-not $process.HasExited) {
                    if ($installStopwatch.Elapsed.TotalMinutes -ge $timeoutMinutes) {
                        Write-RunnerLog -LogPath $logPath -Event 'BuiltInInstallTimeout' -Level 'Error' -Message "$displayName installation exceeded its timeout." -Data @{ Id=$app.Id; ProcessId=$process.Id; ElapsedSeconds=[math]::Round($installStopwatch.Elapsed.TotalSeconds); TimeoutMinutes=$timeoutMinutes }

                        try {
                            Start-Process -FilePath 'taskkill.exe' -ArgumentList @('/PID',[string]$process.Id,'/T','/F') -WindowStyle Hidden -Wait | Out-Null
                        }
                        catch { }

                        throw "Installation of '$($app.Id)' exceeded the $timeoutMinutes minute timeout."
                    }

                    if ($installStopwatch.Elapsed -ge $nextHeartbeat) {
                        Write-RunnerLog -LogPath $logPath -Event 'BuiltInInstallWaiting' -Message "$displayName installation is still running." -Data @{ Id=$app.Id; ProcessId=$process.Id; ElapsedSeconds=[math]::Round($installStopwatch.Elapsed.TotalSeconds) }
                        $nextHeartbeat = $nextHeartbeat.Add([TimeSpan]::FromMinutes(1))
                    }

                    Start-Sleep -Seconds 2
                    $process.Refresh()
                }

                $installStopwatch.Stop()

                if ($process.ExitCode -notin @(0,3010)) {
                    throw "Installation of '$($app.Id)' failed with exit code $($process.ExitCode)."
                }

                Write-RunnerLog -LogPath $logPath -Event 'BuiltInInstallComplete' -Message "Built-in $displayName installation completed." -Data @{ Id=$app.Id; ExitCode=$process.ExitCode; DurationSeconds=[math]::Round($installStopwatch.Elapsed.TotalSeconds) }
                [pscustomobject]@{ ExitCode=$process.ExitCode; Integrity='PublisherValidatedByPreInstall' }
            }
            default {
                throw "Unsupported built-in app type '$($app.Type)' for '$($app.Id)'."
            }
        }
    }

    Write-RunnerLog -LogPath $logPath -Event 'InstallOrder' -Message 'Resolved app installation order.' -Data @{
        Order = @($apps | ForEach-Object { "$($_.Source):$($_.Id)" })
    }

    $preInstallFailures = @{}
    if ($preInstallResult -and $preInstallResult.Apps) {
        foreach ($preInstallApp in @($preInstallResult.Apps)) {
            if ([string]$preInstallApp.Status -eq 'Failed') {
                $preInstallFailures[[string]$preInstallApp.Id] = $preInstallApp
            }
        }
    }

    foreach ($app in $apps) {
        $id = [string]$app.Id
        if ([string]$app.Source -eq 'BuiltIn' -and $preInstallFailures.ContainsKey($id)) {
            $preInstallFailure = $preInstallFailures[$id]
            $message = if ($preInstallFailure.Error) {
                "Installation was not attempted because PreInstall failed: $($preInstallFailure.Error)"
            }
            else {
                'Installation was not attempted because PreInstall did not prepare this app.'
            }
            $failureType = if ($preInstallFailure.FailureType) { [string]$preInstallFailure.FailureType } else { 'PreInstallFailed' }
            $appResults.Add((New-RunnerAppResult -App $app -Status 'Skipped' -FailureType $failureType -ErrorMessage $message))
            Write-RunnerLog -LogPath $logPath -Event 'AppInstallSkipped' -Level 'Error' -Message $message -Data @{ Id=$id; Source=$app.Source; FailureType=$failureType }
            Save-RunnerResult -Status Running
            continue
        }

        $appStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $execution = switch ([string]$app.Source) {
                'Repository' {
                    Invoke-RepositoryPackage -package $app
                }
                'BuiltIn' {
                    Invoke-BuiltInApp -app $app
                }
                default {
                    throw "Unsupported app source '$($app.Source)' for '$($app.Id)'."
                }
            }

            $appStopwatch.Stop()
            $appResults.Add((New-RunnerAppResult -App $app -Status 'Succeeded' -DurationSeconds $appStopwatch.Elapsed.TotalSeconds -Execution $execution))
            Write-RunnerLog -LogPath $logPath -Event 'AppInstallComplete' -Message 'App processing completed.' -Data @{
                Id = $app.Id
                Source = $app.Source
                PackageType = if ($app.PackageType) { [string]$app.PackageType } else { 'App' }
                DurationSeconds = [math]::Round($appStopwatch.Elapsed.TotalSeconds, 1)
            }
            Save-RunnerResult -Status Running
        }
        catch {
            $appErrorRecord = $_
            if ($appStopwatch.IsRunning) { $appStopwatch.Stop() }
            $failure = Get-RunnerFailureInfo -ErrorRecord $appErrorRecord -AppId $id
            $failedExitCode = $null
            if ($failure.Message -match 'exit code\s+(-?\d+)') {
                $failedExitCode = [int]$Matches[1]
            }
            $failedExecution = if ($null -ne $failedExitCode) { [pscustomobject]@{ ExitCode=$failedExitCode; Integrity=$null } } else { $null }
            $appResults.Add((New-RunnerAppResult -App $app -Status 'Failed' -DurationSeconds $appStopwatch.Elapsed.TotalSeconds -Execution $failedExecution -FailureType $failure.FailureType -ErrorMessage $failure.Message))
            Write-RunnerLog -LogPath $logPath -Event 'AppInstallFailed' -Level 'Error' -Message $failure.Message -Data @{
                Id = $app.Id
                Source = $app.Source
                PackageType = if ($app.PackageType) { [string]$app.PackageType } else { 'App' }
                FailureType = $failure.FailureType
                ContinueQueue = (-not $failure.Fatal)
                DurationSeconds = [math]::Round($appStopwatch.Elapsed.TotalSeconds, 1)
            }
            Save-RunnerResult -Status Running
            if ($failure.Fatal) {
                throw
            }
        }
    }

    $runnerStopwatch.Stop()
    $failedAppCount = @($appResults | Where-Object { $_.Status -eq 'Failed' }).Count
    $skippedAppCount = @($appResults | Where-Object { $_.Status -eq 'Skipped' }).Count
    if (($failedAppCount + $skippedAppCount) -gt 0) {
        $summary = "$failedAppCount app(s) failed and $skippedAppCount app(s) were skipped; no automatic retry is scheduled."
        Write-RunnerLog -LogPath $logPath -Event 'InstallCompletedWithErrors' -Level 'Error' -Message $summary -Data @{
            AppCount = @($apps).Count
            SuccessfulAppCount = @($appResults | Where-Object { $_.Status -eq 'Succeeded' }).Count
            FailedAppCount = $failedAppCount
            SkippedAppCount = $skippedAppCount
            CleanupMode = $cleanupMode
            DurationSeconds = [math]::Round($runnerStopwatch.Elapsed.TotalSeconds, 1)
        }
        Save-RunnerResult -Status Failed -FailureType 'AppFailures' -ErrorMessage $summary
        Write-RunnerLog -LogPath $logPath -Event 'CleanupSkipped' -Level 'Warning' -Message 'Runtime source cleanup was skipped because one or more apps were unsuccessful.' -Data @{ Path=$StagedPath; CleanupMode=$cleanupMode; Reason='AppFailures' }
        exit 1
    }

    Write-RunnerLog -LogPath $logPath -Event 'InstallComplete' -Message 'OSD App Runner completed successfully.' -Data @{
        AppCount = @($apps).Count
        CleanupMode = $cleanupMode
        DurationSeconds = [math]::Round($runnerStopwatch.Elapsed.TotalSeconds, 1)
    }
    Save-RunnerResult -Status Succeeded

    if ($cleanupMode -eq 'Never') {
        Write-RunnerLog -LogPath $logPath -Event 'CleanupSkipped' -Message 'Runtime source cleanup was skipped by configuration.' -Data @{ Path = $StagedPath; CleanupMode = $cleanupMode }
    }
    else {
        Start-RunnerCleanup -Path $StagedPath -LogPath $logPath
    }

    exit 0
}
catch {
    $runtimeErrorRecord = $_
    $failure = Get-RunnerFailureInfo -ErrorRecord $runtimeErrorRecord
    $failureMessage = $failure.Message
    if ($runnerStopwatch.IsRunning) { $runnerStopwatch.Stop() }
    if (-not $logPath) {
        try {
            $fallbackDir = Join-Path $env:ProgramData 'OSDApps\Logs'
            New-Item -ItemType Directory -Path $fallbackDir -Force | Out-Null
            $logPath = Join-Path $fallbackDir 'Runtime.log'
        }
        catch { }
    }

    Complete-RunnerAbortedResults -Failure $failure

    if ($logPath) {
        Write-RunnerLog -LogPath $logPath -Event 'InstallFailed' -Level 'Error' -Message $failureMessage -Data @{
            FailureType = $failure.FailureType
            DurationSeconds = [math]::Round($runnerStopwatch.Elapsed.TotalSeconds, 1)
        }
        Write-RunnerLog -LogPath $logPath -Event 'CleanupSkipped' -Level 'Warning' -Message 'Runtime source cleanup was skipped after a critical execution failure.' -Data @{ Path=$StagedPath; CleanupMode=$cleanupMode; Reason=$failure.FailureType }
    }
    Save-RunnerResult -Status Failed -FailureType $failure.FailureType -ErrorMessage $failureMessage

    exit 1
}
finally {
    if ($null -ne $sleepRequest) { Stop-OSDAppSleepPrevention -Request $sleepRequest -Log $sleepLog }
}
