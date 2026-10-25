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
        Write-Host '1. Loading the VisualStudioCode test module...' -ForegroundColor Cyan
        $manifestPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'OSDApps.psd1'
        Remove-Module OSDApps -Force -ErrorAction SilentlyContinue
        $module = Import-Module $manifestPath -Force -PassThru -ErrorAction Stop
        if (-not $module.ExportedFunctions.ContainsKey('Add-OSDAppVisualStudioCode')) { throw 'This source does not include the VisualStudioCode candidate.' }
        $windows = & $module { Resolve-OSDAppWindowsPath }
        $stage = Join-Path $windows 'Windows\Temp\OSDApps'
        if (Test-Path (Join-Path $stage 'DeviceManifest.json')) {
            throw 'An existing deployment queue is present. Use a fresh Windows deployment for this isolated test; nothing was restaged.'
        }
        $testRoot = Join-Path $windows 'ProgramData\OSDApps\Tests'
        New-Item $testRoot -ItemType Directory -Force | Out-Null
        Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $testRoot 'Test-OSDAppsVisualStudioCode.ps1') -Force
        Write-Host '2. Staging VisualStudioCode only and validating deployment integration...' -ForegroundColor Cyan
        Set-OSDAppConfiguration -CleanupMode OnSuccess
        Add-OSDAppVisualStudioCode -Architecture $Architecture -WindowsPath $windows | Format-List
        $check = Test-OSDAppDeployment -WindowsPath $windows -ThrowOnFailure
        if (-not $check.Valid) { throw 'Deployment validation failed.' }
        $manifest = Read-TestRecord (Join-Path $stage 'DeviceManifest.json')
        $apps = @(Get-TestField $manifest 'Apps')
        if ($apps.Count -ne 1 -or $apps[0].Id -ne 'VisualStudioCode') { throw 'Expected exactly one VisualStudioCode entry.' }
        $record = [pscustomobject]@{
            DeploymentId = $manifest.DeploymentId
            ModuleVersion = $module.Version.ToString()
            Architecture = $Architecture
            ExpectedId = 'VisualStudioCode'
            PreflightValid = [bool]$check.Valid
        }
        $record | ConvertTo-Json | Set-Content (Join-Path $testRoot 'VisualStudioCode-Staging.json') -Encoding UTF8
        $record | Format-List
        Write-Host 'VISUAL STUDIO CODE STAGING PASSED - READY FOR REBOOT!' -ForegroundColor Green
        Write-Host 'Keep the USB flash drive attached and the PC online until OOBE. Run wpeutil reboot when ready.'
        return
    }

    if ($winPE) { throw 'Run Validate in full Windows at OOBE.' }
    Write-Host '1. Reading results for the recorded VisualStudioCode deployment...' -ForegroundColor Cyan
    $root = Join-Path $env:ProgramData 'OSDApps'
    $expected = Read-TestRecord (Join-Path $root 'Tests\VisualStudioCode-Staging.json')
    $pre = Read-TestRecord (Join-Path $root 'Results\PreInstall.json')
    $runner = Read-TestRecord (Join-Path $root 'Results\Latest.json')
    $deploymentId = [string](Get-TestField $expected 'DeploymentId')
    if ([string]::IsNullOrWhiteSpace($deploymentId)) { throw 'Missing staging deployment ID.' }
    foreach ($result in @($pre,$runner)) {
        if ([string](Get-TestField $result 'DeploymentId') -ne $deploymentId -or
            [string](Get-TestField $result 'Status') -ne 'Succeeded') { throw 'A phase failed or belongs to a different deployment.' }
        $entries = @(Get-TestField $result 'Apps')
        if ($entries.Count -ne 1 -or [string](Get-TestField $entries[0] 'Id') -ne 'VisualStudioCode' -or
            [string](Get-TestField $entries[0] 'Status') -ne 'Succeeded') { throw 'Expected one successful VisualStudioCode result in each phase.' }
    }
    $installed = @(Get-TestField $runner 'Apps')[0]
    $acquired = @(Get-TestField $pre 'Apps')[0]
    $code = Get-TestField $installed 'ExitCode'
    if ($null -eq $code -or [int]$code -notin @(0,3010)) { throw 'VisualStudioCode installer did not report success.' }
    foreach ($counter in @('FailedAppCount','SkippedAppCount')) {
        $value = Get-TestField $runner $counter
        if ($null -eq $value -or [int]$value -ne 0) { throw "Unexpected result counter: $counter" }
    }
    Write-Host '2. Checking the machine-wide installation...' -ForegroundColor Cyan
    $programFiles = $env:ProgramFiles
    $exe = Join-Path $programFiles 'Microsoft VS Code\Code.exe'
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw "VisualStudioCode executable missing: $exe" }
    $uninstall = @(
        Get-ItemProperty @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*') -ErrorAction SilentlyContinue |
            Where-Object { [string](Get-TestField $_ 'DisplayName') -match '^Microsoft Visual Studio Code(?:\s|$)' }
    )
    if ($uninstall.Count -ne 1) { throw 'Expected one machine-wide VisualStudioCode uninstall entry.' }
    $version = [string](Get-TestField $uninstall[0] 'DisplayVersion')
    $reportedVersion = [string](Get-TestField $installed 'Version')
    if ([string]::IsNullOrWhiteSpace($version)) { throw 'Installed VisualStudioCode registration has no version.' }
    $versionCompared = $reportedVersion -match '^\d+\.\d+\.\d+$'
    if (-not $versionCompared) { throw 'The deployment did not report a concrete release version.' }
    if ($versionCompared -and $version -ne $reportedVersion) { throw 'Installed VisualStudioCode version does not match the deployment result.' }
    $exeVersion = (Get-Item -LiteralPath $exe).VersionInfo.ProductVersion
    if ($exeVersion -notmatch ('^' + [regex]::Escape($reportedVersion) + '(?:$|\s)')) { throw 'Executable version does not match the deployment result.' }
    if (@(Get-Process -Name Code -ErrorAction SilentlyContinue).Count -gt 0) { throw 'The editor is running unexpectedly during OOBE.' }
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
    Write-Host 'VISUAL STUDIO CODE OOBE VALIDATION PASSED!' -ForegroundColor Green
    Write-Host 'Read-only validation. SetupComplete was not rerun. No cache or power settings were changed.'
}
catch {
    Write-Host "VISUAL STUDIO CODE $Phase FAILED: $($_.Exception.Message)" -ForegroundColor Red
    if ($Phase -eq 'Stage') { Write-Host 'Do not reboot on this failed staging result.' }
    throw
}
