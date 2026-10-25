# Validation matrix

This page records version-specific maintenance checks and real OSDApps deployment scenarios after OSDCloud applies Windows. **Staging success alone is not an installation success**: the Windows `SetupComplete.cmd` phases must finish and the individual app results must be checked.

For current operating instructions, use [Choose the right check](maintenance.md#choose-the-right-check) and the [online WinPE example](../Examples/WinPE-Online.md). The [0.45.0 all-app cold procedure](all-apps-cold-validation.md) is retained as a historical, version-pinned test; it is not the next required test or a current-release quick start.

## Reading this evidence

- Each dated record applies to its stated version, commit, configuration and hardware. Older results and limitations are retained as history, not silently upgraded to the latest release.
- Source metadata, local cache inspection, release CI and physical installation test different things. A green result in one category does not establish the others.
- Candidate manifest versions can differ from the release that eventually shipped the feature. Keep that distinction when comparing reports.
- There is no new full deployment result claimed here for 0.49.1. Its vendor-source check below is a separate preparation-PC observation.

## Company Portal and CMTrace Open combined x64 candidate — 24–25 October 2026

The operator validated the combined feature-candidate module on **PC1, x64**, after OSDCloud applied Windows. WinPE staged four entries. During the first Windows boot, SetupComplete reported `Status=Succeeded`, `SuccessfulAppCount=4`, `FailedAppCount=0` and `SkippedAppCount=0`, with exit code 0 for each:

| Queue entry | Physical result |
| --- | --- |
| `WindowsInboxCleanup` | Ran as SYSTEM. Three selected packages (`Microsoft.BingWeather`, `Microsoft.MicrosoftSolitaireCollection`, `Microsoft.GamingApp`) removed; no failures or remaining provisioned/registered instances. |
| `MicrosoftCompanyPortal` | Bundle 11.2.1495.0 provisioned with its offline license and five dependencies. `Get-AppxProvisionedPackage` verified provisioning; the operator subsequently confirmed availability for the signed-in Autopilot user. |
| `CMTraceOpen` | MSI 1.6.3 passed SetupComplete SHA-256 and Authenticode validation; installed silently from vendor filename `CMTrace-Open_1.6.3_x64.msi`; exit code 0; Windows uninstall inventory confirmed 1.6.3. |
| `DisplayLinkGraphicsHotDesking` | Separate **repository** package (not a new OSDApps built-in) completed with exit code 0. Repository version was 12.3.5143.0; Windows uninstall entry reported DisplayLink Graphics 12.3.5011.0. No device-attached driver functionality was established. |

The OSDApps runtime log recorded `InstallComplete` and scheduled `CleanupMode=OnSuccess` cleanup; this excerpt did **not** independently confirm cleanup completion.

On **25 October 2026**, a separate full-Windows USB-preparation test validated `Sync-OSDAppMicrosoftCompanyPortal -Architecture x64` **without** `-KitPath`. The synchronizer downloaded the official Microsoft Preinstall Kit directly from `download.microsoft.com`, selected seven cache files, returned `Updated=True` and `CacheReused=False`, and reported version **11.2.1495.0**. The downloaded ZIP's SHA-256 was `2CED91D35BF33CCD9E8E76377BF1F24E41B6238547AB43675955EED1757A8F9B`.

The physical deployment and automatic Microsoft download are **two separate tests**. This evidence does not establish ARM64 behavior, Company Portal interaction with Intune or Store updates, or DisplayLink hardware operation. The eventual release version can differ from the test candidate's internal manifest.

## Windows Inbox Cleanup built-in — 24 October 2026

The opt-in `WindowsInboxCleanup` built-in was exercised on a physical deployment using the PR #65 test module before release version 0.50.0. The operator reported that OSDCloud staging and `Test-OSDAppDeployment -RequireOfflineReady` both succeeded, with `Valid=True` and `OfflineReady=True`.

- During the first Windows boot, SetupComplete ran the built-in as `NT AUTHORITY\SYSTEM` and returned exit code `0`.
- The structured cleanup report recorded `Removed=13`, `Absent=0`, `Skipped=0` and `Failed=0`; checks immediately after execution showed no provisioned or registered instances for the selected packages.
- After completing Autopilot, the operator confirmed the 13 packages remained absent.
- The first candidate failed at startup because `$PSScriptRoot` was evaluated inside a parameter default under `powershell.exe -File`. The corrected candidate deferred the path resolution to the script body and was staged and retested before recording the successful result.
- PR #65 CI run #440 succeeded after the configuration-path fix on Windows PowerShell 5.1 and PowerShell 7.

These observations validate the tested x64 deployment path and chosen 13-package selection; they do not establish all Windows builds, other architectures, alternate selections or deployment combinations. The physical result was reported by the operator; the full device logs are not stored in this repository.

## Vendor source metadata — 23 October 2026

[`Test-OSDApps-VendorSources.ps1`](../tools/Test-OSDApps-VendorSources.ps1) completed on the Windows preparation PC using a temporary Gallery **0.49.1** module: **15 checks passed, 0 failed, 0 cache write operations**. No installer was downloaded or run, and no USB cache was inspected or changed. The [maintenance guide](maintenance.md#check-vendor-source-metadata) describes the selected variants and report fields.

| Metadata source | Advertised version |
| --- | --- |
| Office MonthlyEnterprise x64 descriptor | `16.0.20430.20180` |
| 7Zip x64 stable release | `26.05` |
| Visual Studio Code x64 stable system installer | `1.143.1` |
| .NET 10.0 Runtime x86 / Desktop Runtime x64 | `10.0.13` |

ODT, Teams MSIX/bootstrapper, Adobe, Chrome, Firefox Rapid en-US, Webex, Zoom and VC++ x86/x64 also passed their response/filename checks. Those checks reported `Not exposed by metadata` for the version; no version was inferred from a filename. These values are an observation at test time, not a list of permanently current builds.

This verifies selected source resolution and response metadata, including Office descriptor parsing. It does not validate installer bytes, publisher signatures, local cache integrity, installation or all supported variants. The two test PCs were not redeployed for this check.

## Nine-app cold deployment — 19 October 2026

Gallery **0.45.0**, deployment `7fbcefad-d354-4876-ac7f-64fe85d1c8c5`, passed the correlated all-app OOBE validator on an x64 target. A USB flash drive was attached with a newly empty active cache; the previous cache was retained in a backup directory. Here, **cold means no reusable app content in the active cache, not absence of a USB flash drive**.

- All seven built-ins reported `AcquisitionOutcome=Downloaded`: Office, Teams, Chrome, Firefox, Webex, Adobe and Zoom.
- The runner reported nine successful apps, zero failed and zero skipped. The two repository packages were NotepadPlusPlus and OmnissaHorizonClient; all nine installer results had exit code 0.
- PreInstall took 294.9 seconds and Runner 379.1 seconds, for 674.0 seconds across those two Windows phases.
- Runtime staging and the cleanup helper were removed; the previous-cache backup was retained.

An earlier attempt failed Office acquisition at its 20-minute timeout and skipped Office installation. The successful run above is a separate deployment; it does not turn that failed attempt into a pass or establish its root cause. These result checks do not establish interactive app behavior or complete post-installation cache health.

## Office online warm cache reuse — 19 October 2026

The implementation candidate for 0.45.1 (manifest version 0.45.0, commit `0ed52e56351a21d723751cbfa3e1290c14d9fbb8`) passed a physical x64 deployment with one Microsoft 365 Apps queue entry. The USB flash drive remained attached and the PC stayed online. The requested configuration was MonthlyEnterprise, nl-nl, x64, without an exact build pin.

- A prior read-only check retrieved the 12,461-byte channel descriptor and confirmed that its advertised build and cached build were both `16.0.20430.20180`. Generation, configuration and publisher checks passed; before/after cache hashes were unchanged.
- Deployment `7afbd915-ab22-4304-8845-8c109368172d` reported `AcquisitionOutcome=CacheReused`, `CacheUsed=True`, no refresh error and 0.9 seconds for the Office preparation item.
- PreInstall completed in 4.1 seconds; Runner completed in 151.1 seconds; their measured total was 155.2 seconds.
- The Office installation item completed in 150.6 seconds with exit code 0. Registration and Word, Excel, PowerPoint and Outlook executables matched `16.0.20430.20180`.
- Final status was Succeeded. Runtime staging and the cleanup helper were removed.
- Implementation CI passed 416 tests on each of Windows PowerShell 5.1 and PowerShell 7, with no failures or skips and all 33 packaged help checks passing ([CI run](https://github.com/roryvossepoel/OSDApps/actions/runs/39289473974)).

This validates online build checking, same-build cache reuse, installation and cleanup for the stated configuration. It does not independently validate every Office payload file, Office activation, interactive app behavior, other architectures or every configuration. Release-package validation is separate from this candidate deployment.

## Scenario coverage

This matrix records detailed deployment evidence for the stated versions. The
[recent Gallery workflow reports](#osdapps-0430-gallery-and-online-deployment-reports--16-october-2026)
are listed separately because their evidence is less detailed.

| Scenario | Status | Evidence / expected behavior |
| --- | --- | --- |
| Empty OSDCloud USB app cache, online | **Validated — 0.36.0 cold run (13 Oct 2026)** | The recoverably cleared active cache was repopulated; correlated results reported 8/8 successful, cleanup completed and the final eight-entry cache was healthy. |
| Existing OSDCloud USB cache, online | **Validated — 0.36.0 warm run (13 Oct 2026)** | Hard offline-readiness preflight passed; all six built-ins used cached content, correlated results reported 8/8 successful, cleanup completed and the cache remained healthy. |
| No USB cache, online | **Validated — 0.30.0 test 1** | Built-ins acquired on Windows volume; repository apps staged in WinPE |
| Existing OSDCloud USB cache, offline | **Validated — 0.34.0 PC 2 (11 Oct 2026)** | LAN disconnected; six BuiltInRefreshSkipped events, five built-in signer/publisher checks and 8/8 successful installations. Earlier 0.30.0 six-app test also passed. |
| No USB, offline | **Not yet validated** | Without complete staged content, affected apps cannot install; ordinary acquisition failures are recorded and independent entries may continue. |

## Zoom Workplace cold deployment — 19 October 2026

The operator ran `tools/Test-OSDAppsZoom.ps1` from reviewed commit
`f3532990d84b5ac3441cdedbed6062125a85ccbb` on a fresh x64 Windows deployment.
The candidate still reported module version `0.44.0`; Zoom is introduced in
release `0.45.0`. Deployment ID: `4a3bafa8-c9c8-4b00-9040-24031520df2f`.

| Check | Observed result |
| --- | --- |
| WinPE staging | One ZoomWorkplace entry, x64, `CacheAvailable=False`, `PreflightValid=True`. |
| Windows acquisition | `Succeeded`, `AcquisitionOutcome=Downloaded`, `CacheUsed=True`, no refresh error; acquisition took 6.1 seconds. This was a new download through the USB cache, not a warm reuse. |
| Installation | Exit code 0; machine-wide MSI registration version `7.2.48556`, executable version `7.2.1.48556`. |
| Settings and cleanup | Public desktop shortcut absent; staging and cleanup helper removed by the validation checks. |
| Timing | PreInstall 9.5 seconds; Runner 8.6 seconds; total Windows phases 18.1 seconds. |

The checker reported `ZOOM OOBE VALIDATION PASSED`. The generic MSI result
reported `Current`, so `VersionCompared=False`: registration and executable
versions were observed, not asserted equal to an exact acquisition version.
First-user onboarding, SSO, ARM64 installation and warm-cache reuse remain
unvalidated by this run. It is a single-app cold test, not a full-app regression.

## Office configuration compatibility and deployment — 18 October 2026

These checks used source builds still reporting module version `0.43.0`, prior
to release preparation for `0.44.0`. Office staging/runtime came from merged
commit `3c4a47c3443b72cb08ad3ba1df56b7004fb4adba`. The existing staging was
revalidated with the corrected single-app validator at
`ddb811ca499b3b38338918cf7c81f63e3aaf8a20`, without restaging or changing its manifest.

| Check | Observed result |
| --- | --- |
| Preparation-PC configuration checks | Matching configuration accepted; changed language and added product rejected; licensing-only change accepted. Generation consistency passed. All 33 live cache files were unchanged by the read-only test. |
| WinPE preflight | One Microsoft365Apps entry, x64, MonthlyEnterprise, nl-nl. All required checks passed, including offline readiness, compatible staged profile and matching runtime files. |
| Windows acquisition | `AcquisitionOutcome=Downloaded`, no refresh error. PreInstall succeeded in 172.5 seconds. |
| Installation | Office `16.0.20430.20180`, exit code 0. Registry version and Word, Excel, PowerPoint and Outlook file versions matched. One app succeeded; none failed or were skipped. |
| Completion | Runner succeeded in 144 seconds; total Windows phases 316.5 seconds. Staging and the cleanup helper were removed. |

The correlated deployment ID was `4c2be036-fc59-43af-b2f1-a376d5efa34b`.
This validates the configuration decisions and a real online Office deployment;
it is not a physical incompatible-configuration failure injection, a complete
eight-app regression, or exhaustive verification of every cache payload file.

## OSDApps 0.43.0 Gallery and online deployment reports — 16 October 2026

The operator reported the following checks while using the Gallery-based
workflow. These reports supplement the historical matrix above; they do not
replace its more detailed, correlated result evidence.

| Check | Reported observation | Evidence available |
| --- | --- | --- |
| Gallery import and read-only USB health on the preparation PC | Imported 0.43.0 with 31 exported commands; architecture parameters found. All eight cache entries were active and healthy, with no obsolete, orphaned, renamed, incomplete or corrupt entries. | Pasted summary output with module version, path and cache counts. |
| Online WinPE deployment without a USB flash drive | Office, Adobe Acrobat Unified and Chrome were staged using the short Gallery command flow; the operator reported successful installation after reboot without the USB flash drive. | Operator confirmation in the development conversation. |
| Online WinPE deployment with a USB flash drive | The same command flow succeeded with the USB flash drive connected; the operator confirmed cache use. | Operator confirmation in the development conversation. |

The queue used Office `MonthlyEnterprise` with `nl-nl`, followed by Adobe Acrobat
Unified and Google Chrome Enterprise. The public example uses configurable
`en-us`. The operator also confirmed that module installation in that WinPE
session needed `-SkipPublisherCheck`; the documented install command includes it.

The preceding Gallery check confirmed 0.43.0. No separate deployment result JSON,
deployment IDs, exact loaded-version output, timing measurements or cleanup
checks were supplied for these two installation reports. Do not interpret them
as proof of a cold cache rebuild, a fully offline deployment, all architectures,
or a fresh complete eight-app regression run. Cache use does not by itself prove
that every vendor update check succeeded or that no download occurred.

## OSDApps 0.39.0 cache and deployment validation — 15 October 2026

The candidate from [PR #27](https://github.com/roryvossepoel/OSDApps/pull/27), commit `08206e105daea529893d348f5dfee750160210fa`, passed the following physical checks. These are separate from the automated test suite.

| Check | Observed result |
| --- | --- |
| Isolated transaction and recovery fixtures on USB | Interrupted-swap recovery, preservation of uncommitted candidates, old-generation preservation after build/validation failures, valid promotion and transaction cleanup all passed. |
| Real synchronization of Teams, Chrome, Firefox, Webex and Adobe | All five generations remained valid. All reported `Updated=False`; this run did not exercise a newer vendor download. Office and repository content were unchanged. |
| Freshly applied x64 PC, online with populated USB cache | All eight apps succeeded, with zero failures or skipped entries. All six built-ins used cached content. PreInstall took 89.8 seconds; Runner took 367.6 seconds. Temporary staging and its cleanup helper were removed. |
| Isolated Chrome acquisition, forced replacement and reuse | Two real downloads passed the signature/generation checks. The second replaced the complete test generation and removed its marker and transaction directories. A third sync reused the generation without changing its files. Full before/after fingerprints confirmed the live app cache was unchanged. |

The two Chrome downloads had the same SHA-256 (`2734DC5577DCBAB49BE037E5A074AEF9948FACA14453B52DEFB01224C196A3F5`). Replacement was forced by changing only HTTP freshness metadata in the isolated test cache. This validates actual download and generation replacement, not an upgrade between two different Chrome versions. No app was installed on the preparation machine by that test.

The deployment was a warm-cache integration run, not a cold download run. These checks do not simulate a physical power interruption or prove licensing and every app's later interactive behavior.

## OSDApps 0.37.0 release-candidate validation — 13 October 2026

The 0.37.0 candidate from [PR #25](https://github.com/roryvossepoel/OSDApps/pull/25) was built from commit `2a2b5f364de1efd9341a9728a975e4fe7428d841`. GitHub Actions passed **240/240 tests** on both Windows PowerShell 5.1 and PowerShell 7, verified **31/31** packaged help topics on both engines and reported no blocking analyzer errors ([CI run](https://github.com/roryvossepoel/OSDApps/actions/runs/38405028071)).

### Automated fault-isolation coverage

Five new file-backed scenarios validate the one-shot partial-failure contract:

- an installer exit-code failure is recorded while the next independent repository app still runs once;
- a built-in acquisition failure recorded by PreInstall causes only that built-in to be skipped by Runner while an independent repository app proceeds;
- a selected repository SHA-256 mismatch aborts before any installer executes and marks remaining work skipped;
- a normal PreInstall acquisition failure produces `CompletedWithErrors` without blocking Runner or creating retry state;
- generated SetupComplete integration calls each phase once and contains no RunOnce, scheduled-task or service persistence.

These automated tests also confirm that partial or fatal failure retains staging and suppresses `OnSuccess` cleanup.

### Physical one-shot failure and normal-control pair

Two freshly applied x64 PCs used the same online OSDCloud USB flash drive and the same ordered eight-app queue as the 0.36.0 pair. Both machines loaded the exact 0.37.0 release-candidate module in WinPE, passed pre-reboot validation and retained the USB and network connection through SetupComplete.

On PC 1, only the staged `NotepadPlusPlus` queue slot was replaced with a controlled repository-style failure probe whose installer wrote a marker and exited with code `42`. SetupComplete recorded that entry once as `Failed` with `FailureType=InstallerFailed`, then continued to the following `OmnissaHorizonClient` entry, which succeeded. The final record contained eight results: seven succeeded, one failed and none were skipped. It reported final status `Failed` with `FailureType=AppFailures`; staging and the probe archive were retained, and no scheduled task, service or RunOnce retry was created. Runtime evidence included `AppInstallFailed`, the later Omnissa completion, `InstallCompletedWithErrors` and `CleanupSkipped`.

PC 2 ran the unchanged eight-app queue as a normal control. Correlated PreInstall and Runner records shared deployment ID `4474a976-162c-49b3-8ab3-945b24316ebe` and both reported `Succeeded`. PreInstall completed in **217.1 seconds** and Runner in **359.1 seconds**. All eight apps succeeded, with zero failed and zero skipped. `OnSuccess` removed `C:\Windows\Temp\OSDApps`, the temporary cleanup helper removed itself, and the post-OOBE check found no OSDApps scheduled task, service or RunOnce entry.

Together, these physical runs validate the intended one-shot boundary: an ordinary installer failure is isolated, later independent work still executes during the same SetupComplete pass, the unsuccessful deployment preserves evidence without arranging a retry, and the normal path retains its successful cleanup behavior. This pair does not simulate a power interruption and does not prove licensing, user sign-in or every app's later interactive behavior. Raw device logs and the controlled test package are not committed to the public repository.

## OSDApps 0.36.0 release-candidate validation — 13 October 2026

The 0.36.0 candidate from [PR #24](https://github.com/roryvossepoel/OSDApps/pull/24) was built from commit `03bbd8a2304a4c6f72d1253c0d2c5c4ac9637229` and installed as `E:\Modules\OSDApps\0.36.0`. Its source tree matched the locally reviewed and tested feature tree. GitHub Actions passed **235/235 tests** on both Windows PowerShell 5.1 and PowerShell 7, verified **31/31** packaged help topics on both engines and reported no blocking analyzer errors ([CI run](https://github.com/roryvossepoel/OSDApps/actions/runs/38364310573)).

### Cache health and reconciliation

The populated `E:\OSDApps` cache was first exercised on the full-Windows preparation machine:

- Offline inspection reported eight active entries, no obsolete, orphaned, renamed, incomplete or corrupt entries, and valid SHA-256 evidence for both repository packages.
- Online desired-state inspection against the configured repository catalog reported the same healthy eight-entry state. `Sync-OSDAppRepository -Prune -WhatIf` made no changes.
- A controlled unregistered `Packages\OSDAppsPruneProbe` folder was classified as `Orphaned`. `-WhatIf` preserved it; an actual transactional prune removed only that folder. Existing repository folder names and archive hashes were unchanged, and the final cache was healthy.
- A controlled legacy `BuiltIn\Teams` folder was classified as `Renamed` with canonical ID `MicrosoftTeams`. Synchronizing Microsoft Teams validated the existing canonical cache, retained its MSIX hash and then removed only the alias. The final cache was healthy.

The transaction log recorded `AcquireCount=0` and `PruneCount=1` for the controlled prune, followed by `PackagePruned` and `SyncComplete`. The Teams test recorded `CacheAliasPruned` only between `BuiltInSyncStart` and a successful `BuiltInSyncComplete`.

### Cold and warm SetupComplete pair

Two freshly applied x64 Windows installations used the same online OSDCloud USB flash drive and the same ordered eight-app queue documented below. Both machines loaded the exact 0.36.0 module in WinPE, retained the USB and network connection through SetupComplete, and were checked after OOBE.

For PC 1, the healthy active cache payload was moved to the recoverable `OSDApps-0.36.0-PreColdBackup` folder outside the active `OSDApps` root. The cold preflight reported `Valid=True`, `OfflineReady=False` and `NetworkRequired=True`, as expected. SetupComplete acquired all six built-ins, synchronized the USB cache and installed all six built-ins plus both SHA-256-validated repository packages.

PC 2 reused the cache populated by PC 1. Its strict `Test-OSDAppDeployment -RequireOfflineReady -MinimumFreeSpaceGB 10 -ThrowOnFailure` preflight reported `Valid=True`, `OfflineReady=True` and `NetworkRequired=False` before reboot.

| Cache state | PreInstall | Runner | Measured Windows total | Built-ins updated | Outcome |
| --- | ---: | ---: | ---: | --- | --- |
| Cold/recoverably cleared | 215.3 s | 364.8 s | **580.1 s (9:40)** | All six | **8/8**, cleanup succeeded |
| Warm/reused | 45.3 s | 364.1 s | **409.4 s (6:49)** | None | **8/8**, cleanup succeeded |

The cold and warm result records used deployment IDs `1efce244-3e62-4bd0-a294-f428ce1e3b8f` and `53c706f5-fa02-48a0-ae6f-13a4d5a26914`, respectively. In this pair, warm-cache reuse reduced PreInstall by **170.0 seconds** while Runner differed by only **0.7 seconds**; the measured total improved by **170.7 seconds**. These are observations from one run per cache state, not a performance benchmark.

On both PCs, the correlated PreInstall and final result records reported `Succeeded`, with eight expected, eight successful and zero failed apps. The final checks also confirmed six built-ins, at least five expected-publisher validations, no warning or error log entries, successful `OnSuccess` cleanup, removal of the cleanup helper, preservation of the persistent result and log, and a healthy desired-state cache with eight active entries and zero problem classifications. The pre-cold backup was intentionally retained after validation.

These two runs validate the online cold and warm SetupComplete paths for this release candidate. They do not add a new offline deployment result and do not prove licensing, user sign-in or later interactive app health. Raw device logs and organization-managed repository packages are not committed to the public repository.

## OSDApps 0.35.0 release-candidate physical validation — 12 October 2026

PC 1 was freshly reinstalled and staged in WinPE with the 0.35.0 release-candidate module loaded from `E:\Modules\OSDApps\0.35.0`. The populated USB cache remained attached and the machine remained online. Before reboot, `Test-OSDAppDeployment -RequireOfflineReady -MinimumFreeSpaceGB 10` passed for the complete eight-app queue.

The first Windows boot then exercised the standalone PreInstall and Runner scripts plus the new result contract. The standalone and nested PreInstall records shared deployment ID `8d5a26e6-0ddd-46f4-8666-b4234097d20b`; both phases and the final result reported `Succeeded`.

| Order | App | Source | Integrity result | Install duration | Outcome |
| ---: | --- | --- | --- | ---: | --- |
| 1 | Microsoft 365 Apps | Built-in | Expected publisher | 147.6 s | Exit code 0 |
| 2 | Microsoft Teams | Built-in | Expected publisher | 1.1 s | Exit code 0 |
| 3 | Google Chrome Enterprise | Built-in | Expected publisher | 18.1 s | Exit code 0 |
| 4 | Mozilla Firefox Enterprise | Built-in | Expected publisher | 20.1 s | Exit code 0 |
| 5 | Cisco Webex | Built-in | Expected publisher | 8.0 s | Exit code 0 |
| 6 | Adobe Acrobat Unified | Built-in | Not assessed, by design | 110.1 s | Exit code 0 |
| 7 | Notepad++ | Repository | SHA-256 | 9.2 s | Exit code 0 |
| 8 | Omnissa Horizon Client | Repository | SHA-256 | 54.2 s | Exit code 0 |

PreInstall completed in **53.9 s** and recorded `CacheUsed=True` for all six built-ins. Cisco Webex was the only built-in with `PackageUpdated=True`; the other five retained their cached packages. Runner completed in **369.0 s**, giving a measured Windows phase total of **422.9 s (7:03)**. The final result recorded eight expected, eight successful and zero failed apps.

After SetupComplete and OOBE, the `OnSuccess` cleanup contract was checked separately: `C:\Windows\Temp\OSDApps` no longer existed, no `OSDApps-Cleanup-*.cmd` helper remained, and `%ProgramData%\OSDApps\Results\Latest.json` plus `%ProgramData%\OSDApps\Logs\Runtime.log` were preserved. The runtime log contained no warning or error entries.

This is one physical release-candidate execution, not a performance benchmark. It validates preflight, staging, cache use, installer exit codes, correlated result reporting and cleanup. It does not prove licensing, user sign-in or every app's later interactive behavior. Raw device logs were reviewed but are not committed to the public repository.

## OSDApps 0.34.1 cold/warm physical validation — 12 October 2026

This pair used the same eight-app queue documented for the 0.34.0 release candidate and reused the populated removable cache between runs. Both were real SetupComplete executions. The `Test-OSDAppDeployment` and `Latest.json` contract first included in 0.35.0 were added afterward, so the evidence here comes from the 0.34.1 runtime log and filesystem outcome and does not validate those newer features.

| Cache state | PreInstall | Runner | Measured Windows total | Cache observation | Outcome |
| --- | ---: | ---: | ---: | --- | --- |
| Cold/cleared | 229.8 s | 366.9 s | **596.7 s (9:57)** | Built-in content populated/refreshed | **8/8**, cleanup succeeded |
| Warm/reused | 43.0 s | 370.2 s | **413.2 s (6:53)** | `AcquireCount=0`; `UpdatedPackageCount=0` | **8/8**, cleanup succeeded |

The phase total excludes image deployment, WinPE staging, reboot and OOBE. The warm observation establishes cache reuse for this run; it is not a general performance benchmark. Installer/provisioning success still does not prove licensing, later user sign-in or every interactive feature.

## OSDApps 0.34.0 release-candidate physical validation — 11 October 2026

These were **Windows SetupComplete executions on two freshly reinstalled x64 PCs**, not just WinPE staging or module unit tests. They exercised development commit `201595501b75875cfa316a989385cedb23ec28e9` from PR #14. The module's version label was still 0.33.0 in this prerelease commit; the tested feature code became the 0.34.0 release candidate after documentation and version preparation.

### App queue (same on both PCs)

| Order | Id | Source | Variant |
| ---: | --- | --- | --- |
| 1 | `Microsoft365Apps` | Built-in | x64, MonthlyEnterprise, nl-nl |
| 2 | `MicrosoftTeams` | Built-in | x64 |
| 3 | `GoogleChromeEnterprise` | Built-in | x64 |
| 4 | `MozillaFirefoxEnterprise` | Built-in | Rapid, x64, en-US |
| 5 | `CiscoWebex` | Built-in | x64 |
| 6 | `AdobeAcrobatUnified` | Built-in | x64 |
| 7 | `NotepadPlusPlus` | Repository | 8.9.8.1, x64 |
| 8 | `OmnissaHorizonClient` | Repository | 8.16.2.36295, x64 |

The two repository apps are private-repository **test content**, not bundled built-ins. They were synchronized to the USB cache and staged in WinPE, with archive SHA-256 checks. The built-ins were acquired/refreshed by the independent `Invoke-OSDAppPreInstall.ps1` runtime in full Windows.

### Measured results

| Machine and network state | PreInstall | Runner | Measured Windows total | Installer outcome |
| --- | ---: | ---: | ---: | --- |
| PC 1 — online, initially empty OSDCloud USB cache | 551.9 s | 366.7 s | **918.6 s (15:19)** | **8/8**, successful |
| PC 2 — fully offline, cache populated by PC 1 | 5.4 s | 394.2 s | **399.6 s (6:40)** | **8/8**, successful |

The measured total is the sum of the two phases, **not** OSDCloud image app, WinPE download/staging, reboot or OOBE time. A single run on each machine is not a performance benchmark.

**PC 1 — complete cold source acquisition.** ODT populated the Office cache (`Version=16.0.20326.20142`, `VersionChanged=True`). Teams, Chrome, Firefox, Cisco Webex and Adobe reported `PackageUpdated=True`. `BuiltInSignatureVerified` confirmed the expected publishers for Office ODT `setup.exe`, Teams `teamsbootstrapper.exe`, Google Chrome MSI, Firefox MSI and Cisco Webex MSI; the four downloaded MSI/bootstrapper candidates were also checked before the USB copy was accepted. `PreInstallComplete` recorded six built-ins and `InstallComplete` recorded eight successful installations with `CleanupMode=OnSuccess`.

**PC 2 — no network.** LAN was physically disconnected before the first Windows boot and remained disconnected for SetupComplete. `CacheVolumeFound` confirmed `E:\OSDApps`, and `BuiltInRefreshSkipped` appeared **six times**, one for each built-in (Office, Teams, Chrome, Firefox, Cisco Webex and Adobe). The five signable staged MSI/EXE packages passed the expected-publisher gate while offline. All six built-in installs and both SHA-256-validated repository package installs returned code `0`, followed by `InstallComplete; AppCount=8; CleanupMode=OnSuccess`.

### Additional validation and boundaries

- A separate warm-cache deployment completed four app installs successfully: Teams, Firefox, Notepad++ and Omnissa Horizon Client (`PreInstall 6.2 s`, `Runner 83.5 s`). A full-Windows Chrome cache sync retained an unchanged trusted MSI (`Updated=False`).
- The Windows 11 OSDApps Viewer showed valid publisher signature states for the five signable built-in cache entries, separate from repository SHA-256 integrity; the two WinPE PCs exercised read-only inventory, app staging and cache inspection.
- Authenticode coverage is intentionally **partial**: Teams MSIX and the Microsoft 365 Apps data tree are not cryptographically verified by the bootstrapper/ODT checks, and Adobe Acrobat's outer ZIP is `Not assessed`. No negative/tampered-package test was performed on hardware; such rejection behavior is covered by unit tests.
- An `ExitCode=0` validates the installer/provisioning path, not product activation, all interactive features, or the effective installed Office update channel. Office's reported cold-cache build differs from the earlier cached build; neither result alone establishes channel correctness.
- Raw device logs were reviewed during validation, but private machine logs and enterprise repository binaries are **not committed** into this public project.

## Real-world end-to-end validation — OSDApps 0.30.0

**Executed:** 9 October 2026, on freshly deployed Windows installations via OSDCloud v2. All four scenarios used OSDApps **0.30.0** from PowerShell Gallery, `CleanupMode=Never`, the same six app IDs, and the same installation order. These are four deployment executions, not repeated statistical benchmark samples.

The app queue, in order:

1. `Microsoft365Apps` (built-in; x64)
2. `Teams` (built-in; x64)
3. `GoogleChromeEnterprise` (built-in; x64)
4. `AdobeAcrobatUnified` (built-in; x64)
5. `OmnissaHorizonClient` (organization-managed repository; x64)
6. `NotepadPlusPlus` (organization-managed repository; x64)

Omnissa Horizon Client and Notepad++ were **test repository packages**, not OSDApps built-ins.

### Measured Windows phases

Durations below are from the `PreInstallComplete` / `InstallComplete` events in `Runtime.log`. **Total = PreInstall + Runner**, excluding WinPE/OSDCloud installation, module installation, repository staging and small gaps between phases.

| Test | USB cache state | PreInstall | Runner | Measured total | Runner outcome |
| --- | --- | ---: | ---: | ---: | --- |
| **1** | No USB connected | 217.3 s | 329.3 s | **546.6 s (9:07)** | **6/6**, success |
| **2** | USB connected, initially empty | 114.2 s | 328.4 s | **442.6 s (7:23)** | **6/6**, success |
| **3** | Same USB, populated (warm) | 41.7 s | 330.4 s | **372.1 s (6:12)** | **6/6**, success |
| **4** | Warm USB, changed Office configuration | 104.1 s | 346.0 s | **450.1 s (7:30)** | **6/6**, success |

**24 of 24 queued app executions reported successful completion** across the four `Runtime.log` files (each app installer returned exit code `0`). This is an installer/runtime result, not proof of every app's later activation or interactive launch.

### Per-test observations

**Test 1 — USB removed after OSDCloud, before OSDApps staging.** The USB remained disconnected through SetupComplete. Four built-ins acquired content on the local OS disk; both repository packages were staged locally in WinPE and their SHA-256 hashes validated by Runner. PreInstall and Runner completed successfully. This validates the USB-optional path and the Office PreInstall self-copy fix.

**Test 2 — cold USB cache.** The `OSDCloud` volume was present at `E:\OSDApps`. Both repository package cache entries passed the WinPE cache check; built-ins were acquired/synchronized to USB in full Windows. `CacheUsed=True`; PreInstall and Runner completed with six successful installs. The same USB was retained for the next scenarios.

**Test 3 — warm USB cache.** PreInstall reported `CacheUsed=True`. Office build `16.0.20430.20146` was unchanged (`VersionChanged=False`). Teams, Chrome and Adobe reported `PackageUpdated=False`; Teams downloaded only the small bootstrapper, not the large MSIX again. PreInstall fell from 114.2 s (cold USB) to 41.7 s (warm USB). Runner times remained close.

**Test 4 — warm USB with changed Microsoft 365 Apps configuration.** The staged XML was checked before reboot: x64 / ODT `OfficeClientEdition=64`, `MonthlyEnterprise`, `nl-nl`, updates enabled, plus `O365ProPlusRetail`, `VisioProRetail` and `ProjectProRetail`. Office PreInstall took 93.5 s; the detected Office build remained `16.0.20430.20146` (`VersionChanged=False`). Runner reported exit code `0` for all six queue entries. **Word, Excel, Visio and Project executables were separately confirmed present in Windows** after installation.

The unchanged build number in test 4 does **not** mean the Office configuration was unchanged: the extra products and language can use the same build. Separately checking installed executables was therefore important.

### Interpretation and remaining checks

- Warm USB versus cold USB reduced the **measured Windows phase** by **70.5 s**, largely in PreInstall (114.2 s to 41.7 s).
- Warm USB versus no USB reduced the measured Windows phase by **174.5 s**, but the no-USB and cold-USB runs had different observed Adobe download speeds. Do **not** attribute the entire difference to cache state; these are single real-world runs, not controlled or statistical benchmarks.
- The four execution paths and six installer exit codes were confirmed; **Office activation and the effective installed update channel were not independently verified**. The requested `MonthlyEnterprise` channel was checked in the staged XML, not confirmed in the installed Office update configuration.
- Other offline conditions (such as no USB with fully staged source), alternate x86/arm64 variants, failure/recovery paths and repeated timed samples remain separate tests.
- Source `Runtime.log` and WinPE staging checks were supplied during testing; raw environment logs were not added to the public repository.

## Offline end-to-end validation — OSDApps 0.30.0 test 5 (9 October 2026)

Test 5 started with a fully populated `OSDCloud` USB cache. All expected built-in source files were checked on the USB flash drive before reboot, and the two repository packages had already been staged. The network connection was physically disconnected before boot and remained unavailable throughout SetupComplete.

The `Runtime.log` confirmed `CacheVolumeFound`, `CacheUsed=True`, `BuiltInRefreshSkipped` for Office, Teams, Chrome and Adobe, and no online refresh. PreInstall completed in **7.6 s**; Runner completed in **380.7 s**. All six entries had successful install/provisioning exit codes (`0`), with a measured total of **388.3 s (6:28)**, excluding WinPE preparation.

The same run exposed an **Adobe staging path mismatch**: `BuiltInCacheRestaged` for Adobe showed the cache was copied from USB during PreInstall because the local archive was not at the manifest's architecture-specific path. The 0.30.1 change fixes that mismatch and adds file-copy regression tests. **Test 5 remains a valid successful fully offline deployment**; the additional path fix removes an unnecessary restage and aligns WinPE staging with runtime expectations.

## MicrosoftTeams rename — 0.31.0

The five completed real-world deployment scenarios above used **0.30.0** and therefore its original built-in ID `Teams`. In **0.31.0**, the canonical built-in ID, cache folder, WinPE staging, runtime manifest type and public cmdlets change to **`MicrosoftTeams`** with no automatic legacy compatibility or USB cache migration. New file-backed Pester tests validate the updated staging and runtime contracts. **0.31.0 field test 6** subsequently completed a six-app SetupComplete deployment with **6/6 exit code 0**, new `MicrosoftTeams` USB cache registration, correct architecture-specific Adobe staging (no `BuiltInCacheRestaged`), and successful `CleanupMode=OnSuccess` (runtime staging removed; `Runtime.log` retained). These later checks do not retroactively change the 0.30.0 historical results.

## Cisco Webex built-in — 0.32.0

Cisco Webex was added with x64 and ARM64 non-localized MSI sources, an architecture-specific optional USB cache, validated MSI parameters and the shared `VendorMsi` SetupComplete runner. File-backed unit tests verify that WinPE cache staging and `DeviceManifest.json` resolve to the identical local MSI path.

**Direct MSI test validated — 10 October 2026, Windows x64 development device.** The official non-localized Cisco x64 `Webex_en.msi` was downloaded successfully (259.9 MiB); Authenticode reported `Valid`, signed by Cisco Systems, Inc. Silent `msiexec /i ... /qn /norestart ALLUSERS=1 ACCEPT_EULA=TRUE AUTOSTART_WITH_WINDOWS=false` completed with exit code `0`; MSI registration showed **Webex 46.9.0.35800**. The full MSI log confirms the three installation properties, per-machine assignment, existing WebView2 Runtime and `MainEngineThread is returning 0` (server and client). Two internal Cisco custom actions (`WixRemoveFoldersEx` and `KillSpark`) logged a local `1603` but were explicitly translated to success by the package; there were no `Return value 3` fatal MSI actions.

**Field validation — 10 October 2026, OSDApps 0.32.0 test build (`a2d111fcde4764486207629200a077d74a2fa6a5`), x64:**

| Test | Verified observation | Result |
| --- | --- | --- |
| Direct x64 MSI on Windows | Cisco-signed, 259.9 MiB, v46.9.0.35800; silent all-users MSI returned 0 | Pass |
| Online SetupComplete, USB **not detected** by runtime | `CacheAvailable=False`, `Target=Local`; PreInstall downloaded 272,531,456 bytes in 3.6 s (reported 73 MB/s); PreInstall 7.6 s; Runner 8.5 s; MSI returned 0; Webex 46.9.0.35800 registered | Pass — **local fallback**, not USB caching |
| Cold USB cache from retained PreInstall runtime in Windows/OOBE | Cache created at `E:\OSDApps\BuiltIn\CiscoWebex\x64\Package.msi`; `CacheSynchronized=True`, `PackageUpdated=True`; 259.9 MiB present | Pass |
| Warm USB cache from repeated PreInstall in Windows/OOBE | `PackageUpdated=False`, `CacheSynchronized=True`, no new download, SHA256 unchanged; observed duration 4.1 s | Pass |
| Fully offline OSDCloud v2 / SetupComplete | In WinPE, USB and local staged MSI were present and **SHA256-identical** before reboot; physically disconnected network; Windows PreInstall logged `CacheAvailable=True`, `CacheVolumeFound` for `E:\OSDApps`, and `BuiltInRefreshSkipped` due to no network; PreInstall 3.5 s; installed from **local staged MSI**, `BuiltInInstallComplete ExitCode=0` in 8 s; Runner 8.5 s; `InstallComplete AppCount=1`; `CleanupSkipped` as configured (`Never`) | Pass |

The offline log demonstrates the USB cache was **detected** during SetupComplete, not that the installer ran directly from the USB volume; the payload had already been copied locally in WinPE. Both SetupComplete deployments used a one-app `CiscoWebex` queue. These measured durations cover only their named phases, not WinPE/OOBE or the entire deployment. The first online run did not populate the USB cache because the volume was not detected at runtime.

**Scope of these 0.32.0 checks:** they did not validate ARM64, a combined queue or online SetupComplete cache reuse. Later eight-app runs recorded above include Webex; ARM64 and other network-failure conditions still require separate evidence.

## Repository script packages and bounded Office fallback — 0.38.0

**Executed:** 13–14 October 2026 on x64 hardware, using OSDApps **0.38.0** from PR #26. The validation package was created externally for the test and is intentionally not included as a built-in or example package. It used `PackageType=Script`, architecture `any`, a SHA-256 protected `Package.zip`, an `Install.ps1` entry point and a harmless HKLM marker written as `NT AUTHORITY\SYSTEM`.

| Test | Verified observation | Result |
| --- | --- | --- |
| USB preparation | Script metadata, archive hash and package layout valid; existing repository packages and hashes unchanged | Pass |
| Script-only SetupComplete | One repository script staged in WinPE; runtime SHA-256 validation succeeded; script returned 0; marker confirmed SYSTEM execution; `Latest.json` succeeded; staging and cleanup helper removed; no retry task, service or RunOnce entry remained | Pass |
| Mixed queue | Six built-ins, two repository apps and one repository script executed in the intended order; all nine completed successfully; app entries retained `PackageType=App` and the script retained `PackageType=Script` | Pass |
| One-shot cleanup | SetupComplete completed once, scheduled normal `OnSuccess` cleanup and left no automatic retry mechanism | Pass |
| Office refresh fallback | ODT exceeded its configured 20-minute refresh timeout; the previously staged Office payload was used successfully and Microsoft 365 Apps installed offline with exit code 0 | Pass, with timeout hardening identified |
| Bounded process-tree termination | Post-fix physical test terminated one parent and two child processes in **0.42 s**; helper reported success and no process remained | Pass |
| Post-interruption cache inspection | Eight active entries; zero obsolete, orphaned, renamed, incomplete or corrupt entries; Office setup signature valid; recorded build `16.0.20430.20146` present; no partial/temp download files detected | Pass |

The mixed deployment reported **PreInstall 2022.7 s** and **Runner 448.9 s** (measured Windows total **2471.6 s / 41:11.6**). Microsoft 365 Apps accounted for **1992.5 s** of PreInstall. Log timestamps showed the 20-minute ODT timeout was reached, but the old parameterless `WaitForExit()` then added approximately 13 minutes while stopping the process. This was a timeout-enforcement defect, not a script-package failure: fallback installation and the remaining queue still succeeded.

The follow-up change terminates the ODT process tree and bounds both the `taskkill.exe` helper and `WaitForExit` calls to five seconds. File-backed regression tests reject any parameterless `WaitForExit()` in PreInstall. CI run 313 passed on both PowerShell 7 and Windows PowerShell 5.1. The physical process-tree test exercises the termination helper directly; the entire 20-minute external network/CDN disturbance was not recreated.

The Office data directory contained the previous build `16.0.20326.20142` and the current recorded build `16.0.20430.20146`. That retained previous version was not classified as an incomplete cache entry and was not removed during this read-only validation.

## Validated built-ins and remaining variants

The 0.30.0 end-to-end tests above cover Microsoft 365 Apps, Microsoft Teams, Adobe Acrobat Unified **x64**, and Google Chrome Enterprise **x64**. The earlier validation matrix also listed Mozilla Firefox Enterprise Rapid x64 as validated; it was **not** part of these four 0.30.0 runs.

Still requiring separate end-to-end checks:

- Google Chrome Enterprise x86
- Mozilla Firefox Enterprise Rapid x86
- Mozilla Firefox Enterprise ESR x64/x86
- Adobe Acrobat Unified x86
- Microsoft Teams x86 / arm64 and Microsoft 365 Apps x86
- Cisco Webex arm64

## Success criteria and logs

1. WinPE stages the intended `DeviceManifest.json` queue and any available repository payload.
2. `Test-OSDAppDeployment` reports `Valid=True`; an intentionally offline run also requires `OfflineReady=True`.
3. USB cache is detected only when connected, or a local no-USB path is selected.
4. Repository `Package.zip` files validate against their SHA-256 metadata.
5. `SetupComplete.cmd` starts `Invoke-OSDAppPreInstall.ps1`; `PreInstallComplete` reports success.
6. `Invoke-OSDAppRunner.ps1` installs the queued apps; each expected `*InstallComplete` has an accepted exit code.
7. `Latest.json` and the final `InstallComplete` agree on final status and app counts.
8. The configured `CleanupMode` is honored; local cleanup does not delete persistent logs or results.

Windows runtime log:

```text
%ProgramData%\OSDApps\Logs\Runtime.log
```

Machine-readable result:

```text
%ProgramData%\OSDApps\Results\Latest.json
```

Module/cache log when USB is attached:

```text
<OSDCloud>:\OSDApps\Logs\Client.log
```

For a no-USB run, module-side logging may be on the Windows volume, while the standalone runner still uses the configured Windows runtime log.

## Historical cold/warm benchmark — OSDApps 0.29.1

The earlier 0.29.1 benchmark is retained separately, using the same hardware, USB flash drive, app set and install order for its cold/warm pair.

| Phase | Cold USB | Warm USB |
| --- | ---: | ---: |
| PreInstall | 125.2 s | 40.6 s |
| Runner | 330.7 s | 327.4 s |
| Measured Windows total | 455.9 s | 368.0 s |

See [Performance](performance.md) for the historical benchmark details and the updated 0.30.0 comparison.


## Isolated sleep prevention test

Run `tools/Test-OSDAppsSleepPrevention.ps1` from a checkout of the implementation candidate in **elevated Windows PowerShell on a development PC**:

```powershell
.\tools\Test-OSDAppsSleepPrevention.ps1
```

To exercise a helper from a downloaded or USB module, supply its actual path:

```powershell
.\tools\Test-OSDAppsSleepPrevention.ps1 -HelperPath 'D:\Modules\OSDApps\<version>\Runtime\OSDAppSleepPrevention.ps1'
```

The test uses the real shared helper and unique power-request reasons. It checks normal completion, controlled failure, explicit disablement and forced termination of its own child process. It reads `powercfg /requests`, never clears another app's request, and changes no apps, cache files, deployment manifests or power settings. The successful output confirms registration and cleanup, not actual sleep behavior. `-HoldSeconds 120` extends only the normal-completion scenario.

Physical API prototype evidence on 20 October 2026, before module integration:

- Normal completion, controlled failure and forced child-process termination all released the request.
- With AC idle sleep configured for one minute, the protected 120-second interval recorded 120 awake seconds and no measured sleep gap.
- With no request active, Kernel-Power event 506 recorded Modern Standby after 60.5 seconds (`Idle Timeout`); event 507 recorded keyboard resume later.

This prototype evidence applies to the tested development PC. Integrated-helper and deployment results are recorded below. Do not rerun SetupComplete to validate a result.

## Sleep prevention deployment — 20 October 2026

Implementation commit: `53f229e7b235e289a703fe7211d8f78e84125958` ([PR #47](https://github.com/roryvossepoel/OSDApps/pull/47)). The candidate retained module version 0.45.1; the feature ships in 0.46.0.

- [CI](https://github.com/roryvossepoel/OSDApps/actions/runs/39407865264) passed 440 tests on each of Windows PowerShell 5.1 and PowerShell 7, with no failures or skipped tests. The real native helper test also passed on both engines.
- On the development PC, the actual runtime helper passed normal completion, controlled failure, disabled mode and forced termination. Registered requests were released; disabled mode registered none. No power settings were changed.
- Physical deployment `a02ec413-915e-4ad5-a2c6-b209a8f7c01e` completed from WinPE through OOBE. Microsoft 365 Apps, Adobe Acrobat Unified and Google Chrome Enterprise each reported `CacheReused` and installer exit code 0.
- PreInstall and Install each logged one successful `SleepPreventionStarted` and `SleepPreventionStopped` pair. No failed or skipped apps remained; staging and the cleanup helper were removed.

| Phase | Duration |
| --- | ---: |
| PreInstall | 10.5 seconds |
| Runner | 276 seconds |
| Total Windows phases | 286.5 seconds |

This deployment verifies power-request registration and release within both real runtime phases, successful installations and cleanup. It does not independently demonstrate an actual idle sleep transition; the earlier prototype idle comparison is separate evidence. Manual sleep, lid actions and battery-policy limitations remain as documented in [Runtime](runtime.md).


### 7Zip physical candidate validation (2026-10-20)

The x64 candidate at `de96798dd5a549b13855cf78cf184ec6010995e0` passed a
clean WinPE-to-OOBE test (deployment `3d547621-288f-400f-95fd-33698a42c15a`).
7Zip 26.04 was downloaded, installed machine-wide with exit code 0, and its
registered and executable versions matched. PreInstall took 4.5 seconds and
Runner 3.1 seconds; staging cleanup passed. This was a download test, not a
warm-cache reuse test. Native ARM64/x86 installation has not been physically tested.

That candidate used the prerelease identifier `SevenZip`. The subsequent naming
change uses `7Zip` for commands, identifiers, cache paths and test filenames.
It does not rename an already-created test cache or change existing test records.
Use `tools/Test-OSDApps7Zip.ps1 -Phase Stage` on a fresh Windows deployment;
its copied `C:\ProgramData\OSDApps\Tests\Test-OSDApps7Zip.ps1 -Phase Validate`
checks the correlated deployment in OOBE. Do not rerun SetupComplete.


## Visual Studio Code physical candidate validation (2026-10-20)

The x64 candidate at `9e2d204d7d2c49ba6c8b3115071193dfd7da72bd`
([PR #51](https://github.com/roryvossepoel/OSDApps/pull/51)) passed a physical
WinPE-to-OOBE deployment: `bb0e91a0-c45e-4fff-9743-cd4478ab362a`.
The candidate retained module version 0.46.0; this built-in ships in 0.47.0.

- Acquisition reported `Downloaded` with no refresh error (8.1 seconds).
- Machine-wide Visual Studio Code 1.142.0 installed with exit code 0.
- Registered, executable and reported versions matched.
- PreInstall took 11.8 seconds; Runner took 36 seconds.
- The OOBE validator passed its installation and cleanup checks; staging was removed.
- Validation was read-only and did not rerun SetupComplete.

[Candidate CI](https://github.com/roryvossepoel/OSDApps/actions/runs/39479913392)
passed on Windows PowerShell 5.1 and PowerShell 7. This physical result covers
x64 download and installation, not ARM64 installation, warm-cache reuse or
interactive editor behavior. The 0.47.0 release includes 7Zip's physical
candidate evidence and naming limitation documented above.

## Visual C++ and .NET prerequisite candidate

`tools/Test-OSDAppsPrerequisites.ps1 -Phase Stage` stages four items on a fresh
x64 WinPE deployment: Visual C++ x86 and x64 (two explicitly selected calls),
.NET 10 Runtime x86, and .NET 10 Desktop Runtime x64. Each Add call selects exactly
one architecture; the test deliberately covers both variants. Use the implementation checkout, not an older Gallery
module. The script refuses an existing queue and copies its validator to
`C:\ProgramData\OSDApps\Tests\Test-OSDAppsPrerequisites.ps1`.

After reboot, run that copied script with `-Phase Validate` in 64-bit Windows
PowerShell at OOBE. It correlates deployment results, checks Visual C++ registry
versions and DLL presence, enumerates actual .NET runtimes using the
architecture-specific `dotnet.exe`, and checks cleanup. It accepts an already
installed newer patch. No installation or SetupComplete rerun occurs during
validation. The initial physical deployment installed all four prerequisites with
exit code 0: Visual C++ x86/x64 14.51.36247.0 and .NET 10.0.13 Runtime x86/Desktop
x64. Preparation took 10.4 seconds and installation took 17.1 seconds; runtime
staging was removed. This evidence predates the final VisualCRedist identity rename.

### Physical validation on 21 October 2026

All three deployments ran on x64 Windows targets and installed Visual C++ x86/x64
14.51.36247.0, .NET 10.0.13 Runtime x86, and .NET 10.0.13 Desktop Runtime x64.
Each reported four successful installations, exit code 0, matching installed
versions and completed staging/helper cleanup.

| Deployment | Acquisition | PreInstall | Runner | Total |
| --- | --- | --- | --- | --- |
| `e2fd7839-9ce7-4c9d-b397-8b08ce1d3318` | All four downloaded | 10.4 s | 17.1 s | 27.5 s |
| `41f5a1e9-f963-440f-83d0-0a5e49783b42` | All four reused the cache | 6.8 s | 15.2 s | 22.0 s |
| `2b2ef9f4-4bc5-46fd-b65d-9f519d2a97f2` | VisualCRedist downloaded; both .NET variants reused the cache | 8.0 s | 15.2 s | 23.2 s |

The final run used commit `c2452dbafa4bab9b5b3b2ed6fd3e3ae08b651aae`, with
`VisualCRedist-x86` and `VisualCRedist-x64` IDs and
`BuiltIn/VisualCRedist/<architecture>` folders. [Candidate CI](https://github.com/roryvossepoel/OSDApps/actions/runs/39552403526)
passed on Windows PowerShell 5.1 and PowerShell 7. The tested candidate still
reported module version 0.47.0; release 0.48.0 contains this implementation.

The first two runs predate the final internal name change. Consequently, physical
VisualCRedist cache reuse under the final folder name has not been separately
demonstrated. .NET 8/9, .NET Runtime x64, Desktop Runtime x86, existing-newer
installation handling and failure/fallback paths have automated coverage but are
not established by these physical runs. Release preparation must pass its own CI.

Earlier preview cache folders remain untouched and are not reused under the new
identity. Keep acquisition results to distinguish successful installation from
verified cache reuse; `CacheUsed=True` alone does not prove reuse.
