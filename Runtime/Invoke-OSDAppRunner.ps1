[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$StagedPath,
    [string[]]$Name
)

$ErrorActionPreference = 'Stop'
$manifestPath = Join-Path $StagedPath 'DeviceManifest.json'
$workRoot = Join-Path $StagedPath 'Work'
$runnerStartedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
$resultPath = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables('%ProgramData%\OSDApps\Results\Latest.json'))
$preInstallResult = $null
$manifest = $null
$apps = @()
$cleanupMode = $null
$logPath = $null
$applicationResults = [System.Collections.Generic.List[object]]::new()

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

function Write-RunnerResult {
    param(
        [Parameter(Mandatory)][ValidateSet('Running','Succeeded','Failed')][string]$Status,
        [string]$FailureType,
        [string]$ErrorMessage
    )

    $directory = Split-Path -Path $resultPath -Parent
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $temporaryPath = "$resultPath.$([guid]::NewGuid().ToString('N')).tmp"
    $completed = @($applicationResults | Where-Object { $_.Status -eq 'Succeeded' }).Count
    $failed = @($applicationResults | Where-Object { $_.Status -eq 'Failed' }).Count
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
        ExpectedApplicationCount  = @($apps).Count
        SuccessfulApplicationCount= $completed
        FailedApplicationCount    = $failed
        PreInstall                = $preInstallResult
        Applications              = @($applicationResults | ForEach-Object { $_ })
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
    Save-RunnerResult -Status Running

    New-Item -ItemType Directory -Path $workRoot -Force | Out-Null

    function Invoke-RepositoryPackage {
        param([Parameter(Mandatory)]$package)
        $packageRoot = Join-Path $StagedPath (Join-Path 'Packages' $package.Id)
        $archivePath = Join-Path $packageRoot 'Package.zip'

        if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
            throw "Package.zip not found for '$($package.Id)': $archivePath"
        }

        if ($package.Archive -and $package.Archive.Sha256) {
            $actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
            if ($actualHash -ne $package.Archive.Sha256) {
                Write-RunnerLog -LogPath $logPath -Event 'PackageIntegrityFailed' -Level 'Error' -Message 'Staged package SHA-256 validation failed.' -Data @{ Id = $package.Id; ExpectedSha256 = $package.Archive.Sha256; ActualSha256 = $actualHash; Archive = $archivePath }
                throw "SHA-256 validation failed for staged package '$($package.Id)'."
            }

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
                $setupPath = Join-Path $StagedPath $app.Setup
                $workingDirectory = Split-Path $setupPath -Parent

                if (-not (Test-Path -LiteralPath $setupPath -PathType Leaf)) {
                    throw "Teams bootstrapper not found: $setupPath"
                }

                $arguments = @('-p')

                if ($app.OfflinePackage) {
                    $offlinePackagePath = Join-Path $StagedPath $app.OfflinePackage
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
                $packagePath = Join-Path $StagedPath $app.Package
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
            'VendorMsi' {
                $packagePath = Join-Path $StagedPath $app.Package
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
                throw "Unsupported built-in application type '$($app.Type)' for '$($app.Id)'."
            }
        }
    }

    Write-RunnerLog -LogPath $logPath -Event 'InstallOrder' -Message 'Resolved application installation order.' -Data @{
        Order = @($apps | ForEach-Object { "$($_.Source):$($_.Id)" })
    }

    foreach ($app in $apps) {
        $applicationStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $execution = switch ([string]$app.Source) {
                'Repository' {
                    Invoke-RepositoryPackage -package $app
                }
                'BuiltIn' {
                    Invoke-BuiltInApp -app $app
                }
                default {
                    throw "Unsupported application source '$($app.Source)' for '$($app.Id)'."
                }
            }

            $applicationStopwatch.Stop()
            $cacheInfo = Get-RunnerCacheInfo -App $app
            $applicationResults.Add([pscustomobject]@{
                Id              = [string]$app.Id
                DisplayName     = if ($app.DisplayName) { [string]$app.DisplayName } else { [string]$app.Id }
                Source          = [string]$app.Source
                Type            = if ($app.Type) { [string]$app.Type } else { $null }
                Version         = if ($app.Version) { [string]$app.Version } elseif ($cacheInfo -and $cacheInfo.Version) { [string]$cacheInfo.Version } else { $null }
                Architecture    = if ($app.Architecture) { [string]$app.Architecture } elseif ($cacheInfo -and $cacheInfo.Architecture) { [string]$cacheInfo.Architecture } else { $null }
                Status          = 'Succeeded'
                ExitCode        = if ($execution) { [int]$execution.ExitCode } else { $null }
                DurationSeconds = [math]::Round($applicationStopwatch.Elapsed.TotalSeconds, 1)
                Integrity       = if ($execution) { [string]$execution.Integrity } else { $null }
                CacheUsed       = if ($cacheInfo -and $null -ne $cacheInfo.Cached) { [bool]$cacheInfo.Cached } else { $null }
                PackageUpdated  = if ($cacheInfo -and $null -ne $cacheInfo.Updated) { [bool]$cacheInfo.Updated } else { $null }
                Error           = $null
            })
            Write-RunnerLog -LogPath $logPath -Event 'ApplicationInstallComplete' -Message 'Application processing completed.' -Data @{
                Id = $app.Id
                Source = $app.Source
                DurationSeconds = [math]::Round($applicationStopwatch.Elapsed.TotalSeconds, 1)
            }
            Save-RunnerResult -Status Running
        }
        catch {
            if ($applicationStopwatch.IsRunning) { $applicationStopwatch.Stop() }
            $applicationError = $_.Exception.Message
            $failedExitCode = $null
            if ($applicationError -match 'exit code\s+(-?\d+)') {
                $failedExitCode = [int]$Matches[1]
            }
            $cacheInfo = Get-RunnerCacheInfo -App $app
            $applicationResults.Add([pscustomobject]@{
                Id              = [string]$app.Id
                DisplayName     = if ($app.DisplayName) { [string]$app.DisplayName } else { [string]$app.Id }
                Source          = [string]$app.Source
                Type            = if ($app.Type) { [string]$app.Type } else { $null }
                Version         = if ($app.Version) { [string]$app.Version } elseif ($cacheInfo -and $cacheInfo.Version) { [string]$cacheInfo.Version } else { $null }
                Architecture    = if ($app.Architecture) { [string]$app.Architecture } elseif ($cacheInfo -and $cacheInfo.Architecture) { [string]$cacheInfo.Architecture } else { $null }
                Status          = 'Failed'
                ExitCode        = $failedExitCode
                DurationSeconds = [math]::Round($applicationStopwatch.Elapsed.TotalSeconds, 1)
                Integrity       = $null
                CacheUsed       = if ($cacheInfo -and $null -ne $cacheInfo.Cached) { [bool]$cacheInfo.Cached } else { $null }
                PackageUpdated  = if ($cacheInfo -and $null -ne $cacheInfo.Updated) { [bool]$cacheInfo.Updated } else { $null }
                Error           = $applicationError
            })
            Write-RunnerLog -LogPath $logPath -Event 'ApplicationInstallFailed' -Level 'Error' -Message $applicationError -Data @{
                Id = $app.Id
                Source = $app.Source
                DurationSeconds = [math]::Round($applicationStopwatch.Elapsed.TotalSeconds, 1)
            }
            throw
        }
    }

    $runnerStopwatch.Stop()
    Write-RunnerLog -LogPath $logPath -Event 'InstallComplete' -Message 'OSD App Runner completed successfully.' -Data @{
        ApplicationCount = @($apps).Count
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
    $failureMessage = $_.Exception.Message
    if ($runnerStopwatch.IsRunning) { $runnerStopwatch.Stop() }
    if (-not $logPath) {
        try {
            $fallbackDir = Join-Path $env:ProgramData 'OSDApps\Logs'
            New-Item -ItemType Directory -Path $fallbackDir -Force | Out-Null
            $logPath = Join-Path $fallbackDir 'Runtime.log'
        }
        catch { }
    }

    $failureType = if ($failureMessage -match 'SHA-256') {
        'HashMismatch'
    }
    elseif ($failureMessage -match 'not found|does not contain') {
        'SourceMissing'
    }
    elseif ($failureMessage -match 'timeout|exceeded') {
        'Timeout'
    }
    elseif ($failureMessage -match 'exit code') {
        'InstallerFailed'
    }
    else {
        'RuntimeError'
    }

    if ($logPath) {
        Write-RunnerLog -LogPath $logPath -Event 'InstallFailed' -Level 'Error' -Message $failureMessage -Data @{
            FailureType = $failureType
            DurationSeconds = [math]::Round($runnerStopwatch.Elapsed.TotalSeconds, 1)
        }
    }
    Save-RunnerResult -Status Failed -FailureType $failureType -ErrorMessage $failureMessage

    exit 1
}
