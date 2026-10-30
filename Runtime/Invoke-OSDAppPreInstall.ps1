[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$StagedPath,
    [ValidateRange(1,120)][int]$OfficeRefreshTimeoutMinutes = 20
)

$ErrorActionPreference = 'Stop'
$sleepRequest = $null
$sleepLog = $null
. (Join-Path $PSScriptRoot 'Enter-OSDAppCacheLock.ps1')
. (Join-Path $PSScriptRoot 'Test-OSDAppOfficeCacheCompatibility.ps1')
$cacheLock = $null
. (Join-Path $PSScriptRoot 'Restore-OSDAppCacheGeneration.ps1')
. (Join-Path $PSScriptRoot 'OSDAppPayloadFile.ps1')
. (Join-Path $PSScriptRoot 'OSDApp7Zip.ps1')
. (Join-Path $PSScriptRoot 'OSDAppVisualStudioCode.ps1')
. (Join-Path $PSScriptRoot 'OSDAppPrerequisite.ps1')
. (Join-Path $PSScriptRoot 'Invoke-OSDAppBuiltInCacheTransaction.ps1')
. (Join-Path $PSScriptRoot 'Assert-OSDAppTransactionSpace.ps1')
Add-Type -AssemblyName System.Net.Http -ErrorAction Stop
$manifestPath = Join-Path $StagedPath 'DeviceManifest.json'
$logPath = [Environment]::ExpandEnvironmentVariables('%ProgramData%\OSDApps\Logs\Runtime.log')
$logDirectory = Split-Path -Path $logPath -Parent
$preInstallStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$preInstallStartedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
$resultPath = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables('%ProgramData%\OSDApps\Results\Latest.json'))
$preInstallResultPath = Join-Path (Split-Path -Path $resultPath -Parent) 'PreInstall.json'
$manifest = $null
$builtInApps = @()
$usbRoot = $null
$networkAvailable = $null
$appResults = [System.Collections.Generic.List[object]]::new()

function Write-PreInstallLog {
    param([string]$Event,[ValidateSet('Info','Warning','Error')][string]$Level='Info',[string]$Message,[hashtable]$Data)
    New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null

    # Runtime.log is shared by PreInstall and the runner. Apply the same
    # 1 MB + 3 archives retention policy in both entry points.
    if (Test-Path -LiteralPath $logPath -PathType Leaf) {
        if ((Get-Item -LiteralPath $logPath).Length -ge 1MB) {
            for ($i = 2; $i -ge 1; $i--) {
                $source = "$logPath.$i"
                $target = "$logPath.$($i + 1)"
                if (Test-Path -LiteralPath $source -PathType Leaf) {
                    Move-Item -LiteralPath $source -Destination $target -Force
                }
            }
            Move-Item -LiteralPath $logPath -Destination "$logPath.1" -Force
            if (Test-Path -LiteralPath "$logPath.4") {
                Remove-Item -LiteralPath "$logPath.4" -Force
            }
        }
    }
    $type = if ($Level -eq 'Warning') { 2 } elseif ($Level -eq 'Error') { 3 } else { 1 }
    $details = @()
    if ($Data) { foreach ($key in @($Data.Keys | Sort-Object)) { $value=$Data[$key]; if ($value -is [System.Collections.IEnumerable] -and $value -isnot [string]) { $value=@($value)-join ',' }; $details += ('{0}={1}' -f $key,$value) } }
    $msg = if ($Message) { "[$Event] $Message" } else { "[$Event]" }
    if ($details.Count -gt 0) { $msg += ' | ' + ($details -join '; ') }
    $msg = $msg -replace '\]LOG\]!>', ']LOG]! >'
    $msg = $msg -replace '[\r\n\x00-\x1F]+', ' '
    $now=(Get-Date).ToUniversalTime(); $time=$now.ToString('HH:mm:ss.fff') + '+000'; $date=$now.ToString('MM-dd-yyyy'); $thread=[System.Threading.Thread]::CurrentThread.ManagedThreadId
    $line='<![LOG[{0}]LOG]!><time="{1}" date="{2}" component="PreInstall" context="" type="{3}" thread="{4}" file="">' -f $msg,$time,$date,$type,$thread
    Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
}

function Stop-PreInstallProcessTree {
    param(
        [Parameter(Mandatory)][System.Diagnostics.Process]$Process,
        [ValidateRange(1,30)][int]$TimeoutSeconds = 5
    )

    try { $Process.Refresh() } catch {}
    if ($Process.HasExited) { return $true }

    # setup.exe can leave Office acquisition child processes behind. Use the
    # Windows process-tree terminator, but bound that helper as well so the
    # PreInstall timeout can never turn into another unbounded wait.
    $taskKillPath = Join-Path $env:SystemRoot 'System32\taskkill.exe'
    if (Test-Path -LiteralPath $taskKillPath -PathType Leaf) {
        try {
            $taskKill = Start-Process -FilePath $taskKillPath -ArgumentList @('/PID', $Process.Id, '/T', '/F') -WindowStyle Hidden -PassThru
            if (-not $taskKill.WaitForExit($TimeoutSeconds * 1000)) {
                try { $taskKill.Kill() } catch {}
            }
        }
        catch {}
    }

    try { $Process.Refresh() } catch {}
    if (-not $Process.HasExited) {
        try { $Process.Kill() } catch {}
    }

    try { [void]$Process.WaitForExit($TimeoutSeconds * 1000) } catch {}
    try { $Process.Refresh() } catch {}
    return [bool]$Process.HasExited
}

