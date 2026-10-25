#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('Stage','Validate')][string]$Phase)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
function Read-TestJson { param([string]$Path) Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
try {
    $winPE = Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT'
    if ($Phase -eq 'Stage') {
        if (-not $winPE -or $env:PROCESSOR_ARCHITECTURE -ne 'AMD64') { throw 'Run Stage in x64 WinPE after OSDCloud, before first boot.' }
        Write-Host '1. Loading the prerequisite candidate...' -ForegroundColor Cyan
        Remove-Module OSDApps -Force -ErrorAction SilentlyContinue
        $module=Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'OSDApps.psd1') -Force -PassThru
        $windows=& $module { Resolve-OSDAppWindowsPath }
        $stage=Join-Path $windows 'Windows\Temp\OSDApps'
        if(Test-Path (Join-Path $stage 'DeviceManifest.json')) { throw 'An existing queue is present. Use a fresh Windows deployment.' }
        $testRoot=Join-Path $windows 'ProgramData\OSDApps\Tests'
        New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
        Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $testRoot 'Test-OSDAppsPrerequisites.ps1') -Force
        Write-Host '2. Staging Visual C++ x86/x64, .NET Runtime x86 and Desktop Runtime x64...' -ForegroundColor Cyan
        Set-OSDAppConfiguration -CleanupMode OnSuccess
        Add-OSDAppVisualCRedist -Architecture x86 -WindowsPath $windows | Format-Table
        Add-OSDAppVisualCRedist -Architecture x64 -WindowsPath $windows | Format-Table
        Add-OSDAppDotNetRuntime -RuntimeType Runtime -Channel 10.0 -Architecture x86 -WindowsPath $windows | Format-Table
        Add-OSDAppDotNetRuntime -RuntimeType Desktop -Channel 10.0 -Architecture x64 -WindowsPath $windows | Format-Table
        $check=Test-OSDAppDeployment -WindowsPath $windows -ThrowOnFailure
        $manifest=Read-TestJson (Join-Path $stage 'DeviceManifest.json')
        $ids=@('VisualCRedist-x86','VisualCRedist-x64','DotNetRuntime-Runtime-10.0-x86','DotNetRuntime-Desktop-10.0-x64')
        if(@($manifest.Apps).Count -ne 4 -or @(Compare-Object $ids @($manifest.Apps.Id)).Count -ne 0) { throw 'Unexpected prerequisite queue.' }
        [pscustomobject]@{DeploymentId=$manifest.DeploymentId;ModuleVersion=$module.Version.ToString();ExpectedIds=$ids;PreflightValid=$check.Valid} |
            ConvertTo-Json | Set-Content (Join-Path $testRoot 'Prerequisites-Staging.json') -Encoding UTF8
        Write-Host 'PREREQUISITES STAGING PASSED - READY FOR REBOOT!' -ForegroundColor Green
        Write-Host 'Keep the USB flash drive attached and the PC online until OOBE. Run wpeutil reboot when ready.'
        return
    }
    if($winPE -or -not [Environment]::Is64BitProcess) { throw 'Run Validate in 64-bit Windows PowerShell at OOBE.' }
    Write-Host '1. Checking correlated deployment results...' -ForegroundColor Cyan
    $root=Join-Path $env:ProgramData 'OSDApps'
    $expected=Read-TestJson (Join-Path $root 'Tests\Prerequisites-Staging.json')
    $pre=Read-TestJson (Join-Path $root 'Results\PreInstall.json')
    $run=Read-TestJson (Join-Path $root 'Results\Latest.json')
    foreach($result in @($pre,$run)) {
        if($result.DeploymentId -ne $expected.DeploymentId -or $result.Status -ne 'Succeeded') { throw 'A deployment phase failed or has a different identity.' }
        if(@($result.Apps).Count -ne 4 -or @(Compare-Object @($expected.ExpectedIds) @($result.Apps.Id)).Count -ne 0 -or @($result.Apps | Where-Object Status -ne 'Succeeded').Count -ne 0) { throw 'Expected four successful prerequisite results.' }
    }
    Write-Host '2. Checking installed runtime registrations and files...' -ForegroundColor Cyan
    $rows=@(foreach($entry in $run.Apps) {
        if($entry.ExitCode -notin @(0,3010) -or [string]$entry.Version -notmatch '^\d+\.\d+\.\d+') { throw "Missing installer success or version: $($entry.Id)" }
        $required=[version]$entry.Version
        if($entry.Id -like 'VisualCRedist-*') {
            $arch=($entry.Id -split '-')[-1]
            $keys=@("HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\$arch","HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\$arch")
            $versions=@(foreach($key in $keys) {
                if(Test-Path $key) { $value=Get-ItemProperty $key; if($value.PSObject.Properties['Installed'] -and $value.Installed -eq 1 -and $value.PSObject.Properties['Version']) { [version](([string]$value.Version).TrimStart('v')) } }
            })
            $installed=$versions | Sort-Object -Descending | Select-Object -First 1
            $folder=if($arch -eq 'x86'){'SysWOW64'}else{'System32'}
            if(-not (Test-Path (Join-Path $env:SystemRoot "$folder\vcruntime140.dll"))) { throw "Missing Visual C++ runtime DLL: $arch" }
        } else {
            $arch=($entry.Id -split '-')[-1]
            $base=if($arch -eq 'x86'){${env:ProgramFiles(x86)}}else{$env:ProgramFiles}
            $dotnet=Join-Path $base 'dotnet\dotnet.exe'
            if(-not (Test-Path $dotnet)) { throw "Missing .NET host: $dotnet" }
            $output=@(& $dotnet --list-runtimes)
            if($LASTEXITCODE -ne 0) { throw '.NET runtime enumeration failed.' }
            $framework=if($entry.Id -like '*-Desktop-*'){'Microsoft.WindowsDesktop.App'}else{'Microsoft.NETCore.App'}
            $versions=@(foreach($line in $output) {if($line -match ('^'+[regex]::Escape($framework)+' (10\.0\.\d+) \[')){[version]$Matches[1]}})
            $installed=$versions | Sort-Object -Descending | Select-Object -First 1
            if($framework -eq 'Microsoft.WindowsDesktop.App') {
                $core=@(foreach($line in $output){if($line -match '^Microsoft.NETCore.App (10\.0\.\d+) \['){[version]$Matches[1]}}) | Sort-Object -Descending | Select-Object -First 1
                if(-not $core -or $core -lt $required) { throw 'Desktop Runtime is missing its required base runtime.' }
            }
        }
        if(-not $installed -or $installed -lt $required) { throw "Installed runtime is missing or older than required: $($entry.Id)" }
        [pscustomobject]@{Id=$entry.Id;RequiredVersion=$required;InstalledVersion=$installed;ExitCode=$entry.ExitCode;Passed=$true}
    })
    $rows | Format-Table -AutoSize
    Write-Host '3. Checking cleanup (up to 30 seconds)...' -ForegroundColor Cyan
    $stage=Join-Path $env:SystemRoot 'Temp\OSDApps';$deadline=(Get-Date).AddSeconds(30)
    do {
        $helpers=@(Get-ChildItem (Join-Path $env:SystemRoot 'Temp') -Filter 'OSDApps-Cleanup-*.cmd' -File)
        $clean=-not (Test-Path $stage) -and $helpers.Count -eq 0
        if($clean){break};Start-Sleep -Seconds 2
    } while((Get-Date) -lt $deadline)
    if(-not $clean){throw 'Staging or cleanup helper remains.'}
    $pre.Apps | Select-Object Id,Status,AcquisitionOutcome,CacheUsed,DurationSeconds | Format-Table -AutoSize
    [pscustomobject]@{DeploymentId=$expected.DeploymentId;ModuleVersion=$expected.ModuleVersion;SuccessfulRuntimes=$rows.Count;PreInstallSeconds=$pre.DurationSeconds;RunnerSeconds=$run.DurationSeconds;StagingRemoved=$clean} | Format-List
    Write-Host 'PREREQUISITES OOBE VALIDATION PASSED!' -ForegroundColor Green
    Write-Host 'Read-only checks. No installation, cache changes or SetupComplete rerun.'
} catch {
    Write-Host "PREREQUISITES $Phase FAILED: $($_.Exception.Message)" -ForegroundColor Red
    if($Phase -eq 'Stage'){Write-Host 'Do not reboot after failed staging.'}
    throw
}
