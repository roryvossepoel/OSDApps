# Windows Update (experimental)

[Documentation](README.md) · [Investigation and acceptance #109](https://github.com/roryvossepoel/OSDStage/issues/109)

Windows Update staging is included from **1.0.0-rc3**. RC4 also attempts the final
update pass after an earlier individual package fails or is skipped.
See [release availability](release-status.md) for the exact package and publication links.
Fresh x64 SetupComplete acceptance passed on PC1 on 3 November 2026, followed by
normal OOBE completion to a regular-account desktop. Monthly cumulative updates,
Autopilot enrollment, cancellation and additional hardware remain separate field coverage.

For the next clean deployment, use the [pinned SetupComplete acceptance procedure](windows-update-acceptance.md).

## Stage in WinPE

After OSDCloud applies Windows, add the step alongside your other OSDStage calls:

```powershell
Add-OSDStageWindowsUpdate -ScanOnly
Test-OSDStageDeployment -ThrowOnFailure
```

The runner always moves Windows Update after every other selected package,
regardless of cmdlet order. If an earlier individual package fails or is skipped,
Windows Update is still attempted. The earlier failure remains visible and the
deployment result remains unsuccessful. Windows Update's own prerequisite and
restart checks still apply; fatal deployment validation errors still stop the
runner before installation. Partial `-Name` runner selections cannot bypass the full queue.
A later call replaces the Windows Update options rather than adding a second pass.

After inspecting the scan report, test installation on the disposable target:

```powershell
Add-OSDStageWindowsUpdate
# Or explicitly include all driver classes (including firmware):
Add-OSDStageWindowsUpdate -IncludeDrivers
# Or include only these WUA driver classes:
Add-OSDStageWindowsUpdate -IncludeDrivers -DriverClass Networking,Sound,Video
```

These are alternatives, not multiple update passes. Staging never updates the WinPE or
preparation computer. Full Windows 11 25H2+ and native 64-bit SYSTEM are required
at execution time. The existing launcher controls the first Windows boot.

To check the corrected selection on an already installed test PC before another
deployment, run the test build's read-only diagnostic:

```powershell
$selection = .\tools\Test-OSDStageWindowsUpdateSelection.ps1
$selection | Format-List Phase, FoundCount, DefaultSelectedCount,
    WithDriversSelectedCount, DriverSelectedCount, ResultPath
$selection.Items | Format-List Title, DefaultSelected, WithDriversSelected,
    DefaultReason, WithDriversReason, DriverClass, BrowseOnly, AutoSelectOnWebSites
```

It performs one scan and compares default selection with driver opt-in. It does
not download update payloads, accept EULAs, install, change policy or reboot.
The separate JSON report includes the raw `BrowseOnly` and `AutoSelectOnWebSites` flags, driver hardware/class and bundle metadata;
it does not overwrite `WindowsUpdate-Result.json`. Running it during OOBE is
selection evidence only, not a SetupComplete installation acceptance test.

## Manual scan and installation test in OOBE

Use an elevated native 64-bit Windows PowerShell console on the disposable test
PC after the deployment runner has finished. This also works in full Windows;
it is a manual runtime test, not proof of SetupComplete execution.

```powershell
# Read-only by default. Includes all driver classes, including Firmware.
$scan = .\tools\Invoke-OSDStageWindowsUpdateOobeTest.ps1 -IncludeDrivers
$scan | Format-List Status, Outcome, SelectionPolicy, FoundCount, SelectedCount, ResultPath
$scan.Items | Format-Table Title, DriverClass, Selected, SelectionReason -Wrap

# Explicit installation. Performs a fresh scan, so available offers can change.
$result = .\tools\Invoke-OSDStageWindowsUpdateOobeTest.ps1 -IncludeDrivers -Install
$result | Format-List Status, Outcome, InstalledCount, RebootRequired, RebootRequested, Error, ResultPath
$result.Items | Format-Table Title, DriverClass, Status, InstallResultCode -Wrap
```

Both invocations accept `-DriverClass Networking,Sound,Video` to narrow driver
selection. Use the same filter for scan and installation. Reports and adjacent
logs use unique paths under `%ProgramData%\OSDStage\Tests`; deployment results
are preserved. The phase is `ManualOobeTest`, distinct from SetupComplete. The
script neither stages a deployment nor changes OOBE state. It does not request a
restart. Firmware installation can take effect at a later restart.

## Selection policy

`QualityAndDriversV5` uses the following rules:

| Candidate | Behavior |
| --- | --- |
| Automatic Security Updates, Critical Updates, Definition Updates, Updates and Update Rollups | Eligible when required metadata and bundle checks pass; covers applicable Windows, .NET and Defender updates, and MSRT |
| Upgrades, Feature Packs, Service Packs and unknown/conflicting classifications | Excluded |
| Browse-only/nonautomatic software, previews and recognized feature/enablement titles | Excluded |
| Drivers without `-IncludeDrivers` | Excluded |
| Drivers with `-IncludeDrivers` | All WUA classes eligible, including Firmware, System, Extension and OtherHardware; no hardware-prefix allowlist |
| Drivers with an explicit `-DriverClass` list | Only exact WUA class-name matches are eligible (case-insensitive); no wildcard or title inference |
| Missing driver class/classification, unreadable bundles or unknown installation behavior | Skipped with a recorded reason |

`-DriverClass` requires `-IncludeDrivers`. These are WUA classes, not INF setup
classes: for example, WUA may report chipset, Bluetooth or HID drivers as
`OtherHardware`. Inspect the scan before choosing a list. An explicit list is
an inclusion filter, not a separate exclusion parameter.

Driver opt-in permits optional and nonautomatic driver offers; neither
`IsAssigned` nor `AutoSelectOnWebSites` is used to reject them. Raw flags remain
in the report. Software retains its automatic/non-browse-only requirement.
Known preview titles remain excluded for both types.

With explicit driver opt-in, `CanRequestUserInput=True` does not by itself
exclude a driver. OSDStage always sets `ForceQuiet=True` and
`AllowSourcePrompts=False`, with no interactive fallback. If an update cannot
honor quiet installation, WUA can return `WU_E_UH_DOESNOTSUPPORTACTION`; the run
records the HRESULT and stops. Software still rejects UI-capable installers.
See [Microsoft's ForceQuiet contract](https://learn.microsoft.com/en-us/windows/win32/api/wuapi/nf-wuapi-iupdateinstaller2-put_forcequiet).

Distinct offers sharing a hardware ID are no longer discarded or ranked from
their titles. WUA receives the selected offers for installation, software first,
then drivers in discovery order. This does not promise the exact selection of
the Windows Update Settings UI, installation of every offer, or the newest
version per device. Driver version and activation behavior still needs physical
acceptance; a failed installation stops the pass and is recorded.

Classification GUIDs are language-independent. Each root offer requires its own
allowed classification. An unclassified software bundle member can inherit its
checked software parent's classification. Explicit excluded classifications,
missing category collections and excluded member titles still reject the bundle.
Only selected root offers are installed; internal binaries are not installed
separately. `ClassificationIds`, `EffectiveClassificationIds` and
`ClassificationSource` record this decision.

The classification policy excludes feature-upgrade categories. Additional title
checks reject recognized previews/enablement packages; these checks are not a
language-independent guarantee for mislabeled vendor metadata. The source and
existing update policy remain authoritative. Verify release/build after the pass
and again after any later restart.

OSDStage leaves update sources and policies unchanged: no WSUS bypass, service
registration, target-release policy edits or Setup/OOBE registry changes. It
operates on offers from the configured source, which may include other Microsoft
products. Automatic driver metadata does not establish Intune approval.
Driver filtering cannot prove that a normal vendor driver contains no embedded
firmware logic. For a strict no-firmware requirement, leave drivers disabled;
see [Microsoft's firmware distribution guidance](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/updating-device-firmware-using-windows-update).
Windows updates and driver updates are **not cached on the OSDCloud USB drive**.
OSDStage obtains them through the configured Windows Update infrastructure
(Windows Update, Microsoft Update or WSUS, as configured). Network access is
required for this step, including when app payloads are already cached
on USB. Windows servicing can reuse its own local download cache; OSDStage does
not force a fresh download of identical content. Offline-ready preflight cannot
succeed with this step selected.

## Execution and restart boundary

One scan selects a fixed set. All selected payloads download first, then software
installs before drivers. Download and install results are checked per update;
partial search/download success does not silently become success. An install
failure stops the remaining update work.

Updates that require a restart after installation remain eligible; requiring a
restart is not permission to initiate one. `RebootRequired` records that Windows
needs a later restart; this alone does not stop the queue. Before each installation,
OSDStage checks WUA's `RebootRequiredBeforeInstallation`. Only a true prerequisite
defers the remaining queue and sets `InstallationBlockedByReboot=True`. Missing
or unreadable prerequisite metadata fails the run instead of attempting an install.
`ExecutionPolicy=ContinueUntilRebootPrerequisiteV1` identifies this behavior.
There is no reboot call, OOBE task, background retry or restart loop. Pending
restart flags are never cleared or suppressed to continue servicing.
The outer deployment wrapper remains responsible for reboot decisions at a valid
lifecycle point. SetupComplete must not be restarted expecting it to resume.

`-TimeoutMinutes` defaults to 30 per operation (scan, download batch, individual
installation). Progress appears every 15 seconds. On expiry, OSDStage requests
WUA cancellation and waits for completion/cleanup. **This is not a hard wall-clock
limit:** Windows servicing can take longer to stop safely. No installer process
is killed and the wrapper is not released while that WUA job is still active.

## Inspect results after SetupComplete

On the installed test device (default results path):

```powershell
$wu = Get-Content "$env:ProgramData\OSDStage\Results\WindowsUpdate-Result.json" -Raw | ConvertFrom-Json
$wu | Format-List Status, Outcome, FoundCount, SelectedCount, InstalledCount,
    RebootRequired, RebootRequested, FurtherScanRequired, DurationSeconds, Error
$wu.Items | Format-Table Title, Selected, SelectionReason, Status, InstallResultCode -AutoSize
```

`WindowsUpdate-Result.log` records progress. The configured results directory is
used when changed through OSDStage configuration. `Latest.json` also includes the
update outcome and aggregate reboot requirement; package execution success is not
proof that every offered update was installed. `Deferred` and
`FurtherScanRequired` describe the remaining work. A successful pass never claims
that a device is fully patched. Release/build are recorded before and after;
quality revision changes are allowed, a release/base-build change is reported as
failure. Verify the release again after any later wrapper-controlled reboot.

## Acceptance before release

**PC1, 2 November 2026, revision `16d61af`:** the new asynchronous runtime
completed in SetupComplete in 19.1 seconds. It found 34 updates, selected and
installed zero, reported no reboot and retained Windows 26H2 build 26300.9711.
The result was `NoEligibleUpdates`, not successful update installation.
KB5007651 and KB2267602 were Definition Updates but were rejected at bundled
software members. A separate read-only WUA inspection confirmed empty category
collections on the Security platform binary and four Defender binaries.
KB890830 was excluded as Update Rollups. The V2 classification-context correction
has regression coverage for this shape. A read-only OOBE check of revision
`7ca3e27` then selected both software updates and continued excluding KB890830.
All 31 offered drivers were rejected as `NotAutomatic`. The subsequent diagnostic
on revision `6b59446` confirmed `BrowseOnly=False` and `AutoSelectOnWebSites=False`
for all 31. V3 therefore separates explicit driver opt-in from automatic software
selection, while retaining the WUA class and hardware checks. In V3, OtherHardware,
System, Extension and Firmware were excluded. Driver installation was pending.

**PC1 software installation, revision `6b59446`:** 34 found, two selected and
both installed in 41.7 seconds during SetupComplete. KB5007651 (10.0.29680.1000)
and KB2267602 (1.463.94.0) each returned InstallResultCode 2. No reboot was required
or requested; Windows 26H2 build 26300.9711 was unchanged. `FurtherScanRequired`
remained true. This validates this software pass, not cumulative-update servicing,
driver installation, or a claim that the device is fully patched.

- Run scan-only in the actual SetupComplete phase and inspect real classifications,
  bundle metadata and skip reasons, including offered release upgrades.
- Install selected updates; compare per-update results with the installed state.
- Test a cumulative update requiring restart, a pre-existing restart prerequisite,
  no eligible updates, source/network failure and cooperative cancellation.
- Opt in to drivers separately; confirm installed driver versions, class filtering,
  firmware behavior and any pending restart before release.
- Confirm earlier packages finish first. An individual package failure or skip must not suppress Windows Update, and must remain visible in the unsuccessful deployment result.
- Confirm the original Windows release, normal OOBE and Autopilot handoff after
  the wrapper completes. No performance or cross-build guarantee is established yet.

## Primary references

- [WUA search criteria](https://learn.microsoft.com/en-us/windows/win32/api/wuapi/nf-wuapi-iupdatesearcher-search)
- [Reboot required before installation](https://learn.microsoft.com/en-us/windows/win32/api/wuapi/nf-wuapi-iupdateinstaller-get_rebootrequiredbeforeinstallation) (reviewed after the PC1 pending-restart test on 2 November 2026)
- [Classification GUIDs](https://learn.microsoft.com/en-us/powershell/module/updateservices/get-wsusclassification)
- [BundledUpdates API](https://learn.microsoft.com/en-us/windows/win32/api/wuapi/nf-wuapi-iupdate-get_bundledupdates) and [Categories API](https://learn.microsoft.com/en-us/windows/win32/api/wuapi/nf-wuapi-iupdate-get_categories) (reviewed 2 November 2026 after PC1 bundle diagnostics)
- [Asynchronous WUA lifetime](https://learn.microsoft.com/en-us/windows/win32/wua_sdk/guidelines-for-asynchronous-wua-operations)
- [BeginInstall](https://learn.microsoft.com/en-us/windows/win32/api/wuapi/nf-wuapi-iupdateinstaller-begininstall)
- [Restart behavior metadata](https://learn.microsoft.com/en-us/windows/win32/api/wuapi/ne-wuapi-installationrebootbehavior)
- [SetupComplete constraints](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/add-a-custom-script-to-windows-setup)

### V4 driver follow-up (2 November 2026)

The V3 physical run installed two software updates in 35.1 seconds and no
drivers. All five Networking/Sound/Video candidates exposed a non-null behavior
object, `CanRequestUserInput=True` and `RebootBehavior=2`. V4 permits these
opted-in drivers only through the existing quiet installer, adds HDAUDIO for
Sound, records both behavior fields, and skips competing offers for an identical
hardware ID. The two Intel 24.20.0.4/24.70.0.3 offers shared one hardware ID.
Driver installation with V4 remains **unverified on hardware**.

### V5 all-class driver and quality-update test (2 November 2026)

PC1 offered 31 drivers, but `IsAssigned=1` returned none. V5 therefore does not
use that criterion. Explicit driver opt-in now covers all classes, with an
optional exact class allowlist. Firmware is included unless a supplied list
omits its class. Updates and Update Rollups are added for regular quality
servicing. The former blanket rejection of shared hardware IDs is removed.
A separate elevated OOBE test tool defaults to scan-only and requires `-Install`
for changes. The subsequent physical evidence is recorded below. Monthly cumulative-update
servicing remains unverified on hardware.

### Pending restart follow-up (2 November 2026)

PC1's manual OOBE V5 test selected 34 offers (two software and 32 drivers). In
107 seconds it reported successful installation of MSRT KB890830, Defender
platform KB4052623, Dell Monitor 1.0.0.0 and Intel System 10.1.37.7. Each had
InstallResultCode 2 and HRESULT 0. Thirty remaining offers were deferred;
no restart was requested and the Windows release was unchanged. A read-only
probe then showed `SystemInfo.RebootRequired=True` but
`Installer.RebootRequiredBeforeInstallation=False`.

The original stop-on-any-restart rule was too restrictive for this evidence.
The corrected runtime retains the aggregate pending-restart flag while checking
the actual WUA prerequisite before each next install. Tests cover continued
installation with a later restart pending and deferral when WUA genuinely
requires a restart first. The continuation result is recorded below; fresh SetupComplete acceptance
subsequently passed on 3 November 2026.


### Continuation and post-restart evidence (2 November 2026)

With runtime revision `433f6d1`, PC1 installed all 29 offers selected by a fresh
manual OOBE scan in 71.7 seconds. Every item returned InstallResultCode 2 and
HRESULT 0. `Status=Succeeded`, `RebootRequired=True`,
`InstallationBlockedByReboot=False`, `RebootRequested=False` and
`ReleaseUnchanged=True`. The earlier pass had already downloaded content, so this
is not a fresh-download performance benchmark. The result is 29/29 for this scan,
not a claim that every offer from the original 34-item scan installed.

After a user-initiated restart, firmware visibly updated. Active versions were
confirmed: Dell BIOS 1.19.3, Intel Ethernet 12.19.2.66, Intel Wi-Fi 24.70.0.3,
Realtek Audio 6.0.9974.1 and Intel UHD Graphics 32.0.101.7088.
A post-restart scan offered eight more drivers, mostly software/audio components,
with no pending reboot. A later fresh installation scan selected ten drivers
and installed all ten in 35.8 seconds, each with result 2/HRESULT 0, no required
or requested restart. WUA history independently contained those installations;
the Settings UI showed up-to-date but an empty history. The UI difference has
not been explained and is not used as an acceptance gate.

These results support the one-pass boundary: a successful pass means the selected
set completed, not that a future scan must be empty. Driver extensions can create
software-component devices that receive their own updates. This is a plausible
explanation for the later offers, not a verified dependency map for every item.
OSDStage does not rescan or resume after reboot; subsequent servicing belongs to
the normal Windows Update management process. No OOBE restart loop is added.

References reviewed for this follow-up:

- [Component INF files and independently serviced child devices](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/using-a-component-inf-file)
- [Extension INF files](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/using-an-extension-inf-file)
- [WUA history queries](https://learn.microsoft.com/en-us/windows/win32/api/wuapi/nf-wuapi-iupdatesearcher-queryhistory)
- [WUA operation result codes](https://learn.microsoft.com/en-us/windows/win32/api/wuapi/ne-wuapi-operationresultcode)

### Fresh SetupComplete and desktop acceptance (3 November 2026)

Source `c714ceba585eeb26ddad8ad5c8324f1b4595fc8a`, deployment
`5a54004c-5e97-46f9-b237-dda969343b49`, completed 3/3 packages: 7-Zip,
file configuration and Windows Update. There were no failed or skipped packages.
The Windows Update report recorded `Phase=LastWithinSetupComplete`,
`SelectionPolicy=QualityAndDriversV5`,
`ExecutionPolicy=ContinueUntilRebootPrerequisiteV1`, `IncludeDrivers=True`,
and 36 found/selected/installed updates in 265.3 seconds.
`Status=Succeeded`, `Outcome=RebootRequired`, `RebootRequired=True`,
`InstallationBlockedByReboot=False`, `RebootRequested=False`,
`FurtherScanRequired=True`, with no error. The runner correctly treated exit
3010 as success with a restart requirement. Windows remained 26H2, build
26300.9711 (`ReleaseUnchanged=True`).

Independent checks confirmed the same deployment ID, actual SetupComplete phase,
Windows Update last in the queue, and the configuration marker written before
updates. Normal OOBE completed to a desktop with a regular account; this device
was not registered in Autopilot, so enrollment was not tested.

Windows Settings subsequently offered seven updates: a newer Security platform
KB5007651 (10.0.29680.1000 versus the pass's 10.0.29628.1000), four Realtek/Waves
components, and Intel System titles 10.1.37.7 and 30.100.2417.30 already present
in the original pass. The user installed these through Settings and restarted.
The next scan showed up-to-date, with a separate preview offer; the two Intel
titles did not recur. Their initial re-offer cause is unknown: titles alone do
not establish identical update IDs/device targets. The green result includes
this additional Settings round, not just the SetupComplete pass.

BIOS 1.19.3 was already current from the preceding day's test and survived the
Windows reinstall. This run is not new evidence of a firmware flash. Monthly
cumulative Windows/.NET updates were not offered and remain untested in the field.

## Review updates in the delivery report

The automatic [delivery report](delivery-report.md) includes a Windows Update card with correlated totals and individual outcomes from this deployment. `Attention` distinguishes restart/follow-up requirements from installation failure. The report records the SetupComplete pass; it does not trigger another scan or refresh itself after restart. Retain the original `WindowsUpdate-Result.json` and log for diagnostics.
