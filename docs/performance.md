# Performance

OSDApps records PreInstall and Runner durations separately. The measurements below describe the stated versions and conditions, not a performance guarantee for the current release.

The [validation matrix](testing.md) includes newer 0.36.0 and 0.39.0 measurements and the recent Gallery workflow reports. Office replacement acquires a fresh complete generation. PreInstall can now skip that acquisition when a compatible generation matches the CDN descriptor or requested build pin; physical timings for this new reuse path are not yet measured. The recent Gallery workflow reports include no new timings.

## OSDApps 0.35.0 release candidate — populated USB cache, online (12 October 2026)

A freshly reinstalled x64 PC completed the eight-app queue after hard offline-readiness preflight passed in WinPE. The populated USB cache remained attached and networking was available. All six built-ins recorded cache use; Cisco Webex refreshed while the other five cached packages were retained.

| Phase | Duration | Result |
| --- | ---: | --- |
| PreInstall | 53.9 s | Succeeded; six built-ins |
| Runner | 369.0 s | 8/8 successful |
| **Measured Windows total** | **422.9 s (7:03)** | **Succeeded** |

The total excludes image deployment, WinPE staging, reboot and OOBE. It is one release-candidate field observation, not a controlled cache-speed comparison or performance guarantee. See the [0.35.0 validation record](testing.md#osdapps-0350-release-candidate-physical-validation--12-october-2026) for integrity, result-correlation and cleanup evidence.

## OSDApps 0.34.0 — full eight-app deployment comparison (11 October 2026)

On two freshly installed x64 test PCs, the same six built-ins and two repository apps completed through SetupComplete with `CleanupMode=OnSuccess`. Built-in installer signatures and expected publishers were enforced on Office `setup.exe`, Teams `teamsbootstrapper.exe`, Chrome, Firefox and Cisco Webex; Adobe's outer ZIP remains outside the Authenticode scope.

| Scenario | PreInstall | Runner | Measured Windows total | Results |
| --- | ---: | ---: | ---: | --- |
| PC 1 — initially empty OSDCloud USB cache, online | 551.9 s | 366.7 s | **918.6 s (15:19)** | **8/8** installed |
| PC 2 — populated USB cache, LAN disconnected | 5.4 s | 394.2 s | **399.6 s (6:40)** | **8/8** installed |

The offline PreInstall phase was **546.5 s shorter**; the overall measured Windows phase was **519.0 s shorter**. PC 1 downloaded vendor content (including Office/Adobe), while PC 2 recorded six `BuiltInRefreshSkipped` events and used signed local content. The two devices and their network/cache conditions differed, so these are observed times, **not a controlled hardware speed comparison or guaranteed throughput**. WinPE staging, OSDCloud OS application, boot and OOBE are excluded.

See the [0.34.0 validation matrix](testing.md#osdapps-0340-release-candidate-physical-validation--11-october-2026) for app order, package variants and verification boundaries.

## End-to-end measurements — OSDApps 0.30.0 (9 October 2026)

Four fresh OSDCloud v2 deployments validated the same six-application queue: Microsoft 365 Apps, Teams, Chrome Enterprise, Adobe Acrobat Unified, Omnissa Horizon Client (repository), and Notepad++ (repository). The fourth run changed the Office XML to MonthlyEnterprise / nl-nl with Visio and Project.

| Scenario | PreInstall | Runner | Measured Windows total | Application results |
| --- | ---: | ---: | ---: | --- |
| 1. No USB cache, online | 217.3 s | 329.3 s | **546.6 s (9:07)** | 6/6 successful |
| 2. Cold USB cache, online | 114.2 s | 328.4 s | **442.6 s (7:23)** | 6/6 successful |
| 3. Warm USB cache, online | 41.7 s | 330.4 s | **372.1 s (6:12)** | 6/6 successful |
| 4. Warm USB, modified Office XML | 104.1 s | 346.0 s | **450.1 s (7:30)** | 6/6 successful |

The timings are reported by the runtime itself; the measured total is the **sum of the PreInstall and Runner durations**, not full end-to-end OSDCloud elapsed time. It excludes the module install, WinPE staging and brief hand-off gaps.

### Acquisition/refresh timings (seconds)

| Built-in app | No USB | Cold USB | Warm USB | Warm USB + changed Office |
| --- | ---: | ---: | ---: | ---: |
| Microsoft 365 Apps | 69.4 | 74.5 | 31.8 | 93.5 |
| Microsoft Teams | 4.3 | 5.4 | 1.2 | 1.5 |
| Google Chrome Enterprise | 2.4 | 3.0 | 0.5 | 0.5 |
| Adobe Acrobat Unified | 138.0 | 27.6 | 4.7 | 4.9 |

The no-USB Adobe transfer took approximately 137 seconds, versus 21.9 seconds for the cold-USB Adobe transfer. This is an observed network/CDN difference and **must not be represented as caching speedup**: both scenarios acquired Adobe content from the vendor for the first time.

### Per-application processing times (seconds)

These timings are from `ApplicationInstallComplete` and include any per-item validation or extraction performed in Runner.

| Application | No USB | Cold USB | Warm USB | Changed Office |
| --- | ---: | ---: | ---: | ---: |
| Microsoft 365 Apps | 136.4 | 136.5 | 138.5 | 150.8 |
| Microsoft Teams | 1.1 | 1.1 | 1.1 | 1.1 |
| Google Chrome Enterprise | 18.1 | 18.1 | 18.2 | 18.1 |
| Adobe Acrobat Unified | 107.8 | 107.7 | 107.8 | 109.8 |
| Omnissa Horizon Client | 55.2 | 55.4 | 55.2 | 55.5 |
| Notepad++ | 10.2 | 9.2 | 9.2 | 10.2 |

**Warm-cache effect:** cold USB versus warm USB saved **70.5 seconds** in the measured Windows phases (442.6 s to 372.1 s). PreInstall saved 72.5 seconds while Runner differed by 2.0 seconds. The USB cache retained the same Office build (16.0.20430.20146), and Teams/Chrome/Adobe reported `PackageUpdated=False`; Teams refreshed only its small bootstrapper.

**Changed Office configuration:** Office PreInstall grew from 31.8 s to 93.5 s and Office's install item from 138.5 s to 150.8 s. Although the Office build stayed the same, **Word, Excel, Visio and Project executables were verified present after SetupComplete**. The effective Office update channel and licensing activation still need separate verification.

All four runs completed the six-entry queue successfully according to `Runtime.log` (24 successful installer/provisioning result codes in total). These are **single field observations**, not repeatability or statistical performance claims; installation/activation of all apps has not been interactively validated.

See [Validation matrix](testing.md) for the test sequence, acceptance criteria, cache behavior and outstanding coverage.

## Warm USB cache, fully offline — OSDApps 0.30.0 test 5 (9 October 2026)

| Phase | Duration |
| --- | ---: |
| PreInstall (offline cache fallback) | 7.6 s |
| Runner (six applications) | 380.7 s |
| **Measured total** | **388.3 s (6:28)** |

All six installer/provisioning calls exited with code `0` with networking disconnected before reboot. The populated USB cache was recognized. Office, Teams and Chrome used existing local staging, while Adobe was restaged from USB after a local staging path mismatch. That mismatch is corrected in **0.30.1**; these numbers describe the original successful **0.30.0** field run, not a benchmark of the patched release.

## Historical cold/warm cache benchmark — OSDApps 0.29.1

The following benchmark was captured with OSDApps 0.29.1 using the same hardware, the same OSDCloud USB flash drive, the same application order, and the same deployment configuration.

![OSDApps 0.29.1 cold vs warm cache benchmark](images/cold-warm-benchmark.svg)

| Phase | Cold cache | Warm cache | Difference |
| --- | ---: | ---: | ---: |
| PreInstall / refresh | 125.2 s | 40.6 s | -84.6 s |
| Runner / installations | 330.7 s | 327.4 s | -3.3 s |
| **Total measured Windows phase** | **455.9 s** | **368.0 s** | **-87.9 s** |

That is approximately:

```text
Cold cache  7 min 36 s
Warm cache  6 min 08 s
Difference  1 min 28 s faster
```

The warm-cache run is about 19% faster across the measured PreInstall + Runner phases.

## Application set

The validated queue deliberately mixed built-in and repository applications:

| Application | Source |
| --- | --- |
| Microsoft 365 Apps | Built-in |
| Microsoft Teams | Built-in |
| Google Chrome Enterprise | Built-in |
| Omnissa Horizon Client | Self-maintained repository example |
| Notepad++ | Self-maintained repository example |
| Adobe Acrobat Unified | Built-in |

`OmnissaHorizonClient` and `NotepadPlusPlus` were packages from the test repository used for this benchmark. They are not built into OSDApps. Their repository synchronization/cache validation occurred in WinPE; the Runner measurements shown here cover the later local validation/extraction/installation phase.

The installation order was identical for both runs.

## What the benchmark shows

The important result is not only that the warm-cache deployment is faster. The location of the time saving is equally important.

```text
PreInstall
125.2 s → 40.6 s
84.6 s faster

Runner
330.7 s → 327.4 s
3.3 s faster
```

The Runner remains almost identical between both runs. The cache therefore does what it is designed to do: reduce acquisition and refresh work before installation while keeping the installation queue and install behavior stable.

## Per-application installation consistency

The complete application-processing timings were also highly consistent:

| Application | Cold cache | Warm cache | Difference |
| --- | ---: | ---: | ---: |
| Microsoft 365 Apps | 142.6 s | 141.6 s | -1.0 s |
| Microsoft Teams | 1.1 s | 1.1 s | 0.0 s |
| Google Chrome Enterprise | 18.1 s | 18.2 s | +0.1 s |
| Omnissa Horizon Client | 48.9 s | 47.7 s | -1.2 s |
| Notepad++ | 10.2 s | 9.2 s | -1.0 s |
| Adobe Acrobat Unified | 109.4 s | 109.3 s | -0.1 s |

In this recorded pair, the difference was concentrated in acquisition rather than installation. Two runs do not establish a general performance rule.

For repository applications, `ApplicationInstallComplete` includes the complete processing time for that queue item, including SHA-256 validation and extraction before `Install.ps1` is started.

## Cold-cache acquisition observations

During the cold run:

| Built-in | Refresh duration | Download observation |
| --- | ---: | --- |
| Microsoft 365 Apps | 84.5 s | Office content synchronized by ODT |
| Microsoft Teams | 6.0 s | 272.9 MB MSIX downloaded in 4.3 s |
| Google Chrome Enterprise | 3.0 s | 161.8 MB MSI downloaded in 2.3 s |
| Adobe Acrobat Unified | 28.1 s | 1617.6 MB ZIP downloaded in 22.7 s |

The measured transfer rates for the large direct downloads were approximately:

```text
Teams MSIX   63.8 MB/s
Chrome MSI   70.2 MB/s
Adobe ZIP    71.4 MB/s
```

Microsoft 365 Apps is intentionally different: OSDApps delegates Office synchronization to the Office Deployment Tool rather than implementing a separate generic HTTP freshness mechanism.

## Warm-cache behavior

During the warm run:

- Microsoft 365 Apps retained build `16.0.20430.20146` and reported `VersionChanged=False`;
- Microsoft Teams reported `PackageUpdated=False`;
- Google Chrome Enterprise reported `PackageUpdated=False`;
- Adobe Acrobat Unified reported `PackageUpdated=False`;
- Omnissa Horizon Client and Notepad++ both reported `PackageCurrent` during repository synchronization.

The only intentional Teams download was the small Teams bootstrapper. The much larger Teams MSIX was reused from cache.

This was the observed warm-cache behavior in 0.29.1. Office replacement uses a fresh complete generation, as described above:

```text
existing cache
→ validate freshness
→ download only when required
→ stage locally
→ install in the same queue order
```

## Reproducing the benchmark

This is the historical 0.29.1 command sequence, including its module path and test-repository IDs. For a new test, use the current [online deployment guide](../Examples/WinPE-Online.md), supply your own repository and record the loaded module version and settings. Do not expect a current build to reproduce historical timings.

The historical runs used this application order:

```powershell
Import-Module E:\Modules\OSDApps\OSDApps.psd1 -Force

Set-OSDAppConfiguration `
    -CatalogUri "https://example.blob.core.windows.net/osdapps/catalog.json" `
    -CleanupMode Never

# Built-ins
Add-OSDAppMicrosoft365Apps
Add-OSDAppMicrosoftTeams
Add-OSDAppGoogleChromeEnterprise

# Example applications from the configured repository
Add-OSDApp OmnissaHorizonClient
Add-OSDApp NotepadPlusPlus

# Built-in
Add-OSDAppAdobeAcrobatUnified
```

For the cold run, start with an empty OSDApps cache. For the warm run, reuse the cache populated by the cold run.

Relevant runtime events include:

```text
BuiltInRefreshComplete
PreInstallComplete
ApplicationInstallComplete
InstallComplete
```

The runtime log is written by default to:

```text
%ProgramData%\OSDApps\Logs\Runtime.log
```

The module-side cache and staging log remains:

```text
<OSDCloud>:\OSDApps\Logs\Client.log
```

Performance depends on network, vendor CDN throughput, storage, CPU, application behavior, and hardware. These numbers are therefore a validated reference measurement, not a guaranteed deployment duration.
