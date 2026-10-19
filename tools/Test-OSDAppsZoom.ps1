#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Stage','Validate')][string]$Phase,
    [ValidateSet('x64','arm64')][string]$Architecture = 'x64'
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
        Write-Host '1. Loading the Zoom test module...' -ForegroundColor Cyan
        $manifestPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'OSDApps.psd1'
        Remove-Module OSDApps -Force -ErrorAction SilentlyContinue
        $module = Import-Module $manifestPath -Force -PassThru -ErrorAction Stop
        if (-not $module.ExportedFunctions.ContainsKey('Add-OSDAppZoomWorkplace')) { throw 'This source does not include the Zoom candidate.' }
        $windows = & $module { Resolve-OSDAppWindowsPath }
        $stage = Join-Path $windows 'Windows\Temp\OSDApps'
        if (Test-Path (Join-Path $stage 'DeviceManifest.json')) {
            throw 'An existing deployment queue is present. Use a fresh Windows deployment for this isolated test; nothing was restaged.'
        }
        $testRoot = Join-Path $windows 'ProgramData\OSDApps\Tests'
        New-Item $testRoot -ItemType Directory -Force | Out-Null
        Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $testRoot 'Test-OSDAppsZoom.ps1') -Force
        Write-Host '2. Staging Zoom only and validating deployment integration...' -ForegroundColor Cyan
        Set-OSDAppConfiguration -CleanupMode OnSuccess
        Add-OSDAppZoomWorkplace -Architecture $Architecture -WindowsPath $windows -NoDesktopShortcut -ZConfig @{ DisableZoomOnboarding = $true } | Format-List
        $check = Test-OSDAppDeployment -WindowsPath $windows -ThrowOnFailure
        if (-not $check.Valid) { throw 'Deployment validation failed.' }
        $manifest = Read-TestRecord (Join-Path $stage 'DeviceManifest.json')
        $apps = @(Get-TestField $manifest 'Apps')
        if ($apps.Count -ne 1 -or $apps[0].Id -ne 'ZoomWorkplace') { throw 'Expected exactly one Zoom entry.' }
        $record = [pscustomobject]@{
            DeploymentId = $manifest.DeploymentId
            ModuleVersion = $module.Version.ToString()
            Architecture = $Architecture
            ExpectedId = 'ZoomWorkplace'
            NoDesktopShortcut = $true
            PreflightValid = [bool]$check.Valid
        }
        $record | ConvertTo-Json | Set-Content (Join-Path $testRoot 'Zoom-Staging.json') -Encoding UTF8
        $record | Format-List
        Write-Host 'ZOOM STAGING PASSED - READY FOR REBOOT!' -ForegroundColor Green
        Write-Host 'Keep the USB flash drive attached and the PC online until OOBE. Run wpeutil reboot when ready.'
        return
    }

    if ($winPE) { throw 'Run Validate in full Windows at OOBE.' }
    Write-Host '1. Reading results for the recorded Zoom deployment...' -ForegroundColor Cyan
    $root = Join-Path $env:ProgramData 'OSDApps'
    $expected = Read-TestRecord (Join-Path $root 'Tests\Zoom-Staging.json')
    $pre = Read-TestRecord (Join-Path $root 'Results\PreInstall.json')
    $runner = Read-TestRecord (Join-Path $root 'Results\Latest.json')
    $deploymentId = [string](Get-TestField $expected 'DeploymentId')
    if ([string]::IsNullOrWhiteSpace($deploymentId)) { throw 'Missing staging deployment ID.' }
    foreach ($result in @($pre,$runner)) {
        if ([string](Get-TestField $result 'DeploymentId') -ne $deploymentId -or
            [string](Get-TestField $result 'Status') -ne 'Succeeded') { throw 'A phase failed or belongs to a different deployment.' }
        $entries = @(Get-TestField $result 'Applications')
        if ($entries.Count -ne 1 -or [string](Get-TestField $entries[0] 'Id') -ne 'ZoomWorkplace' -or
            [string](Get-TestField $entries[0] 'Status') -ne 'Succeeded') { throw 'Expected one successful Zoom result in each phase.' }
    }
    $installed = @(Get-TestField $runner 'Applications')[0]
    $acquired = @(Get-TestField $pre 'Applications')[0]
    $code = Get-TestField $installed 'ExitCode'
    if ($null -eq $code -or [int]$code -notin @(0,3010)) { throw 'Zoom installer did not report success.' }
    foreach ($counter in @('FailedApplicationCount','SkippedApplicationCount')) {
        $value = Get-TestField $runner $counter
        if ($null -eq $value -or [int]$value -ne 0) { throw "Unexpected result counter: $counter" }
    }
    Write-Host '2. Checking the machine-wide installation...' -ForegroundColor Cyan
    $exe = Join-Path $env:ProgramFiles 'Zoom\bin\Zoom.exe'
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw "Zoom executable missing: $exe" }
    $uninstall = @(
        Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' |
            Where-Object { [string](Get-TestField $_ 'DisplayName') -match '^Zoom( Workplace)?(\s*\(.*\))?$' }
    )
    if ($uninstall.Count -ne 1) { throw 'Expected one machine-wide Zoom uninstall entry.' }
    $version = [string](Get-TestField $uninstall[0] 'DisplayVersion')
    $reportedVersion = [string](Get-TestField $installed 'Version')
    if ([string]::IsNullOrWhiteSpace($version)) { throw 'Installed Zoom registration has no version.' }
    $versionCompared = $reportedVersion -match '^\d+(?:\.\d+){1,3}$'
    if ($versionCompared -and $version -ne $reportedVersion) { throw 'Installed MSI version does not match the deployment result.' }
    $shortcuts = @(Get-ChildItem -LiteralPath ([Environment]::GetFolderPath('CommonDesktopDirectory')) -Filter '*Zoom*.lnk' -File)
    if ($shortcuts.Count -ne 0) { throw 'The no-desktop-shortcut setting was not honored.' }

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
        DesktopShortcutAbsent=$true; StagingRemoved=$clean
    } | Format-List
    Write-Host 'ZOOM OOBE VALIDATION PASSED!' -ForegroundColor Green
    Write-Host 'Read-only validation. First-user onboarding and sign-in behavior still require a user-session check.'
}
catch {
    Write-Host "ZOOM $Phase FAILED: $($_.Exception.Message)" -ForegroundColor Red
    if ($Phase -eq 'Stage') { Write-Host 'Do not reboot on this failed staging result.' }
    throw
}