function Write-PreInstallResult {
    param(
        [Parameter(Mandatory)][ValidateSet('Succeeded','CompletedWithErrors','Failed')][string]$Status,
        [string]$FailureType,
        [string]$ErrorMessage
    )

    $directory = Split-Path -Path $preInstallResultPath -Parent
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $temporaryPath = "$preInstallResultPath.$([guid]::NewGuid().ToString('N')).tmp"
    $successful = @($appResults | Where-Object { $_.Status -eq 'Succeeded' }).Count
    $failed = @($appResults | Where-Object { $_.Status -eq 'Failed' }).Count
    $record = [ordered]@{
        SchemaVersion           = '1.0'
        DeploymentId           = if ($manifest -and $manifest.DeploymentId) { [string]$manifest.DeploymentId } else { $null }
        Phase                   = 'PreInstall'
        Status                  = $Status
        StartedAtUtc            = $preInstallStartedAtUtc
        CompletedAtUtc          = (Get-Date).ToUniversalTime().ToString('o')
        DurationSeconds         = [math]::Round($preInstallStopwatch.Elapsed.TotalSeconds, 1)
        BuiltInAppCount = @($builtInApps).Count
        SuccessfulBuiltInAppCount = $successful
        FailedBuiltInAppCount = $failed
        CacheUsed               = [bool]$usbRoot
        CachePath               = $usbRoot
        FallbackAppCount = @($appResults | Where-Object { $_.AcquisitionOutcome -eq 'FallbackCacheUsed' }).Count
        OfflineCacheAppCount = @($appResults | Where-Object { $_.AcquisitionOutcome -eq 'OfflineCacheUsed' }).Count
        HasAcquisitionWarnings  = @($appResults | Where-Object { $_.AcquisitionOutcome -in @('FallbackCacheUsed','OfflineCacheUsed') }).Count -gt 0
        NetworkAvailable        = $networkAvailable
        Apps            = @($appResults | ForEach-Object { $_ })
        FailureType             = $FailureType
        Error                   = $ErrorMessage
    }

    try {
        $record | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath $temporaryPath -Encoding UTF8 -ErrorAction Stop
        Move-Item -LiteralPath $temporaryPath -Destination $preInstallResultPath -Force -ErrorAction Stop
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-PreInstallFailureType {
    param([Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$ErrorRecord)

    if ($ErrorRecord.Exception.Data.Contains('OSDAppsCacheLockFailure')) { return 'CacheLockUnavailable' }
    $message = $ErrorRecord.Exception.Message
    if ($ErrorRecord.Exception -is [System.Security.SecurityException]) { return 'TrustValidationFailed' }
    if ($ErrorRecord.Exception -is [System.IO.InvalidDataException]) { return 'ManifestInvalid' }
    if ($message -match 'Insufficient free space') { return 'InsufficientDiskSpace' }
    if ($message -match 'no network|not reachable') { return 'NetworkUnavailable' }
    if ($message -match 'timeout|exceeded') { return 'Timeout' }
    if ($message -match 'no staged|no .*cached|missing') { return 'CacheOrSourceMissing' }
    if ($message -match 'metadata|HTTP|response|download|acquisition') { return 'RemoteAcquisition' }
    'PreInstallError'
}

function Set-PreInstallAcquisitionResult {
    param(
        [Parameter(Mandatory)][hashtable]$Result,
        [Parameter(Mandatory)][ValidateSet('Downloaded','CacheReused','OfflineCacheUsed','FallbackCacheUsed')][string]$Outcome,
        [System.Management.Automation.ErrorRecord]$RefreshError,
        [string]$CacheDecisionReason
    )

    $Result.Outcome = $Outcome
    # Current primary-content acquisition, not a version comparison or an earlier cache sync.
    # Helper-only downloads (for example the Teams bootstrapper) do not set this flag.
    $Result.PackageUpdated = ($Outcome -eq 'Downloaded')
    if ($CacheDecisionReason) { $Result.CacheDecisionReason = $CacheDecisionReason }
    # Offline/fallback outcomes supersede any earlier reason for attempting a refresh.
    if ($Outcome -eq 'OfflineCacheUsed') {
        $Result.CacheDecisionReason = 'No network was available; existing staged content passed the applicable fallback checks. Currency was not checked.'
    }
    elseif ($Outcome -eq 'FallbackCacheUsed') {
        $Result.CacheDecisionReason = 'Refresh failed; existing staged content passed the applicable fallback checks. Currency was not confirmed.'
        if ($RefreshError) { $Result.CacheDecisionReason += ' ' + $RefreshError.Exception.Message }
    }
    if ($RefreshError) {
        $Result.RefreshFailureType = Get-PreInstallFailureType -ErrorRecord $RefreshError
        $Result.RefreshError = $RefreshError.Exception.Message
    }
}

function Get-PreInstallHttpCacheReason {
    param(
        [AllowNull()][AllowEmptyString()][string]$PackagePath,
        $CacheInfo,
        [Parameter(Mandatory)]$Remote,
        [Parameter(Mandatory)][bool]$MetadataMatches
    )
    # Explain the existing HTTP comparison; do not add a freshness or integrity check.
    if ($MetadataMatches) { return 'The existing primary payload matches the vendor HTTP metadata.' }
    if (-not $PackagePath -or -not (Test-Path -LiteralPath $PackagePath -PathType Leaf)) { return 'The primary payload is missing from the selected cache location.' }
    if (-not $CacheInfo) { return 'CacheInfo.json is missing or unreadable; cache currency cannot be established.' }
    if (($Remote.ETag -and $CacheInfo.RemoteETag) -or
        ($Remote.LastModified -and $CacheInfo.RemoteLastModified -and $Remote.ContentLength -and $CacheInfo.RemoteContentLength)) {
        return 'Vendor HTTP metadata differs from the recorded cache metadata; this does not necessarily mean a newer app version.'
    }
    return 'Comparable vendor/cache HTTP metadata is unavailable; cache currency cannot be established.'
}

function Test-InternetEndpoint {
    param([Parameter(Mandatory)][string]$Uri,[int]$TimeoutSec=10)
    try { Invoke-WebRequest -Uri $Uri -Method Head -UseBasicParsing -TimeoutSec $TimeoutSec -ErrorAction Stop | Out-Null; return $true } catch { return $false }
}

function Get-OfficeCacheVersion {
    param([Parameter(Mandatory)][string]$OfficeRoot)
    $dataPath=Join-Path $OfficeRoot 'Office\Data'
    if (-not (Test-Path -LiteralPath $dataPath -PathType Container)) { return $null }
    $versions=@(Get-ChildItem -LiteralPath $dataPath -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } | ForEach-Object { try { [pscustomobject]@{Name=$_.Name;Version=[version]$_.Name} } catch{} } | Sort-Object Version -Descending)
    if ($versions.Count -gt 0) { return $versions[0].Name }
    return $null
}

function Test-OfficeCacheGeneration {
    param(
        [Parameter(Mandatory)][string]$OfficeRoot,
        [Parameter(Mandatory)][string]$ExpectedVersion,
        [ValidateSet('x64','x86')][string]$Architecture='x64'
    )
    $dataPath=Join-Path $OfficeRoot 'Office\Data';$prefix=if($Architecture -eq 'x86'){'v32'}else{'v64'}
    $versions=@(Get-ChildItem -LiteralPath $dataPath -Directory -ErrorAction SilentlyContinue|Where-Object{$_.Name -match '^\d+\.\d+\.\d+\.\d+$'})
    if($versions.Count -ne 1){throw "Expected exactly one Office version directory; found $($versions.Count)."}
    if($versions[0].Name -ne $ExpectedVersion){throw "Office cache version '$($versions[0].Name)' does not match '$ExpectedVersion'."}
    if(@(Get-ChildItem -LiteralPath $versions[0].FullName -File -Recurse -ErrorAction Stop).Count -eq 0){throw 'The active Office version directory contains no files.'}
    $sharedCab=Join-Path $dataPath "$prefix.cab";$versionCab=Join-Path $dataPath ("{0}_{1}.cab" -f $prefix,$ExpectedVersion)
    if(-not(Test-Path -LiteralPath $sharedCab -PathType Leaf)){throw "$prefix.cab is missing."}
    if(-not(Test-Path -LiteralPath $versionCab -PathType Leaf)){throw "The version-specific $prefix CAB is missing."}
    $sharedHash=(Get-FileHash -LiteralPath $sharedCab -Algorithm SHA256).Hash;$versionHash=(Get-FileHash -LiteralPath $versionCab -Algorithm SHA256).Hash
    if($sharedHash -ne $versionHash){throw "$prefix.cab does not match the active version-specific CAB."}
    $true
}

function Set-OfficeDownloadSourcePath {
    param([Parameter(Mandatory)][string]$SourcePath,[Parameter(Mandatory)][string]$DestinationPath)
    [xml]$xml=Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8
    $add=$xml.Configuration.Add
    if(-not $add){throw 'Office configuration does not contain an Add element.'}
    $add.SetAttribute('SourcePath',(Split-Path -Path $DestinationPath -Parent))
    $settings=[System.Xml.XmlWriterSettings]::new();$settings.Indent=$true;$settings.Encoding=[System.Text.UTF8Encoding]::new($false)
    $writer=[System.Xml.XmlWriter]::Create($DestinationPath,$settings);try{$xml.Save($writer)}finally{$writer.Dispose()}
}

function Get-MicrosoftTeamsPackageVersion {
    param([Parameter(Mandatory)][string]$Path)
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    $archive=[System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $entry=$archive.Entries | Where-Object { $_.FullName -eq 'AppxManifest.xml' } | Select-Object -First 1
        if (-not $entry) { throw 'AppxManifest.xml was not found in the Teams MSIX.' }
        $reader=New-Object System.IO.StreamReader($entry.Open())
        try { [xml]$m=$reader.ReadToEnd() } finally { $reader.Dispose() }
        return [string]$m.Package.Identity.Version
    } finally { $archive.Dispose() }
}

function Get-RemoteMetadata {
    param([Parameter(Mandatory)][string]$Uri,[int]$TimeoutSec=15)
    $handler=[System.Net.Http.HttpClientHandler]::new(); $handler.AllowAutoRedirect=$true
    $client=[System.Net.Http.HttpClient]::new($handler); $client.Timeout=[TimeSpan]::FromSeconds($TimeoutSec)
    try {
        $request=[System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Head,$Uri)
        $response=$client.SendAsync($request).GetAwaiter().GetResult()
        try {
            $response.EnsureSuccessStatusCode() | Out-Null
            [pscustomobject]@{
                ETag=if($response.Headers.ETag){[string]$response.Headers.ETag.Tag}else{$null}
                LastModified=if($response.Content.Headers.LastModified){$response.Content.Headers.LastModified.UtcDateTime.ToString('o')}else{$null}
                ContentLength=if($response.Content.Headers.ContentLength){[int64]$response.Content.Headers.ContentLength}else{$null}
                FinalUri=[string]$response.RequestMessage.RequestUri.AbsoluteUri
            }
        } finally { $response.Dispose(); $request.Dispose() }
    } finally { $client.Dispose(); $handler.Dispose() }
}

function Save-PreInstallDownload {
    [CmdletBinding(DefaultParameterSetName='Exact')]
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory,ParameterSetName='Exact')][string]$DestinationPath,
        [Parameter(Mandatory,ParameterSetName='Vendor')][string]$DestinationDirectory,
        [Parameter(Mandatory,ParameterSetName='Vendor')][string]$ExpectedExtension,
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Description,
        [int]$TimeoutMinutes = 30
    )
    $directory = if ($PSCmdlet.ParameterSetName -eq 'Vendor') { $DestinationDirectory } else { Split-Path -Path $DestinationPath -Parent }
    $extension = if ($PSCmdlet.ParameterSetName -eq 'Vendor') { $ExpectedExtension } else { [IO.Path]::GetExtension($DestinationPath) }
    New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop | Out-Null
    $tempPath = Join-Path $directory ('.osdapps-download-' + [guid]::NewGuid().ToString('N'))
    $handler = [Net.Http.HttpClientHandler]::new(); $handler.AllowAutoRedirect = $true
    $client = [Net.Http.HttpClient]::new($handler); $client.Timeout = [TimeSpan]::FromMinutes($TimeoutMinutes)
    $response = $null; $source = $null; $target = $null
    $watch = [Diagnostics.Stopwatch]::StartNew()
    Write-PreInstallLog -Event 'DownloadStart' -Message "Downloading $Description." -Data @{Id=$Id;Uri=$Uri;Destination=$directory}
    try {
        $response = $client.GetAsync($Uri,[Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        $response.EnsureSuccessStatusCode() | Out-Null
        $name = Get-OSDAppDownloadFileName -Response $response -ExpectedExtension $extension
        if ($PSCmdlet.ParameterSetName -eq 'Exact' -and $name -cne (Split-Path -Path $DestinationPath -Leaf)) {
            throw [IO.InvalidDataException]::new('Vendor response filename differs from the requested exact filename.')
        }
        $DestinationPath = Join-Path $directory $name
        $source = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $target = [IO.FileStream]::new($tempPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $buffer = New-Object byte[] (1024 * 1024)
        [long]$downloaded = 0
        while (($read=$source.Read($buffer,0,$buffer.Length)) -gt 0) { $target.Write($buffer,0,$read); $downloaded += $read }
        $target.Dispose(); $target = $null
        $expectedBytes = $response.Content.Headers.ContentLength
        if ($downloaded -le 0 -or ($null -ne $expectedBytes -and $downloaded -ne $expectedBytes)) {
            throw [IO.InvalidDataException]::new('Downloaded payload is empty or differs from Content-Length.')
        }
        Move-Item -LiteralPath $tempPath -Destination $DestinationPath -Force -ErrorAction Stop
        $watch.Stop()
        Write-PreInstallLog -Event 'DownloadComplete' -Message "$Description download completed." -Data @{
            Id=$Id;Bytes=$downloaded;SizeMB=[math]::Round($downloaded/1MB,1)
            DurationSeconds=[math]::Round($watch.Elapsed.TotalSeconds,1)
            AverageMBps=[math]::Round(($downloaded/1MB)/[math]::Max(0.001,$watch.Elapsed.TotalSeconds),1)
            Destination=$DestinationPath;PayloadFileName=$name
        }
        Get-Item -LiteralPath $DestinationPath -ErrorAction Stop
    }
    finally {
        if ($target) { $target.Dispose() }; if ($source) { $source.Dispose() }; if ($response) { $response.Dispose() }
        $client.Dispose(); $handler.Dispose(); $watch.Stop()
        if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue }
    }
}

function Copy-DirectoryReplace {
    param([Parameter(Mandatory)][string]$Source,[Parameter(Mandatory)][string]$Destination)
    New-Item -ItemType Directory -Path (Split-Path $Destination -Parent) -Force | Out-Null
    $temp="$Destination.refresh"
    if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force}
    Copy-Item -LiteralPath $Source -Destination $temp -Recurse -Force
    if(Test-Path -LiteralPath $Destination){Remove-Item -LiteralPath $Destination -Recurse -Force}
    Move-Item -LiteralPath $temp -Destination $Destination -Force
}

