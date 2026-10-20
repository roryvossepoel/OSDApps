#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Stage','Validate')][string]$Phase,
    [ValidateSet('x64','x86','arm64')][string]$Architecture = 'x64'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-TestField {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -ne $property) { $property.Value }
}
function Read-TestRecord {
    param([string]$Path)
    Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
}

try {
    $winPE = Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT'
    if ($Phase -eq 'Stage') {
        if (-not $winPE) { throw 'Run Stage in WinPE after OSDCloud, before the first Windows boot.' }
        Write-Host '1. Loading the 7Zip test module...' -ForegroundColor Cyan
        $manifestPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'OSDApps.psd1'
        Remove-Module OSDApps -Force -ErrorAction SilentlyContinue
        $module = Import-Module $manifestPath -Force -PassThru -ErrorAction Stop
        if (-not $module.ExportedFunctions.ContainsKey('Add-OSDApp7Zip')) { throw 'This source does not include the 7Zip candidate.' }
        $windows = & $module { Resolve-OSDAppWindowsPath }
        $stage = Join-Path $windows 'Windows\Temp\OSDApps'
        if (Test-Path (Join-Path $stage 'DeviceManifest.json')) {
            throw 'An existing deployment queue is present. Use a fresh Windows deployment for this isolated test; nothing was restaged.'
        }
        $testRoot = Join-Path $windows 'ProgramData\OSDApps\Tests'
        New-Item $testRoot -ItemType Directory -Force | Out-Null
        Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $testRoot 'Test-OSDApps7Zip.ps1') -Force
        Write-Host '2. Staging 7Zip only and validating deployment integration...' -ForegroundColor Cyan
        Set-OSDAppConfiguration -CleanupMode OnSuccess
        Add-OSDApp7Zip -Architecture $Architecture -WindowsPath $windows | Format-List
        $check = Test-OSDAppDeployment -WindowsPath $windows -ThrowOnFailure
        if (-not $check.Valid) { throw 'Deployment validation failed.' }
        $manifest = Read-TestRecord (Join-Path $stage 'DeviceManifest.json')
        $apps = @(Get-TestField $manifest 'Apps')
        if ($apps.Count -ne 1 -or $apps[0].Id -ne '7Zip') { throw 'Expected exactly one 7Zip entry.' }
        $record = [pscustomobject]@{
            DeploymentId = $manifest.DeploymentId
            ModuleVersion = $module.Version.ToString()
            Architecture = $Architecture
            ExpectedId = '7Zip'
            PreflightValid = [bool]$check.Valid
        }
        $record | ConvertTo-Json | Set-Content (Join-Path $testRoot '7Zip-Staging.json') -Encoding UTF8
        $record | Format-List
        Write-Host '7ZIP STAGING PASSED - READY FOR REBOOT!' -ForegroundColor Green
        Write-Host 'Keep the USB flash drive attached and the PC online until OOBE. Run wpeutil reboot when ready.'
        return
    }

    if ($winPE) { throw 'Run Validate in full Windows at OOBE.' }
    Write-Host '1. Reading results for the recorded 7Zip deployment...' -ForegroundColor Cyan
    $root = Join-Path $env:ProgramData 'OSDApps'
    $expected = Read-TestRecord (Join-Path $root 'Tests\7Zip-Staging.json')
    $pre = Read-TestRecord (Join-Path $root 'Results\PreInstall.json')
    $runner = Read-TestRecord (Join-Path $root 'Results\Latest.json')
    $deploymentId = [string](Get-TestField $expected 'DeploymentId')
    if ([string]::IsNullOrWhiteSpace($deploymentId)) { throw 'Missing staging deployment ID.' }
    foreach ($result in @($pre,$runner)) {
        if ([string](Get-TestField $result 'DeploymentId') -ne $deploymentId -or
            [string](Get-TestField $result 'Status') -ne 'Succeeded') { throw 'A phase failed or belongs to a different deployment.' }
        $entries = @(Get-TestField $result 'Applications')
        if ($entries.Count -ne 1 -or [string](Get-TestField $entries[0] 'Id') -ne '7Zip' -or
            [string](Get-TestField $entries[0] 'Status') -ne 'Succeeded') { throw 'Expected one successful 7Zip result in each phase.' }
    }
    $installed = @(Get-TestField $runner 'Applications')[0]
    $acquired = @(Get-TestField $pre 'Applications')[0]
    $code = Get-TestField $installed 'ExitCode'
    if ($null -eq $code -or [int]$code -notin @(0,3010)) { throw '7Zip installer did not report success.' }
    foreach ($counter in @('FailedApplicationCount','SkippedApplicationCount')) {
        $value = Get-TestField $runner $counter
        if ($null -eq $value -or [int]$value -ne 0) { throw "Unexpected result counter: $counter" }
    }
    Write-Host '2. Checking the machine-wide installation...' -ForegroundColor Cyan
    $programFiles = if ($expected.Architecture -eq 'x86' -and ${env:ProgramFiles(x86)}) { ${env:ProgramFiles(x86)} } else { $env:ProgramFiles }
    $exe = Join-Path $programFiles '7-Zip\7zFM.exe'
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw "7Zip executable missing: $exe" }
    $uninstall = @(
        Get-ItemProperty @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*') -ErrorAction SilentlyContinue |
            Where-Object { [string](Get-TestField $_ 'DisplayName') -match '^7-Zip(?:\s|$)' }
    )
    if ($uninstall.Count -ne 1) { throw 'Expected one machine-wide 7Zip uninstall entry.' }
    $version = [string](Get-TestField $uninstall[0] 'DisplayVersion')
    $reportedVersion = [string](Get-TestField $installed 'Version')
    if ([string]::IsNullOrWhiteSpace($version)) { throw 'Installed 7Zip registration has no version.' }
    $versionCompared = $reportedVersion -match '^\d+\.\d+$'
    if (-not $versionCompared) { throw 'The deployment did not report a concrete release version.' }
    if ($versionCompared -and $version -ne $reportedVersion) { throw 'Installed 7Zip version does not match the deployment result.' }
    Write-Host '3. Checking cleanup (up to 30 seconds)...' -ForegroundColor Cyan
    $stage = Join-Path $env:SystemRoot 'Temp\OSDApps'
    $deadline = (Get-Date).AddSeconds(30)
    do {
        $helpers = @(Get-ChildItem (Join-Path $env:SystemRoot 'Temp') -Filter 'OSDApps-Cleanup-*.cmd' -File)
        $clean = -not (Test-Path $stage) -and $helpers.Count -eq 0
        if ($clean) { break }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)
    if (-not $clean) { throw 'Runtime staging or cleanup helper remains.' }
    $acquired | Select-Object Id,Status,AcquisitionOutcome,CacheUsed,RefreshError,DurationSeconds | Format-List
    [pscustomobject]@{
        DeploymentId=$deploymentId; ModuleVersion=$expected.ModuleVersion
        InstalledVersion=$version; ReportedVersion=$reportedVersion; VersionCompared=$versionCompared
        ExecutableVersion=(Get-Item $exe).VersionInfo.FileVersion
        ExitCode=$code; PreInstallSeconds=$pre.DurationSeconds; RunnerSeconds=$runner.DurationSeconds
        StagingRemoved=$clean
    } | Format-List
    Write-Host '7ZIP OOBE VALIDATION PASSED!' -ForegroundColor Green
    Write-Host 'Read-only validation. SetupComplete was not rerun. No cache or power settings were changed.'
}
catch {
    Write-Host "7ZIP $Phase FAILED: $($_.Exception.Message)" -ForegroundColor Red
    if ($Phase -eq 'Stage') { Write-Host 'Do not reboot on this failed staging result.' }
    throw
}
