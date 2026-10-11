# Validation matrix

This page tracks real OSDCloud v2 / OSDApps deployment scenarios. **Staging success alone is not an installation success**: the Windows `SetupComplete.cmd` phases must finish and the individual app results must be checked.

## Scenario coverage

| Scenario | Status | Evidence / expected behavior |
| --- | --- | --- |
| Empty OSDCloud USB cache, online | **Validated — 0.34.0 PC 1 (11 Oct 2026)** | Six built-ins freshly acquired and signed where supported; 8/8 installed. Earlier 0.30.0 six-app test also passed. |
| Existing OSDCloud USB cache, online | **Validated — 0.30.0 tests 3 and 4** | Reuse/freshness checking; altered Office configuration tested separately |
| No USB cache, online | **Validated — 0.30.0 test 1** | Built-ins acquired on Windows volume; repository apps staged in WinPE |
| Existing OSDCloud USB cache, offline | **Validated — 0.34.0 PC 2 (11 Oct 2026)** | LAN disconnected; six BuiltInRefreshSkipped events, five built-in signer/publisher checks and 8/8 successful installations. Earlier 0.30.0 six-app test also passed. |
| No USB, offline | **Not yet validated** | Without a complete staged fallback, PreInstall is expected to stop before Runner |

## OSDApps 0.34.0 release-candidate physical validation — 11 October 2026

These were **Windows SetupComplete executions on two freshly reinstalled x64 PCs**, not just WinPE staging or module unit tests. They exercised development commit `201595501b75875cfa316a989385cedb23ec28e9` from PR #14. The module's version label was still 0.33.0 in this prerelease commit; the tested feature code became the 0.34.0 release candidate after documentation and version preparation.

### Application queue (same on both PCs)

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

The measured total is the sum of the two phases, **not** OSDCloud image application, WinPE download/staging, reboot or OOBE time. A single run on each machine is not a performance benchmark.

**PC 1 — complete cold source acquisition.** ODT populated the Office cache (`Version=16.0.20326.20142`, `VersionChanged=True`). Teams, Chrome, Firefox, Cisco Webex and Adobe reported `PackageUpdated=True`. `BuiltInSignatureVerified` confirmed the expected publishers for Office ODT `setup.exe`, Teams `teamsbootstrapper.exe`, Google Chrome MSI, Firefox MSI and Cisco Webex MSI; the four downloaded MSI/bootstrapper candidates were also checked before the USB copy was accepted. `PreInstallComplete` recorded six built-ins and `InstallComplete` recorded eight successful installations with `CleanupMode=OnSuccess`.

**PC 2 — no network.** LAN was physically disconnected before the first Windows boot and remained disconnected for SetupComplete. `CacheVolumeFound` confirmed `E:\OSDApps`, and `BuiltInRefreshSkipped` appeared **six times**, one for each built-in (Office, Teams, Chrome, Firefox, Cisco Webex and Adobe). The five signable staged MSI/EXE packages passed the expected-publisher gate while offline. All six built-in installs and both SHA-256-validated repository package installs returned code `0`, followed by `InstallComplete; ApplicationCount=8; CleanupMode=OnSuccess`.

### Additional validation and boundaries

- A separate warm-cache deployment completed four application installs successfully: Teams, Firefox, Notepad++ and Omnissa Horizon Client (`PreInstall 6.2 s`, `Runner 83.5 s`). A full-Windows Chrome cache sync retained an unchanged trusted MSI (`Updated=False`).
- The Windows 11 OSDApps Viewer showed valid publisher signature states for the five signable built-in cache entries, separate from repository SHA-256 integrity; the two WinPE PCs exercised read-only inventory, app staging and cache inspection.
- Authenticode coverage is intentionally **partial**: Teams MSIX and the Microsoft 365 Apps data tree are not cryptographically verified by the bootstrapper/ODT checks, and Adobe Acrobat's outer ZIP is `Not assessed`. No negative/tampered-package test was performed on hardware; such rejection behavior is covered by unit tests.
- An `ExitCode=0` validates the installer/provisioning path, not product activation, all interactive features, or the effective installed Office update channel. Office's reported cold-cache build differs from the earlier cached build; neither result alone establishes channel correctness.
- Raw device logs were reviewed during validation, but private machine logs and enterprise repository binaries are **not committed** into this public project.

