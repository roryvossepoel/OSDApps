# OSDApps documentation

OSDApps is CLI-first. Use PowerShell to configure, cache and stage applications and machine-context scripts; use OSDApps Viewer to inspect what was prepared. Start with the workflow for the environment you are actually using.

## Start here

| I want to... | Guide | Where it runs |
| --- | --- | --- |
| Understand the full deployment sequence | [Getting started](getting-started.md) | Windows preparation → WinPE → first Windows boot |
| Put the module and reusable app content on USB | [Prepare a USB cache](../Examples/Prepare-UsbCache.md) | Full Windows preparation machine |
| Stage apps after OSDCloud has applied Windows | [Online WinPE deployment](../Examples/WinPE-Online.md) | WinPE, before the first Windows boot |
| Integrate staging with OSDT or another launcher | [Launcher integration](../Examples/Launcher-Integration.md) | WinPE; exit-code gate before the launcher reboots |
| Deploy without network from prepared content | [Offline WinPE deployment](../Examples/WinPE-Offline.md) | WinPE and SetupComplete, with a complete matching cache |
| Preflight staging and inspect cache, signatures and logs | [Getting started](getting-started.md#3-inspect-before-reboot) and [OSDApps Viewer](viewer.md) | WinPE or full Windows |
| Audit or reconcile long-lived repository cache content | [Cache health and reconciliation](repository.md#cache-health-and-reconciliation) | Full Windows preparation or WinPE cache session |
| Package your own application or machine-context script | [Package authoring walkthrough](../Examples/Build-Repository-Package.md) | Full Windows authoring machine |

**Do not run deployment staging examples against your preparation machine's Windows drive.** Each example identifies its environment and what it changes. The Viewer is read-only; the Add and Sync commands are not.

## User guides

| Topic | Contents |
| --- | --- |
| [Built-in applications](built-in-apps.md) | Per-app configuration, architectures, vendor sources and signature/publisher policy |
| [Repository apps and scripts](repository.md) | Catalog/alias structure, package authoring, cache health, transactional reconciliation and SHA-256 integrity |
| [Viewer](viewer.md) | Launch options, tab contents, cache/version/signature meanings and read-only boundaries |
| [Runtime and cleanup](runtime.md) | SetupComplete, PreInstall, Runner, machine-readable results, configuration, logs and failure handling |
| [FAQ and troubleshooting](faq.md) | Environment mistakes, cache and network failures, trust checks, logs and upgrades |

## Architecture and development

| Topic | Contents |
| --- | --- |
| [Architecture](architecture.md) | Acquisition, cache, local staging and the ordered device manifest |
| [Public metadata](public-metadata.md) | `metadata/builtins.json`, icons and external Viewer consumers |
| [Contributing](../CONTRIBUTING.md) | Contribution and built-in app request policy |
| [Maintenance](maintenance.md) | Optional read-only USB, release and saved-result checks on the preparation PC |
| [Releasing](releasing.md) | CI, module build, release tags and verified PowerShell Gallery publication |

## Evidence and history

[Validation matrix](testing.md) records what was actually tested, on which version, and what remains outside the test scope. [Performance](performance.md) keeps the measured phase timings and their limitations. [Changelog](../CHANGELOG.md) preserves version-specific behavior changes and migration history.

Historical test results are not claims about every currently supported architecture or every device. A successful installer exit code does not independently prove product activation, sign-in or all interactive features.

## Common terms

| Term | Meaning |
| --- | --- |
| Preparation machine | Full Windows computer used to download the module, build packages or maintain USB content |
| Windows target | The offline Windows installation selected for deployment, not the preparation machine |
| USB cache | Content under `\OSDApps` on the volume identified by `CacheVolumeLabel` (default `OSDCloud`) |
| Local staging | `Windows\Temp\OSDApps` under the Windows target, containing its manifest, runtime and app content |
| Built-in | Vendor-native integration maintained by OSDApps; payloads are not distributed by the module |
| Repository package | Your own `Package.zip` plus published metadata, classified as `Application` or `Script` |
| Staged | Queued for SetupComplete; not evidence of successful installation |

[Back to the project](../README.md)
