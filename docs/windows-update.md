# Windows Update (experimental)

[Documentation](README.md) · [Investigation and acceptance #109](https://github.com/roryvossepoel/OSDStage/issues/109)

This development feature is **not in Gallery 1.0.0-rc2**. Software update installation has
succeeded inside SetupComplete on PC1. Driver installation, cumulative updates
requiring restart, cancellation and Autopilot handoff still require physical acceptance.
Use the reviewed test build, not the Gallery module, for the following commands.

## Stage in WinPE

After OSDCloud applies Windows, add the step alongside your other OSDStage calls:

```powershell
Add-OSDStageWindowsUpdate -ScanOnly
Test-OSDStageDeployment -ThrowOnFailure
```

The runner always moves Windows Update after every other selected package,
regardless of cmdlet order. If an earlier package fails or is skipped, the update
step is skipped. Partial `-Name` runner selections cannot bypass the full queue.
A later call replaces the Windows Update options rather than adding a second pass.

After inspecting the scan report, test installation on the disposable target:

```powershell
Add-OSDStageWindowsUpdate
# Or explicitly include the supported hardware drivers:
Add-OSDStageWindowsUpdate -IncludeDrivers
```

These are alternatives, not two update passes. Staging never updates the WinPE or
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

## Selection policy

| Candidate | Behavior |
| --- | --- |
| Automatic Security Updates, Critical Updates, Definition Updates | Eligible when required metadata and every bundle member pass validation |
| Upgrades, Feature Packs, Service Packs, general Updates and Update Rollups | Excluded; broad classifications can include enablement packages or non-security previews |
| Browse-only/preview offers, interactive software updates, unknown interaction or reboot metadata | Excluded |
| Missing classification on a root offer, conflicting or unrecognized classifications | Skipped with a reason; never inferred safe from a title |
| Software bundle member with a readable category collection but no classification | May use its checked software parent's allowed quality classification; all other member checks still apply |
| Drivers | Off by default |
| Opted-in hardware drivers | Restricted to WUA Networking, Sound and Video classes with recognized PCI/USB/HID/Bluetooth/print hardware identities; HDAUDIO is also allowed for Sound |
| Firmware, BIOS, System, Extension, SoftwareComponent, OtherHardware and unknown driver classes | Excluded |

For root driver offers, `-IncludeDrivers` permits `AutoSelectOnWebSites=False`
when `BrowseOnly=False` and all driver checks pass. Explicit opt-in supplies the
selection decision; it does not make the offer automatically selected by Windows.
Browse-only offers and missing selection flags remain excluded. Software still
requires `AutoSelectOnWebSites=True`, even with drivers enabled.

With explicit driver opt-in, `CanRequestUserInput=True` does not by itself
exclude a driver. OSDStage always sets `ForceQuiet=True` and
`AllowSourcePrompts=False`, with no interactive fallback. If an update cannot
honor quiet installation, WUA can return `WU_E_UH_DOESNOTSUPPORTACTION`; the run
records the HRESULT and stops. Software still rejects UI-capable installers.
See [Microsoft's ForceQuiet contract](https://learn.microsoft.com/en-us/windows/win32/api/wuapi/nf-wuapi-iupdateinstaller2-put_forcequiet).

Multiple otherwise eligible root driver offers with the same hardware ID are
all skipped as `MultipleDriverOffersForHardware` (case-insensitive). OSDStage
does not guess driver ranking from titles or install competing versions in scan
order. Distinct hardware IDs are not proof of distinct physical devices; this
is a conservative duplicate-offer guard, not a full PnP ranking implementation.
The report records `CanRequestUserInput` and `RebootBehavior` for diagnosis.

Classification GUIDs are language-independent. `ConservativeQualityV4` requires
each root offer to have its own allowed classification. A software member with no
classification can use its checked software parent's effective classification,
including through nested software bundles. This is OSDStage's selection policy,
not a claim that WUA populates inherited categories. A null/unreadable category
collection, an explicit unknown or excluded classification, a driver member or
an unclassified root offer is not rescued by this rule. Explicit member
classifications and preview/feature/interactive exclusions are still checked.
Only the selected root offer is passed to the installer, never its binaries
individually. All inspected siblings are recorded, including after a rejection.

Each bundle decision records the actual `ClassificationIds`,
`EffectiveClassificationIds` and `ClassificationSource` (`Own`, `ParentBundle`
or `None`). This distinguishes absent categories from an explicitly excluded
classification when inspecting a result.

Title exclusions are additional checks, not the primary release boundary. This intentionally conservative first
version can skip legitimate updates, including KB5007651 or MSRT if their actual
classification is outside the allowlist. Inspect the report before broadening a
policy; do not enable all `Type='Software'` results or rely on English titles.

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
required for this step, including when application payloads are already cached
on USB. Windows servicing can reuse its own local download cache; OSDStage does
not force a fresh download of identical content. Offline-ready preflight cannot
succeed with this step selected.

## Execution and restart boundary

One scan selects a fixed set. All selected payloads download first, then software
installs before drivers. Download and install results are checked per update;
partial search/download success does not silently become success. An install
failure stops the remaining update work.

Updates that require a restart after installation remain eligible; requiring a
restart is not permission to initiate one. If WUA requires a restart, the report records it and any remaining updates are
deferred. There is no reboot call, OOBE task, background retry or restart loop.
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
selection, while retaining the WUA class and hardware checks. OtherHardware,
System, Extension and Firmware remain excluded. Driver installation is pending.

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
- Opt in to drivers separately; confirm hardware behavior and firmware exclusion.
- Confirm earlier packages finish first and their failures suppress this step.
- Confirm the original Windows release, normal OOBE and Autopilot handoff after
  the wrapper completes. No performance or cross-build guarantee is established yet.

## Primary references

- [WUA search criteria](https://learn.microsoft.com/en-us/windows/win32/api/wuapi/nf-wuapi-iupdatesearcher-search)
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