# Avoid PowerShell's self-copy error when the OSDCloud USB cache is absent.
# In that case the acquisition directory is already the local staged directory.
function Copy-OfficeConfigurationToCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LocalConfig,
        [Parameter(Mandatory)][string]$AcquireConfig
    )

    $sourcePath = [System.IO.Path]::GetFullPath($LocalConfig)
    $destinationPath = [System.IO.Path]::GetFullPath($AcquireConfig)
    if ([string]::Equals($sourcePath, $destinationPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        return
    }

    Copy-Item -LiteralPath $LocalConfig -Destination $AcquireConfig -Force -ErrorAction Stop
}

function Test-LocalOfficeSource {
    param([string]$Root, [Parameter(Mandatory)][string]$ConfigurationPath, [hashtable]$Decision)
    try{
        $cacheInfoPath=Join-Path $Root 'CacheInfo.json'
        if(-not(Test-Path -LiteralPath $cacheInfoPath -PathType Leaf)){
            if ($null -ne $Decision) { $Decision.CacheDecisionReason = 'The checked Office location has no recorded generation; CacheInfo.json is missing.' }
            return $false
        }
        $cacheInfo=Get-Content -LiteralPath $cacheInfoPath -Raw -Encoding UTF8|ConvertFrom-Json
        Test-OfficeCacheGeneration -OfficeRoot $Root -ExpectedVersion ([string]$cacheInfo.Version) -Architecture $(if([string]$cacheInfo.Architecture -eq 'x86'){'x86'}else{'x64'})|Out-Null
        $compatibility = Test-OSDAppOfficeCacheCompatibility -OfficeRoot $Root -ConfigurationPath $ConfigurationPath
        if ($null -ne $Decision) {
            $Decision.CacheDecisionReason = if ($compatibility.Compatible) {
                'The Office generation and requested configuration passed validation.'
            } else {
                'The Office cache is incompatible with the requested configuration. ' + ($compatibility.Reasons -join ' ')
            }
        }
        if (-not $compatibility.Compatible) {
            Write-PreInstallLog -Event 'OfficeCacheIncompatible' -Level Warning -Message 'Office fallback does not match the requested configuration.' -Data @{ Id='Microsoft365Apps'; Reasons=($compatibility.Reasons -join ' ') }
        }
        return $compatibility.Compatible
    }catch{
        if ($null -ne $Decision) { $Decision.CacheDecisionReason = 'Office generation validation failed. ' + $_.Exception.Message }
        return $false
    }
}

function Copy-OfficeCachePayload {
    param([string]$SourceRoot, [string]$DestinationRoot, [string]$ConfigurationPath)
    $compatibility = Test-OSDAppOfficeCacheCompatibility -OfficeRoot $SourceRoot -ConfigurationPath $ConfigurationPath
    if (-not $compatibility.Compatible) { throw ('Office cache cannot satisfy this deployment. ' + ($compatibility.Reasons -join ' ')) }
    # Never copy the cache XML over the selected deployment configuration.
    Copy-Item -LiteralPath (Join-Path $SourceRoot 'setup.exe') -Destination (Join-Path $DestinationRoot 'setup.exe') -Force
    Copy-DirectoryReplace -Source (Join-Path $SourceRoot 'Office') -Destination (Join-Path $DestinationRoot 'Office')
    $info = Get-Content -LiteralPath (Join-Path $SourceRoot 'CacheInfo.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $info | Add-Member -NotePropertyName PayloadProfile -NotePropertyValue $compatibility.CachedProfile -Force
    $info | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $DestinationRoot 'CacheInfo.json') -Encoding UTF8
}

function Test-LocalMicrosoftTeamsSource {
    param([string]$Root)
    return ((Test-Path -LiteralPath (Join-Path $Root 'teamsbootstrapper.exe') -PathType Leaf) -and (Test-OSDAppBuiltInPayload -Root $Root -ExpectedExtension '.msix'))
}

function Test-LocalAdobeAcrobatUnifiedSource {
    param([string]$Root)
    return (Test-OSDAppBuiltInPayload -Root $Root -ExpectedExtension '.zip')
}

function Test-LocalMsiSource {
    param([string]$Root)
    return (Test-OSDAppBuiltInPayload -Root $Root -ExpectedExtension '.msi')
}

function Restore-PreInstallBuiltInCache {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Id)
    $recovery = Restore-OSDAppCacheGeneration -Root $Root -Validate {
        param($candidate)
        Assert-OSDAppRecoverableBuiltInGeneration -Root $candidate -Id $Id -SignatureValidator {
            param($appId, $file)
            Assert-PreInstallSignedPayload -Id $appId -Path $file
        } -OfficeValidator {
            param($officeRoot, $version, $architecture)
            Test-OfficeCacheGeneration -OfficeRoot $officeRoot -ExpectedVersion $version -Architecture $architecture | Out-Null
        } -TeamsVersionReader {
            param($file)
            Get-MicrosoftTeamsPackageVersion -Path $file
        }
    }
    if ($recovery) {
        Write-PreInstallLog -Event 'CacheGenerationRecovered' -Message 'Validated previous USB cache generation restored after an interrupted directory swap.' -Data @{Id=$Id;Path=$Root;PreviousPath=$recovery.PreviousPath}
    }
}

function Remove-PreInstallTransactionResidue {
    param([Parameter(Mandatory)][string]$Root)
    $parent=Split-Path -Path $Root -Parent;$leaf=Split-Path -Path $Root -Leaf
    Get-ChildItem -LiteralPath $parent -Directory -ErrorAction SilentlyContinue|
        Where-Object{$_.Name -like "$leaf.osdapps-new-*" -or $_.Name -like "$leaf.osdapps-old-*"}|
        ForEach-Object{Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue}
}

function Assert-PreInstallSignedPayload {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Path
    )

    # SetupComplete runs standalone: the private OSDApps module functions
    # are not guaranteed to be installed on the target Windows machine.
    $expected = switch ($Id) {
        'Microsoft365Apps'         { 'Microsoft Corporation'; break }
        'MicrosoftTeams'           { 'Microsoft Corporation'; break }
        'GoogleChromeEnterprise'   { 'Google LLC'; break }
        'CiscoWebex'               { 'Cisco Systems, Inc.'; break }
        'ZoomWorkplace'            { 'Zoom Communications, Inc.'; break }
        'MozillaFirefoxEnterprise' { 'Mozilla Corporation'; break }
        default                    { $null }
    }
    if (-not $expected) {
        throw [System.Security.SecurityException]::new("No trusted signer policy exists for built-in '$Id'.")
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required signed built-in file missing: $Path"
    }

    $signature = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop
    if ([string]$signature.Status -ne 'Valid' -or -not $signature.SignerCertificate) {
        throw [System.Security.SecurityException]::new("Built-in '$Id' signature validation failed (status: $($signature.Status)): $Path")
    }

    $subject = [string]$signature.SignerCertificate.Subject
    $orgMatch = [regex]::Match($subject, '(?:^|,\s*)O=(?:"(?<quoted>(?:[^"]|"")*)"|(?<plain>[^,]+))(?=,|$)')
    $org = if ($orgMatch.Success) {
        if ($orgMatch.Groups['quoted'].Success) {
            $orgMatch.Groups['quoted'].Value.Replace('""','"')
        } else {
            $orgMatch.Groups['plain'].Value.Trim()
        }
    } else { $null }
    if (-not [string]::Equals($org,$expected,[StringComparison]::OrdinalIgnoreCase)) {
        throw [System.Security.SecurityException]::new("Built-in '$Id' publisher mismatch. Expected '$expected'; signer subject: $subject")
    }
    Write-PreInstallLog -Event 'BuiltInSignatureVerified' -Message 'Built-in MSI/EXE Authenticode and expected publisher validated.' -Data @{Id=$Id;File=$Path;Publisher=$expected}
}

