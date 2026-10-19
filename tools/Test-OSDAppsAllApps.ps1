#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Stage','Validate')][string]$Phase,
    [uri]$CatalogUri
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$requiredVersion = '0.45.0'
$builtInIds = @('Microsoft365Apps','MicrosoftTeams','GoogleChromeEnterprise','MozillaFirefoxEnterprise','CiscoWebex','AdobeAcrobatUnified','ZoomWorkplace')
$repositoryIds = @('NotepadPlusPlus','OmnissaHorizonClient')
$expectedIds = @($builtInIds) + @($repositoryIds)
$backupPath = $null

function Get-TestField {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -ne $property) { $property.Value }
}
function Read-TestRecord {
    param([string]$Path)
    Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}
function Assert-TestIdSet {
    param([object[]]$Entries, [string[]]$Expected, [string]$Context)
    $actual = @($Entries | ForEach-Object { [string](Get-TestField $_ 'Id') })
    if ($actual.Count -ne $Expected.Count -or
        @($actual | Sort-Object -Unique).Count -ne $Expected.Count -or
        @(Compare-Object -ReferenceObject $Expected -DifferenceObject $actual).Count -ne 0) {
        throw "$Context does not contain exactly the expected application IDs."
    }
}

try {
    $winPE = Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT'
    if ($Phase -eq 'Stage') {
        if (-not $winPE) { throw 'Run Stage in WinPE after OSDCloud, before the first Windows boot.' }
        if ($env:PROCESSOR_ARCHITECTURE -ne 'AMD64') { throw 'This nine-application test requires an x64 PC and x64 WinPE.' }
        if (-not $CatalogUri -or $CatalogUri.Scheme -ne 'https') { throw 'Supply the HTTPS repository catalog containing NotepadPlusPlus and OmnissaHorizonClient.' }

        Write-Host '1. Loading OSDApps 0.45.0 from PowerShell Gallery...' -ForegroundColor Cyan
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Install-Module OSDApps -RequiredVersion $requiredVersion -Repository PSGallery -Force -SkipPublisherCheck
        Remove-Module OSDApps -Force -ErrorAction SilentlyContinue
        $module = Import-Module OSDApps -RequiredVersion $requiredVersion -Force -PassThru
        if ($module.Version.ToString() -ne $requiredVersion -or
            -not $module.ExportedFunctions.ContainsKey('Add-OSDAppZoomWorkplace')) {
            throw 'The required Gallery module with Zoom support was not loaded.'
        }
        $windows = & $module { Resolve-OSDAppWindowsPath }
        $stage = Join-Path $windows 'Windows\Temp\OSDApps'
        if (Test-Path -LiteralPath $stage) { throw 'Existing OSDApps staging found. Use a fresh Windows deployment; nothing was cleared.' }

        Write-Host '2. Checking USB, free space and repository availability...' -ForegroundColor Cyan
        $volumes = @(Get-Volume | Where-Object { $_.FileSystemLabel -eq 'OSDCloud' -and $_.DriveLetter })
        if ($volumes.Count -ne 1) { throw 'Expected exactly one mounted OSDCloud USB volume.' }
        $usb = $volumes[0]
        $usbRoot = "$($usb.DriveLetter):\"
        if ($windows.Substring(0,1) -eq [string]$usb.DriveLetter) { throw 'Windows and the USB cache must be on different volumes.' }
        $windowsVolume = Get-Volume -DriveLetter $windows.Substring(0,1)
        if ($usb.SizeRemaining -lt 15GB -or $windowsVolume.SizeRemaining -lt 25GB) {
            throw 'This test requires at least 15 GB free on USB and 25 GB free on the Windows volume, without deleting the previous cache.'
        }
        $catalog = & $module { param($Uri,$Ids) Get-OSDAppCatalogPackages -CatalogUri $Uri -Name $Ids } $CatalogUri $repositoryIds
        foreach ($id in $repositoryIds) {
            $compatible = @($catalog.Packages | Where-Object { $_.Id -eq $id -and $_.Architecture -in @('x64','any') })
            if ($compatible.Count -eq 0) { throw "No compatible repository package found for $id." }
        }

        Write-Host '3. Preserving the previous cache and starting an empty cache...' -ForegroundColor Cyan
        $cache = Join-Path $usbRoot 'OSDApps'
        $testRoot = Join-Path $windows 'ProgramData\OSDApps\Tests'
        New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
        Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $testRoot 'Test-OSDAppsAllApps.ps1') -Force
        if (Test-Path -LiteralPath $cache) {
            $cacheItem = Get-Item -LiteralPath $cache
            if (-not $cacheItem.PSIsContainer -or ($cacheItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                throw 'The cache path must be a normal directory.'
            }
            # WinPE is the isolated test environment. Check for an active cache
            # operation before renaming; do not run another cache tool concurrently.
            $lock = & $module { param($Path) Enter-OSDAppCacheLock -CachePath $Path -Operation 'cold-test cache backup' } $cache
            $lock.Dispose()
            $backupName = 'OSDApps-Backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N')
            $backupPath = Join-Path $usbRoot $backupName
            Rename-Item -LiteralPath $cache -NewName $backupName
            if ((Test-Path -LiteralPath $cache) -or -not (Test-Path -LiteralPath $backupPath -PathType Container)) {
                throw 'The previous cache could not be safely preserved.'
            }
            Write-Host "Previous cache preserved: $backupPath"
        }
        New-Item -ItemType Directory -Path $cache | Out-Null
        if (@(Get-ChildItem -LiteralPath $cache -Force).Count -ne 0) { throw 'The new cache is not empty.' }
        [pscustomobject]@{ CachePath=$cache; PreviousCacheBackup=$backupPath; ModuleVersion=$requiredVersion } |
            ConvertTo-Json | Set-Content (Join-Path $testRoot 'AllApps-Preparation.json') -Encoding UTF8

        Write-Host '4. Staging seven built-ins and two repository applications...' -ForegroundColor Cyan
        Set-OSDAppConfiguration -CatalogUri $CatalogUri -CacheVolumeLabel OSDCloud -CleanupMode OnSuccess
        Add-OSDAppMicrosoft365Apps -Channel MonthlyEnterprise -Language nl-nl -Architecture x64 -WindowsPath $windows | Out-Host
        Add-OSDAppMicrosoftTeams -Architecture x64 -WindowsPath $windows | Out-Host
        Add-OSDAppGoogleChromeEnterprise -Architecture x64 -WindowsPath $windows | Out-Host
        Add-OSDAppMozillaFirefoxEnterprise -Channel Rapid -Language en-US -Architecture x64 -WindowsPath $windows | Out-Host
        Add-OSDAppCiscoWebex -Architecture x64 -WindowsPath $windows | Out-Host
        Add-OSDAppAdobeAcrobatUnified -Architecture x64 -WindowsPath $windows | Out-Host
        Add-OSDAppZoomWorkplace -Architecture x64 -NoDesktopShortcut -ZConfig @{ DisableZoomOnboarding=$true } -WindowsPath $windows | Out-Host
        Add-OSDApp -Name $repositoryIds -WindowsPath $windows | Out-Host

        Write-Host '5. Validating the complete deployment queue...' -ForegroundColor Cyan
        $manifest = Read-TestRecord (Join-Path $stage 'DeviceManifest.json')
        Assert-TestIdSet -Entries @(Get-TestField $manifest 'Apps') -Expected $expectedIds -Context 'Staged queue'
        $preflight = Test-OSDAppDeployment -WindowsPath $windows -MinimumFreeSpaceGB 20 -ThrowOnFailure
        if (-not $preflight.Valid) { throw 'Deployment preflight failed.' }
        $record = [pscustomobject]@{
            TestMode='Cold'; ModuleVersion=$requiredVersion; DeploymentId=$manifest.DeploymentId
            ExpectedIds=$expectedIds; BuiltInIds=$builtInIds; CachePath=$cache
            PreviousCacheBackup=$backupPath; PreflightValid=$true
        }
        $record | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $testRoot 'AllApps-Staging.json') -Encoding UTF8
        $record | Format-List
        Write-Host 'ALL APPS COLD STAGING PASSED - READY FOR REBOOT!' -ForegroundColor Green
        Write-Host 'Keep the USB attached and the PC online until OOBE. Run wpeutil reboot when ready.'
        return
    }

    if ($winPE) { throw 'Run Validate in full Windows at OOBE.' }
    Write-Host '1. Reading the correlated deployment results...' -ForegroundColor Cyan
    $root = Join-Path $env:ProgramData 'OSDApps'
    $expected = Read-TestRecord (Join-Path $root 'Tests\AllApps-Staging.json')
    $pre = Read-TestRecord (Join-Path $root 'Results\PreInstall.json')
    $runner = Read-TestRecord (Join-Path $root 'Results\Latest.json')
    $preApps = @(Get-TestField $pre 'Applications')
    $runApps = @(Get-TestField $runner 'Applications')
    $preApps | Select-Object Id,Status,AcquisitionOutcome,CacheUsed,DurationSeconds,RefreshError,Error | Format-Table -AutoSize
    $runApps | Select-Object Id,Status,DurationSeconds,ExitCode,Error | Format-Table -AutoSize
    $deploymentId = [string](Get-TestField $expected 'DeploymentId')
    if ([string]::IsNullOrWhiteSpace($deploymentId)) { throw 'The staging deployment ID is missing.' }
    foreach ($result in @($pre,$runner)) {
        if ([string](Get-TestField $result 'DeploymentId') -ne $deploymentId -or
            [string](Get-TestField $result 'Status') -ne 'Succeeded') { throw 'A phase failed or belongs to another deployment.' }
    }
    Assert-TestIdSet -Entries $preApps -Expected $builtInIds -Context 'PreInstall results'
    Assert-TestIdSet -Entries $runApps -Expected $expectedIds -Context 'Runner results'
    foreach ($entry in @($preApps) + @($runApps)) {
        if ([string](Get-TestField $entry 'Status') -ne 'Succeeded') { throw "Application failed or skipped: $($entry.Id)" }
    }
    foreach ($entry in $preApps) {
        if ([string](Get-TestField $entry 'AcquisitionOutcome') -ne 'Downloaded' -or
            -not [string]::IsNullOrWhiteSpace([string](Get-TestField $entry 'RefreshError'))) {
            throw "Cold acquisition was not confirmed for $($entry.Id). Inspect acquisition details."
        }
    }
    foreach ($counter in @('FailedApplicationCount','SkippedApplicationCount')) {
        $value = Get-TestField $runner $counter
        if ($null -eq $value -or [int]$value -ne 0) { throw "Unexpected result counter: $counter" }
    }

    Write-Host '2. Checking runtime cleanup (up to 30 seconds)...' -ForegroundColor Cyan
    $stage = Join-Path $env:SystemRoot 'Temp\OSDApps'
    $deadline = (Get-Date).AddSeconds(30)
    do {
        $helpers = @(Get-ChildItem (Join-Path $env:SystemRoot 'Temp') -Filter 'OSDApps-Cleanup-*.cmd' -File)
        $clean = -not (Test-Path $stage) -and $helpers.Count -eq 0
        if ($clean) { break }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)
    if (-not $clean) { throw 'Runtime staging or a cleanup helper remains.' }
    [pscustomobject]@{
        ModuleVersion=$expected.ModuleVersion; TestMode=$expected.TestMode; DeploymentId=$deploymentId
        PreInstallSeconds=$pre.DurationSeconds; RunnerSeconds=$runner.DurationSeconds
        TotalSeconds=[math]::Round(([double]$pre.DurationSeconds + [double]$runner.DurationSeconds),1)
        DownloadedBuiltIns=$preApps.Count; SuccessfulApplications=$runApps.Count
        FailedApplications=0; SkippedApplications=0; StagingRemoved=$clean; CleanupHelperRemoved=$clean
        PreviousCacheBackup=$expected.PreviousCacheBackup
    } | Format-List
    Write-Host 'ALL APPS COLD OOBE VALIDATION PASSED!' -ForegroundColor Green
    Write-Host 'Read-only result and cleanup checks. No SetupComplete rerun. Interactive app behavior and cache health require separate checks.'
}
catch {
    Write-Host "ALL APPS $Phase FAILED: $($_.Exception.Message)" -ForegroundColor Red
    if ($backupPath) { Write-Host "Previous cache remains at: $backupPath" }
    if ($Phase -eq 'Stage') { Write-Host 'Do not reboot or rerun staging after this failed result. Preserve the output for diagnosis.' }
    throw
}
