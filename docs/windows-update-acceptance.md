# Windows Update: SetupComplete acceptance test

[Windows Update guide](windows-update.md) · [PR #111](https://github.com/roryvossepoel/OSDStage/pull/111)

Prepared for the next clean PC1 deployment after the 2 November 2026 manual OOBE
acceptance. This is a development build, not the Gallery RC2 module. The module
source is pinned to `c714ceba585eeb26ddad8ad5c8324f1b4595fc8a`; its Windows Update
runtime is identical to the successfully tested `433f6d1` runtime. The newer
revision incorporates current main and records the evidence.

The test performs one scan and installs the eligible selected set. Additional
updates offered after installation or restart are acceptable and do not cause an
automatic second pass. Firmware is included by `-IncludeDrivers`. Keep the test
PC on mains power and connected to the network.

## 1. Launcher: WinPE, after OSDCloud has applied Windows

Use this block in the launcher's OSDStage section before its normal restart to
Windows. It replaces the Gallery-module import for this test. It does not reboot,
run Windows Update in WinPE or restart the OSDCloud installation. Start with a
fresh Windows deployment; do not rerun SetupComplete on the existing OOBE test.

The small acceptance queue contains 7-Zip, a marker file and Windows Update.
You can add your normal apps and configuration at the indicated position. An
earlier individual package failure or skip does not suppress Windows Update;
it still leaves the overall deployment unsuccessful. Inspect Latest.json and
the runtime log if no update report is produced. The cmdlets detect the offline Windows volume;
only add `-WindowsPath` if more than one Windows installation is present.

```powershell
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT')) {
    throw 'Run this staging block in WinPE after OSDCloud, before the first Windows boot.'
}

$testCommit = 'c714ceba585eeb26ddad8ad5c8324f1b4595fc8a'
$testRoot = Join-Path $env:TEMP ('OSDStage-WU-Acceptance-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$zipPath = Join-Path $testRoot 'source.zip'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -UseBasicParsing `
    -Uri "https://github.com/roryvossepoel/OSDStage/archive/$testCommit.zip" `
    -OutFile $zipPath

# Avoid the Expand-Archive module-loading issue seen in this WinPE image.
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $testRoot)
$moduleRoot = Join-Path $testRoot "OSDStage-$testCommit"
Remove-Module OSDStage -Force -ErrorAction SilentlyContinue
Import-Module (Join-Path $moduleRoot 'OSDStage.psd1') -Force -ErrorAction Stop
if (-not (Get-Command Add-OSDStageWindowsUpdate).Parameters.ContainsKey('DriverClass')) {
    throw 'The expected Windows Update test module was not imported.'
}

# Retain staging for inspection. Use the usual OnSuccess setting after acceptance.
Set-OSDStageConfiguration -EnableBuiltIns $true -CleanupMode Never
Add-OSDStage7Zip
Add-OSDStageDirectory -Path '%ProgramData%\OSDStageAcceptance' -Force
Add-OSDStageFile -Path '%ProgramData%\OSDStageAcceptance\BeforeWindowsUpdate.txt' `
    -Content "Configuration applied before Windows Update; test build $testCommit" -Force

# Add any other normal app/configuration staging calls here.

Add-OSDStageWindowsUpdate -IncludeDrivers
$deployment = Test-OSDStageDeployment -ThrowOnFailure
$deployment
"Test build: $testCommit"
"Staging: $($deployment.StagedPath)"
```

`Valid=True` is expected; `OfflineReady=False` and `NetworkRequired=True` are
expected for Windows Update. Do not add `-RequireOfflineReady` or `-ScanOnly` to
this installation test. Let the launcher complete its normal first Windows boot.
The update runtime must not initiate a reboot during SetupComplete. Any later
restart belongs to the existing deployment wrapper at a valid lifecycle point.

## 2. After SetupComplete: read the results in OOBE

Open the elevated native Windows PowerShell console as in the earlier test.
This block reads the default results directory and retained staging; it does not
install, scan or reboot. If your launcher configures another results path, change
`$resultsRoot` to that directory.

```powershell
$ErrorActionPreference = 'Stop'
$resultsRoot = Join-Path $env:ProgramData 'OSDStage\Results'
$deployment = Get-Content (Join-Path $resultsRoot 'Latest.json') -Raw | ConvertFrom-Json
$deployment | Format-List Status, ExpectedPackageCount, SuccessfulPackageCount,
    FailedPackageCount, SkippedPackageCount, RebootRequired
$deployment.Packages | Format-Table Id, Status, ExitCode, RebootRequired,
    WindowsUpdateStatus, WindowsUpdateOutcome -AutoSize

$wuPath = Join-Path $resultsRoot 'WindowsUpdate-Result.json'
if (-not (Test-Path -LiteralPath $wuPath)) {
    throw 'No Windows Update report: inspect the preceding package results and runtime log first.'
}
$wu = Get-Content -LiteralPath $wuPath -Raw | ConvertFrom-Json
$wu | Format-List DeploymentId, Phase, Status, Outcome, SelectionPolicy, ExecutionPolicy,
    IncludeDrivers, DriverClass, ScanOnly, FoundCount, SelectedCount, InstalledCount,
    RebootRequired, InstallationBlockedByReboot, RebootRequested, FurtherScanRequired,
    DurationSeconds, ReleaseBefore, ReleaseAfter, ReleaseUnchanged, Error
$wu.Items | Format-Table Title, Type, DriverClass, Selected, SelectionReason,
    Status, InstallResultCode, InstallHResult -Wrap

$marker = Join-Path $env:ProgramData 'OSDStageAcceptance\BeforeWindowsUpdate.txt'
[pscustomobject]@{
    SameDeployment = ($deployment.DeploymentId -eq $wu.DeploymentId)
    ActualSetupComplete = ($wu.Phase -eq 'LastWithinSetupComplete')
    WindowsUpdateLast = (@($deployment.Packages)[-1].Id -eq 'WindowsUpdate')
    MarkerPresent = (Test-Path -LiteralPath $marker)
    MarkerWrittenBeforeUpdates = $(if (Test-Path -LiteralPath $marker) {
        (Get-Item -LiteralPath $marker).LastWriteTimeUtc -le ([DateTime]$wu.StartedAtUtc).ToUniversalTime()
    } else { $false })
    NoRestartRequested = ($wu.RebootRequested -eq $false)
}
Get-Content -LiteralPath $marker
Get-Content (Join-Path $resultsRoot 'WindowsUpdate-Result.log') -Tail 30
```

Keep `Latest.json`, `WindowsUpdate-Result.json`, `WindowsUpdate-Result.log` and
the runtime log before reinstalling the PC. The marker and retained staging are
test-only. A successful installation with `RebootRequired=True` is valid;
`InstallationBlockedByReboot=True` means the remaining work was deferred because
WUA requires a restart first. `FurtherScanRequired=True` is not an installation
failure and does not cause another pass.

## 3. Acceptance decision

- All earlier app/configuration packages succeeded, the marker exists and Windows
  Update ran last in the same deployment with `Phase=LastWithinSetupComplete`.
- Review the count and individual result of installed, skipped, failed or deferred
  updates. No feature upgrade was selected and `ReleaseUnchanged=True`.
- `RebootRequested=False`; Windows reaches normal OOBE. Check that the launcher's
  own restart behavior still works as designed, without assuming SetupComplete resumes.
- After a later wrapper-controlled or explicit test restart, confirm BIOS and
  important driver versions and the Windows release again. Firmware can apply here.
- Continue through the intended Autopilot handoff. A new read-only scan may offer
  additional driver components; zero remaining updates is not the one-pass contract.

This pinned source procedure passed on PC1 on 3 November 2026; see the
[recorded SetupComplete evidence](windows-update.md#fresh-setupcomplete-and-desktop-acceptance-3-november-2026). Monthly Windows/.NET cumulative servicing,
cooperative timeout/cancellation and other hardware remain separate coverage
items; this PC's current ESD does not prove those cases. Autopilot enrollment
also remains untested on this non-Autopilot device. This procedure pins the
original test source; use the RC3 Gallery package for release-installation acceptance.
