# Combined technical acceptance

Technical stability and one combined deployment come before Viewer work, GitHub
Pages and a possible rename. Earlier operator-confirmed tests remain evidence;
missing retained logs alone are not a reason to reinstall a machine again.
This new run checks interaction between retained features, not whether the earlier
individual tests happened.

## Test boundary

Use one fresh x64 Windows 11 25H2 or later deployment and one pinned module commit.
The profile uses normal USB caching and one SetupComplete run. It does not rename,
clear or prune the cache, force a reboot, schedule retries or repair user settings
after sign-in. The launcher still owns the normal first Windows start.

This is coverage of every retained configuration family with representative apps,
not every installer, architecture, parameter set or failure mode in one run.
Keep full Windows PowerShell 5.1 and PowerShell 7 CI, cache migration/transaction,
failure handling, integrity and secret-cleanup tests as separate release gates.
A successful staging check is not a successful deployment; successful runner
entries are not proof of the rendered desktop or working hardware.

Language-pack injection, regional defaults, time zone and wallpaper/lock-screen
customization are outside this profile and outside the agreed module scope.

## Explicit selections

Choose five distinct repository IDs: one App, one harmless Script, a Font, a
Certificate package and a Driver package. Confirm what each package actually does.
Use the previously tested root certificate and Realtek driver set where available.
Do not substitute a corporate VPN/provisioning script merely to fill the Script
slot. A script fixture can create a harmless marker under `C:\ProgramData\OSDApps\Tests`.
Certificate store selection comes from its repository manifest (machine Root or CA).
The test itself does not choose the store or download a new trust anchor.

Supply an existing supported Wi-Fi XML export locally. It may contain a clear-text
key: keep it outside the repository and do not paste it in reports. The source XML
belongs to the operator; runtime cleanup removes OSDApps' staged copy, not that
source file. This run tests XML input; the parameter-generated variant remains
covered separately. The test PC needs an enabled Wi-Fi adapter and its driver.
Keep wired internet available for capability downloads; importing a Wi-Fi profile
does not prove connectivity or supply internet before that import runs.

## Preparation and staging

1. Run [Prepare-OSDAppsCombinedTest.ps1](../tools/Prepare-OSDAppsCombinedTest.ps1)
   on the preparation PC with the reviewed full commit SHA as `-Revision`.
   It finds the USB volume by label `OSDCloud`, installs an isolated test copy under
   `TestModules`, and returns its `TestPath`. It never imports Gallery OSDApps.
2. Run the returned `Invoke-OSDAppsCombinedTest.ps1` with `-Phase Prepare`,
   `-CatalogUri`, `-AppId`, `-ScriptId`, `-FontId`, `-CertificateId`, `-DriverId`
   and `-WiFiProfilePath`. This validates selections and normally synchronizes the
   selected repository packages, Chrome and Adobe without pruning the existing cache.
3. After OSDCloud applies a fresh Windows image, run that same script in WinPE with
   `-Phase Stage` and the same selections. Resolve the USB label again because its
   drive letter can change. `-WindowsPath` may explicitly identify the applied OS.
   Check the returned validation before continuing with the normal launcher.

Do not add this profile after an existing staging block: it deliberately refuses
existing `Windows\Temp\OSDApps` content. If staging fails midway, do not boot and
call it a complete test. Diagnose the error; no rollback of earlier staged entries
is promised. The script never deletes existing staging to hide that failure.

The profile deliberately uses `CleanupMode OnSuccess`. Runtime results remain
outside staging; failed runs retain diagnostic staging except for secret cleanup.
A small `ProgramData\OSDApps\Tests\Combined-Staging.json` records the commit,
deployment ID, expected IDs and cached versions without Wi-Fi XML or credentials.
These cached versions are preparation evidence, not a promise that the pre-install
refresh will install those exact versions; use the runtime results for that.

## Expected observations

| Area | Selected operation | Acceptance |
| --- | --- | --- |
| Built-in apps | Chrome Enterprise and Acrobat Unified x64 | Both installed; acquisition outcome recorded |
| Repository App and Script | Explicit IDs | App usable; harmless script marker present |
| Fonts | Explicit Font ID | Expected font installed and usable |
| Certificates | Explicit Certificate ID | Expected thumbprint in the manifest-selected LocalMachine store |
| Drivers | Explicit Driver ID | Expected INF/provider present in DriverStore; binding to hardware is separate |
| Registry | Nested empty key, string and DWORD in both 32/64 views | `HKLM\SOFTWARE\OSDApps\Tests\Combined`; Marker names the view, Number = 42 |
| Environment | Set, expandable string, PATH append and removal | Machine OSDAppsMega = CombinedTest; OSDAppsMegaExpanded retains REG_EXPAND_SZ; one PATH entry; seeded OSDAppsMegaRemove absent |
| Services | WSearch Manual/Stopped; Spooler Automatic/Running | Per-operation before/after result; a later Windows state change is separate |
| Optional features | Enable TelnetClient; disable WorkFolders-Client | Per-feature state and any pending restart reported honestly |
| Capabilities | Add XPS.Viewer; remove OpenSSH.Client | Installed / NotPresent; distinguish actual changes from already-correct state |
| Wi-Fi | Supplied all-user profile | Import succeeds; operator can connect; staged XML/config removed |
| Start | Edge, Explorer, Settings | Pins shown at first sign-in; user can change them |
| Taskbar | Settings, Explorer | Selected pins shown; previously accepted additional Outlook pin is recorded if present |
| Inbox apps | Remove Solitaire, BingWeather, BingNews | Absent provisioning; already-absent items are not proof of an actual removal |
| Associations | PDF to Acrobat.Document.DC; HTTP/HTTPS/HTM/HTML to ChromeHTML | Correct initial handlers; user can subsequently change PDF and browser defaults |
| Cleanup | OnSuccess | Owned staging removed; results preserved; USB cache remains usable |

All installers are queued before association import. Registry seeding precedes
variable removal. The environment step does not refresh already-running parent
processes; inspect machine state or a newly started process. The explicit PATH
entry is a test marker and does not install a tool directory.

## Read-only result check

After the normal deployment completes, manually run
[Test-OSDAppsCombinedResult.ps1](../tools/Test-OSDAppsCombinedResult.ps1) from the
same test module. It checks the stored deployment ID, all 16 unique expected
entries, successful states, consistent counters and removal of staging. It rejects
old results, missing entries, duplicate IDs and incomplete cleanup. It does not
perform corrections, create tasks, force a restart or claim visual acceptance.

If runner success appears before asynchronous cleanup finishes, wait for normal
cleanup to finish before repeating this read-only inspection. Do not delete the
stage directory to manufacture a pass. Record the table's manual observations
separately, especially user-editable defaults/pins and Wi-Fi connectivity.

Retain the staging record and the matching `ProgramData\OSDApps\Results` files.
Review logs before sharing. Never archive the entire staging tree or original
Wi-Fi XML as routine test evidence. If a defect is found, fix it and run the
smallest relevant regression test before deciding whether another full deployment
is needed. Viewer, Pages and rename remain deferred until technical acceptance.