function Sync-PreInstallVendorMsi {
    param(
        [Parameter(Mandatory)][psobject]$App,
        [Parameter(Mandatory)][string]$RelativeRoot,
        [Parameter(Mandatory)][string]$PackageUri,
        [Parameter(Mandatory)][string]$DisplayName,
        [Parameter(Mandatory)][hashtable]$Acquisition,
        [ValidateSet('.msi','.zip')][string]$ExpectedExtension = '.msi'
    )
    $id = [string]$App.Id
    $localRoot = Join-Path $StagedPath $RelativeRoot
    $acquireRoot = if ($usbRoot) { Join-Path $usbRoot $RelativeRoot } else { $localRoot }
    New-Item -ItemType Directory -Path $localRoot -Force | Out-Null
    if ($usbRoot) { Restore-PreInstallBuiltInCache -Root $acquireRoot -Id $id }
    New-Item -ItemType Directory -Path $acquireRoot -Force | Out-Null

    function Assert-SelectedPayload {
        param([string]$Root)
        $path = Assert-OSDAppCachedPayload -Root $Root -ExpectedExtension $ExpectedExtension -Id $id -Architecture ([string]$App.Architecture)
        if ($ExpectedExtension -eq '.msi') { Assert-PreInstallSignedPayload -Id $id -Path $path }
        else {
            Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
            $zip = [IO.Compression.ZipFile]::OpenRead($path)
            try { if ($zip.Entries.Count -eq 0) { throw [IO.InvalidDataException]::new('Vendor ZIP is empty.') } }
            finally { $zip.Dispose() }
        }
        $path
    }
    if ($usbRoot -and -not (Test-OSDAppBuiltInPayload -Root $localRoot -ExpectedExtension $ExpectedExtension) -and
        (Test-OSDAppBuiltInPayload -Root $acquireRoot -ExpectedExtension $ExpectedExtension)) {
        $path = Assert-SelectedPayload -Root $acquireRoot
        Copy-OSDAppBuiltInPayload -Path $path -DestinationDirectory $localRoot
        Copy-Item -LiteralPath (Join-Path $acquireRoot 'CacheInfo.json') -Destination (Join-Path $localRoot 'CacheInfo.json') -Force -ErrorAction Stop
        Write-PreInstallLog -Event 'BuiltInCacheRestaged' -Message "$DisplayName USB payload staged locally." -Data @{Id=$id;PayloadFileName=(Split-Path $path -Leaf)}
    }
    if (-not $networkAvailable) {
        if (-not (Test-OSDAppBuiltInPayload -Root $localRoot -ExpectedExtension $ExpectedExtension)) {
            $Acquisition.CacheDecisionReason = 'The cached payload is missing or its metadata is unsupported; a new download is required.'
            throw "$DisplayName requires a download, but no network and no supported staged cache are available."
        }
        Assert-SelectedPayload -Root $localRoot | Out-Null
        Set-PreInstallAcquisitionResult -Result $Acquisition -Outcome OfflineCacheUsed
        Write-PreInstallLog -Event 'BuiltInRefreshSkipped' -Level Warning -Message "No network; validated $DisplayName payload will be used." -Data @{Id=$id}
        return
    }
    try {
        $previous = $null; $path = $null
        $refreshRequired = $false
        if (Test-OSDAppBuiltInPayload -Root $acquireRoot -ExpectedExtension $ExpectedExtension) {
            $path = Assert-SelectedPayload -Root $acquireRoot
            $previous = Get-Content -LiteralPath (Join-Path $acquireRoot 'CacheInfo.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        }
        elseif (Test-Path -LiteralPath (Join-Path $acquireRoot 'CacheInfo.json')) {
            $refreshRequired = $true
            $Acquisition.CacheDecisionReason = 'The primary payload is missing, or the cache has unsupported metadata; a new validated generation is required.'
            Write-PreInstallLog -Event 'BuiltInCacheRefreshRequired' -Level Warning -Message $Acquisition.CacheDecisionReason -Data @{Id=$id;Path=$acquireRoot}
        }
        $remote = Get-RemoteMetadata -Uri $PackageUri
        $matches = $false
        if ($path -and $previous -and [string]$previous.PackageUri -ceq $PackageUri) {
            if ($remote.ETag -and $previous.RemoteETag) { $matches = $remote.ETag -eq [string]$previous.RemoteETag }
            elseif ($remote.LastModified -and $previous.RemoteLastModified -and $remote.ContentLength -and $previous.RemoteContentLength) {
                $matches = ($remote.LastModified -eq [string]$previous.RemoteLastModified -and [long]$remote.ContentLength -eq [long]$previous.RemoteContentLength)
            }
        }
        $Acquisition.CacheDecisionReason = Get-PreInstallHttpCacheReason -PackagePath $path -CacheInfo $previous -Remote $remote -MetadataMatches $matches
        if ($refreshRequired) { $Acquisition.CacheDecisionReason = 'The primary payload is missing, or the cache has unsupported metadata; a new validated generation is required.' }
        if (-not $matches) {
            Invoke-OSDAppBuiltInCacheTransaction -Root $acquireRoot -ExpectedBytes ([double]$remote.ContentLength) -MinimumFreeSpaceGB $(if($ExpectedExtension -eq '.zip'){3}else{1}) -Build {
                param($candidate)
                $download = Save-PreInstallDownload -Uri $PackageUri -DestinationDirectory $candidate -ExpectedExtension $ExpectedExtension -Id $id -Description $DisplayName -TimeoutMinutes 30
                if (-not $download -or -not $download.FullName) { throw 'Download must return its actual vendor payload path.' }
                $payload = [string]$download.FullName
                if ($ExpectedExtension -eq '.msi') { Assert-PreInstallSignedPayload -Id $id -Path $payload }
                $record = [ordered]@{
                    Id=$id;Cached=[bool]$usbRoot;Version='Current';Architecture=$App.Architecture
                    PayloadFileName=(Split-Path -Path $payload -Leaf)
                    Sha256=(Get-FileHash -LiteralPath $payload -Algorithm SHA256).Hash;Size=(Get-Item -LiteralPath $payload).Length
                    SourcePolicy='Evergreen';SyncMethod='HttpMetadata';Updated=$true;PackageUri=$PackageUri
                    RemoteETag=$remote.ETag;RemoteLastModified=$remote.LastModified;RemoteContentLength=$remote.ContentLength
                    RemoteFinalUri=$remote.FinalUri;SyncedAt=(Get-Date).ToUniversalTime().ToString('o')
                }
                if ($App.PSObject.Properties['Channel']) { $record.Channel = [string]$App.Channel }
                if ($App.PSObject.Properties['Language']) { $record.Language = [string]$App.Language }
                $record | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $candidate 'CacheInfo.json') -Encoding UTF8 -ErrorAction Stop
            } -Validate { param($candidate) Assert-SelectedPayload -Root $candidate | Out-Null } | Out-Null
        }
        $path = Assert-SelectedPayload -Root $acquireRoot
        if ($usbRoot) {
            Copy-OSDAppBuiltInPayload -Path $path -DestinationDirectory $localRoot
            Copy-Item -LiteralPath (Join-Path $acquireRoot 'CacheInfo.json') -Destination (Join-Path $localRoot 'CacheInfo.json') -Force -ErrorAction Stop
        }
        Set-PreInstallAcquisitionResult -Result $Acquisition -Outcome $(if($matches){'CacheReused'}else{'Downloaded'})
        Write-PreInstallLog -Event 'BuiltInRefreshComplete' -Message "$DisplayName is ready for installation." -Data @{Id=$id;PayloadFileName=(Split-Path $path -Leaf);PackageUpdated=(-not $matches);CacheSynchronized=[bool]$usbRoot}
    }
    catch {
        if ($_.Exception -is [Security.SecurityException] -or $_.Exception -is [IO.InvalidDataException]) { throw }
        $refreshError = $_
        if (Test-OSDAppBuiltInPayload -Root $localRoot -ExpectedExtension $ExpectedExtension) {
            Assert-SelectedPayload -Root $localRoot | Out-Null
            Set-PreInstallAcquisitionResult -Result $Acquisition -Outcome FallbackCacheUsed -RefreshError $refreshError
            Write-PreInstallLog -Event 'BuiltInRefreshFailed' -Level Warning -Message $refreshError.Exception.Message -Data @{Id=$id;Fallback='ExistingStagedPayload'}
            return
        }
        throw "$DisplayName acquisition failed and no staged fallback is available. $($refreshError.Exception.Message)"
    }
}


try {
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Device manifest not found: $manifestPath" }
    . (Join-Path $PSScriptRoot 'OSDAppSleepPrevention.ps1')
    $manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $manifest.Runtime) { throw 'Device manifest Runtime configuration is missing.' }
    if ($manifest.Runtime.ResultPath) {
        $resultPath = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables([string]$manifest.Runtime.ResultPath))
        $preInstallResultPath = Join-Path (Split-Path -Path $resultPath -Parent) 'PreInstall.json'
    }
    if (-not $manifest.Runtime.CacheVolumeLabel) { throw 'Device manifest Runtime.CacheVolumeLabel is missing.' }
    if (-not $manifest.Runtime.LogPath) { throw 'Device manifest Runtime.LogPath is missing.' }

    $cacheVolumeLabel = [string]$manifest.Runtime.CacheVolumeLabel
    $logPath = [Environment]::ExpandEnvironmentVariables([string]$manifest.Runtime.LogPath)
    $logDirectory = Split-Path -Path $logPath -Parent

    $preventSleep = Get-OSDAppPreventSleep -Runtime $manifest.Runtime
    $sleepLog = {
        param($EventName, $Level, $Message)
        Write-PreInstallLog -Event $EventName -Level $Level -Message $Message
    }
    $sleepRequest = Start-OSDAppSleepPrevention -Enabled $preventSleep -Reason 'OSDApps PreInstall is acquiring app content.' -Log $sleepLog

    $apps=if($manifest.PSObject.Properties.Name -contains 'Apps'){@($manifest.Apps)}else{@()}
    $builtInApps=@($apps | Where-Object { [string]$_.Source -eq 'BuiltIn' -and [string]$_.Type -notin @('WindowsInboxCleanupScript','WindowsFeatureScript','WindowsCapabilityScript','DefaultAssociationScript','EnvironmentVariableScript','ServiceScript','DesktopSettingsScript','WiFiProfileScript','CertificateScript','CompanyPortalAppxBundle') -and [string]$_.Id -ne 'CMTraceOpen' })
    if($builtInApps.Count -eq 0){
        $preInstallStopwatch.Stop()
        Write-PreInstallLog -Event 'RefreshSkipped' -Message 'No built-in apps require acquisition. Nothing to refresh.'
        try { Write-PreInstallResult -Status Succeeded } catch { Write-PreInstallLog -Event 'ResultWriteFailed' -Level Warning -Message $_.Exception.Message }
        exit 0
    }

    $cacheVolume=Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.FileSystemLabel -eq $cacheVolumeLabel -and $_.DriveLetter } | Select-Object -First 1
    $usbRoot=if($cacheVolume){"$($cacheVolume.DriveLetter):\OSDApps"}else{$null}
    $lockRoot = if ($usbRoot) { $usbRoot } else { $StagedPath }
    $cacheLock = Enter-OSDAppCacheLock -CachePath $lockRoot -Operation 'PreInstall cache acquisition and recovery'
    Write-PreInstallLog -Event 'RefreshStart' -Message 'Starting built-in acquisition and refresh before installation.' -Data @{StagedPath=$StagedPath;BuiltInApps=@($builtInApps.Id);CacheAvailable=[bool]$usbRoot;CacheRoot=$usbRoot}
    if($usbRoot){New-Item -ItemType Directory -Path $usbRoot -Force | Out-Null; Write-PreInstallLog -Event 'CacheVolumeFound' -Message 'OSDCloud USB cache is available and will be used automatically.' -Data @{CacheRoot=$usbRoot}}
    else{Write-PreInstallLog -Event 'CacheVolumeNotFound' -Message 'No OSDCloud USB cache is connected. Built-ins will be acquired directly to the local Windows runtime.'}

    $networkAvailable=[System.Net.NetworkInformation.NetworkInterface]::GetIsNetworkAvailable()

    foreach($app in $builtInApps){
        $builtInStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $appError = $null
        $appFailureType = $null
        $acquisition = @{ Outcome = 'Failed'; PackageUpdated = $null; CacheDecisionReason = $null; RefreshFailureType = $null; RefreshError = $null }
        try {
            switch($app.Id){
            'Microsoft365Apps' {
                $localRoot=Join-Path $StagedPath 'BuiltIn\Microsoft365Apps'
                New-Item -ItemType Directory -Path $localRoot -Force | Out-Null
                $acquireRoot=if($usbRoot){Join-Path $usbRoot 'BuiltIn\Microsoft365Apps'}else{$localRoot}
                if($usbRoot){Restore-PreInstallBuiltInCache -Root $acquireRoot -Id 'Microsoft365Apps'}
                New-Item -ItemType Directory -Path $acquireRoot -Force | Out-Null
                $localConfig=Join-Path $localRoot 'configuration.xml'
                if(-not (Test-Path -LiteralPath $localConfig -PathType Leaf)){throw 'Microsoft 365 Apps configuration.xml is missing from the staged deployment intent.'}

                $payloadProfile = Get-OSDAppOfficePayloadProfile -Path $localConfig
                $officeArchitecture = if ($payloadProfile.Architecture) { $payloadProfile.Architecture } else { [string]$app.Architecture }

                $officeUsbDecision = @{ CacheDecisionReason = $null }
                if($usbRoot -and -not (Test-LocalOfficeSource -Root $localRoot -ConfigurationPath $localConfig) -and (Test-LocalOfficeSource -Root $acquireRoot -ConfigurationPath $localConfig -Decision $officeUsbDecision)){
                    Copy-OfficeCachePayload -SourceRoot $acquireRoot -DestinationRoot $localRoot -ConfigurationPath $localConfig
                    Write-PreInstallLog -Event 'BuiltInCacheRestaged' -Message 'Existing Microsoft 365 Apps USB cache was staged locally.' -Data @{Id='Microsoft365Apps'}
                }

                if(-not $networkAvailable){
                    if(Test-LocalOfficeSource -Root $localRoot -ConfigurationPath $localConfig){Assert-PreInstallSignedPayload -Id 'Microsoft365Apps' -Path (Join-Path $localRoot 'setup.exe');Set-PreInstallAcquisitionResult -Result $acquisition -Outcome OfflineCacheUsed;Write-PreInstallLog -Event 'BuiltInRefreshSkipped' -Level 'Warning' -Message 'No network is available. Existing staged Office payload will be used.' -Data @{Id='Microsoft365Apps'}; continue}
                    throw 'Microsoft 365 Apps has no compatible staged or USB-cached payload for the requested configuration and no network connection is available to acquire one.'
                }

                $transactionRoot=$null;$backupRoot=$null
                try {
                    # Keep the existing generation read-only. Only a compatible,
                    # consistent and current source can bypass ODT acquisition.
                    $officeSourceCompatible = Test-LocalOfficeSource -Root $localRoot -ConfigurationPath $localConfig -Decision $acquisition
                    if ($officeSourceCompatible -and
                        (Test-OSDAppOfficeCacheCurrent -OfficeRoot $localRoot -ConfigurationPath $localConfig -Decision $acquisition)) {
                        Assert-PreInstallSignedPayload -Id 'Microsoft365Apps' -Path (Join-Path $localRoot 'setup.exe')
                        Set-PreInstallAcquisitionResult -Result $acquisition -Outcome CacheReused
                        Write-PreInstallLog -Event 'BuiltInCacheReused' -Message 'Compatible Microsoft 365 Apps cache matches the requested build or current CDN build; ODT acquisition was skipped.' -Data @{Id='Microsoft365Apps';Version=(Get-OfficeCacheVersion -OfficeRoot $localRoot)}
                        continue
                    }
                    if (-not $officeSourceCompatible -and $officeUsbDecision.CacheDecisionReason) {
                        $acquisition.CacheDecisionReason += ' USB cache assessment: ' + $officeUsbDecision.CacheDecisionReason
                    }
                    Assert-OSDAppTransactionSpace -Path $acquireRoot -ExistingPath $acquireRoot -MinimumFreeSpaceGB 8 -Operation 'Microsoft 365 Apps cache refresh' | Out-Null
                    $transactionRoot="$acquireRoot.osdapps-new-$([guid]::NewGuid().ToString('N'))"
                    $backupRoot="$acquireRoot.osdapps-old-$([guid]::NewGuid().ToString('N'))"
                    New-Item -ItemType Directory -Path $transactionRoot -Force | Out-Null
                    $acquireConfig=Join-Path $transactionRoot 'configuration.xml'
                    Copy-Item -LiteralPath $localConfig -Destination $acquireConfig -Force
                    $downloadConfig=Join-Path $transactionRoot 'download-configuration.xml'
                    Set-OfficeDownloadSourcePath -SourcePath $localConfig -DestinationPath $downloadConfig
                    $setupPath=Join-Path $transactionRoot 'setup.exe'
                    $odtUri=if($app.OfficeDeploymentToolUri){[string]$app.OfficeDeploymentToolUri}else{'https://officecdn.microsoft.com/pr/wsus/setup.exe'}
                    Save-PreInstallDownload -Uri $odtUri -DestinationPath $setupPath -Id 'Microsoft365Apps' -Description 'Office Deployment Tool' -TimeoutMinutes 5 | Out-Null
                    Assert-PreInstallSignedPayload -Id 'Microsoft365Apps' -Path $setupPath
                    if(-not (Test-InternetEndpoint -Uri $odtUri)){throw 'Microsoft 365 Apps CDN is not reachable.'}
                    $previous=Get-OfficeCacheVersion -OfficeRoot $acquireRoot
                    Write-PreInstallLog -Event 'BuiltInRefreshStart' -Message 'Synchronizing Microsoft 365 Apps content.' -Data @{Id='Microsoft365Apps';Target=if($usbRoot){'USB'}else{'Local'};PreviousVersion=$previous;TimeoutMinutes=$OfficeRefreshTimeoutMinutes}
                    $process=Start-Process -FilePath $setupPath -ArgumentList @('/download',$downloadConfig) -WorkingDirectory $transactionRoot -PassThru
                    $sw=[System.Diagnostics.Stopwatch]::StartNew()
                    while(-not $process.HasExited){if($sw.Elapsed.TotalMinutes -ge $OfficeRefreshTimeoutMinutes){$terminated=Stop-PreInstallProcessTree -Process $process -TimeoutSeconds 5;throw "Office Deployment Tool cache refresh exceeded the $OfficeRefreshTimeoutMinutes minute timeout. ProcessTreeTerminated=$terminated"};Start-Sleep -Seconds 2;$process.Refresh()}
                    $sw.Stop()
                    if($process.ExitCode -ne 0){throw "Office Deployment Tool exited with code $($process.ExitCode)."}
                    $version=Get-OfficeCacheVersion -OfficeRoot $transactionRoot
                    if(-not $version){throw 'Office acquisition completed but Office\Data does not contain a resolvable version.'}
                    if ($payloadProfile.Version -match '^\d+\.\d+\.\d+\.\d+$' -and $version -ne $payloadProfile.Version) { throw 'Downloaded Office version does not match the requested version.' }
                    Test-OfficeCacheGeneration -OfficeRoot $transactionRoot -ExpectedVersion $version -Architecture $officeArchitecture | Out-Null
                    $cacheInfo=[ordered]@{Id='Microsoft365Apps';Cached=[bool]$usbRoot;Version=$version;Architecture=$officeArchitecture;Channel=$payloadProfile.Channel;ProductId=@($payloadProfile.Products)[0];Language=@($payloadProfile.Languages | Select-Object -Unique);PayloadProfile=$payloadProfile;SourcePolicy='Evergreen';SyncMethod='OfficeDeploymentTool';Updated=($previous -ne $version);SyncedAt=(Get-Date).ToUniversalTime().ToString('o')}
                    $cacheInfoPath=Join-Path $transactionRoot 'CacheInfo.json';$cacheInfo|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $cacheInfoPath -Encoding UTF8
                    Remove-Item -LiteralPath $downloadConfig -Force
                    $hadPrevious=Test-Path -LiteralPath $acquireRoot -PathType Container
                    if($hadPrevious){Move-Item -LiteralPath $acquireRoot -Destination $backupRoot -ErrorAction Stop}
                    try{Move-Item -LiteralPath $transactionRoot -Destination $acquireRoot -ErrorAction Stop}
                    catch{if($hadPrevious -and (Test-Path -LiteralPath $backupRoot -PathType Container) -and -not(Test-Path -LiteralPath $acquireRoot)){Move-Item -LiteralPath $backupRoot -Destination $acquireRoot -ErrorAction SilentlyContinue};throw}
                    if(Test-Path -LiteralPath $backupRoot -PathType Container){Remove-Item -LiteralPath $backupRoot -Recurse -Force}
                    Remove-PreInstallTransactionResidue -Root $acquireRoot
                    $setupPath=Join-Path $acquireRoot 'setup.exe';$acquireConfig=Join-Path $acquireRoot 'configuration.xml';$cacheInfoPath=Join-Path $acquireRoot 'CacheInfo.json';$removedVersions=@()
                    if($usbRoot){
                        Copy-Item -LiteralPath $setupPath -Destination (Join-Path $localRoot 'setup.exe') -Force
                        Copy-Item -LiteralPath $acquireConfig -Destination $localConfig -Force
                        Copy-Item -LiteralPath $cacheInfoPath -Destination (Join-Path $localRoot 'CacheInfo.json') -Force
                        Copy-DirectoryReplace -Source (Join-Path $acquireRoot 'Office') -Destination (Join-Path $localRoot 'Office')
                    }
                    $versionChanged = ($previous -ne $version)
                    Set-PreInstallAcquisitionResult -Result $acquisition -Outcome Downloaded
                    Write-PreInstallLog -Event 'BuiltInRefreshComplete' -Message 'Microsoft 365 Apps content is ready for installation.' -Data @{Id='Microsoft365Apps';Version=$version;CacheSynchronized=[bool]$usbRoot;VersionChanged=$versionChanged;RemovedVersions=$removedVersions;SourcePolicy='Evergreen';SyncMethod='OfficeDeploymentTool';DurationSeconds=[math]::Round($builtInStopwatch.Elapsed.TotalSeconds,1)}
                } catch {
                    if($transactionRoot -and (Test-Path -LiteralPath $transactionRoot)){Remove-Item -LiteralPath $transactionRoot -Recurse -Force -ErrorAction SilentlyContinue}
                    if($backupRoot -and (Test-Path -LiteralPath $backupRoot -PathType Container) -and -not(Test-Path -LiteralPath $acquireRoot)){Move-Item -LiteralPath $backupRoot -Destination $acquireRoot -ErrorAction SilentlyContinue}
                    if(Test-LocalOfficeSource -Root $localRoot -ConfigurationPath $localConfig){Assert-PreInstallSignedPayload -Id 'Microsoft365Apps' -Path (Join-Path $localRoot 'setup.exe');Set-PreInstallAcquisitionResult -Result $acquisition -Outcome FallbackCacheUsed -RefreshError $_;Write-PreInstallLog -Event 'BuiltInRefreshFailed' -Level 'Warning' -Message $_.Exception.Message -Data @{Id='Microsoft365Apps';Fallback='ExistingStagedPayload'};continue}
                    throw "Microsoft 365 Apps acquisition failed and no compatible staged fallback is available for the requested configuration. $($_.Exception.Message)"
                }
            }
            'MicrosoftTeams' {
                $localRoot = Join-Path $StagedPath 'BuiltIn\MicrosoftTeams'
                $acquireRoot = if ($usbRoot) { Join-Path $usbRoot 'BuiltIn\MicrosoftTeams' } else { $localRoot }
                $architecture = [string]$app.Architecture
                if ($architecture -notin @('x86','x64','arm64')) { throw [IO.InvalidDataException]::new('Invalid Teams architecture.') }
                New-Item -ItemType Directory -Path $localRoot -Force | Out-Null
                if ($usbRoot) { Restore-PreInstallBuiltInCache -Root $acquireRoot -Id MicrosoftTeams }
                New-Item -ItemType Directory -Path $acquireRoot -Force | Out-Null
                $msixUri = [string]$app.MsixUri
                $bootstrapperUri = [string]$app.BootstrapperUri
                if ($usbRoot -and -not (Test-LocalMicrosoftTeamsSource -Root $localRoot) -and (Test-LocalMicrosoftTeamsSource -Root $acquireRoot)) {
                    $payload = Assert-OSDAppCachedPayload -Root $acquireRoot -ExpectedExtension '.msix' -Id MicrosoftTeams -Architecture $architecture
                    Assert-PreInstallSignedPayload -Id MicrosoftTeams -Path (Join-Path $acquireRoot 'teamsbootstrapper.exe')
                    Copy-Item -LiteralPath (Join-Path $acquireRoot 'teamsbootstrapper.exe') -Destination (Join-Path $localRoot 'teamsbootstrapper.exe') -Force -ErrorAction Stop
                    Copy-OSDAppBuiltInPayload -Path $payload -DestinationDirectory $localRoot
                    Copy-Item -LiteralPath (Join-Path $acquireRoot 'CacheInfo.json') -Destination (Join-Path $localRoot 'CacheInfo.json') -Force -ErrorAction Stop
                }
                if (-not $networkAvailable) {
                    Assert-OSDAppCachedPayload -Root $localRoot -ExpectedExtension '.msix' -Id MicrosoftTeams -Architecture $architecture | Out-Null
                    Assert-PreInstallSignedPayload -Id MicrosoftTeams -Path (Join-Path $localRoot 'teamsbootstrapper.exe')
                    Set-PreInstallAcquisitionResult -Result $acquisition -Outcome OfflineCacheUsed
                    continue
                }
                try {
                    $previous = $null; $activeMsix = $null; $matches = $false
                    if (Test-LocalMicrosoftTeamsSource -Root $acquireRoot) {
                        $activeMsix = Assert-OSDAppCachedPayload -Root $acquireRoot -ExpectedExtension '.msix' -Id MicrosoftTeams -Architecture $architecture
                        $previous = Get-Content -LiteralPath (Join-Path $acquireRoot 'CacheInfo.json') -Raw -Encoding UTF8 | ConvertFrom-Json
                    }
                    $remote = Get-RemoteMetadata -Uri $msixUri
                    if ($activeMsix -and $previous) {
                        if ($remote.ETag -and $previous.RemoteETag) { $matches = $remote.ETag -eq [string]$previous.RemoteETag }
                        elseif ($remote.LastModified -and $previous.RemoteLastModified -and $remote.ContentLength -and $previous.RemoteContentLength) {
                            $matches = ($remote.LastModified -eq [string]$previous.RemoteLastModified -and [long]$remote.ContentLength -eq [long]$previous.RemoteContentLength)
                        }
                    }
                    $acquisition.CacheDecisionReason = (Get-PreInstallHttpCacheReason -PackagePath $activeMsix -CacheInfo $previous -Remote $remote -MetadataMatches $matches) + ' The Teams bootstrapper is downloaded separately.'
                    Invoke-OSDAppBuiltInCacheTransaction -Root $acquireRoot -ExpectedBytes ([double]$remote.ContentLength) -MinimumFreeSpaceGB 2 -Build {
                        param($candidate)
                        $bootstrapper = Join-Path $candidate 'teamsbootstrapper.exe'
                        Save-PreInstallDownload -Uri $bootstrapperUri -DestinationPath $bootstrapper -Id MicrosoftTeams -Description 'Microsoft Teams bootstrapper' -TimeoutMinutes 5 | Out-Null
                        Assert-PreInstallSignedPayload -Id MicrosoftTeams -Path $bootstrapper
                        if ($matches) {
                            Copy-OSDAppBuiltInPayload -Path $activeMsix -DestinationDirectory $candidate
                            $msix = Join-Path $candidate ([string]$previous.PayloadFileName)
                        }
                        else {
                            $download = Save-PreInstallDownload -Uri $msixUri -DestinationDirectory $candidate -ExpectedExtension '.msix' -Id MicrosoftTeams -Description 'Microsoft Teams MSIX' -TimeoutMinutes 15
                            $msix = [string]$download.FullName
                        }
                        $version = Get-MicrosoftTeamsPackageVersion -Path $msix
                        if (-not $version) { throw [IO.InvalidDataException]::new('Downloaded Teams MSIX version could not be read.') }
                        [ordered]@{
                            Id='MicrosoftTeams';Cached=[bool]$usbRoot;Version=$version;Architecture=$architecture
                            PayloadFileName=(Split-Path -Path $msix -Leaf);Sha256=(Get-FileHash -LiteralPath $msix -Algorithm SHA256).Hash
                            Size=(Get-Item -LiteralPath $msix).Length;SourcePolicy='Evergreen';SyncMethod='HttpMetadata';Updated=(-not $matches)
                            BootstrapperUri=$bootstrapperUri;RemoteETag=$remote.ETag;RemoteLastModified=$remote.LastModified
                            RemoteContentLength=$remote.ContentLength;RemoteFinalUri=$remote.FinalUri;SyncedAt=(Get-Date).ToUniversalTime().ToString('o')
                        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $candidate 'CacheInfo.json') -Encoding UTF8 -ErrorAction Stop
                    } -Validate {
                        param($candidate)
                        $msix = Assert-OSDAppCachedPayload -Root $candidate -ExpectedExtension '.msix' -Id MicrosoftTeams -Architecture $architecture
                        Assert-PreInstallSignedPayload -Id MicrosoftTeams -Path (Join-Path $candidate 'teamsbootstrapper.exe')
                        Get-MicrosoftTeamsPackageVersion -Path $msix | Out-Null
                    } | Out-Null
                    if ($usbRoot) {
                        Copy-Item -LiteralPath (Join-Path $acquireRoot 'teamsbootstrapper.exe') -Destination (Join-Path $localRoot 'teamsbootstrapper.exe') -Force -ErrorAction Stop
                        Copy-OSDAppBuiltInPayload -Path (Resolve-OSDAppBuiltInPayloadPath -Root $acquireRoot -ExpectedExtension '.msix') -DestinationDirectory $localRoot
                        Copy-Item -LiteralPath (Join-Path $acquireRoot 'CacheInfo.json') -Destination (Join-Path $localRoot 'CacheInfo.json') -Force -ErrorAction Stop
                    }
                    Set-PreInstallAcquisitionResult -Result $acquisition -Outcome $(if($matches){'CacheReused'}else{'Downloaded'})
                }
                catch {
                    if ($_.Exception -is [Security.SecurityException] -or $_.Exception -is [IO.InvalidDataException]) { throw }
                    $refreshError = $_
                    if (-not (Test-LocalMicrosoftTeamsSource -Root $localRoot)) { throw "Microsoft Teams acquisition failed and no staged fallback is available. $($refreshError.Exception.Message)" }
                    Assert-OSDAppCachedPayload -Root $localRoot -ExpectedExtension '.msix' -Id MicrosoftTeams -Architecture $architecture | Out-Null
                    Assert-PreInstallSignedPayload -Id MicrosoftTeams -Path (Join-Path $localRoot 'teamsbootstrapper.exe')
                    Set-PreInstallAcquisitionResult -Result $acquisition -Outcome FallbackCacheUsed -RefreshError $refreshError
                }
            }
            'AdobeAcrobatUnified' {
                $architecture = [string]$app.Architecture
                if ($architecture -notin @('x86','x64')) { throw [IO.InvalidDataException]::new('Invalid Adobe architecture.') }
                $packageUri = if ($app.PackageUri) { [string]$app.PackageUri } elseif ($architecture -eq 'x64') {
                    'https://trials.adobe.com/AdobeProducts/APRO/Acrobat_HelpX/win32/Acrobat_DC_Web_x64_WWMUI.zip'
                } else { 'https://trials.adobe.com/AdobeProducts/APRO/Acrobat_HelpX/win32/Acrobat_DC_Web_WWMUI.zip' }
                Sync-PreInstallVendorMsi -App $app -RelativeRoot (Join-Path 'BuiltIn\AdobeAcrobatUnified' $architecture) -PackageUri $packageUri -DisplayName 'Adobe Acrobat Unified' -Acquisition $acquisition -ExpectedExtension '.zip'
            }
            'CiscoWebex' {
                $architecture = if ($app.Architecture) { [string]$app.Architecture } else { 'x64' }
                if ($architecture -notin @('x64','arm64')) { throw "Cisco Webex supports only x64 and arm64; received '$architecture'." }
                $packageUri = if ($app.PackageUri) {
                    [string]$app.PackageUri
                }
                else {
                    switch ($architecture) {
                        'x64' { 'https://binaries.webex.com/WebexOfclDesktop-Win-64-Gold/Webex_en.msi' }
                        'arm64' { 'https://binaries.webex.com/WebexOfclDesktop-Win-Arm-64-Gold/Webex_en.msi' }
                    }
                }
                $relativeRoot = Join-Path 'BuiltIn\CiscoWebex' $architecture
                Sync-PreInstallVendorMsi -App $app -RelativeRoot $relativeRoot -PackageUri $packageUri -DisplayName 'Cisco Webex' -Acquisition $acquisition
            }
            { $app.Type -eq 'PrerequisiteExe' } {
                $spec = Get-OSDAppPrerequisiteSpec -Family $app.Family -Architecture $app.Architecture -RuntimeType $app.RuntimeType -Channel $app.Channel
                if ($app.Id -ne $spec.Id -or $app.PayloadRoot -ne $spec.RelativeRoot) { throw 'Invalid runtime deployment identity or path.' }
                $architecture = [string]$app.Architecture
                $relativeRoot = $spec.RelativeRoot
                $localRoot = Join-Path $StagedPath $relativeRoot
                $acquireRoot = if ($usbRoot) { Join-Path $usbRoot $relativeRoot } else { $localRoot }
                try {
                    if (-not $networkAvailable) { throw 'No network connection is available.' }
                    $sync = Sync-OSDAppPrerequisiteGeneration -Root $acquireRoot -Spec $spec -Log {
                        param($record)
                        Write-PreInstallLog -Event $record.Event -Level $record.Level -Message $record.Message -Data $record.Data
                    } -Download {
                        param($uri, $destination)
                        Save-PreInstallDownload -Uri $uri -DestinationDirectory $destination -ExpectedExtension '.exe' -Id $spec.Id -Description 'Runtime EXE' -TimeoutMinutes 10
                    }
                    if ($usbRoot) {
                        New-Item -ItemType Directory -Path $localRoot -Force | Out-Null
                        Copy-OSDAppBuiltInPayload -Path (Resolve-OSDAppBuiltInPayloadPath -Root $acquireRoot -ExpectedExtension '.exe') -DestinationDirectory $localRoot
                        Copy-Item -LiteralPath (Join-Path $acquireRoot 'CacheInfo.json') -Destination (Join-Path $localRoot 'CacheInfo.json') -Force
                    }
                    Assert-OSDAppPrerequisiteGeneration -Root $localRoot -Spec $spec -VerifyPublisher | Out-Null
                    Set-PreInstallAcquisitionResult -Result $acquisition -Outcome $(if ($sync.Updated) { 'Downloaded' } else { 'CacheReused' }) -CacheDecisionReason $sync.CacheDecisionReason
                }
                catch {
                    if ($_.Exception -is [NotSupportedException]) { throw }
                    $refreshFailure = $_
                    # A fallback must pass the same full hash and provenance checks.
                    try { Assert-OSDAppPrerequisiteGeneration -Root $localRoot -Spec $spec -VerifyPublisher | Out-Null }
                    catch { throw "Runtime acquisition failed with no valid staged fallback. $($refreshFailure.Exception.Message)" }
                    Set-PreInstallAcquisitionResult -Result $acquisition -Outcome $(if ($networkAvailable) { 'FallbackCacheUsed' } else { 'OfflineCacheUsed' }) -RefreshError $refreshFailure
                }
            }
            'VisualStudioCode' {
                $architecture = [string]$app.Architecture
                $relativeRoot = Join-Path 'BuiltIn\VisualStudioCode' $architecture
                $localRoot = Join-Path $StagedPath $relativeRoot
                $acquireRoot = if ($usbRoot) { Join-Path $usbRoot $relativeRoot } else { $localRoot }
                try {
                    if (-not $networkAvailable) { throw 'No network connection is available.' }
                    $sync = Sync-OSDAppVisualStudioCodeGeneration -Root $acquireRoot -Architecture $architecture -Download {
                        param($uri, $destination)
                        Save-PreInstallDownload -Uri $uri -DestinationDirectory $destination -ExpectedExtension '.exe' -Id 'VisualStudioCode' -Description 'VisualStudioCode EXE' -TimeoutMinutes 10
                    }
                    if ($usbRoot) {
                        New-Item -ItemType Directory -Path $localRoot -Force | Out-Null
                        Copy-OSDAppBuiltInPayload -Path (Resolve-OSDAppBuiltInPayloadPath -Root $acquireRoot -ExpectedExtension '.exe') -DestinationDirectory $localRoot
                        Copy-Item -LiteralPath (Join-Path $acquireRoot 'CacheInfo.json') -Destination (Join-Path $localRoot 'CacheInfo.json') -Force
                    }
                    Assert-OSDAppVisualStudioCodeGeneration -Root $localRoot -Architecture $architecture -VerifyPublisher | Out-Null
                    Set-PreInstallAcquisitionResult -Result $acquisition -Outcome $(if ($sync.Updated) { 'Downloaded' } else { 'CacheReused' }) -CacheDecisionReason $sync.CacheDecisionReason
                }
                catch {
                    $refreshFailure = $_
                    # A fallback must pass the same full hash and provenance checks.
                    try { Assert-OSDAppVisualStudioCodeGeneration -Root $localRoot -Architecture $architecture -VerifyPublisher | Out-Null }
                    catch { throw "VisualStudioCode acquisition failed with no valid staged fallback. $($refreshFailure.Exception.Message)" }
                    Set-PreInstallAcquisitionResult -Result $acquisition -Outcome $(if ($networkAvailable) { 'FallbackCacheUsed' } else { 'OfflineCacheUsed' }) -RefreshError $refreshFailure
                }
            }
            '7Zip' {
                $architecture = [string]$app.Architecture
                $relativeRoot = Join-Path 'BuiltIn\7Zip' $architecture
                $localRoot = Join-Path $StagedPath $relativeRoot
                $acquireRoot = if ($usbRoot) { Join-Path $usbRoot $relativeRoot } else { $localRoot }
                try {
                    if (-not $networkAvailable) { throw 'No network connection is available.' }
                    $sync = Sync-OSDApp7ZipGeneration -Root $acquireRoot -Architecture $architecture -Log {
                        param($record)
                        Write-PreInstallLog -Event $record.Event -Level $record.Level -Message $record.Message -Data $record.Data
                    } -Download {
                        param($uri, $destination)
                        Save-PreInstallDownload -Uri $uri -DestinationDirectory $destination -ExpectedExtension '.exe' -Id '7Zip' -Description '7Zip EXE' -TimeoutMinutes 10
                    }
                    if ($usbRoot) {
                        New-Item -ItemType Directory -Path $localRoot -Force | Out-Null
                        Copy-OSDAppBuiltInPayload -Path (Resolve-OSDAppBuiltInPayloadPath -Root $acquireRoot -ExpectedExtension '.exe') -DestinationDirectory $localRoot
                        Copy-Item -LiteralPath (Join-Path $acquireRoot 'CacheInfo.json') -Destination (Join-Path $localRoot 'CacheInfo.json') -Force
                    }
                    Assert-OSDApp7ZipGeneration -Root $localRoot -Architecture $architecture | Out-Null
                    Set-PreInstallAcquisitionResult -Result $acquisition -Outcome $(if ($sync.Updated) { 'Downloaded' } else { 'CacheReused' }) -CacheDecisionReason $sync.CacheDecisionReason
                }
                catch {
                    $refreshFailure = $_
                    # A fallback must pass the same full hash and provenance checks.
                    try { Assert-OSDApp7ZipGeneration -Root $localRoot -Architecture $architecture | Out-Null }
                    catch { throw "7Zip acquisition failed with no valid staged fallback. $($refreshFailure.Exception.Message)" }
                    Set-PreInstallAcquisitionResult -Result $acquisition -Outcome $(if ($networkAvailable) { 'FallbackCacheUsed' } else { 'OfflineCacheUsed' }) -RefreshError $refreshFailure
                }
            }
            'ZoomWorkplace' {
                $architecture = if ($app.Architecture) { [string]$app.Architecture } else { 'x64' }
                if ($architecture -notin @('x64','arm64')) { throw "Zoom Workplace supports only x64 and arm64; received '$architecture'." }
                $packageUri = if ($app.PackageUri) {
                    [string]$app.PackageUri
                }
                else {
                    switch ($architecture) {
                        'x64' { 'https://zoom.us/client/latest/ZoomInstallerFull.msi?archType=x64' }
                        'arm64' { 'https://zoom.us/client/latest/ZoomInstallerFull.msi?archType=winarm64' }
                    }
                }
                $relativeRoot = Join-Path 'BuiltIn\ZoomWorkplace' $architecture
                Sync-PreInstallVendorMsi -App $app -RelativeRoot $relativeRoot -PackageUri $packageUri -DisplayName 'Zoom Workplace' -Acquisition $acquisition
            }
            'GoogleChromeEnterprise' {
                $architecture = if ($app.Architecture) { [string]$app.Architecture } else { 'x64' }
                $packageUri = if ($app.PackageUri) {
                    [string]$app.PackageUri
                }
                else {
                    switch ($architecture) {
                        'x86' { 'https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise.msi' }
                        default { 'https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi' }
                    }
                }

                $relativeRoot = Join-Path 'BuiltIn\GoogleChromeEnterprise' $architecture
                Sync-PreInstallVendorMsi -App $app -RelativeRoot $relativeRoot -PackageUri $packageUri -DisplayName 'Google Chrome Enterprise' -Acquisition $acquisition
            }
            'MozillaFirefoxEnterprise' {
                $channel = if ($app.Channel) { [string]$app.Channel } else { 'Rapid' }
                $architecture = if ($app.Architecture) { [string]$app.Architecture } else { 'x64' }
                $language = if ($app.Language) { [string]$app.Language } else { 'en-US' }

                $packageUri = if ($app.PackageUri) {
                    [string]$app.PackageUri
                }
                else {
                    $product = if ($channel -eq 'ESR') { 'firefox-esr-msi-latest-ssl' } else { 'firefox-msi-latest-ssl' }
                    $os = if ($architecture -eq 'x64') { 'win64' } else { 'win' }
                    "https://download.mozilla.org/?product=$product&os=$os&lang=$language"
                }

                $relativeRoot = Join-Path 'BuiltIn\MozillaFirefoxEnterprise' (Join-Path $channel (Join-Path $architecture $language))
                Sync-PreInstallVendorMsi -App $app -RelativeRoot $relativeRoot -PackageUri $packageUri -DisplayName 'Mozilla Firefox Enterprise' -Acquisition $acquisition
            }
            default {
                throw [System.IO.InvalidDataException]::new("Unsupported built-in app Id '$($app.Id)' in the device manifest.")
            }
            }
        }
        catch {
            $appErrorRecord = $_
            $appError = $appErrorRecord.Exception.Message
            $appFailureType = Get-PreInstallFailureType -ErrorRecord $appErrorRecord
            $fatal = (
                $appErrorRecord.Exception -is [System.Security.SecurityException] -or
                $appErrorRecord.Exception -is [System.IO.InvalidDataException]
            )
            Write-PreInstallLog -Event 'AppRefreshFailed' -Level 'Error' -Message $appError -Data @{
                Id = $app.Id
                FailureType = $appFailureType
                ContinueQueue = (-not $fatal)
                DurationSeconds = [math]::Round($builtInStopwatch.Elapsed.TotalSeconds,1)
            }
            if ($fatal) { throw }
        }
        finally {
            if (-not $appError) { Set-OSDAppManifestPayload -App $app -StagedPath $StagedPath }
            if ($builtInStopwatch.IsRunning) { $builtInStopwatch.Stop() }
            $appResults.Add([pscustomobject]@{
                Id              = [string]$app.Id
                DisplayName     = if ($app.DisplayName) { [string]$app.DisplayName } else { [string]$app.Id }
                Status          = if ($appError) { 'Failed' } else { 'Succeeded' }
                DurationSeconds = [math]::Round($builtInStopwatch.Elapsed.TotalSeconds,1)
                CacheUsed       = [bool]$usbRoot
                PackageUpdated  = if ($appError) { $null } else { $acquisition.PackageUpdated }
                AcquisitionOutcome = if ($appError) { 'Failed' } else { $acquisition.Outcome }
                CacheDecisionReason = if ($appError) { 'Acquisition failed. ' + $appError } else { $acquisition.CacheDecisionReason }
                RefreshFailureType = $acquisition.RefreshFailureType
                RefreshError    = $acquisition.RefreshError
                FailureType     = $appFailureType
                Error           = $appError
            })
            $appResult = $appResults[$appResults.Count - 1]
            $level = if ($appError) { 'Error' } elseif ($acquisition.Outcome -in @('FallbackCacheUsed','OfflineCacheUsed')) { 'Warning' } else { 'Info' }
            Write-PreInstallLog -Event 'AppAcquisitionComplete' -Level $level -Message 'Built-in preparation outcome recorded; installation is a separate step.' -Data @{
                Id = $app.Id
                Status = $appResult.Status
                AcquisitionOutcome = $appResult.AcquisitionOutcome
                CacheUsed = $appResult.CacheUsed
                PackageUpdated = $appResult.PackageUpdated
                CacheDecisionReason = $appResult.CacheDecisionReason
                RefreshFailureType = $appResult.RefreshFailureType
                RefreshError = $appResult.RefreshError
            }
        }
    }

    # Runner starts in a new process and reads this exact, atomically saved manifest.
    $manifestTemp = "$manifestPath.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        $manifest | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $manifestTemp -Encoding UTF8 -ErrorAction Stop
        Move-Item -LiteralPath $manifestTemp -Destination $manifestPath -Force -ErrorAction Stop
    }
    finally {
        if (Test-Path -LiteralPath $manifestTemp) { Remove-Item -LiteralPath $manifestTemp -Force -ErrorAction SilentlyContinue }
    }
    $preInstallStopwatch.Stop()
    $failedAppCount = @($appResults | Where-Object { $_.Status -eq 'Failed' }).Count
    if ($failedAppCount -gt 0) {
        $summary = "$failedAppCount built-in app(s) could not be prepared; independent apps will continue and no automatic retry is scheduled."
        Write-PreInstallLog -Event 'RefreshCompletedWithErrors' -Level 'Error' -Message $summary -Data @{CacheUsed=[bool]$usbRoot;BuiltInAppCount=@($builtInApps).Count;FailedBuiltInAppCount=$failedAppCount;DurationSeconds=[math]::Round($preInstallStopwatch.Elapsed.TotalSeconds,1)}
        Write-PreInstallLog -Event 'PreInstallComplete' -Level 'Warning' -Message 'PreInstall completed with app errors. Runner execution may continue for unaffected apps.' -Data @{BuiltInAppCount=@($builtInApps).Count;FailedBuiltInAppCount=$failedAppCount;DurationSeconds=[math]::Round($preInstallStopwatch.Elapsed.TotalSeconds,1)}
        try { Write-PreInstallResult -Status CompletedWithErrors -FailureType 'AppFailures' -ErrorMessage $summary } catch { Write-PreInstallLog -Event 'ResultWriteFailed' -Level Warning -Message $_.Exception.Message }
        exit 0
    }

    Write-PreInstallLog -Event 'RefreshComplete' -Message 'Built-in acquisition and refresh completed. Installation will continue.' -Data @{CacheUsed=[bool]$usbRoot;DurationSeconds=[math]::Round($preInstallStopwatch.Elapsed.TotalSeconds,1)}
    $fallbackCount = @($appResults | Where-Object { $_.AcquisitionOutcome -eq 'FallbackCacheUsed' }).Count
    $offlineCount = @($appResults | Where-Object { $_.AcquisitionOutcome -eq 'OfflineCacheUsed' }).Count
    $completionLevel = if (($fallbackCount + $offlineCount) -gt 0) { 'Warning' } else { 'Info' }
    Write-PreInstallLog -Event 'PreInstallComplete' -Level $completionLevel -Message 'PreInstall completed successfully; inspect acquisition outcomes for cache fallback or offline use.' -Data @{BuiltInAppCount=@($builtInApps).Count;FallbackAppCount=$fallbackCount;OfflineCacheAppCount=$offlineCount;DurationSeconds=[math]::Round($preInstallStopwatch.Elapsed.TotalSeconds,1)}
    try { Write-PreInstallResult -Status Succeeded } catch { Write-PreInstallLog -Event 'ResultWriteFailed' -Level Warning -Message $_.Exception.Message }
    exit 0
} catch {
    if ($preInstallStopwatch.IsRunning) { $preInstallStopwatch.Stop() }
    $failureMessage = $_.Exception.Message
    $failureType = Get-PreInstallFailureType -ErrorRecord $_

    Write-PreInstallLog -Event 'RefreshFailed' -Level 'Error' -Message $failureMessage -Data @{FailureType=$failureType;DurationSeconds=[math]::Round($preInstallStopwatch.Elapsed.TotalSeconds,1)}
    try { Write-PreInstallResult -Status Failed -FailureType $failureType -ErrorMessage $failureMessage } catch { Write-PreInstallLog -Event 'ResultWriteFailed' -Level Warning -Message $_.Exception.Message }
    exit 1
}
finally {
    try { if ($cacheLock) { $cacheLock.Dispose() } }
    finally {
        if ($null -ne $sleepRequest) { Stop-OSDAppSleepPrevention -Request $sleepRequest -Log $sleepLog }
    }
}
