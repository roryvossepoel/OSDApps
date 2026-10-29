# Changelog

## Unreleased

- Add experimental initial file/protocol associations through Add-OSDAppDefaultAssociation, with parameter or XML input, merged staging, SHA-256 validation and one-shot DISM baseline export/merge/import during SetupComplete. No policy enforcement, forced reboot or post-sign-in correction. Physical first-user acceptance remains required.

- Add opt-in initial Start and taskbar pins through Add-OSDAppStartPins and Add-OSDAppTaskbarPins. Includes independent configuration, transactional staging, target compatibility checks, result reporting and a combined manual deployment example. Start uses applyOnce; taskbar uses the native file policy with Replace and PinGeneration=1. Empty lists use the documented sentinel. Physical testing confirmed the requested pins, with an additional Outlook pin whose source remains unconfirmed.

- Add repository `PackageType=Font` with `Add-OSDAppFont`, Font-aware authoring/validation, machine-wide TTF/OTF installation, idempotent `AlreadyPresent` handling, conflict protection and per-font result reporting.

## 0.51.0

- Add the opt-in Microsoft Company Portal built-in. `Sync-OSDAppMicrosoftCompanyPortal` now downloads the official Microsoft Preinstall Kit automatically on full Windows, while `-KitPath` remains available for a manual/offline source. Stage the architecture-matched bundle, offline license and dependencies in WinPE; provision Company Portal for future user profiles during SetupComplete.
- Add the opt-in CMTrace Open built-in. Synchronize the latest stable upstream x64 or ARM64 MSI, validate the official GitHub release SHA-256 and Authenticode signature on full Windows, preserve the vendor MSI filename, and verify integrity again before silent MSI installation during SetupComplete. Support previously synchronized legacy `Package.msi` caches without another download.
- Keep both built-ins independent of custom Azure repository packages and compatible with the existing OSDApps app queue and Windows Inbox Cleanup script.
- Physical x64 validation (PC1): Windows Inbox Cleanup removed the three selected packages under SYSTEM; Company Portal 11.2.1495.0 provisioned and was available to the signed-in Autopilot user; CMTrace Open 1.6.3 and the separate DisplayLink repository package installed. Result: four succeeded, zero failed or skipped.
- Separate full-Windows preparation test confirmed the automatic Microsoft Company Portal download without `-KitPath`: `Updated=True`, `CacheReused=False`, seven selected cached files, official Microsoft Download Center source. ARM64 is supported in the interface but was not physically validated.

## 0.50.0