## Real-world end-to-end validation — OSDApps 0.30.0

**Executed:** 9 October 2026, on freshly deployed Windows installations via OSDCloud v2. All four scenarios used OSDApps **0.30.0** from PowerShell Gallery, `CleanupMode=Never`, the same six application IDs, and the same installation order. These are four deployment executions, not repeated statistical benchmark samples.

The application queue, in order:

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

**24 of 24 queued application executions reported successful completion** across the four `Runtime.log` files (each application installer returned exit code `0`). This is an installer/runtime result, not proof of every app's later activation or interactive launch.

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

Test 5 started with a fully populated `OSDCloud` USB cache. All expected built-in source files were checked on the USB stick before reboot, and the two repository packages had already been staged. The network connection was physically disconnected before boot and remained unavailable throughout SetupComplete.

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
| Fully offline OSDCloud v2 / SetupComplete | In WinPE, USB and local staged MSI were present and **SHA256-identical** before reboot; physically disconnected network; Windows PreInstall logged `CacheAvailable=True`, `CacheVolumeFound` for `E:\OSDApps`, and `BuiltInRefreshSkipped` due to no network; PreInstall 3.5 s; installed from **local staged MSI**, `BuiltInInstallComplete ExitCode=0` in 8 s; Runner 8.5 s; `InstallComplete ApplicationCount=1`; `CleanupSkipped` as configured (`Never`) | Pass |

The offline log demonstrates the USB cache was **detected** during SetupComplete, not that the installer ran directly from the USB volume; the payload had already been copied locally in WinPE. Both SetupComplete deployments used a one-app `CiscoWebex` queue. These measured durations cover only their named phases, not WinPE/OOBE or the entire deployment. The first online run did not populate the USB cache because the volume was not detected at runtime.

**Remaining limitations:** ARM64 MSI retrieval, signature and installation have **not** been field-validated; the combined seven-app SetupComplete scenario has not been run. USB cache re-use across an additional **online SetupComplete** run and recovery under other network failures are also not established by these tests.

## Validated built-ins and remaining variants

The 0.30.0 end-to-end tests above cover Microsoft 365 Apps, Microsoft Teams, Adobe Acrobat Unified **x64**, and Google Chrome Enterprise **x64**. The earlier validation matrix also listed Mozilla Firefox Enterprise Rapid x64 as validated; it was **not** part of these four 0.30.0 runs.

Still requiring separate end-to-end checks:

- Google Chrome Enterprise x86
- Mozilla Firefox Enterprise Rapid x86
- Mozilla Firefox Enterprise ESR x64/x86
- Adobe Acrobat Unified x86
- Microsoft Teams x86 / arm64 and Microsoft 365 Apps x86 (new public architecture contract)

## Success criteria and logs

1. WinPE stages the intended `DeviceManifest.json` queue and any available repository payload.
2. USB cache is detected only when connected, or a local no-USB path is selected.
3. Repository `Package.zip` files validate against their SHA-256 metadata.
4. `SetupComplete.cmd` starts `Invoke-OSDAppPreInstall.ps1`; `PreInstallComplete` reports success.
5. `Invoke-OSDAppRunner.ps1` installs the six queued applications; each expected `*InstallComplete` has an accepted exit code.
6. The final `InstallComplete` reports the expected application count.
7. The configured `CleanupMode` is honored; for these tests `Never` retained the staged runtime.

Windows runtime log:

```text
%ProgramData%\OSDApps\Logs\Runtime.log
```

Module/cache log when USB is attached:

```text
<OSDCloud>:\OSDApps\Logs\Client.log
```

For a no-USB run, module-side logging may be on the Windows volume, while the standalone runner still uses the configured Windows runtime log.

## Historical cold/warm benchmark — OSDApps 0.29.1

The earlier 0.29.1 benchmark is retained separately, using the same hardware, USB stick, application set and install order for its cold/warm pair.

| Phase | Cold USB | Warm USB |
| --- | ---: | ---: |
| PreInstall | 125.2 s | 40.6 s |
| Runner | 330.7 s | 327.4 s |
| Measured Windows total | 455.9 s | 368.0 s |

See [Performance](performance.md) for the historical benchmark details and the updated 0.30.0 comparison.
