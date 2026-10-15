[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$StagedPath,
    [ValidateRange(1,120)][int]$OfficeRefreshTimeoutMinutes = 20
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Enter-OSDAppCacheLock.ps1')
$cacheLock = $null
. (Join-Path $PSScriptRoot 'Restore-OSDAppCacheGeneration.ps1')
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
$applicationResults = [System.Collections.Generic.List[object]]::new()

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
    $successful = @($applicationResults | Where-Object { $_.Status -eq 'Succeeded' }).Count
    $failed = @($applicationResults | Where-Object { $_.Status -eq 'Failed' }).Count
    $record = [ordered]@{
        SchemaVersion           = '1.0'
        DeploymentId           = if ($manifest -and $manifest.DeploymentId) { [string]$manifest.DeploymentId } else { $null }
        Phase                   = 'PreInstall'
        Status                  = $Status
        StartedAtUtc            = $preInstallStartedAtUtc
        CompletedAtUtc          = (Get-Date).ToUniversalTime().ToString('o')
        DurationSeconds         = [math]::Round($preInstallStopwatch.Elapsed.TotalSeconds, 1)
        BuiltInApplicationCount = @($builtInApps).Count
        SuccessfulBuiltInApplicationCount = $successful
        FailedBuiltInApplicationCount = $failed
        CacheUsed               = [bool]$usbRoot
        CachePath               = $usbRoot
        NetworkAvailable        = $networkAvailable
        Applications            = @($applicationResults | ForEach-Object { $_ })
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
    if ($message -match 'no network|not reachable') { return 'NetworkUnavailable' }
    if ($message -match 'timeout|exceeded') { return 'Timeout' }
    if ($message -match 'no staged|no .*cached|missing') { return 'CacheOrSourceMissing' }
    if ($message -match 'metadata|HTTP|response|download|acquisition') { return 'RemoteAcquisition' }
    'PreInstallError'
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
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$DestinationPath,
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Description,
        [int]$TimeoutMinutes = 30
    )

    $directory = Split-Path -Path $DestinationPath -Parent
    if ($directory) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }

    $tempPath = "$DestinationPath.download"
    if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force }

    $handler = [System.Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect = $true
    $client = [System.Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromMinutes($TimeoutMinutes)
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    Write-PreInstallLog -Event 'DownloadStart' -Message "Downloading $Description." -Data @{ Id=$Id; Uri=$Uri; Destination=$DestinationPath }

    try {
        $response = $client.GetAsync($Uri, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        try {
            $response.EnsureSuccessStatusCode() | Out-Null
            $totalBytes = $response.Content.Headers.ContentLength
            $source = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()

            $target = [System.IO.FileStream]::new(
                $tempPath,
                [System.IO.FileMode]::Create,
                [System.IO.FileAccess]::Write,
                [System.IO.FileShare]::None
            )

            try {
                $buffer = New-Object byte[] (1024 * 1024)
                [int64]$downloaded = 0

                while (($read = $source.Read($buffer, 0, $buffer.Length)) -gt 0) {
                    $target.Write($buffer, 0, $read)
                    $downloaded += $read
                }
            }
            finally {
                $target.Dispose()
                $source.Dispose()
            }
        }
        finally {
            $response.Dispose()
        }

        if (Test-Path -LiteralPath $DestinationPath) {
            Remove-Item -LiteralPath $DestinationPath -Force
        }
        Move-Item -LiteralPath $tempPath -Destination $DestinationPath -Force

        $stopwatch.Stop()
        $bytes = (Get-Item -LiteralPath $DestinationPath).Length
        $seconds = [math]::Max($stopwatch.Elapsed.TotalSeconds, 0.001)
        $averageMBps = [math]::Round(($bytes / 1MB) / $seconds, 1)

        Write-PreInstallLog -Event 'DownloadComplete' -Message "$Description download completed." -Data @{
            Id=$Id
            Bytes=$bytes
            SizeMB=[math]::Round($bytes / 1MB, 1)
            DurationSeconds=[math]::Round($seconds, 1)
            AverageMBps=$averageMBps
            Destination=$DestinationPath
        }
    }
    catch {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
        throw
    }
    finally {
        if ($stopwatch.IsRunning) { $stopwatch.Stop() }
        $client.Dispose()
        $handler.Dispose()
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
    param([string]$Root)
    try{
        $cacheInfoPath=Join-Path $Root 'CacheInfo.json'
        if(-not(Test-Path -LiteralPath $cacheInfoPath -PathType Leaf)){return $false}
        $cacheInfo=Get-Content -LiteralPath $cacheInfoPath -Raw -Encoding UTF8|ConvertFrom-Json
        Test-OfficeCacheGeneration -OfficeRoot $Root -ExpectedVersion ([string]$cacheInfo.Version) -Architecture $(if([string]$cacheInfo.Architecture -eq 'x86'){'x86'}else{'x64'})|Out-Null
        return $true
    }catch{return $false}
}

function Test-LocalMicrosoftTeamsSource {
    param([string]$Root)
    return ((Test-Path -LiteralPath (Join-Path $Root 'teamsbootstrapper.exe') -PathType Leaf) -and (Test-Path -LiteralPath (Join-Path $Root 'teams.msix') -PathType Leaf))
}

function Remove-LegacyMicrosoftTeamsCache {
    param(
        [string]$UsbRoot,
        [string]$CanonicalRoot
    )

    if (-not $UsbRoot -or -not (Test-LocalMicrosoftTeamsSource -Root $CanonicalRoot)) { return }
    $legacyRoot = Join-Path $UsbRoot 'BuiltIn\Teams'
    if (-not (Test-Path -LiteralPath $legacyRoot)) { return }

    try {
        # Validate the signable canonical component again at the deletion
        # boundary. Teams MSIX remains outside the explicit signature scope.
        Assert-PreInstallSignedPayload -Id 'MicrosoftTeams' -Path (Join-Path $CanonicalRoot 'teamsbootstrapper.exe')
        Remove-Item -LiteralPath $legacyRoot -Recurse -Force -ErrorAction Stop
        Write-PreInstallLog -Event 'CacheAliasPruned' -Message 'Retired Microsoft Teams cache was removed after canonical replacement validation.' -Data @{Alias='Teams';CanonicalId='MicrosoftTeams';Path=$legacyRoot}
    }
    catch {
        Write-PreInstallLog -Event 'CacheAliasPruneFailed' -Level 'Warning' -Message $_.Exception.Message -Data @{Alias='Teams';CanonicalId='MicrosoftTeams';Path=$legacyRoot}
    }
}

function Test-LocalAdobeAcrobatUnifiedSource {
    param([string]$Root)
    return (Test-Path -LiteralPath (Join-Path $Root 'Package.zip') -PathType Leaf)
}

function Test-LocalMsiSource {
    param([string]$Root)
    return (Test-Path -LiteralPath (Join-Path $Root 'Package.msi') -PathType Leaf)
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
        [Parameter(Mandatory)][string]$DisplayName
    )

    $id = [string]$App.Id
    $localRoot = Join-Path $StagedPath $RelativeRoot
    New-Item -ItemType Directory -Path $localRoot -Force | Out-Null

    $acquireRoot = if ($usbRoot) { Join-Path $usbRoot $RelativeRoot } else { $localRoot }
    if ($usbRoot) { Restore-PreInstallBuiltInCache -Root $acquireRoot -Id $id }
    New-Item -ItemType Directory -Path $acquireRoot -Force | Out-Null

    if ($usbRoot -and -not (Test-LocalMsiSource -Root $localRoot) -and (Test-LocalMsiSource -Root $acquireRoot)) {
        Assert-PreInstallSignedPayload -Id $id -Path (Join-Path $acquireRoot 'Package.msi')
        Copy-Item -LiteralPath (Join-Path $acquireRoot 'Package.msi') -Destination (Join-Path $localRoot 'Package.msi') -Force
        if (Test-Path -LiteralPath (Join-Path $acquireRoot 'CacheInfo.json') -PathType Leaf) {
            Copy-Item -LiteralPath (Join-Path $acquireRoot 'CacheInfo.json') -Destination (Join-Path $localRoot 'CacheInfo.json') -Force
        }
        Write-PreInstallLog -Event 'BuiltInCacheRestaged' -Message "Existing $DisplayName USB cache was staged locally." -Data @{ Id=$id }
    }

    if (-not $networkAvailable) {
        if (Test-LocalMsiSource -Root $localRoot) {
            Assert-PreInstallSignedPayload -Id $id -Path (Join-Path $localRoot 'Package.msi')
            Write-PreInstallLog -Event 'BuiltInRefreshSkipped' -Level 'Warning' -Message "No network is available. Existing staged $DisplayName payload will be used." -Data @{ Id=$id }
            return
        }
        throw "$DisplayName has no staged or USB-cached payload and no network connection is available to acquire one."
    }

    $transactionRoot = $null
    $backupRoot = $null
    try {
        $cacheInfoPath = Join-Path $acquireRoot 'CacheInfo.json'
        $cacheInfo = $null
        if (Test-Path -LiteralPath $cacheInfoPath -PathType Leaf) {
            try { $cacheInfo = Get-Content -LiteralPath $cacheInfoPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
        }

        $packagePath = Join-Path $acquireRoot 'Package.msi'
        Write-PreInstallLog -Event 'BuiltInRefreshStart' -Message "Checking $DisplayName cache for updates." -Data @{ Id=$id; Target=if($usbRoot){'USB'}else{'Local'} }

        $remote = Get-RemoteMetadata -Uri $PackageUri
        $matches = $false

        if ((Test-Path -LiteralPath $packagePath -PathType Leaf) -and $cacheInfo) {
            if ($remote.ETag -and $cacheInfo.RemoteETag) {
                $matches = $remote.ETag -eq [string]$cacheInfo.RemoteETag
            }
            elseif ($remote.LastModified -and $cacheInfo.RemoteLastModified -and $remote.ContentLength -and $cacheInfo.RemoteContentLength) {
                $matches = (
                    $remote.LastModified -eq [string]$cacheInfo.RemoteLastModified -and
                    [int64]$remote.ContentLength -eq [int64]$cacheInfo.RemoteContentLength
                )
            }
        }

        $updated = $false
        $generationRoot = $acquireRoot
        if (-not $matches) {
            Assert-OSDAppTransactionSpace -Path $acquireRoot -ExistingPath $acquireRoot -ExpectedBytes ([double]$remote.ContentLength) -MinimumFreeSpaceGB 1 -Operation "$id cache refresh" | Out-Null
            $transactionRoot = "$acquireRoot.osdapps-new-$([guid]::NewGuid().ToString('N'))"
            $backupRoot = "$acquireRoot.osdapps-old-$([guid]::NewGuid().ToString('N'))"
            New-Item -ItemType Directory -Path $transactionRoot -Force | Out-Null
            $generationRoot = $transactionRoot
            $packagePath = Join-Path $generationRoot 'Package.msi'
            Save-PreInstallDownload -Uri $PackageUri -DestinationPath $packagePath -Id $id -Description "$DisplayName MSI" -TimeoutMinutes 15
            Assert-PreInstallSignedPayload -Id $id -Path $packagePath
            $updated = $true
        }

        Assert-PreInstallSignedPayload -Id $id -Path $packagePath
        $cacheInfoPath = Join-Path $generationRoot 'CacheInfo.json'
        $cacheRecord = [ordered]@{
            Id                  = $id
            Cached              = [bool]$usbRoot
            Version             = 'Current'
            Architecture        = $App.Architecture
            SourcePolicy        = 'Evergreen'
            SyncMethod          = 'HttpMetadata'
            Updated             = $updated
            PackageUri          = $PackageUri
            RemoteETag          = $remote.ETag
            RemoteLastModified  = $remote.LastModified
            RemoteContentLength = $remote.ContentLength
            RemoteFinalUri      = $remote.FinalUri
            SyncedAt            = (Get-Date).ToUniversalTime().ToString('o')
        }
        if ($App.PSObject.Properties.Name -contains 'Channel' -and $App.Channel) { $cacheRecord.Channel = [string]$App.Channel }
        if ($App.PSObject.Properties.Name -contains 'Language' -and $App.Language) { $cacheRecord.Language = [string]$App.Language }

        $cacheRecord | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $cacheInfoPath -Encoding UTF8

        if ($transactionRoot) {
            if (-not (Test-LocalMsiSource -Root $transactionRoot)) { throw "$DisplayName candidate generation is incomplete." }
            $validatedInfo = Get-Content -LiteralPath $cacheInfoPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ([string]$validatedInfo.Id -ne $id) { throw "$DisplayName candidate metadata is inconsistent." }
            $hadPrevious = Test-Path -LiteralPath $acquireRoot -PathType Container
            if ($hadPrevious) { Move-Item -LiteralPath $acquireRoot -Destination $backupRoot -ErrorAction Stop }
            try { Move-Item -LiteralPath $transactionRoot -Destination $acquireRoot -ErrorAction Stop }
            catch {
                if ($hadPrevious -and (Test-Path -LiteralPath $backupRoot -PathType Container) -and -not (Test-Path -LiteralPath $acquireRoot)) { Move-Item -LiteralPath $backupRoot -Destination $acquireRoot -ErrorAction SilentlyContinue }
                throw
            }
            if (Test-Path -LiteralPath $backupRoot -PathType Container) { Remove-Item -LiteralPath $backupRoot -Recurse -Force }
            $transactionRoot = $null
            Remove-PreInstallTransactionResidue -Root $acquireRoot
            $packagePath = Join-Path $acquireRoot 'Package.msi'
            $cacheInfoPath = Join-Path $acquireRoot 'CacheInfo.json'
        }

        if ($usbRoot) {
            Copy-Item -LiteralPath $packagePath -Destination (Join-Path $localRoot 'Package.msi') -Force
            Copy-Item -LiteralPath $cacheInfoPath -Destination (Join-Path $localRoot 'CacheInfo.json') -Force
        }

        Write-PreInstallLog -Event 'BuiltInRefreshComplete' -Message "$DisplayName content is ready for installation." -Data @{ Id=$id; PackageUpdated=$updated; CacheSynchronized=[bool]$usbRoot; SourcePolicy='Evergreen'; SyncMethod='HttpMetadata'; DurationSeconds=[math]::Round($builtInStopwatch.Elapsed.TotalSeconds,1) }
    }
    catch {
        if ($transactionRoot -and (Test-Path -LiteralPath $transactionRoot)) { Remove-Item -LiteralPath $transactionRoot -Recurse -Force -ErrorAction SilentlyContinue }
        if ($backupRoot -and (Test-Path -LiteralPath $backupRoot -PathType Container) -and -not (Test-Path -LiteralPath $acquireRoot)) { Move-Item -LiteralPath $backupRoot -Destination $acquireRoot -ErrorAction SilentlyContinue }
        if (Test-LocalMsiSource -Root $localRoot) {
            Assert-PreInstallSignedPayload -Id $id -Path (Join-Path $localRoot 'Package.msi')
            Write-PreInstallLog -Event 'BuiltInRefreshFailed' -Level 'Warning' -Message $_.Exception.Message -Data @{ Id=$id; Fallback='ExistingStagedPayload' }
            return
        }
        throw "$DisplayName acquisition failed and no staged fallback is available. $($_.Exception.Message)"
    }
}

try {
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Device manifest not found: $manifestPath" }
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

    $apps=if($manifest.PSObject.Properties.Name -contains 'Apps'){@($manifest.Apps)}else{@()}
    $builtInApps=@($apps | Where-Object { [string]$_.Source -eq 'BuiltIn' })
    if($builtInApps.Count -eq 0){
        $preInstallStopwatch.Stop()
        Write-PreInstallLog -Event 'RefreshSkipped' -Message 'No built-in applications are staged. Nothing to refresh.'
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
        $applicationError = $null
        $applicationFailureType = $null
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

                if($usbRoot -and -not (Test-LocalOfficeSource -Root $localRoot) -and (Test-LocalOfficeSource -Root $acquireRoot)){
                    Copy-Item -LiteralPath (Join-Path $acquireRoot 'setup.exe') -Destination (Join-Path $localRoot 'setup.exe') -Force
                    Copy-Item -LiteralPath (Join-Path $acquireRoot 'configuration.xml') -Destination $localConfig -Force
                    if(Test-Path -LiteralPath (Join-Path $acquireRoot 'CacheInfo.json') -PathType Leaf){Copy-Item -LiteralPath (Join-Path $acquireRoot 'CacheInfo.json') -Destination (Join-Path $localRoot 'CacheInfo.json') -Force}
                    Copy-DirectoryReplace -Source (Join-Path $acquireRoot 'Office') -Destination (Join-Path $localRoot 'Office')
                    Write-PreInstallLog -Event 'BuiltInCacheRestaged' -Message 'Existing Microsoft 365 Apps USB cache was staged locally.' -Data @{Id='Microsoft365Apps'}
                }

                if(-not $networkAvailable){
                    if(Test-LocalOfficeSource -Root $localRoot){Assert-PreInstallSignedPayload -Id 'Microsoft365Apps' -Path (Join-Path $localRoot 'setup.exe');Write-PreInstallLog -Event 'BuiltInRefreshSkipped' -Level 'Warning' -Message 'No network is available. Existing staged Office payload will be used.' -Data @{Id='Microsoft365Apps'}; continue}
                    throw 'Microsoft 365 Apps has no staged or USB-cached payload and no network connection is available to acquire one.'
                }

                $transactionRoot=$null;$backupRoot=$null
                try {
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
                    Save-PreInstallDownload -Uri $odtUri -DestinationPath $setupPath -Id 'Microsoft365Apps' -Description 'Office Deployment Tool' -TimeoutMinutes 5
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
                    Test-OfficeCacheGeneration -OfficeRoot $transactionRoot -ExpectedVersion $version -Architecture $app.Architecture | Out-Null
                    $cacheInfo=[ordered]@{Id='Microsoft365Apps';Cached=[bool]$usbRoot;Version=$version;Architecture=$app.Architecture;Channel=$app.Channel;ProductId=$app.ProductId;Language=@($app.Language);SourcePolicy='Evergreen';SyncMethod='OfficeDeploymentTool';Updated=($previous -ne $version);SyncedAt=(Get-Date).ToUniversalTime().ToString('o')}
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
                    Write-PreInstallLog -Event 'BuiltInRefreshComplete' -Message 'Microsoft 365 Apps content is ready for installation.' -Data @{Id='Microsoft365Apps';Version=$version;CacheSynchronized=[bool]$usbRoot;VersionChanged=$versionChanged;RemovedVersions=$removedVersions;SourcePolicy='Evergreen';SyncMethod='OfficeDeploymentTool';DurationSeconds=[math]::Round($builtInStopwatch.Elapsed.TotalSeconds,1)}
                } catch {
                    if($transactionRoot -and (Test-Path -LiteralPath $transactionRoot)){Remove-Item -LiteralPath $transactionRoot -Recurse -Force -ErrorAction SilentlyContinue}
                    if($backupRoot -and (Test-Path -LiteralPath $backupRoot -PathType Container) -and -not(Test-Path -LiteralPath $acquireRoot)){Move-Item -LiteralPath $backupRoot -Destination $acquireRoot -ErrorAction SilentlyContinue}
                    if(Test-LocalOfficeSource -Root $localRoot){Assert-PreInstallSignedPayload -Id 'Microsoft365Apps' -Path (Join-Path $localRoot 'setup.exe');Write-PreInstallLog -Event 'BuiltInRefreshFailed' -Level 'Warning' -Message $_.Exception.Message -Data @{Id='Microsoft365Apps';Fallback='ExistingStagedPayload'};continue}
                    throw "Microsoft 365 Apps acquisition failed and no staged fallback is available. $($_.Exception.Message)"
                }
            }
            'MicrosoftTeams' {
                $localRoot=Join-Path $StagedPath 'BuiltIn\MicrosoftTeams'; New-Item -ItemType Directory -Path $localRoot -Force | Out-Null
                $acquireRoot=if($usbRoot){Join-Path $usbRoot 'BuiltIn\MicrosoftTeams'}else{$localRoot}
                if($usbRoot){Restore-PreInstallBuiltInCache -Root $acquireRoot -Id 'MicrosoftTeams'}
                New-Item -ItemType Directory -Path $acquireRoot -Force | Out-Null
                if($usbRoot -and -not (Test-LocalMicrosoftTeamsSource -Root $localRoot) -and (Test-LocalMicrosoftTeamsSource -Root $acquireRoot)){
                    Assert-PreInstallSignedPayload -Id 'MicrosoftTeams' -Path (Join-Path $acquireRoot 'teamsbootstrapper.exe')
                    Copy-Item -LiteralPath (Join-Path $acquireRoot 'teamsbootstrapper.exe') -Destination (Join-Path $localRoot 'teamsbootstrapper.exe') -Force
                    Copy-Item -LiteralPath (Join-Path $acquireRoot 'teams.msix') -Destination (Join-Path $localRoot 'teams.msix') -Force
                    if(Test-Path -LiteralPath (Join-Path $acquireRoot 'CacheInfo.json') -PathType Leaf){Copy-Item -LiteralPath (Join-Path $acquireRoot 'CacheInfo.json') -Destination (Join-Path $localRoot 'CacheInfo.json') -Force}
                    Write-PreInstallLog -Event 'BuiltInCacheRestaged' -Message 'Existing Microsoft Teams USB cache was staged locally.' -Data @{Id='MicrosoftTeams'}
                }

                if(-not $networkAvailable){
                    if(Test-LocalMicrosoftTeamsSource -Root $localRoot){Assert-PreInstallSignedPayload -Id 'MicrosoftTeams' -Path (Join-Path $localRoot 'teamsbootstrapper.exe');Remove-LegacyMicrosoftTeamsCache -UsbRoot $usbRoot -CanonicalRoot $acquireRoot;Write-PreInstallLog -Event 'BuiltInRefreshSkipped' -Level 'Warning' -Message 'No network is available. Existing staged Teams payload will be used.' -Data @{Id='MicrosoftTeams'};continue}
                    throw 'Microsoft Teams has no staged or USB-cached payload and no network connection is available to acquire one.'
                }
                $transactionRoot=$null;$backupRoot=$null
                try {
                    $architecture=if($app.Architecture){[string]$app.Architecture}else{'x64'}
                    $msixUri=if($app.MsixUri){[string]$app.MsixUri}else{switch($architecture){'x86'{'https://go.microsoft.com/fwlink/?clcid=0x409&linkid=2196060'}'x64'{'https://go.microsoft.com/fwlink/?linkid=2196106'}'arm64'{'https://go.microsoft.com/fwlink/?clcid=0x409&linkid=2196207'}}}
                    $bootstrapperUri=if($app.BootstrapperUri){[string]$app.BootstrapperUri}else{'https://go.microsoft.com/fwlink/?clcid=0x409&linkid=2243204'}
                    $cacheInfoPath=Join-Path $acquireRoot 'CacheInfo.json'; $cacheInfo=$null
                    if(Test-Path -LiteralPath $cacheInfoPath -PathType Leaf){try{$cacheInfo=Get-Content -LiteralPath $cacheInfoPath -Raw -Encoding UTF8 | ConvertFrom-Json}catch{}}
                    $msixPath=Join-Path $acquireRoot 'teams.msix'; $bootstrapperPath=Join-Path $acquireRoot 'teamsbootstrapper.exe'
                    $remote=Get-RemoteMetadata -Uri $msixUri; $matches=$false
                    if((Test-Path -LiteralPath $msixPath -PathType Leaf) -and $cacheInfo){if($remote.ETag -and $cacheInfo.RemoteETag){$matches=$remote.ETag -eq [string]$cacheInfo.RemoteETag}elseif($remote.LastModified -and $cacheInfo.RemoteLastModified -and $remote.ContentLength -and $cacheInfo.RemoteContentLength){$matches=($remote.LastModified -eq [string]$cacheInfo.RemoteLastModified -and [int64]$remote.ContentLength -eq [int64]$cacheInfo.RemoteContentLength)}}
                    Assert-OSDAppTransactionSpace -Path $acquireRoot -ExistingPath $acquireRoot -ExpectedBytes ([double]$remote.ContentLength) -MinimumFreeSpaceGB 2 -Operation 'Microsoft Teams cache refresh' | Out-Null
                    $transactionRoot="$acquireRoot.osdapps-new-$([guid]::NewGuid().ToString('N'))";$backupRoot="$acquireRoot.osdapps-old-$([guid]::NewGuid().ToString('N'))";New-Item -ItemType Directory -Path $transactionRoot -Force|Out-Null
                    $candidateBootstrapper=Join-Path $transactionRoot 'teamsbootstrapper.exe';$candidateMsix=Join-Path $transactionRoot 'teams.msix'
                    Save-PreInstallDownload -Uri $bootstrapperUri -DestinationPath $candidateBootstrapper -Id 'MicrosoftTeams' -Description 'Microsoft Teams bootstrapper' -TimeoutMinutes 5;Assert-PreInstallSignedPayload -Id 'MicrosoftTeams' -Path $candidateBootstrapper
                    if($matches){Copy-Item -LiteralPath $msixPath -Destination $candidateMsix -Force;$updated=$false;$version=if($cacheInfo -and $cacheInfo.Version){[string]$cacheInfo.Version}else{Get-MicrosoftTeamsPackageVersion -Path $candidateMsix}}
                    else{Save-PreInstallDownload -Uri $msixUri -DestinationPath $candidateMsix -Id 'MicrosoftTeams' -Description "Microsoft Teams $architecture MSIX" -TimeoutMinutes 15;$version=Get-MicrosoftTeamsPackageVersion -Path $candidateMsix;$updated=$true}
                    Get-MicrosoftTeamsPackageVersion -Path $candidateMsix|Out-Null
                    [ordered]@{Id='MicrosoftTeams';Cached=[bool]$usbRoot;Version=$version;Architecture=$architecture;SourcePolicy='Evergreen';SyncMethod='HttpMetadata';Updated=$updated;BootstrapperUri=$bootstrapperUri;RemoteETag=$remote.ETag;RemoteLastModified=$remote.LastModified;RemoteContentLength=$remote.ContentLength;RemoteFinalUri=$remote.FinalUri;SyncedAt=(Get-Date).ToUniversalTime().ToString('o')}|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $transactionRoot 'CacheInfo.json') -Encoding UTF8
                    $hadPrevious=Test-Path -LiteralPath $acquireRoot -PathType Container;if($hadPrevious){Move-Item -LiteralPath $acquireRoot -Destination $backupRoot -ErrorAction Stop}
                    try{Move-Item -LiteralPath $transactionRoot -Destination $acquireRoot -ErrorAction Stop}catch{if($hadPrevious -and(Test-Path -LiteralPath $backupRoot -PathType Container)-and-not(Test-Path -LiteralPath $acquireRoot)){Move-Item -LiteralPath $backupRoot -Destination $acquireRoot -ErrorAction SilentlyContinue};throw}
                    if(Test-Path -LiteralPath $backupRoot -PathType Container){Remove-Item -LiteralPath $backupRoot -Recurse -Force};$transactionRoot=$null;Remove-PreInstallTransactionResidue -Root $acquireRoot
                    $bootstrapperPath=Join-Path $acquireRoot 'teamsbootstrapper.exe';$msixPath=Join-Path $acquireRoot 'teams.msix';$cacheInfoPath=Join-Path $acquireRoot 'CacheInfo.json'
                    if($usbRoot){Copy-Item -LiteralPath $bootstrapperPath -Destination (Join-Path $localRoot 'teamsbootstrapper.exe') -Force;Copy-Item -LiteralPath $msixPath -Destination (Join-Path $localRoot 'teams.msix') -Force;Copy-Item -LiteralPath $cacheInfoPath -Destination (Join-Path $localRoot 'CacheInfo.json') -Force}
                    Remove-LegacyMicrosoftTeamsCache -UsbRoot $usbRoot -CanonicalRoot $acquireRoot
                    Write-PreInstallLog -Event 'BuiltInRefreshComplete' -Message 'Microsoft Teams content is ready for installation.' -Data @{Id='MicrosoftTeams';Version=$version;PackageUpdated=$updated;CacheSynchronized=[bool]$usbRoot;SourcePolicy='Evergreen';SyncMethod='HttpMetadata';DurationSeconds=[math]::Round($builtInStopwatch.Elapsed.TotalSeconds,1)}
                } catch {
                    if($transactionRoot -and(Test-Path -LiteralPath $transactionRoot)){Remove-Item -LiteralPath $transactionRoot -Recurse -Force -ErrorAction SilentlyContinue}
                    if($backupRoot -and(Test-Path -LiteralPath $backupRoot -PathType Container)-and-not(Test-Path -LiteralPath $acquireRoot)){Move-Item -LiteralPath $backupRoot -Destination $acquireRoot -ErrorAction SilentlyContinue}
                    if(Test-LocalMicrosoftTeamsSource -Root $localRoot){Assert-PreInstallSignedPayload -Id 'MicrosoftTeams' -Path (Join-Path $localRoot 'teamsbootstrapper.exe');Write-PreInstallLog -Event 'BuiltInRefreshFailed' -Level 'Warning' -Message $_.Exception.Message -Data @{Id='MicrosoftTeams';Fallback='ExistingStagedPayload'};continue}
                    throw "Microsoft Teams acquisition failed and no staged fallback is available. $($_.Exception.Message)"
                }
            }
            'AdobeAcrobatUnified' {
                $architecture=if($app.Architecture){[string]$app.Architecture}else{'x64'}
                $localRoot=Join-Path $StagedPath (Join-Path 'BuiltIn\AdobeAcrobatUnified' $architecture)
                New-Item -ItemType Directory -Path $localRoot -Force | Out-Null
                $acquireRoot=if($usbRoot){Join-Path $usbRoot (Join-Path 'BuiltIn\AdobeAcrobatUnified' $architecture)}else{$localRoot}
                if($usbRoot){Restore-PreInstallBuiltInCache -Root $acquireRoot -Id 'AdobeAcrobatUnified'}
                New-Item -ItemType Directory -Path $acquireRoot -Force | Out-Null

                if($usbRoot -and -not (Test-LocalAdobeAcrobatUnifiedSource -Root $localRoot) -and (Test-LocalAdobeAcrobatUnifiedSource -Root $acquireRoot)){
                    Copy-Item -LiteralPath (Join-Path $acquireRoot 'Package.zip') -Destination (Join-Path $localRoot 'Package.zip') -Force
                    if(Test-Path -LiteralPath (Join-Path $acquireRoot 'CacheInfo.json') -PathType Leaf){Copy-Item -LiteralPath (Join-Path $acquireRoot 'CacheInfo.json') -Destination (Join-Path $localRoot 'CacheInfo.json') -Force}
                    Write-PreInstallLog -Event 'BuiltInCacheRestaged' -Message 'Existing Adobe Acrobat Unified USB cache was staged locally.' -Data @{Id='AdobeAcrobatUnified'}
                }

                if(-not $networkAvailable){
                    if(Test-LocalAdobeAcrobatUnifiedSource -Root $localRoot){
                        Write-PreInstallLog -Event 'BuiltInRefreshSkipped' -Level 'Warning' -Message 'No network is available. Existing staged Adobe Acrobat Unified payload will be used.' -Data @{Id='AdobeAcrobatUnified'}
                        continue
                    }
                    throw 'Adobe Acrobat Unified has no staged or USB-cached payload and no network connection is available to acquire one.'
                }

                $transactionRoot=$null;$backupRoot=$null
                try {
                    $packageUri=if($app.PackageUri){[string]$app.PackageUri}else{switch($architecture){'x86'{'https://trials.adobe.com/AdobeProducts/APRO/Acrobat_HelpX/win32/Acrobat_DC_Web_WWMUI.zip'}default{'https://trials.adobe.com/AdobeProducts/APRO/Acrobat_HelpX/win32/Acrobat_DC_Web_x64_WWMUI.zip'}}}
                    $cacheInfoPath=Join-Path $acquireRoot 'CacheInfo.json'
                    $cacheInfo=$null
                    if(Test-Path -LiteralPath $cacheInfoPath -PathType Leaf){try{$cacheInfo=Get-Content -LiteralPath $cacheInfoPath -Raw -Encoding UTF8 | ConvertFrom-Json}catch{}}
                    $packagePath=Join-Path $acquireRoot 'Package.zip'

                    Write-PreInstallLog -Event 'BuiltInRefreshStart' -Message 'Checking Adobe Acrobat Unified cache for updates.' -Data @{Id='AdobeAcrobatUnified';Target=if($usbRoot){'USB'}else{'Local'}}

                    $remote=Get-RemoteMetadata -Uri $packageUri
                    $matches=$false
                    if((Test-Path -LiteralPath $packagePath -PathType Leaf) -and $cacheInfo){
                        if($remote.ETag -and $cacheInfo.RemoteETag){
                            $matches=$remote.ETag -eq [string]$cacheInfo.RemoteETag
                        }
                        elseif($remote.LastModified -and $cacheInfo.RemoteLastModified -and $remote.ContentLength -and $cacheInfo.RemoteContentLength){
                            $matches=($remote.LastModified -eq [string]$cacheInfo.RemoteLastModified -and [int64]$remote.ContentLength -eq [int64]$cacheInfo.RemoteContentLength)
                        }
                    }

                    $updated=$false;$generationRoot=$acquireRoot
                    if(-not $matches){
                        Assert-OSDAppTransactionSpace -Path $acquireRoot -ExistingPath $acquireRoot -ExpectedBytes ([double]$remote.ContentLength) -MinimumFreeSpaceGB 3 -Operation 'Adobe Acrobat Unified cache refresh' | Out-Null
                        $transactionRoot="$acquireRoot.osdapps-new-$([guid]::NewGuid().ToString('N'))";$backupRoot="$acquireRoot.osdapps-old-$([guid]::NewGuid().ToString('N'))"
                        New-Item -ItemType Directory -Path $transactionRoot -Force|Out-Null;$generationRoot=$transactionRoot;$packagePath=Join-Path $generationRoot 'Package.zip'
                        Save-PreInstallDownload -Uri $packageUri -DestinationPath $packagePath -Id 'AdobeAcrobatUnified' -Description "Adobe Acrobat Unified $architecture package" -TimeoutMinutes 30
                        $updated=$true
                    }

                    $cacheInfoPath=Join-Path $generationRoot 'CacheInfo.json'
                    [ordered]@{
                        Id='AdobeAcrobatUnified'
                        Cached=[bool]$usbRoot
                        Version='Current'
                        Architecture=$architecture
                        SourcePolicy='Evergreen'
                        SyncMethod='HttpMetadata'
                        Updated=$updated
                        PackageUri=$packageUri
                        RemoteETag=$remote.ETag
                        RemoteLastModified=$remote.LastModified
                        RemoteContentLength=$remote.ContentLength
                        RemoteFinalUri=$remote.FinalUri
                        SyncedAt=(Get-Date).ToUniversalTime().ToString('o')
                    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $cacheInfoPath -Encoding UTF8

                    if($transactionRoot){
                        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue;$archive=$null
                        try{$archive=[System.IO.Compression.ZipFile]::OpenRead($packagePath);if($archive.Entries.Count -eq 0){throw 'Adobe candidate ZIP is empty.'}}finally{if($archive){$archive.Dispose()}}
                        $validatedInfo=Get-Content -LiteralPath $cacheInfoPath -Raw -Encoding UTF8|ConvertFrom-Json;if([string]$validatedInfo.Id -ne 'AdobeAcrobatUnified'){throw 'Adobe candidate metadata is inconsistent.'}
                        $hadPrevious=Test-Path -LiteralPath $acquireRoot -PathType Container;if($hadPrevious){Move-Item -LiteralPath $acquireRoot -Destination $backupRoot -ErrorAction Stop}
                        try{Move-Item -LiteralPath $transactionRoot -Destination $acquireRoot -ErrorAction Stop}catch{if($hadPrevious -and(Test-Path -LiteralPath $backupRoot -PathType Container)-and-not(Test-Path -LiteralPath $acquireRoot)){Move-Item -LiteralPath $backupRoot -Destination $acquireRoot -ErrorAction SilentlyContinue};throw}
                        if(Test-Path -LiteralPath $backupRoot -PathType Container){Remove-Item -LiteralPath $backupRoot -Recurse -Force};$transactionRoot=$null;Remove-PreInstallTransactionResidue -Root $acquireRoot;$packagePath=Join-Path $acquireRoot 'Package.zip';$cacheInfoPath=Join-Path $acquireRoot 'CacheInfo.json'
                    }

                    if($usbRoot){
                        Copy-Item -LiteralPath $packagePath -Destination (Join-Path $localRoot 'Package.zip') -Force
                        Copy-Item -LiteralPath $cacheInfoPath -Destination (Join-Path $localRoot 'CacheInfo.json') -Force
                    }

                    Write-PreInstallLog -Event 'BuiltInRefreshComplete' -Message 'Adobe Acrobat Unified content is ready for installation.' -Data @{Id='AdobeAcrobatUnified';PackageUpdated=$updated;CacheSynchronized=[bool]$usbRoot;SourcePolicy='Evergreen';SyncMethod='HttpMetadata';DurationSeconds=[math]::Round($builtInStopwatch.Elapsed.TotalSeconds,1)}
                }
                catch {
                    if($transactionRoot -and(Test-Path -LiteralPath $transactionRoot)){Remove-Item -LiteralPath $transactionRoot -Recurse -Force -ErrorAction SilentlyContinue}
                    if($backupRoot -and(Test-Path -LiteralPath $backupRoot -PathType Container)-and-not(Test-Path -LiteralPath $acquireRoot)){Move-Item -LiteralPath $backupRoot -Destination $acquireRoot -ErrorAction SilentlyContinue}
                    if(Test-LocalAdobeAcrobatUnifiedSource -Root $localRoot){
                        Write-PreInstallLog -Event 'BuiltInRefreshFailed' -Level 'Warning' -Message $_.Exception.Message -Data @{Id='AdobeAcrobatUnified';Fallback='ExistingStagedPayload'}
                        continue
                    }
                    throw "Adobe Acrobat Unified acquisition failed and no staged fallback is available. $($_.Exception.Message)"
                }
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
                Sync-PreInstallVendorMsi -App $app -RelativeRoot $relativeRoot -PackageUri $packageUri -DisplayName 'Cisco Webex'
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
                Sync-PreInstallVendorMsi -App $app -RelativeRoot $relativeRoot -PackageUri $packageUri -DisplayName 'Google Chrome Enterprise'
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
                Sync-PreInstallVendorMsi -App $app -RelativeRoot $relativeRoot -PackageUri $packageUri -DisplayName 'Mozilla Firefox Enterprise'
            }
            default {
                throw [System.IO.InvalidDataException]::new("Unsupported built-in application Id '$($app.Id)' in the device manifest.")
            }
            }
        }
        catch {
            $applicationErrorRecord = $_
            $applicationError = $applicationErrorRecord.Exception.Message
            $applicationFailureType = Get-PreInstallFailureType -ErrorRecord $applicationErrorRecord
            $fatal = (
                $applicationErrorRecord.Exception -is [System.Security.SecurityException] -or
                $applicationErrorRecord.Exception -is [System.IO.InvalidDataException]
            )
            Write-PreInstallLog -Event 'ApplicationRefreshFailed' -Level 'Error' -Message $applicationError -Data @{
                Id = $app.Id
                FailureType = $applicationFailureType
                ContinueQueue = (-not $fatal)
                DurationSeconds = [math]::Round($builtInStopwatch.Elapsed.TotalSeconds,1)
            }
            if ($fatal) { throw }
        }
        finally {
            if ($builtInStopwatch.IsRunning) { $builtInStopwatch.Stop() }
            $applicationResults.Add([pscustomobject]@{
                Id              = [string]$app.Id
                DisplayName     = if ($app.DisplayName) { [string]$app.DisplayName } else { [string]$app.Id }
                Status          = if ($applicationError) { 'Failed' } else { 'Succeeded' }
                DurationSeconds = [math]::Round($builtInStopwatch.Elapsed.TotalSeconds,1)
                CacheUsed       = [bool]$usbRoot
                FailureType     = $applicationFailureType
                Error           = $applicationError
            })
        }
    }

    $preInstallStopwatch.Stop()
    $failedApplicationCount = @($applicationResults | Where-Object { $_.Status -eq 'Failed' }).Count
    if ($failedApplicationCount -gt 0) {
        $summary = "$failedApplicationCount built-in application(s) could not be prepared; independent applications will continue and no automatic retry is scheduled."
        Write-PreInstallLog -Event 'RefreshCompletedWithErrors' -Level 'Error' -Message $summary -Data @{CacheUsed=[bool]$usbRoot;BuiltInAppCount=@($builtInApps).Count;FailedBuiltInApplicationCount=$failedApplicationCount;DurationSeconds=[math]::Round($preInstallStopwatch.Elapsed.TotalSeconds,1)}
        Write-PreInstallLog -Event 'PreInstallComplete' -Level 'Warning' -Message 'PreInstall completed with application errors. Runner execution may continue for unaffected applications.' -Data @{BuiltInAppCount=@($builtInApps).Count;FailedBuiltInApplicationCount=$failedApplicationCount;DurationSeconds=[math]::Round($preInstallStopwatch.Elapsed.TotalSeconds,1)}
        try { Write-PreInstallResult -Status CompletedWithErrors -FailureType 'ApplicationFailures' -ErrorMessage $summary } catch { Write-PreInstallLog -Event 'ResultWriteFailed' -Level Warning -Message $_.Exception.Message }
        exit 0
    }

    Write-PreInstallLog -Event 'RefreshComplete' -Message 'Built-in acquisition and refresh completed. Installation will continue.' -Data @{CacheUsed=[bool]$usbRoot;DurationSeconds=[math]::Round($preInstallStopwatch.Elapsed.TotalSeconds,1)}
    Write-PreInstallLog -Event 'PreInstallComplete' -Message 'PreInstall completed successfully.' -Data @{BuiltInAppCount=@($builtInApps).Count;DurationSeconds=[math]::Round($preInstallStopwatch.Elapsed.TotalSeconds,1)}
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
    if ($cacheLock) { $cacheLock.Dispose() }
}
