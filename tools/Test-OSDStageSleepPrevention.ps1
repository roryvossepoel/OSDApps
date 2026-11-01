# Run in an elevated Windows PowerShell session on a development PC.
# Exercises the real runtime helper without staging or installing apps.
[CmdletBinding()]
param(
    [string]$HelperPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'Runtime\OSDStageSleepPrevention.ps1'),
    [ValidateRange(1,300)][int]$HoldSeconds = 10,
    [switch]$Child,
    [string]$Reason
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Run this test on Windows.' }
if (-not (Test-Path -LiteralPath $HelperPath -PathType Leaf)) { throw "Runtime helper not found: $HelperPath" }
$HelperPath = (Resolve-Path -LiteralPath $HelperPath).Path
. $HelperPath

if ($Child) {
    $request = Start-OSDStageSleepPrevention -Reason $Reason
    if ($null -eq $request) { throw 'Child power request registration failed.' }
    try { Start-Sleep -Seconds 60 }
    finally { Stop-OSDStageSleepPrevention -Request $request }
    return
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run Windows PowerShell as administrator.'
}

function Test-ProbeRequest {
    param([Parameter(Mandatory)][string]$Text)
    $output = & powercfg.exe /requests 2>&1
    if ($LASTEXITCODE -ne 0) { throw "powercfg /requests failed: $output" }
    return (($output -join "`n").Contains($Text))
}

$results = [System.Collections.Generic.List[object]]::new()
$token = [guid]::NewGuid().ToString('N')
foreach ($scenario in @('NormalCompletion','ControlledFailure','Disabled')) {
    $reasonText = "OSDStage isolated $scenario $token"
    $enabled = $scenario -ne 'Disabled'
    Write-Host "Testing: $scenario" -ForegroundColor Cyan
    $request = Start-OSDStageSleepPrevention -Enabled $enabled -Reason $reasonText
    try {
        $registered = Test-ProbeRequest -Text $reasonText
        if ($enabled -and ($null -eq $request -or -not $registered)) { throw 'Power request was not registered.' }
        if (-not $enabled -and ($null -ne $request -or $registered)) { throw 'Disabled mode created a request.' }
        if ($scenario -eq 'NormalCompletion') {
            Write-Host "Request active for $HoldSeconds seconds. Keep AC power connected."
            Start-Sleep -Seconds $HoldSeconds
        }
        if ($scenario -eq 'ControlledFailure') { throw 'Expected controlled test failure.' }
    }
    catch {
        if ($_.Exception.Message -ne 'Expected controlled test failure.') { throw }
    }
    finally { Stop-OSDStageSleepPrevention -Request $request }

    $released = -not (Test-ProbeRequest -Text $reasonText)
    if (-not $released) { throw "Power request remains after $scenario." }
    $results.Add([pscustomobject]@{
        Scenario=$scenario; RequestRegistered=$registered; RequestReleased=$released
        Passed=($registered -eq $enabled -and $released)
    })
}

Write-Host 'Testing: ForcedTermination (only the isolated child process)' -ForegroundColor Cyan
$reasonText = "OSDStage isolated ForcedTermination $token"
$testScript = $PSCommandPath.Replace("'", "''")
$helperLiteral = $HelperPath.Replace("'", "''")
$command = "& '$testScript' -HelperPath '$helperLiteral' -Child -Reason '$reasonText'"
$encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
$engine = (Get-Process -Id $PID).Path
$diagnostics = Join-Path ([IO.Path]::GetTempPath()) "OSDStage-SleepTest-$token"
New-Item -ItemType Directory -Path $diagnostics -Force | Out-Null
$childProcess = $null
try {
    $childProcess = Start-Process -FilePath $engine -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-EncodedCommand',$encoded) -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $diagnostics 'stdout.log') -RedirectStandardError (Join-Path $diagnostics 'stderr.log')
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $registered = $false
    while ($timer.Elapsed.TotalSeconds -lt 20 -and -not $childProcess.HasExited) {
        $registered = Test-ProbeRequest -Text $reasonText
        if ($registered) { break }
        Start-Sleep -Milliseconds 250
    }
    if (-not $registered) { throw "Child request was not observed. Diagnostics: $diagnostics" }
    $childProcess.Kill()
    if (-not $childProcess.WaitForExit(5000)) { throw 'Isolated child process did not exit within five seconds.' }
    $released = -not (Test-ProbeRequest -Text $reasonText)
    if (-not $released) { throw 'Child power request was not released after process termination.' }
    $results.Add([pscustomobject]@{
        Scenario='ForcedTermination'; RequestRegistered=$registered; RequestReleased=$released; Passed=$released
    })
}
finally {
    if ($null -ne $childProcess) {
        try {
            if (-not $childProcess.HasExited) {
                $childProcess.Kill()
                $null = $childProcess.WaitForExit(5000)
            }
        }
        finally { $childProcess.Dispose() }
    }
}

$results | Format-Table -AutoSize
Write-Host 'OSDStage RUNTIME SLEEP PREVENTION TEST PASSED!' -ForegroundColor Green
Write-Host 'No apps, cache files, deployment manifests or power settings were changed.'
Write-Host "Helper: $HelperPath"
Write-Host "Child diagnostics: $diagnostics"
Write-Host 'This tests request registration and cleanup; it does not prove an actual idle sleep transition.'
