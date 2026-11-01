# Windows Update (experimental)

[Documentation](README.md) · [Investigation and acceptance #109](https://github.com/roryvossepoel/OSDStage/issues/109)

This development feature is **not in Gallery 1.0.0-rc1**. A native WUA scan has
succeeded inside SetupComplete on PC1; this new asynchronous implementation,
installation, cancellation and Autopilot handoff still require physical acceptance.
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
# Or explicitly include the supported automatic hardware drivers:
Add-OSDStageWindowsUpdate -IncludeDrivers
```

These are alternatives, not two update passes. Staging never updates the WinPE or
preparation computer. Full Windows 11 25H2+ and native 64-bit SYSTEM are required
at execution time. The existing launcher controls the first Windows boot.

## Selection policy

| Candidate | Behavior |
| --- | --- |
| Automatic Security Updates, Critical Updates, Definition Updates | Eligible when required metadata and every bundle member pass validation |
| Upgrades, Feature Packs, Service Packs, general Updates and Update Rollups | Excluded; broad classifications can include enablement packages or non-security previews |
| Optional/preview/interactive updates, mandatory-reboot handlers | Excluded |
| Missing, conflicting or unrecognized metadata, including bundled children | Skipped with a reason; never inferred safe from a title |
| Drivers | Off by default |
| Opted-in automatic hardware drivers | Restricted to Net, Display, Media, HIDClass, Bluetooth, Printer and Image classes with recognized PCI/USB/HID/Bluetooth/print hardware identities |
| Firmware, BIOS, System, Extension, SoftwareComponent and unknown driver classes | Excluded |

Classification GUIDs are language-independent. Title exclusions are additional
checks, not the primary release boundary. This intentionally conservative first
version can skip legitimate updates, including KB5007651 or MSRT if their actual
classification is outside the allowlist. Inspect the report before broadening a
policy; do not enable all `Type='Software'` results or rely on English titles.

OSDStage leaves update sources and policies unchanged: no WSUS bypass, service
registration, target-release policy edits or Setup/OOBE registry changes. It
operates on offers from the configured source, which may include other Microsoft
products. Automatic driver metadata does not establish Intune approval.
Windows Update payloads use Windows servicing's own cache, not the OSDCloud USB
cache. Offline-ready preflight cannot succeed with this step selected.

## Execution and restart boundary

One scan selects a fixed set. All selected payloads download first, then software
installs before drivers. Download and install results are checked per update;
partial search/download success does not silently become success. An install
failure stops the remaining update work.

If WUA requires a restart, the report records it and any remaining updates are
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
- [Asynchronous WUA lifetime](https://learn.microsoft.com/en-us/windows/win32/wua_sdk/guidelines-for-asynchronous-wua-operations)
- [BeginInstall](https://learn.microsoft.com/en-us/windows/win32/api/wuapi/nf-wuapi-iupdateinstaller-begininstall)
- [SetupComplete constraints](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/add-a-custom-script-to-windows-setup)
