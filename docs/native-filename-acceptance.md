# Fresh-cache native-filename acceptance

This is the acceptance procedure for PR72, not a published-release instruction.
Do not merge or publish on source checks alone. Do not use the older nine-app
Gallery test, which imports its historical pinned release. Keep the exact same
reviewed candidate commit on the preparation PC and the target USB module copy.

## Source validation on the full-Windows development PC

From the candidate repository directory, with Windows PowerShell 5.1, PowerShell
7, Pester 6.2.0 and PSScriptAnalyzer available in their respective hosts:

```powershell
.\tools\Test-OSDAppsMega.ps1
```

Require both engine reports to pass, no skipped/not-run tests, successful package
build and packaged help validation in CI. The test fixtures simulate installer
content; they do not provision real Appx packages or prove a physical installation.

## Prepare a new cache on full Windows

Use a disposable x64 test PC and a fresh OSDCloud cache. Do not format the boot
media or delete unrelated files. Cache reset is an explicit operator action,
not something the module migrates or performs automatically.

Import the candidate module by its actual local path rather than from Gallery.
For this example, the complete candidate source is in `C:\Work\OSDApps`:

```powershell
$ErrorActionPreference = 'Stop'
Import-Module C:\Work\OSDApps\OSDApps.psd1 -Force
Set-OSDAppConfiguration -CacheVolumeLabel OSDCloud

Sync-OSDAppMicrosoft365Apps -Architecture x64 -Channel MonthlyEnterprise -Language nl-nl
Sync-OSDAppMicrosoftTeams -Architecture x64
Sync-OSDAppGoogleChromeEnterprise -Architecture x64
Sync-OSDAppMozillaFirefoxEnterprise -Architecture x64 -Channel Rapid -Language en-US
Sync-OSDAppAdobeAcrobatUnified -Architecture x64
Sync-OSDAppCiscoWebex -Architecture x64
Sync-OSDAppZoomWorkplace -Architecture x64
Sync-OSDApp7Zip -Architecture x64
Sync-OSDAppVisualStudioCode -Architecture x64
Sync-OSDAppVisualCRedist -Architecture x64
Sync-OSDAppDotNetRuntime -Architecture x64 -Channel 10.0 -RuntimeType Desktop
Sync-OSDAppMicrosoftCompanyPortal -Architecture x64
Sync-OSDAppCMTraceOpen -Architecture x64

Get-OSDAppCache -VerifySignatures |
    Format-Table Id, Version, Valid, SignatureStatus -AutoSize
Test-OSDAppCache -VerifySignatures
```

Stop on any failure. Inspect each recorded vendor filename, hash and byte size.
Company Portal also records the exact license and dependency filenames. Office
keeps its vendor-managed layout and recorded configuration profile. Inbox cleanup
is bundled with the module and has no vendor cache to synchronize.

Copy the complete candidate module to a separate USB folder, for example
`X:\Modules\OSDAppsCandidate`, replacing `X:` with the actual USB drive letter.
Do not mix files from another module version or previous staging.

## Stage on the disposable target in WinPE

Run only after OSDCloud has applied Windows, before its first boot. Replace the
module path with the actual USB path visible in WinPE. These commands must not
run against the preparation PC's Windows installation.

