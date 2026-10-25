Describe 'Launcher staging example process contract' {
    BeforeAll {
        $example = Join-Path (Split-Path $PSScriptRoot -Parent) 'Examples/Stage-OSDApps.ps1'
        $engine = (Get-Process -Id $PID).Path
    }

    It 'returns the expected exit code and stops at <Failure>' -TestCases @(
        @{ Failure = 'None'; ExitCode = 0; Expected = 'Environment,Gallery,Import,Office,Adobe,Chrome,Preflight' }
        @{ Failure = 'Environment'; ExitCode = 1; Expected = 'Environment' }
        @{ Failure = 'Gallery'; ExitCode = 1; Expected = 'Environment,Gallery' }
        @{ Failure = 'Import'; ExitCode = 1; Expected = 'Environment,Gallery,Import' }
        @{ Failure = 'Office'; ExitCode = 1; Expected = 'Environment,Gallery,Import,Office' }
        @{ Failure = 'Adobe'; ExitCode = 1; Expected = 'Environment,Gallery,Import,Office,Adobe' }
        @{ Failure = 'Chrome'; ExitCode = 1; Expected = 'Environment,Gallery,Import,Office,Adobe,Chrome' }
        @{ Failure = 'Preflight'; ExitCode = 1; Expected = 'Environment,Gallery,Import,Office,Adobe,Chrome,Preflight' }
    ) {
        param($Failure, $ExitCode, $Expected)
        $wrapper = Join-Path $TestDrive "$Failure.ps1"
        $trace = Join-Path $TestDrive "$Failure.trace"
        # Exercise the unchanged example in a child process. Replace external
        # actions with trace-only commands: no downloads, staging or reboot.
        $harness = @'
$failure = '__FAILURE__'
$trace = '__TRACE__'
function Invoke-Stub {
    param([string]$Step)
    Add-Content -LiteralPath $trace -Value $Step
    if ($failure -eq $Step) { Write-Error "Simulated $Step failure" }
}
function Test-Path {
    param([string]$LiteralPath)
    Add-Content -LiteralPath $trace -Value 'Environment'
    if ($LiteralPath -ne 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT') { throw 'Unexpected path check.' }
    $failure -ne 'Environment'
}
function Install-Module {
    param($Name, [switch]$Force, [switch]$SkipPublisherCheck)
    if ($Name -ne 'OSDApps' -or -not $Force -or -not $SkipPublisherCheck) { throw 'Wrong Gallery request.' }
    Invoke-Stub Gallery
}
function Import-Module {
    param($Name, [switch]$Force)
    if ($Name -ne 'OSDApps' -or -not $Force) { throw 'Wrong module import.' }
    Invoke-Stub Import
}
function Add-OSDAppMicrosoft365Apps {
    param($Channel, $Language)
    if ($Channel -ne 'MonthlyEnterprise' -or $Language -ne 'en-us') { throw 'Wrong Office options.' }
    Invoke-Stub Office
}
function Add-OSDAppAdobeAcrobatUnified { Invoke-Stub Adobe }
function Add-OSDAppGoogleChromeEnterprise { Invoke-Stub Chrome }
function Test-OSDAppDeployment {
    param([switch]$ThrowOnFailure)
    if (-not $ThrowOnFailure) { throw 'Preflight must terminate on failure.' }
    Invoke-Stub Preflight
    [pscustomobject]@{
        WindowsPath = 'C:\'; DeploymentId = 'test'; AppCount = 3
        Valid = $true; OfflineReady = $false; NetworkRequired = $true
    }
}
& '__EXAMPLE__'
exit $LASTEXITCODE
'@
        $harness = $harness.Replace('__FAILURE__', $Failure).
            Replace('__TRACE__', $trace.Replace("'", "''")).
            Replace('__EXAMPLE__', $example.Replace("'", "''"))
        Set-Content -LiteralPath $wrapper -Value $harness -Encoding UTF8
        # Own the process handle from launch. Start-Process without -Wait followed
        # by Refresh can lose ExitCode on Windows PowerShell 5.1/.NET Framework.
        $child = [System.Diagnostics.Process]::new()
        $child.StartInfo.FileName = $engine
        $child.StartInfo.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $wrapper
        $child.StartInfo.UseShellExecute = $false
        $child.StartInfo.CreateNoWindow = $true
        $child.StartInfo.RedirectStandardOutput = $true
        $child.StartInfo.RedirectStandardError = $true
        $started = $false
        try {
            $started = $child.Start()
            if (-not $started) { throw 'Could not start launcher example test.' }
            $outputTask = $child.StandardOutput.ReadToEndAsync()
            $errorTask = $child.StandardError.ReadToEndAsync()
            if (-not $child.WaitForExit(20000)) { throw 'Launcher example test exceeded its time limit.' }
            $child.ExitCode | Should -Be $ExitCode
            ((Get-Content -LiteralPath $trace) -join ',') | Should -Be $Expected
            $output = $outputTask.GetAwaiter().GetResult()
            if ($ExitCode -eq 0) {
                $output | Should -Match 'OSDApps staging passed'
            } else {
                $output | Should -Not -Match 'OSDApps staging passed'
                $errorTask.GetAwaiter().GetResult() | Should -Match 'Do not reboot'
            }
        }
        finally {
            if ($started -and -not $child.HasExited) { $child.Kill() }
            $child.Dispose()
        }
    }
}
