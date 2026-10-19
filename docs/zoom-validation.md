# Zoom Workplace validation

Zoom Workplace is introduced in OSDApps `0.45.0`. For a source-based validation,
use the exact reviewed commit and its adjacent module; the script does not
replace an installed module. A source candidate may retain the preceding
release version, so record the commit as well as the manifest version.
Gallery testing requires the published release containing the Zoom commands.

## WinPE staging

On a fresh test PC, apply Windows with OSDCloud and remain in WinPE. Download the
reviewed commit ZIP from GitHub and extract it onto the USB flash drive or a local
temporary directory. From the extracted repository root run:

```powershell
.\tools\Test-OSDAppsZoom.ps1 -Phase Stage
```

For a native ARM64 target, explicitly add `-Architecture arm64`. Start with x64.
The script imports its adjacent source module, refuses an existing deployment
queue, stages **only Zoom**, suppresses the desktop shortcut and configures
`DisableZoomOnboarding=1`. It runs deployment preflight and records the deployment
ID. It does not install anything in WinPE, clear the cache or reboot automatically.
A missing cache is allowed: Windows acquires Zoom before installation.

Only after `ZOOM STAGING PASSED - READY FOR REBOOT!`:

```powershell
wpeutil reboot
```

Keep networking available and the USB flash drive connected until OOBE appears.
Only the Zoom cache variant may be acquired/refreshed; other app caches are not
selected for this deployment. Existing Zoom content is preserved if replacement
fails validation. A usable staged fallback can allow installation with a reported
refresh warning; inspect `AcquisitionOutcome` and `RefreshError` as well as success.

## OOBE validation

Open a command prompt with Shift+F10 and run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\ProgramData\OSDApps\Tests\Test-OSDAppsZoom.ps1 -Phase Validate
```

This copy was placed on the OS disk during staging. It needs no module download.
It validates the matching deployment ID, both successful phases, installer exit
code, machine-wide executable and MSI registration/version, absent public desktop
shortcut and runtime cleanup. It does not rerun SetupComplete or start Zoom. The generic MSI runtime may report
`Current` rather than an exact version. In that case `VersionCompared=False` is
explicitly reported; the installed version is read from machine registration.

Send back the result and acquisition details. A second fresh deployment can test
cache reuse. Do not manually rerun SetupComplete on the first PC. After signing
in to a disposable user account, separately verify first-launch behavior; a
successful MSI exit does not prove every Zoom policy or SSO flow works.

## Evidence boundaries

Automated tests cover configuration serialization, staging with and without
cache, publisher decisions, transactional recovery, reuse and PreInstall
acquisition/fallback. Vendor calls and installer processes in unit tests use
fixtures. Live x64 and ARM64 endpoints were checked and the downloaded x64 MSI
certificate organization inspected on 18 October 2026. A physical x64 cold deployment passed on 19 October 2026, including the normal
Windows acquisition and installation path; see [the recorded evidence](testing.md#zoom-workplace-cold-deployment--19-october-2026).
ARM64 deployment, warm reuse and first-user configuration/sign-in checks remain
pending. The upcoming full-app cold deployment is a separate regression test.