```powershell
$ErrorActionPreference = 'Stop'
if (-not (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT')) {
    throw 'Run this staging block in WinPE on the disposable target.'
}
Import-Module X:\Modules\OSDAppsCandidate\OSDApps.psd1 -Force
Set-OSDAppConfiguration -CacheVolumeLabel OSDCloud -CleanupMode Never

Add-OSDAppVisualCRedist -Architecture x64
Add-OSDAppDotNetRuntime -Architecture x64 -Channel 10.0 -RuntimeType Desktop
Add-OSDAppMicrosoft365Apps -Architecture x64 -Channel MonthlyEnterprise -Language nl-nl
Add-OSDAppMicrosoftTeams -Architecture x64
Add-OSDAppGoogleChromeEnterprise -Architecture x64
Add-OSDAppMozillaFirefoxEnterprise -Architecture x64 -Channel Rapid -Language en-US
Add-OSDAppAdobeAcrobatUnified -Architecture x64
Add-OSDAppCiscoWebex -Architecture x64
Add-OSDAppZoomWorkplace -Architecture x64
Add-OSDApp7Zip -Architecture x64
Add-OSDAppVisualStudioCode -Architecture x64
Add-OSDAppMicrosoftCompanyPortal -Architecture x64
Add-OSDAppCMTraceOpen -Architecture x64
Add-OSDAppWindowsInboxCleanup -Preset Tested13 -DiagnoseOnly

Test-OSDAppDeployment -RequireOfflineReady -ThrowOnFailure
Show-OSDAppUI -Offline
```

This queue contains 14 built-ins. Cleanup runs in diagnosis mode; removal needs a
separate explicit destructive acceptance test. `CleanupMode Never` retains
staging for inspection and does not test automatic successful-stage cleanup.
Inspect every manifest path: it must name the recorded actual vendor file, not
an extension-only placeholder. Close the Viewer, then continue the normal
OSDCloud reboot. Never manually rerun the SetupComplete scripts.

## Required deployment scenarios

| Scenario | Preparation | Required evidence |
| --- | --- | --- |
| Prepared offline | All 13 vendor caches prepared; target networking unavailable during SetupComplete | Exact staged filenames/hashes; successful offline installs and provisioning. Reconnect at OOBE for Autopilot. |
| Prepared online | Same current-format caches on a fresh target | Reuse where vendor metadata permits; any update retains its new vendor filename in both cache and manifest. |
| Cold online | Fresh cache with **only Company Portal and CMTrace Open pre-synchronized** | Other eligible built-ins have null pending payload paths before boot, then exact acquired names after PreInstall. Use preflight without RequireOfflineReady. |
| Fault handling | Synthetic tests only, never execute a deliberately tampered installer | Hash/signature failures stop unsafe execution; missing metadata is not guessed; independent download/installer failures are recorded. |

A successful warm online deployment is not proof of cold acquisition or fully
offline behavior. Use a fresh Windows deployment for each physical scenario.

## Inspect results in deployed Windows

After normal SetupComplete, inspect the correlated reports and retained staging.
This read-only block requires every expected entry and counter, not just a green
top-level status:

```powershell
$ErrorActionPreference = 'Stop'
$result = Get-Content C:\ProgramData\OSDApps\Results\Latest.json -Raw | ConvertFrom-Json
$manifest = Get-Content C:\Windows\Temp\OSDApps\DeviceManifest.json -Raw | ConvertFrom-Json
$expected = @($manifest.Apps.Id)
$actual = @($result.Apps.Id)
if ($result.Status -ne 'Succeeded' -or
    $result.DeploymentId -ne $manifest.DeploymentId -or
    $expected.Count -ne 14 -or $actual.Count -ne 14 -or
    @($actual | Select-Object -Unique).Count -ne 14 -or
    @(Compare-Object $expected $actual).Count -ne 0 -or
    $result.ExpectedAppCount -ne 14 -or $result.SuccessfulAppCount -ne 14 -or
    $result.FailedAppCount -ne 0 -or $result.SkippedAppCount -ne 0 -or
    @($result.Apps | Where-Object Status -ne Succeeded).Count -ne 0) {
    throw 'Deployment acceptance failed. Preserve all reports and logs.'
}
$result.Apps | Format-Table Id, PackageType, Status, ExitCode, Integrity -AutoSize
```

Check installed app versions independently, then sign in through Autopilot and
verify Company Portal registration and app launch. Appx provisioning alone is
not proof of user registration. Inspect `Runtime.log`, `PreInstall.json`,
`Latest.json` and the retained `DeviceManifest.json` together. Record the candidate
commit, device architecture and scenario with every result. ARM64/x86 require
separate physical evidence; do not infer them from this x64 procedure.