- Add opt-in `Add-OSDAppWindowsInboxCleanup` built-in Script with explicit package selection or the `Tested13` preset, integrity-checked offline staging, SYSTEM execution during SetupComplete, early diagnostics and per-package result reporting. No Azure catalog or vendor download is needed.
- Skip bundled scripts in the PreInstall acquisition phase without changing the ordered SetupComplete queue. Include preflight hash verification, read-only Viewer metadata and regression tests. Keep the separate `WindowsInboxAppCleanup` repository package compatible and unchanged.
- Fix the startup failure when `powershell.exe -File` evaluated a `$PSScriptRoot`-dependent parameter default before entering the script body. Resolve `config.json` only after parameter binding; add regression coverage.
- Validate on a physical Windows deployment: the built-in ran as `NT AUTHORITY\SYSTEM`, removed all 13 selected packages with zero failures and exit code 0. The operator confirmed they remained absent after completing Autopilot. See [validation evidence](docs/testing.md#windows-inbox-cleanup-built-in--24-october-2026).

## 0.49.1

- Persist automatic VisualCppRedist/SevenZip predecessor cleanup outcomes in the existing client and PreInstall logs, including preservation reasons and failures. Keep cleanup guards, cache reuse and synchronization result objects unchanged; logging failures do not change cleanup decisions.

- Add Diagnostics mode to the standalone maintenance tool: export deployment results, runtime log rotations and bounded installer-log candidates to a local ZIP with a source inventory, hashes and collection warnings. No new module cmdlet or runtime behavior change.

- Clarify the scope of local cache integrity, publisher checks, Office configuration compatibility and vendor freshness in the maintenance guide, FAQ and Viewer documentation.

## 0.49.0

- Automatically remove known retired VisualCppRedist and SevenZip cache variants after validating their canonical replacements. Preserve other architectures, links and recovery content.

- Add explicit `Clear-OSDAppCache -BuiltIn -Prune` maintenance for unmanaged built-in root folders and loose files. Preserve managed variants, legacy payload filenames, registered aliases, filesystem links and recovery content. Support read-only preview, per-item confirmation and the existing exclusive cache writer lock.

- Preserve vendor installer filenames for built-in downloads, USB caches and Windows staging, including the Teams MSIX. Continue reading legacy generic-name caches without forced downloads. Keep the `Package.zip` contract for custom repository apps and scripts. Reject unsafe download filenames and ambiguous built-in payloads.

- Document Intune ESP detection for apps preinstalled by OSDApps, including compatible newer versions.
- Validate vendor filenames and legacy cache reuse on two physical deployments and USB caches, plus isolated automatic cleanup on Windows.

## 0.48.1

- Explain built-in cache reuse, acquisition, offline fallback and failures with a per-deployment `CacheDecisionReason` in PreInstall results, Runner results and acquisition logs. Preserve the existing cache policies and distinguish changed HTTP metadata from a confirmed new app version.

## 0.48.0

- Add Visual C++ v14 x86/x64 and .NET Runtime/Desktop built-ins with separate variant identities, Microsoft verification, transactional caches and installed-version checks. Runtime items are staged before apps.
- Require exactly one explicit architecture for all four runtime Add/Sync cmdlets. Offer only supported stable .NET channels, enforce offline support deadlines and reject known EOL channels without cached fallback. Network failures may still use verified cache content within the supported channel lifetime.
- Use `VisualCRedist` consistently for public commands, package IDs and cache folders. Earlier preview cache folders are not migrated or deleted automatically.
- Validate physical cold and warm deployments of Visual C++ x86/x64 and .NET 10 Runtime x86/Desktop x64, followed by a successful deployment using the final VisualCRedist names. All four installed versions and exit codes passed; staging was removed. See [validation evidence](docs/testing.md#visual-c-and-net-prerequisite-candidate).

## 0.47.0

- Add Visual Studio Code Stable system-installer staging and synchronization for x64 and ARM64, with official release SHA-256, Microsoft publisher verification and transactional cache replacement.
- Add 7Zip built-in staging and cache synchronization for x64, x86 and ARM64, with official release SHA-256 verification and transactional cache replacement.

- Record successful physical x64 7Zip and Visual Studio Code deployment tests, including installed versions and runtime cleanup. See [validation evidence](docs/testing.md).
- Gate automatic release creation on a module version increase. Other manifest changes skip publication; manual release requests retain strict tag and source validation.

## 0.46.0

- Prevent automatic idle sleep during PreInstall and Runner with a temporary process-owned Windows power request. Release it on success and failure without changing power plans; log warnings and continue if the request is unavailable.
- Add `Set-OSDAppConfiguration -PreventSleep $false` to opt out before staging. Defaults to true, including manifests without the optional field. Stage and preflight-check the shared helper.
- Add isolated helper tests, standalone phase lifetime coverage and a development-PC script for real request registration, disablement and cleanup, including forced process termination.

- Validate real helper registration and cleanup on the development PC and a physical WinPE-to-OOBE deployment: Office, Adobe Acrobat and Chrome reused their caches and installed successfully; both runtime phases released their power requests and runtime cleanup completed. See [validation evidence](docs/testing.md#sleep-prevention-deployment--20-october-2026).

## 0.45.1

- Reuse a compatible, structurally consistent Office generation during online PreInstall when its build matches the architecture-specific build advertised by the Microsoft CDN, or an exact build pin matches. Skip ODT acquisition and report `CacheReused`; keep complete-generation replacement for changed or missing content.
- Preserve requested installation XML, signature validation, offline/failure fallback and one-shot execution. Metadata failures are reported as fallback warnings, not confirmed reuse. Explicit preparation-PC Office Sync still requests a fresh generation.
- Add regression tests for actual runtime reuse, unchanged USB content, changed configuration, inconsistent generations and metadata failure. Windows PowerShell 5.1 and PowerShell 7 each passed 416 tests on the implementation candidate. A physical x64 warm deployment confirmed `CacheReused`, matching Office 16.0.20430.20180 executables, exit code 0 and completed cleanup. See [validation evidence](docs/testing.md#office-online-warm-cache-reuse--19-october-2026).

## 0.45.0

- Add Zoom Workplace x64/ARM64 as a signed, transactionally cached VendorMsi built-in with Add and Sync commands, offline staging, acquisition reporting and cache inspection.
- Support optional desktop shortcut suppression, SSO host and validated ZConfig/ZRecommend maps without changing vendor defaults or adding a second execution mechanism.
- Add automated integration coverage and a staged WinPE/OOBE test procedure. Both Windows PowerShell 5.1 and PowerShell 7 passed 383 tests and all 33 packaged help checks on the implementation candidate.
- Validate a physical x64 Zoom deployment on 19 October 2026: new download, installer exit code 0, absent desktop shortcut and completed cleanup. See [validation evidence](docs/testing.md#zoom-workplace-cold-deployment--19-october-2026). ARM64 deployment, warm reuse and first-user settings remain pending.

## 0.44.0

### Office cache compatibility

- Check Office payload configuration compatibility before reusing cached content during staging or falling back after acquisition fails. Record payload configuration provenance separately from the requested installation configuration.
- Keep one active Office cache generation. Changes to acquisition settings, such as architecture, channel, products or languages, require compatible content; an incompatible previous generation cannot satisfy the new request. Licensing-only settings outside the acquisition configuration do not require different payload content.
- Continue attempting a fresh complete Office generation during online PreInstall. A validated replacement is promoted transactionally; failed acquisition preserves the old cache, but fallback is allowed only when its content is compatible with the requested configuration.
- Document structural generation checks, configuration matching and their limits: these checks do not verify every Office payload file against a trusted hash or expected size.

### Fixes and documentation

- Accept valid single-app queues on Windows PowerShell 5.1 while continuing to reject empty, duplicate or invalid queues.
- Build packaged help under inherited StrictMode and read parameter defaults from exported function bodies correctly.
- Simplify the Gallery quick start, add a WinPE launcher example with an exit-code gate, expand repository package authoring and align documentation around USB flash drives and pre-OOBE execution.
- Refresh workflow diagrams and aggregate Gallery downloads across versions. Align the Gallery module description with the README. No new public commands or GUI staging features are included.

### Validation

- The implementation candidate passed 369 tests on each of Windows PowerShell 5.1 and PowerShell 7, with zero failures or skipped tests and all 31 packaged help topics verified ([CI](https://github.com/roryvossepoel/OSDApps/actions/runs/39157805653)). Release preparation and publication validate their own source again.
- Physical Office configuration checks and a single-Office deployment through OOBE passed on 18 October 2026: fresh acquisition, installer exit code 0, matching installed version and completed cleanup. See the [validation evidence](docs/testing.md#office-configuration-compatibility-and-deployment--18-october-2026) for tested commits and scope.

## 0.43.0

- Add optional `-Architecture x64|arm64` to `Sync-OSDAppRepository` and `Get-OSDAppCacheHealth` for preparing and checking repository content for another target architecture.
- Keep the host architecture as the default and prefer an exact variant before `any`. Missing compatible variants fail before cache mutation; existing transaction, hash, locking and pruning rules still apply.
- Keep one cached variant per repository Id. Switching architecture replaces that Id transactionally; it does not create a multi-architecture cache layout or alter WinPE/SetupComplete target selection.
- Show acquisition outcomes and refresh warnings alongside installation results in the getting-started guide.

## 0.42.0

- Record each built-in's current-deployment acquisition outcome in PreInstall and Runner results: `Downloaded`, `CacheReused`, `OfflineCacheUsed`, `FallbackCacheUsed` or `Failed`.
- Preserve the refresh failure type and message when an acceptable staged fallback allows preparation and installation to continue. Classify insufficient acquisition space as `InsufficientDiskSpace`.
- Add fallback/offline counts and an acquisition-warning flag to the PreInstall record, plus an `AppAcquisitionComplete` log event. Successful preparation with fallback/offline use emits a warning-level completion summary.
- Keep installer status, exit codes, one-shot execution, cleanup decisions and existing result fields unchanged. Older PreInstall records report `Unknown`; repository entries report `NotApplicable` for the built-in acquisition outcome.

## 0.41.0

- Protect all public built-in synchronizers, repository synchronization/pruning and cache clearing with one exclusive file handle per cache root, held through recovery, commit and cleanup.
- Use the same lock in standalone PreInstall, including local acquisition when no USB cache is present. Report `CacheLockUnavailable` and stop before touching a busy acquisition cache; no automatic retry is added.
- Prevent repository staging from treating lock acquisition failures as network failures eligible for cached fallback.
- Release handles in `finally`; process termination releases them through the operating system. Keep the empty `.osdapps-cache.lock` file in place to avoid delete/recreate races. File existence alone never blocks use.
- Keep `-WhatIf` free of lock creation. Stage and validate the shared runtime helper without adding public commands or settings.

## 0.40.0

- Check free space before preparing a replacement built-in cache generation, using the known payload length or an existing-generation estimate plus a 20% allowance and 64 MB overhead, subject to the configured minimum.
- Apply the same check in standalone PreInstall; an insufficient-space refresh follows the existing staged-fallback policy instead of replacing the active cache.
- Budget the complete changed repository batch before downloading and recheck remaining work before each archive. Reused packages are excluded; pending pruning is not counted as available space.
- Keep MSI/ZIP cache reuse independent of replacement-space thresholds. Teams still prepares a candidate bootstrapper and MSIX, including when the MSIX is reused.
- Stage and validate the shared space helper without adding public commands. Unknown download lengths remain estimates; checks do not reserve disk capacity or guarantee installer workspace.

## 0.39.1

### Documentation and discovery

- Rework the README around a short WinPE example using Microsoft 365 Apps, Adobe Acrobat Unified and Google Chrome Enterprise.
- Remove release pins and unnecessary switches from installation examples; USB workflows discover the newest version saved on the selected USB flash drive.
- Correct the workflow diagrams: independent package sources, optional cache preparation, machine-context scripts and one-shot SetupComplete processing. Use explicit backgrounds for readable diagrams in light and dark GitHub themes.
- Show total PowerShell Gallery downloads across all versions and update the module description and discovery tags.
- Document existing App/Script labeling in all relevant Viewer tabs. No public commands, UI behavior, installer logic or cache transaction behavior changed.

## 0.39.0

### Cache resilience

- Microsoft Teams, Google Chrome Enterprise, Mozilla Firefox Enterprise, Cisco Webex and Adobe Acrobat Unified now acquire changed content into a complete sibling cache generation. The active directory is replaced only after required files, metadata and the applicable publisher or archive checks succeed.
- Directory promotion uses a same-volume backup and rollback boundary. A failed download, validation or promotion leaves the prior active generation available; a successful promotion removes the prior generation and residue from older interrupted transactions.
- The standalone SetupComplete PreInstall runtime uses the same generation-level contract. Existing staged content remains the one-shot fallback when an online refresh fails.
- If an interrupted swap leaves the active USB directory absent, the next built-in sync or PreInstall invocation restores exactly one validated previous `.osdapps-old-<guid>` generation before acquisition or offline fallback. Active directories are never overwritten by recovery; uncommitted `.new` content is never promoted. Ambiguous or invalid backups are preserved and reported. Read-only cache checks do not mutate the cache and SetupComplete is never scheduled to retry.

### Validation

- Added fault-injection coverage proving failed candidate validation does not change active content, successful promotion replaces the complete generation, and stale transaction directories are removed only after a valid generation is active.
- Added source-wiring regression coverage for all five non-Office built-ins in both the module synchronizers and standalone PreInstall runtime.
- Added interrupted-swap recovery tests, including offline restaging in standalone PreInstall, preservation on validation/rename failure, ambiguous backups, idempotence, WhatIf and staging of the shared recovery helper.

## 0.38.0

### Added

- Added optional repository `PackageType` metadata with supported values `App` and `Script`. `Add-OSDAppPackage` writes `App` by default; existing manifests without the property remain compatible and resolve to `App`.
- Package type now flows unchanged through catalog resolution, transactional cache synchronization, `Get-OSDApp`, `Get-OSDAppCache`, device staging, the read-only Viewer, runtime logs and each `Latest.json` app result.

### Execution contract

- Apps and scripts use the same `Package/Install.ps1` entry point, SHA-256 enforcement, ordered one-shot SetupComplete queue, timeout, success-code handling and 0.37.0 failure-isolation behavior. `PackageType` is classification metadata and does not select a different or less trusted runtime path.
- OSDApps does not automatically reboot, retry or roll back script changes. Scripts run as SYSTEM during SetupComplete and must not initiate a restart; user-profile (`HKCU`) configuration is outside this phase's machine-context contract.

### Validation

- Added compatibility and propagation tests for explicit script packages, legacy manifests, unsupported package types, Viewer labeling and runtime result reporting.

### Cache resilience

- Microsoft 365 Apps refresh timeout handling now terminates the complete ODT process tree through bounded waits before falling back to an already staged payload.
- Microsoft 365 Apps refresh builds and validates a complete replacement generation before switching the active cache directory. The previous directory is removed only after promotion. An earlier selective version-folder/CAB pruning approach was superseded during validation; individual Office payload files must not be pruned from an active generation.

## 0.37.0

### Added

- Added one-shot, per-app fault isolation to the standalone SetupComplete runtime. A normal acquisition, source, timeout or installer failure is recorded for that app while independent queue entries continue exactly once.
- PreInstall now writes per-built-in outcomes and can finish as `CompletedWithErrors`. Runner skips only built-ins that PreInstall could not prepare, continues repository and unaffected built-in apps, and records `SkippedAppCount` and `UnsuccessfulAppCount` in `Latest.json`.
- Added explicit `AppRefreshFailed`, `RefreshCompletedWithErrors`, `AppInstallSkipped` and `InstallCompletedWithErrors` events for partial outcomes.

### Safety and execution contract

- SetupComplete remains a single execution path. OSDApps does not create RunOnce entries, scheduled tasks, services or any other automatic retry mechanism.
- Repository SHA-256 checks now run for every available selected archive before the first installer starts. A hash mismatch, invalid manifest/queue or supported-publisher trust failure remains fatal and prevents further app execution.
- Installer exit-code failures, timeouts and missing app-local source do not block unrelated apps. The final deployment still reports `Failed`, returns a nonzero Runner exit code, retains staging and suppresses `OnSuccess` cleanup whenever any app failed or was skipped.

### Validation

- Added Windows runtime tests proving continuation after a controlled installer exit code, continuation after a recorded PreInstall acquisition failure, all-installer blocking on a repository hash mismatch, staging retention after partial failure and absence of persistence-based retry mechanisms.
- The release candidate passed **240/240 tests** on both Windows PowerShell 5.1 and PowerShell 7, with **31/31 packaged command-help topics** verified on each engine and no blocking analyzer errors ([CI run](https://github.com/roryvossepoel/OSDApps/actions/runs/38405028071)).
- Two freshly applied x64 PCs passed a physical SetupComplete pair using the same eight-app queue and USB cache. A controlled repository installer failure on PC 1 was recorded once (exit code `42`), did not prevent the following Omnissa package from succeeding, produced a final failed result with 7 succeeded / 1 failed / 0 skipped, retained staging and created no retry persistence. PC 2 then completed the unchanged normal queue with **8/8 succeeded**, zero failed or skipped, correlated successful phase records, successful `OnSuccess` cleanup and no scheduled task, service or RunOnce entry.

## 0.36.0

### Added

- Added read-only `Get-OSDAppCacheHealth` with aggregate health, removable size and per-entry `Active`, `Pinned`, `Obsolete`, `Orphaned`, `Renamed`, `Incomplete` and `Corrupt` classifications.
- Added optional root-catalog `Aliases` for retired repository IDs. Catalog resolution, selective synchronization and `Add-OSDApp` map aliases to one canonical ID. Merge-only sync retires conflicting legacy metadata but preserves its files until explicit pruning.
- Added `Sync-OSDAppRepository -Prune` for complete desired-state reconciliation and `-PinnedId` for intentional retention of valid canonical packages.

### Cache safety

- Repository prune resolves the complete architecture-compatible plan and acquires and SHA-256-validates replacements before changing persistent content. Stale folders remain in a same-volume transaction backup until `CacheCatalog.json` commits; a failed commit restores promoted and removed folders plus the prior catalog.
- Selective `-Name` synchronization remains merge-only and cannot be combined with `-Prune`. Unknown, alias, missing and corrupt pins are rejected. `-WhatIf` stops before cache writes.
- `Clear-OSDAppCache -Name` now resolves exact safe IDs in both built-in and repository namespaces instead of relying on a hard-coded built-in list, allowing retired identities to be removed explicitly.
- `MicrosoftTeams` metadata declares `Teams` as a retired cache alias. Full-Windows `Sync-OSDAppMicrosoftTeams` and standalone PreInstall remove `BuiltIn\Teams` only after the canonical cache is complete and its bootstrapper passes the existing Microsoft trust gate. PreInstall treats cleanup failure as a logged warning so it cannot turn an otherwise usable deployment into a failure. No legacy public command or SetupComplete identity was restored.

### Validation

- Added file-backed tests for desired-state classification, offline health, corruption despite pins, repository alias conflicts and authoring, canonical alias staging, successful prune, empty desired state, valid pin retention, `WhatIf`, commit-failure rollback, dynamic named clearing and guarded Teams alias cleanup.
- The release candidate passed **235/235 tests** on both Windows PowerShell 5.1 and PowerShell 7, with **31/31 packaged command-help topics** verified on each engine and no blocking analyzer errors ([CI run](https://github.com/roryvossepoel/OSDApps/actions/runs/38364310573)).
- Full-Windows testing on a populated eight-entry USB cache passed offline and online desired-state health checks, prune `WhatIf`, a controlled transactional orphan prune with unchanged retained package hashes, and guarded migration of a temporary `BuiltIn\Teams` alias with the canonical Teams MSIX unchanged.
- Two freshly applied x64 PCs passed the complete online eight-app SetupComplete path with the same USB flash drive. The recoverably cleared cold run repopulated a healthy cache in `PreInstall 215.3 s + Runner 364.8 s`; all six built-ins were updated. The subsequent warm run passed hard offline-readiness and completed in `PreInstall 45.3 s + Runner 364.1 s` with no built-in updates. Both correlated result sets reported **8/8 successful installations**, no runtime warnings or errors, successful `OnSuccess` cleanup and a final healthy eight-entry cache.

### Compatibility and scope

- Windows PowerShell 5.1 remains the minimum supported version. Existing schema-1 repositories without `Aliases` remain compatible, and normal synchronization remains non-destructive unless `-Prune` is explicitly supplied.
- Repository pruning changes persistent cache content only; it does not prune the source repository, built-in caches or device staging. Cache health is diagnostic evidence, not installed-app or licensing state.

## 0.35.0

### Added

- Added `Test-OSDAppDeployment` for pre-reboot validation of the manifest, ordered queue, SetupComplete integration, staged runtime version, repository SHA-256, built-in definitions, free space and optional hard offline readiness.
- Added `Test-OSDAppCache` for one aggregate cache-readiness result with entry counts, payload validity and optional supported signature checks. `Get-OSDAppCache` also accepts an explicit `-CachePath`.
- Added atomic `%ProgramData%\OSDApps\Results\Latest.json` reporting with a stable deployment ID, PreInstall context, top-level outcome and per-app status, exit code, duration, integrity and cache/update metadata. `Get-OSDAppDeploymentResult` reads the result.
- Added configurable `ResultPath`; it is persisted with the other standalone runtime settings.

### Validation

- Added file-backed preflight, online/offline readiness, repository tamper, runtime mismatch, cache aggregation, result parsing and standalone Runner result tests for Windows PowerShell 5.1 and PowerShell 7 CI.
- The release candidate passed **205/205 tests on each PowerShell engine**, with **30/30 packaged command-help topics** verified and no blocking analyzer errors ([CI run](https://github.com/roryvossepoel/OSDApps/actions/runs/38284146281)). Publication validates the merged source again.
- The 0.35.0 release candidate passed a physical online deployment from a populated USB cache on 12 October 2026. `Test-OSDAppDeployment -RequireOfflineReady` passed before reboot; correlated PreInstall and final JSON results recorded **8/8 successful installations**, `PreInstall` in **53.9 s**, Runner in **369.0 s**, and the expected `OnSuccess` cleanup outcome. All six built-ins used cached content, Cisco Webex refreshed, the five signable built-ins passed expected-publisher validation, and both repository packages passed SHA-256 validation.
- OSDApps 0.34.1 separately passed a physical cold/warm eight-app pair on the same date; it remains historical evidence for the earlier runtime.

### Compatibility and scope

- Windows PowerShell 5.1 remains the minimum supported version. The built-in app set, repository contract, cleanup policy and installer success-code handling are unchanged from 0.34.1.
- Preflight and cache validation are read-only. Result writing is best effort so a result-path problem does not change an otherwise successful installation into a failure; `Runtime.log` remains the authoritative fallback.
- A successful result records installer/provisioning evidence. It does not prove licensing, user sign-in or later interactive app health.

## 0.34.1

### Fixed

- `New-OSDAppPackage` and `Add-OSDAppPackage` now stop before destination changes when `-WhatIf` is used or confirmation is declined. Preview no longer returns a success object for an archive or publication that was not created.
- Package validation completes its own temporary extraction and cleanup without inheriting the caller's preview/confirmation preferences. The caller's preferences and destination approval remain intact; input validation can still create temporary files before approval.
- Improved nonfatal MSI inventory and repository-validation diagnostics, and removed automatic-variable name collisions in client logging and Viewer cache selection while preserving existing callers and selection behavior.

### Help and documentation

- Ship offline `Get-Help` for all 27 exported commands, including parameters, execution environments and examples, with packaged help verified in fresh PowerShell processes.
- Reworked onboarding, the Viewer guide, troubleshooting, and Windows preparation / online and offline WinPE examples.

### Validation

- CI runs the full Pester suite, analyzer, distribution build and packaged-help checks separately on Windows PowerShell 5.1 and PowerShell 7. Empty, incomplete and discovery-failed test runs now fail the gate; detailed test and analyzer reports are retained.
- Added file-backed tests for actual declined confirmations, new/existing destinations, same-version replacement previews, temporary-file cleanup, invalid input and simulated compression/extraction failures. Fixture installers must never execute.
- The reviewed authoring candidate passed **194/194 tests on each PowerShell engine**, with **27/27 packaged command-help topics** verified ([CI run](https://github.com/roryvossepoel/OSDApps/actions/runs/38217563557)). Release-preparation and publication workflows validate their own source again; this earlier result is not a claim that a later release has already passed.
- Analyzer warning/informational findings remain; the validation gate reports no blocking errors for that candidate.

### Compatibility and scope

- Windows PowerShell 5.1 remains the minimum supported version. Public command parameters, built-in apps, deployment defaults, signature policy and the standalone SetupComplete runtime are unchanged from 0.34.0.
- Normal package build/publication is not transactional rollback. This maintenance release adds no new physical WinPE or app-installation validation; the hardware evidence recorded under 0.34.0 remains specific to that version.

## 0.34.0

### Added

- Added read-only `Show-OSDAppUI` (**OSDApps Viewer**) with Staged for device, Apps, Cache and Logs views, responsive columns, search, sorting, Vendor information and actual staged configuration details. Windows PowerShell 5.1/WinPE compatibility has been exercised on two x64 PCs.
- Added optional `Vendor` metadata in per-app repository manifests, propagated to USB cache and staging without repackaging ZIPs.
- Added precise built-in cache versions where available (MSI ProductVersion and Acrobat patch filename), while keeping vendor-managed version policy distinct.

### Security

- Viewer now checks Windows Authenticode trust and the expected certificate **organization** for signable built-in MSI/EXE packages by default on full Windows. WinPE reports that checks are unavailable rather than implying they passed. Strictly offline Viewer inspections can explicitly use `-SkipSignatureVerification`.
- The CLI `Get-OSDAppCache` retains fast inspection by default and explicit `-VerifySignatures`; signature state remains distinct from file-presence and repository SHA-256 integrity.
- Full-Windows built-in MSI/EXE synchronization validates downloaded candidate files before replacing an existing cache, checks saved cache hits again, and rejects unsigned, untrusted or unexpected-publisher files.
- Standalone SetupComplete PreInstall now checks corresponding installer signatures before refresh, installation or fallback. A failed trust check can stop a deployment rather than silently using an untrusted cache.
- **Scope limitations:** Office checks `setup.exe` but not the complete Office content tree; Teams checks the bootstrapper but not `teams.msix`; Adobe's outer `Package.zip` remains Not assessed for Authenticode. Repository ZIPs continue using manifest SHA-256 validation. Certificate chain and revocation checks may need network access even when repository lookup is offline.

### Validation

- **Automated:** release-candidate CI passed **145/145 Pester tests** with Windows PowerShell 5.1 signer/publisher smoke tests, module build, and no blocking PSScriptAnalyzer findings (commit `201595501b75875cfa316a989385cedb23ec28e9`). Re-run CI after the version/documentation release-preparation changes.
- **Viewer on real devices:** Windows 11 read-only UI, default built-in signature status and expected publishers, cache metadata/version inspection, and WinPE Viewer/staging on two x64 PCs validated. The Viewer never changed the USB cache or deployment manifest.
- **Windows cache synchronization:** real Chrome Enterprise x64 warm-cache sync succeeded with `Updated=False`, after validating the cached signed package. Real cached MSI/EXE signatures from Microsoft, Google, Cisco and Mozilla passed with their expected organizations.
- **Warm SetupComplete:** a four-app deployment installed Teams, Firefox, Notepad++ and Omnissa Horizon Client successfully (PreInstall **6.2 s**, Runner **83.5 s**, `AppCount=4`, `CleanupMode=OnSuccess`).
- **Cold online SetupComplete (PC 1, 11 October 2026):** empty OSDCloud USB cache; six built-ins newly acquired and two repository packages synced and SHA-256-validated in WinPE. Five signable built-in MSI/EXE payloads passed expected-publisher Authenticode gates. All **8/8** installations returned success (`PreInstallComplete` **551.9 s**; `InstallComplete` **366.7 s**; `CleanupMode=OnSuccess`). Microsoft 365 Apps reported build `16.0.20326.20142`, `VersionChanged=True`; the earlier cache had `16.0.20430.20146`. These are source/cache versions, not independently checked installed Office update-channel settings.
- **Fully offline SetupComplete (PC 2, 11 October 2026):** LAN disconnected, populated OSDCloud USB cache attached. The runtime recorded `CacheVolumeFound` and `BuiltInRefreshSkipped` for **all six built-ins**, with no vendor refresh required. All **five** signable cached built-in installers passed Authenticode and expected-publisher validation. All **8/8** installations returned success (`PreInstallComplete` **5.4 s**; `InstallComplete` **394.2 s**; `CleanupMode=OnSuccess`).
- **Limits:** installer/provisioning exit code `0` does not prove licensing, user sign-in, or every app's later interactive functionality. Adobe's outer ZIP, Teams MSIX and the Office data tree are outside the specific MSI/EXE signature scope; publisher signing is not full payload-chain verification. No malicious/invalid signed payload was intentionally deployed on test hardware.


## 0.33.0

### Added

- Added `-SkipCacheRefresh` to the generic repository `Add-OSDApp` command for explicitly offline staging from an existing USB cache.
- Added automatic, SHA-256-validated offline fallback when a configured repository cannot be synchronized. The fallback is allowed only when **all** requested repository packages are present and valid.
- Introduced transactional multi-app repository synchronization: download and validate packages before committing them together, with catalog/package rollback on a failed commit.

### Fixed

- `Add-OSDApp -WhatIf` no longer synchronizes or changes the offline Windows installation.
- Repeated OSDApps staging maintains a single installation-queue entry and refreshes its own SetupComplete blocks while preserving third-party commands.
- Reject malformed/duplicate OSDApps SetupComplete markers and invalid repository package identifiers instead of silently creating an inconsistent deployment.
- Tightened cache cleanup and commit/error logging; made PreInstall, Runner and Client CMTrace-style log messages single-line, and added bounded PreInstall log rotation.
- Generic `Add-OSDApp` now explicitly redirects built-in Microsoft Teams and Cisco Webex IDs to their dedicated commands.

### Validation

- **CI (10 October 2026):** 74/74 Pester tests passed, with PSScriptAnalyzer free of blocking errors and distributable module build successful. The suite includes SHA-256 failure and transactional catalog-commit rollback simulations.
- **WinPE + SetupComplete physical validation (10 October 2026):** Two x64 PCs using the same USB cache completed separate online and fully offline deployments. Each staged Horizon Client 8.16.2.36295 and Notepad++ 8.9.8.1 without duplicate manifest entries/SetupComplete blocks; SetupComplete independently revalidated both staged SHA-256 hashes; both installations exited 0 on both PCs (4/4).
- Runner totals: **60.2 s** (PC1 online, without USB at Windows boot) and **59.1 s** (PC2 offline, USB attached). `CleanupMode Never` was used deliberately for validation.
- **Limit:** physical power-interruption/catalog-publish failure rollback was not fault-injected; rollback was validated in automated tests. These measurements are two test executions, not a performance benchmark.

## 0.32.0

### Added

- Added Cisco Webex App as a vendor-native built-in, with `Add-OSDAppCiscoWebex` and `Sync-OSDAppCiscoWebex`, supporting non-localized official Cisco MSI sources for x64 and ARM64.
- Introduced architecture-specific USB cache and WinPE staging under `BuiltIn/CiscoWebex/<architecture>`; full-Windows PreInstall refresh, offline fallback, hash-aware file staging tests, and the existing generic `VendorMsi` Runner integration.
- Added optional MSI configuration: autostart, organizational EULA acceptance, pre-sign-in update checks, Outlook integration, Cisco sign-in identity placeholders, theme, timeout, and validated additional MSI properties.
- Added cache discovery, cache clearing, built-in metadata, Webex icon, user documentation and file-backed Pester regression tests.

### Validation

- Automated MSI property, x64/ARM64 staging and vendor manifest/cache path tests are included.
- **x64 practice validation (10 October 2026):** Cisco-signed 259.9 MiB MSI v46.9.0.35800 installed silently with exit code 0; online SetupComplete passed (download 3.6 s, install 8 s); cold and warm USB cache passed (warm 4.1 s, zero re-downloads); fully offline SetupComplete from locally staged USB cache passed (PreInstall 3.5 s, Runner 8.5 s, exit 0).
- ARM64 is supported in the interface but **has not been field-validated**. A combined seven-app queue and online SetupComplete warm-cache reuse remain untested. See [test evidence](docs/testing.md#cisco-webex-built-in--0320).
- Documented the stable public `metadata/builtins.json` contract and viewer integration; no breaking metadata schema changes.

## 0.31.0

### Breaking changes

- Renamed the built-in app ID `Teams` to `MicrosoftTeams` throughout the module, `DeviceManifest.json`, cache metadata, PreInstall, Runner, logs and the machine-readable built-in catalog.
- Replaced `Add-OSDAppTeams` / `Sync-OSDAppTeams` with `Add-OSDAppMicrosoftTeams` / `Sync-OSDAppMicrosoftTeams`. No compatibility aliases are shipped.
- Moved the canonical Teams cache and staging directory from `BuiltIn/Teams` to `BuiltIn/MicrosoftTeams`. Previously populated USB caches are **not automatically migrated**; run `Sync-OSDAppMicrosoftTeams` on full Windows before using old media for a fully offline deployment.
- Updated the built-in manifest type from `TeamsBootstrapper` to `MicrosoftTeamsBootstrapper`. Regenerate deployment manifests with 0.31.0.

### Changed

- Updated cache discovery and clearing, WinPE staging, SetupComplete acquisition and installation, public examples, built-in JSON metadata and icon URL.
- Updated the app-queue diagram and renamed the published Teams icon to `metadata/icons/microsoftteams.svg`.

### Validation

- Extended file-backed staging regression tests and added explicit tests for the new public commands, absent legacy exports, manifest identity/type and paths, cache recognition, and runtime dispatch.
- The earlier successful OSDCloud field tests 1–5 were executed with 0.30.0 and remain historical evidence. A new 0.31.0 field deployment is pending.

## 0.30.1

### Fixed

- Corrected Adobe Acrobat Unified WinPE staging from the USB cache: `Package.zip` now lands under `BuiltIn/AdobeAcrobatUnified/<architecture>/`, matching its DeviceManifest entry and SetupComplete runtime path. Previously, it was copied to the parent directory, so offline PreInstall had to restage it from USB.
- Adobe staging now stops on copy errors, a missing staged archive, or an archive size mismatch instead of reporting successful staging for an absent/partial payload.
- Added syntax-only validation for custom Office `-ConfigurationXml` in both Add and Sync, rejecting missing files and malformed XML while leaving ODT-specific settings to Microsoft.
- Corrected the Office architecture documentation to use public `x86` and `x64` values.

### Validation

- Added file-backed Pester regression tests for Adobe x64 and x86 staging, missing-cache staging intent, and exact cache-to-manifest staging paths for the other four built-in apps.
- Documented the successful 0.30.0 warm-USB offline field test (test 5, six installations with exit code 0) and the Adobe restaging anomaly that exposed this bug.
- The patched 0.30.1 staging path requires deployment verification; the prior 0.30.0 offline test remains successful.

## 0.30.0

### Added

- Added optional Visio Professional and Project Professional products via `-IncludeVisio` and `-IncludeProject`.
- Added Office `-UpdatesEnabled`, default true, to Add and Sync commands.
- Centralized Office XML generation and retained custom `-ConfigurationXml` support.

### Changed

- Standardized architectures as `x86` / `x64` / `arm64` where offered; all built-ins default to `x64`.
- Office XML translates x86/x64 into required ODT OfficeClientEdition 32/64.
- Removed Teams Auto architecture selection and old numeric Office architecture parameters.
- Updated built-in metadata and documentation.

### Validation

- Added Office configuration and architecture regression tests. At the time of tagging 0.30.0, full SetupComplete deployment still required field validation.

### Post-release field validation (9 October 2026)

- Completed four fresh OSDCloud v2 SetupComplete scenarios: no USB cache, cold USB cache, warm USB cache, and warm USB with changed Office configuration.
- All six app queue items completed successfully in each run (24/24 successful installer/provisioning results).
- Word, Excel, Visio and Project executables were confirmed present following the modified Office installation.
- Captured PreInstall/Runner measurements and remaining coverage limitations in [Validation matrix](docs/testing.md) and [Performance](docs/performance.md).
- Office licensing activation and the effective installed update channel were not independently verified.

## 0.29.3

### Fixed

- Fixed Microsoft 365 Apps PreInstall failure when no OSDCloud USB cache is attached: the local `configuration.xml` was copied onto itself, triggering a terminating PowerShell error before any apps could install.
- PreInstall now skips copying the Office configuration when the source and destination resolve to the same file, while still copying between distinct USB and local paths.
- Prevents this specific failure from prematurely terminating `SetupComplete.cmd` before the OSDApps app runner starts.

### Validation

- Added regression tests for identical and distinct Office configuration paths, including actual file content checks.
- Automated regression coverage includes both identical and distinct Office configuration paths. A full six-app end-to-end deployment without USB caching remains to be confirmed.

## 0.29.2

### Fixed

- Repository apps added with `Add-OSDApp` can now be downloaded and staged when the OSDCloud USB cache volume is no longer attached.
- When no OSDCloud cache volume is found, repository packages use `Windows\\Temp\\OSDApps\\RepositoryCache` on the offline Windows partition.
- `Get-OSDAppCache` returns an empty result instead of throwing when the optional USB cache volume is absent.

### Validation

- Added Pester regression tests for USB-free repository staging and optional cache inspection.
- Existing SHA256 package validation, `DeviceManifest.json` updates, and SetupComplete staging remain in use.
- Tests passed in GitHub Actions; successful installation of repository packages after SetupComplete must still be verified in an end-to-end deployment.

## 0.29.1

### Added

- Added machine-readable `metadata/builtins.json` for external tooling and repository viewers, with Pester validation against exported built-in commands.
- Added the MIT license and PowerShell Gallery license metadata.
- Added Pester coverage for module import/exports, configuration, DeviceManifest queue behavior, repository authoring/validation, and selective cache-catalog merging.
- Added PSScriptAnalyzer configuration and local validation/build scripts.
- Added GitHub Actions CI for manifest validation, analysis, Pester tests, example validation, distributable builds, and build artifacts.
- Added a dedicated PowerShell Gallery publish workflow that validates, builds, checks release-tag/version alignment, and publishes only through the configured GitHub secret.
- Added PowerShell Gallery metadata and release-process documentation.

### Changed

- Removed the remaining internal `BuiltInApps` staging path from built-in helpers; built-ins now write directly to the single ordered `Apps[]` manifest model.
- Polished and simplified the README and maintained documentation, removed redundant legacy documentation/templates, and aligned cleanup/source terminology.
- Updated GitHub Actions to `actions/checkout@v5`, made PSGallery publishing release-only, and included the MIT license in the distributable module.
- Added a validated cold-cache versus warm-cache performance benchmark and visual, including PreInstall, Runner and per-app timing results.
- Renamed the default standalone SetupComplete runtime log from `Install.log` to `Runtime.log`.
- `Client.log` remains the module-side log for staging, synchronization, cache and repository operations.
- Updated runtime fallback logging and documentation to use `%ProgramData%\OSDApps\Logs\Runtime.log`.

## 0.29.0

### Added

- Added `Get-OSDAppCache` to inspect repository and built-in cache entries, including source, version, architecture, last sync time, size, validity, source policy and sync method.
- Added explicit `PreInstallComplete` and runner duration logging.
- Added generic per-app `AppInstallComplete` timing events across repository and built-in apps.
- Added failure categories for PreInstall and Runner failures.
- Extended repository validation with duplicate references, orphaned manifests, required success codes, archive definition validation, package size and repository free-space information.

### Changed

- Built-in cache metadata now uses consistent `SourcePolicy`, `SyncMethod` and `Updated` fields.
- Built-in refresh completion events include per-app refresh duration.
- Runner success and failure events include total runtime duration.

## 0.28.1

### Changed

- `Set-OSDAppConfiguration` is now silent by default, matching normal PowerShell `Set-*` behavior.
- Added `-PassThru` to return the effective configuration when desired.
- Use `Get-OSDAppConfiguration` to display the active configuration explicitly.

## 0.28.0

### Changed

- Renamed the module and project identity from `OSDAppClient` to `OSDApps`.
- The module entry files are now `OSDApps.psd1` and `OSDApps.psm1`; public cmdlets keep the `OSDApp` noun prefix.
- Consolidated deployment, runtime, cache, and lightweight repository authoring into one module.
- A separate OSDAppRepo module is no longer part of the architecture.

### Added

- Added `New-OSDAppRepository` for creating the static repository structure and empty `catalog.json`.
- Added `New-OSDAppPackage` for building the fixed `Package/Install.ps1` archive contract.
- Added `Add-OSDAppPackage` for generating package metadata, SHA-256, repository folders, and catalog references.
- Added `Test-OSDAppPackage` and `Test-OSDAppRepository` validation helpers.
- Added repository and package source templates under `Examples`.
- Expanded repository documentation so a repository can also be built manually without helper cmdlets.

## 0.27.1

### Fixed

- Selective repository synchronization now merges synchronized packages into the existing `CacheCatalog.json` instead of replacing the catalog with only the latest selection.
- Existing cached repository apps remain registered when another app is synchronized later.
- Re-synchronizing the same app replaces only that app's cache catalog entry.
- Synchronization logging now reports both the number of packages synchronized in the current operation and the total cached package count.

## 0.27.0

### Changed

- Added `Set-OSDAppConfiguration` and `Get-OSDAppConfiguration` as the single general configuration surface.
- Removed the standalone `Set-OSDAppCatalog` configuration cmdlet.
- General configuration now includes `CatalogUri`, `CleanupMode`, `CacheVolumeLabel`, and `LogPath`.
- `CleanupMode` replaces the previous `KeepSource` runtime flag and supports `OnSuccess` or `Never`.
- Staging writes the effective runtime configuration into `DeviceManifest.json`.
- PreInstall uses the staged `CacheVolumeLabel` and `LogPath`.
- The runner uses the staged `CleanupMode` and `LogPath`.
- Repository discovery and synchronization use the configured `CatalogUri`.
- Configuration values can be updated individually; unspecified values are preserved.

## 0.26.0

### Changed

- Simplified `DeviceManifest.json` to one ordered `Apps` array.
- `Apps` contains both repository and built-in apps with a `Source` field and all metadata required by PreInstall and the runner.
- The position of an app in `Apps` is its installation order; no separate `Packages`, `BuiltInApps`, or `InstallOrder` collections are used.
- Every `Add-*` operation appends or moves its complete app entry to the end of `Apps`.
- PreInstall filters built-ins from `Apps` for acquisition/refresh while preserving queue order.
- The runner executes `Apps` from top to bottom across both repository and built-in sources.

## 0.25.0

### Changed

- Replaced fixed built-in priorities with a single global installation order.
- Every `Add-*` call appends its app to `DeviceManifest.json` under `InstallOrder`.
- Repository and built-in apps can now be interleaved in exactly the order they were added.
- Re-adding an app moves it to the end of `InstallOrder` without duplicating it.
- The runner logs the resolved global order through the `InstallOrder` event.
- Manifests without `InstallOrder` retain a compatibility fallback of repository apps first, then built-ins.

## 0.24.3

### Changed

- Built-in apps now use an explicit installation priority independent of staging or manifest order.
- Current built-in installation order:
  1. Microsoft 365 Apps
  2. Microsoft Teams
  3. Google Chrome Enterprise
  4. Mozilla Firefox Enterprise
  5. Adobe Acrobat Unified
- Unknown future built-ins use the default middle priority until an explicit position is assigned.
- Repository apps continue to install before built-in apps.
- The runner logs the resolved built-in order through the `BuiltInInstallOrder` event.

## 0.24.2

### Changed

- Built-in installation order is now deterministic.
- Microsoft 365 Apps is installed before the other built-in apps.
- Adobe Acrobat Unified is installed last.
- Other built-in apps retain their relative order from `DeviceManifest.json`.
- Repository apps continue to run before built-in apps.

## 0.24.1

### Fixed

- Repository staging no longer replaces the entire `DeviceManifest.json`.
- Existing `BuiltInApps` and `Runtime` metadata are preserved when `Add-OSDApp` stages repository apps.
- Existing repository package entries are merged by Id instead of being discarded.
- This fixes deployments where built-in apps were staged first and then silently removed from the manifest by a later repository app stage.

## 0.24.0

### Changed

- Repository packages now use a single top-level `Package` directory inside `Package.zip`.
- The runtime resolves repository installers from `Package/Install.ps1`.
- Repository `Install.ps1` now runs with the extracted `Package` directory as its working directory.
- Root-level `Install.ps1` archives are no longer supported.

## 0.23.0

### Changed

- Simplified the repository contract again: every deployable package now keeps `manifest.json` directly beside `Package.zip`.
- Root `catalog.json` points directly to package manifests per app and architecture.
- Package manifests contain all package metadata: Id, display name, version, architecture, success codes, archive filename, and SHA-256.
- `Package.zip` is resolved relative to its sibling package manifest; no `SourcePath` field is required.
- No migration or legacy repository compatibility is provided.

## 0.22.0

### Changed

- Adopted a clean repository contract using root `catalog.json` plus one `Apps/<Id>/manifest.json` per app.
- OSDAppClient resolves only the required app manifest(s), then flattens package metadata internally for the existing cache and runtime pipeline.
- Package `SourcePath` is relative to the app manifest.
- `Get-OSDAppCatalog` now reports app count instead of package count.
- No legacy single-manifest repository compatibility is provided.

## 0.21.5

### Changed

- `Add-OSDApp` now automatically synchronizes only the requested repository app(s) when an online catalog is configured.
- Normal repository deployment no longer requires a separate `Sync-OSDAppRepository` step.
- `Sync-OSDAppRepository` remains available for explicit full or selective cache preloading/refresh.
- If no online catalog is configured, `Add-OSDApp` can still use an existing valid repository cache.

## 0.21.4

### Fixed

- Existing OSD Apps blocks in `SetupComplete.cmd` are now refreshed instead of being left untouched.
- This repairs stale runner paths from older staging runs while preserving unrelated SetupComplete content.
- Current repository and built-in staging both use `%SystemDrive%\Windows\Temp\OSDApps` for PreInstall and Runner execution.

## 0.21.3

### Fixed

- Repository packages using a relative `Archive.SourcePath` can now be synchronized from an HTTP/HTTPS catalog.
- Relative package paths are resolved against the catalog location, so a catalog such as `https://host/container/manifest.json` can reference `Packages/App/Version/Architecture/Package.zip`.
- Local filesystem repositories continue to resolve `SourcePath` relative to the local manifest directory.

## 0.21.2

### Fixed

- Removed an accidental duplicated tail from both Firefox Enterprise public cmdlet files that caused a PowerShell parser error during module import.
- No Firefox acquisition, cache, staging, or installation behavior changed.

## 0.21.1

### Changed

- Kept Firefox Enterprise defaults intentionally simple: Rapid Release, x64, and `en-US`.
- Added PowerShell tab completion for common Firefox locales on `Add-OSDAppMozillaFirefoxEnterprise` and `Sync-OSDAppMozillaFirefoxEnterprise`.
- `-Language` remains open for other valid Mozilla locale values; completion is guidance rather than a hard allow-list.

### Validation

- Validated blank-cache bootstrap for Google Chrome Enterprise x64 and Mozilla Firefox Enterprise Rapid x64.
- Both vendor MSI packages were downloaded during SetupComplete, persisted to the OSDCloud USB cache, staged locally, and installed successfully with exit code `0`.

## 0.21.0

### Added

- Added `GoogleChromeEnterprise` built-in support using Google's vendor-hosted Enterprise MSI.
- Added x64 and x86 Chrome cache variants; x64 is the default.
- Added `MozillaFirefoxEnterprise` built-in support using Mozilla's official MSI download endpoint.
- Added Firefox Rapid Release and ESR channels, x64/x86 architectures, and configurable Mozilla language.
- Added generic `VendorMsi` SetupComplete runtime support using `msiexec.exe /i ... /qn /norestart`.
- Added MSI installation heartbeat, timeout protection, and success handling for exit codes `0` and `3010`.

### Validation

- Chrome and Firefox integrations are implemented but still require end-to-end OSD validation.


## 0.20.3

### Changed

- Replaced large SetupComplete `Invoke-WebRequest` downloads with streaming `HttpClient` transfers.
- Uses temporary `.download` files and only replaces the destination after a successful transfer.
- Added runtime transfer metrics: bytes, size, duration, and average MB/s.
- Improved module download progress with transferred/total size, percentage, average speed, elapsed time, and estimated remaining time.
- Applied the streaming path to Adobe Acrobat Unified, Teams MSIX/bootstrapper, and Office Deployment Tool bootstrapper downloads.


## 0.20.2

### Changed

- Added a 15-minute default timeout for Adobe Acrobat Unified installation during SetupComplete.
- Added 60-second `BuiltInInstallWaiting` heartbeat events while Adobe Setup is still running.
- Added `BuiltInInstallTimeout` logging and process-tree termination on timeout.
- Added `-InstallTimeoutMinutes` to `Add-OSDAppAdobeAcrobatUnified` for controlled overrides.


## 0.20.1

### Added

- Added `AdobeAcrobatUnified` as a third built-in app.
- Adobe Acrobat Unified now supports both x64 and x86 packages; x64 is the default and cache variants are stored separately.
- Added `Sync-OSDAppAdobeAcrobatUnified` and `Add-OSDAppAdobeAcrobatUnified`.
- Uses Adobe's official x64 Unified Acrobat/Reader ZIP as the vendor source.
- Supports the same optional OSDCloud USB cache model as Microsoft 365 Apps and Teams.
- Cached Adobe content remains compressed as `Package.zip`; the runner extracts it locally during SetupComplete and launches `Setup.exe /sAll /msi ADDLOCAL=ALL`.
- Supports blank-cache bootstrap, cache reuse, no-USB online acquisition, and offline fallback when a complete cached payload has already been staged.


## 0.19.0

### Changed

- Simplified the public command surface. Low-level cache validation, content staging, repository synchronization internals, and SetupComplete integration are now private helpers.
- Renamed local repository cache metadata from `CacheManifest.json` to `CacheCatalog.json`.
- `Get-OSDAppCatalog` now reports compact catalog status instead of listing apps.
- `Get-OSDApp` is now the unified app discovery command for online repository state, USB cache state, and built-in apps.
- `Add-OSDApp` remains repository-only; Microsoft 365 Apps and Teams use dedicated Add commands.
- Built-in completion logging now distinguishes synchronization from an actual content/version change:
  - Microsoft 365 Apps: `CacheSynchronized`, `VersionChanged`
  - Microsoft Teams: `CacheSynchronized`, `PackageUpdated`

### Built-in acquisition

- Built-in deployment no longer requires pre-populated USB media.
- A connected volume labeled `OSDCloud` is detected automatically and used as cache source and destination.
- A blank `OSDCloud` volume can be populated during SetupComplete.
- Without USB media, built-ins can be acquired directly to the local Windows runtime when online.
- Existing cached content is staged as fallback before the full-Windows refresh phase.

### Validated

- Blank `OSDCloud` USB cache bootstrap for Microsoft 365 Apps and Teams.
- Existing-cache + online refresh for Microsoft 365 Apps and Teams.
- Successful local staging, installation, and runtime cleanup scheduling for both built-ins.

## 0.18.x

Introduced optional USB built-in acquisition, dedicated built-in Add commands, OSDCloud-style verbose console output, and the standalone full-Windows PreInstall refresh phase.
