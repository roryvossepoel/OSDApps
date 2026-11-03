# RC4: published Gallery acceptance

[Release availability](release-status.md) · [Delivery reports](delivery-report.md) · [Windows Update](windows-update.md) · [Release procedure](releasing.md)

**Accepted on 3 November 2026:** the published `1.0.0-rc4` Gallery package was
staged in WinPE and completed its focused three-entry SetupComplete test on two
physical x64 devices. Both runs succeeded, and the operator subsequently
confirmed the normal OOBE and first-sign-in experience, including Autopilot/Intune
where applicable. Execution evidence and operator confirmation are distinguished
below.

This record complements the earlier
[19-entry component and delivery-report acceptance](delivery-report.md#broad-component-acceptance-3-november-2026).
It records acceptance of the published release candidate; stable `1.0.0` remains
a separate release decision.

## Published package and test profile

A focused acceptance helper ran in WinPE after OSDCloud applied fresh Windows
and before the first Windows boot. It downloaded the published module using
`Save-Module -Name OSDStage -Repository PSGallery -RequiredVersion '1.0.0-rc4'
-AllowPrerelease` into a new isolated temporary directory. It removed any loaded
OSDStage module and explicitly imported the downloaded
`OSDStage\1.0.0\OSDStage.psd1` manifest. Numeric module version `1.0.0` and
prerelease metadata `rc4` were checked before staging.

The same profile was used on both devices:

1. `7Zip`: built-in 7-Zip, x64.
2. `WindowsCapabilities`: add `XPS.Viewer~~~~0.0.1.0`.
3. `WindowsUpdate`: install the selected updates last, with `-IncludeDrivers`
   and `-TimeoutMinutes 60`.

Built-ins were enabled, repository packages were disabled, and
`CleanupMode OnSuccess` was selected. The helper validated the offline Windows
target, rejected existing OSDStage staging, ran the deployment preflight and
recorded the expected three entry IDs. It did not request a restart. The devices
then followed the normal first Windows boot with power, network and the
`OSDCloud` USB connected.

`RC4-Acceptance-Staging.json` records the Gallery source, module version,
prerelease, isolated loaded-module path, profile and deployment ID. The
delivery-report module metadata also records `1.0.0-rc4` for each run.

## Devices and run identity

| Evidence | Dell | Surface |
| --- | --- | --- |
| Model | Dell Pro Micro QCM1250 | Surface Laptop Go 2 |
| Architecture | x64 | x64 |
| Windows release and build | 26H2, 26300.9711 | 26H2, 26300.9711 |
| Deployment ID | `3173bf04-ff82-4822-9078-e9ede68fd11b` | `1f5ab34a-f416-4a71-a136-3435e75e0a47` |
| Module | `1.0.0-rc4` from PSGallery | `1.0.0-rc4` from PSGallery |
| Expected / succeeded entries | 3 / 3 | 3 / 3 |
| Failed / skipped entries | 0 / 0 | 0 / 0 |
| Report checks passed | 8 / 8 | 8 / 8 |

For each device, the staging record, `PreInstall.json`, `Latest.json`,
`WindowsCapabilities-Result.json`, `WindowsUpdate-Result.json` and
`DeliveryReport.json` identify the same deployment. The runtime log confirms the
execution order `7Zip`, `WindowsCapabilities`, `WindowsUpdate`. Report and runner
timestamps, duration, package counts and restart state agree.

The eight successful report checks cover deployment identity, complete package
results, Windows capabilities evidence, recognized terminal package states,
Windows Update evidence, restart evidence, module metadata and cache currency.
The generated HTML and JSON delivery reports were included in the reviewed
evidence. Raw device logs and identifying computer names are not published here.

## Results and timing

These are the durations recorded by OSDStage. PreInstall is measured separately
from the runner; neither duration represents the entire Windows deployment.

| Step | Dell | Surface |
| --- | --- | --- |
| PreInstall acquisition and cache checks | 4.3 s | 7.4 s |
| 7-Zip | 2.4 s | 3.1 s |
| XPS Viewer | 331.3 s (5 min 31.3 s) | 564.1 s (9 min 24.1 s) |
| Windows Update, runner package duration | 210.8 s (3 min 30.8 s) | 185.9 s (3 min 5.9 s) |
| Runner total | 545.5 s (9 min 5.5 s) | 755.2 s (12 min 35.2 s) |
| Windows Update, internal duration | 208.2 s (3 min 28.2 s) | 182.4 s (3 min 2.4 s) |

Both devices installed 7-Zip `26.05` successfully with exit code `0`. The existing
USB payload was validated against the current official release metadata and
reused with `AcquisitionOutcome=CacheReused`. No fallback, offline-cache or
acquisition warning was recorded.

XPS Viewer changed from `NotPresent` to `Installed` on both devices, with exit
code `0`, no timeout and no restart requested by the capability operation. The
previous Surface `0x800f0831` failure was not reproduced. This confirms successful
installation on these two devices and this Windows build; it does not establish
the cause of the earlier failure or a causal fix.

The Surface runner took 209.7 s (3 min 29.7 s) longer overall. Its XPS operation
took 232.8 s (3 min 52.8 s) longer, while its Windows Update package took 24.9 s
less. The extra time within OSDStage was therefore concentrated in XPS Viewer.
The reviewed evidence does not contain the separate vendor driver-pack/MSI
installation logs, so it cannot attribute time before OSDStage to that process.

The runtime logs record successful completion and scheduling of `OnSuccess`
cleanup. They do not independently verify that the staging directory was later
removed.

## Windows Update and restart evidence

| Evidence | Dell | Surface |
| --- | --- | --- |
| Phase | `LastWithinSetupComplete` | `LastWithinSetupComplete` |
| Found / selected / installed | 36 / 36 / 36 | 4 / 4 / 4 |
| Software updates | 3 | 3 |
| Hardware updates | 33, including 3 firmware entries | 1 audio processing driver |
| Status | `Succeeded` | `Succeeded` |
| Outcome | `RebootRequired` | `SelectedUpdatesInstalled` |
| Runner package exit code | `3010` | `0` |
| `RebootRequired` | `True` | `False` |
| `RebootRequested` | `False` | `False` |
| `InstallationBlockedByReboot` | `False` | `False` |
| `FurtherScanRequired` | `True` | `True` |
| `TimedOut` | `False` | `False` |
| `ReleaseUnchanged` | `True` | `True` |

All selected updates reported successful download and installation, with result
code `2` and HRESULT `0` for both operations. No failed, skipped or deferred
update was recorded. Both scans selected software from the KB890830 malicious
software removal tool, KB5007651 Windows Security platform and KB2267602 Defender
security intelligence families. The Surface hardware update was Microsoft
Corporation AudioProcessingObject `1.0.4.7057`.

The Dell still processed 33 hardware updates in this final online pass despite
its earlier driver injection during WinPE. The Surface's single offered hardware
update does not by itself establish the duration or outcome of its earlier
driver-pack installation.

Neither scan offered a cumulative Windows or .NET update. Both recorded the same
Windows release and build before and after the pass. Windows Update content was
acquired through the configured update source, separately from the 7-Zip USB
cache.

Both delivery reports have `ExecutionStatus=Succeeded`, `ErrorPresent=False` and
overall `Status=Attention`:

- Dell: a restart was required, and a follow-up scan was recommended.
- Surface: a follow-up scan was recommended; this Windows Update run did not
  report a restart requirement.

These attention states accurately describe follow-up work after successful
execution. No automatic restart was requested by the recorded Windows Update
runs. The records do not prove that a subsequent restart occurred, that firmware
was applied or which BIOS version was active afterward. They also do not contain
the results of a later update scan.

## Operator confirmation and acceptance scope

The operator explicitly confirmed that both devices reached normal OOBE and a
successful first Windows sign-in, including the Autopilot/Intune path where
applicable. This is operator acceptance in addition to the SetupComplete evidence.
The reviewed archives contain no tenant enrollment logs and do not separately
identify which device was registered for Autopilot. The delivery reports remain
execution reports rather than enrollment certificates.

The published Gallery-to-WinPE-to-SetupComplete path is accepted for this profile
on these two x64 devices. Both XPS operations succeeded and Windows Update ran
last, with the required distinction between a restart being needed and a restart
being requested. The earlier broad component acceptance remains applicable to
its separately documented selections.

Remaining coverage includes an actual cumulative Windows/.NET update offer and
its servicing outcome, additional hardware and ARM64. These successful runs also
do not exercise timeout/cancellation or an earlier package failure. No claim of
fully patched Windows, completed firmware application or universal hardware
acceptance follows from a single update pass. See the
[Windows Update guide](windows-update.md) for the one-pass contract and the
[release procedure](releasing.md) for the separate stable-release decision.
