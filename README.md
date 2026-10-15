# OSDApps

[![PowerShell Gallery Version](https://img.shields.io/powershellgallery/v/OSDApps?label=PowerShell%20Gallery)](https://www.powershellgallery.com/packages/OSDApps)
[![PowerShell Gallery Downloads (latest version)](https://img.shields.io/badge/dynamic/xml?url=https%3A%2F%2Fwww.powershellgallery.com%2Fapi%2Fv2%2FPackages%3F%2524filter%3DId%2Beq%2B%2527OSDApps%2527%2Band%2BIsAbsoluteLatestVersion%2Beq%2Btrue%26%2524select%3DVersion%252CVersionDownloadCount&query=%2F%2F*%5Blocal-name()%3D'VersionDownloadCount'%5D&label=downloads%20(latest)&color=blue&cacheSeconds=3600)](https://www.powershellgallery.com/packages/OSDApps)
[![Module CI](https://github.com/roryvossepoel/OSDApps/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/roryvossepoel/OSDApps/actions/workflows/ci.yml)
[![Windows PowerShell 5.1](https://img.shields.io/badge/Windows%20PowerShell-5.1-blue)](#install-from-powershell-gallery)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**Prepare applications and machine-context scripts with PowerShell. Run them through SetupComplete. Inspect the result with a read-only Viewer.**

OSDApps adds application deployment to OSDCloud v2: vendor-native built-ins, organization-managed repository packages, an optional USB cache, and one ordered installation queue before OOBE continues.

[Getting started](docs/getting-started.md) · [Examples](Examples/README.md) · [Viewer](docs/viewer.md) · [Documentation](docs/README.md) · [Changelog](CHANGELOG.md)

## How it works

![OSDApps end-to-end architecture](docs/images/osdapps-architecture.svg)

| Phase | Runs in | Responsibility |
| --- | --- | --- |
| Prepare cache, optionally | Full Windows | `Sync-OSDApp*` downloads content to an OSDCloud cache volume. |
| Stage | WinPE, after Windows is applied | `Add-OSDApp*` writes the device queue, copies available content and prepares SetupComplete. Repository packages are synchronized here when requested. |
| Acquire and install | First Windows boot | Standalone PreInstall refreshes built-ins or uses a usable local fallback; Runner attempts each independent queue entry once and records partial failures. |
| Validate and inspect | WinPE or Windows | `Test-OSDAppDeployment` checks staged readiness before reboot; `Show-OSDAppUI` displays state; `Get-OSDAppDeploymentResult` reads the final machine result. |

The CLI owns configuration and automation. The Viewer does not add or remove apps. The OSDApps module does **not** need to be installed in the deployed Windows installation: the required runtime scripts are staged automatically.

## Install from PowerShell Gallery

**Run on a full Windows preparation machine**, or in an online WinPE session with PowerShellGet available. These examples pin **0.39.0**:

```powershell
Install-Module OSDApps -RequiredVersion 0.39.0 -Scope CurrentUser -Force -SkipPublisherCheck
Import-Module OSDApps -RequiredVersion 0.39.0 -Force
```

For offline WinPE, save the module to USB first; see [Prepare a USB cache](Examples/Prepare-UsbCache.md). PowerShellGet is the documented WinPE/Windows PowerShell 5.1 installation path. `Install-PSResource` is an alternative only on a machine where PSResourceGet is already available.

## Quick start

**Run this in WinPE after OSDCloud has applied Windows, before the first Windows boot.** The module must already be loaded. Internet is needed during the first Windows boot unless suitable content was cached beforehand.

This minimal example uses two built-ins and does not require a repository:

```powershell
$ErrorActionPreference = 'Stop'

if (-not (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT')) {
    throw 'Run this staging example in WinPE, not on the Windows preparation machine.'
}

Set-OSDAppConfiguration -CleanupMode OnSuccess

Add-OSDAppMicrosoftTeams -Architecture x64
Add-OSDAppMozillaFirefoxEnterprise -Channel Rapid -Language en-US -Architecture x64

# Optional: inspect the queue without querying an online repository.
Show-OSDAppUI -Offline
```

The Add cmdlets discover the offline Windows target, or accept an explicit `-WindowsPath`. They prepare installation; they do **not** install these apps in WinPE. Keep the cache USB attached through SetupComplete when it is being used, and close the Viewer before rebooting.

SetupComplete is intentionally one-shot. OSDApps does not install a retry task or RunOnce entry. A normal installer/source failure is recorded per application and independent remaining entries continue; a manifest, repository-integrity or supported-publisher trust failure aborts the queue. Any unsuccessful entry retains local staging and makes the final machine result `Failed`.

Repository packages may be classified as `Application` or `Script`. Both use
the same versioned `Package.zip`, `Package/Install.ps1`, SHA-256 enforcement,
ordered queue and failure contract; the type changes presentation and reporting,
not execution privileges or trust.

For a complete workflow, use the [online WinPE example](Examples/WinPE-Online.md) or the [offline WinPE example](Examples/WinPE-Offline.md). Neither example formats a disk or reboots automatically.

## Application sources

| Source | Content owner | Version and acquisition |
| --- | --- | --- |
| Built-in | Software vendor | OSDApps uses a vendor-native acquisition path and refreshes content in full Windows. |
| Repository | Your organization | You publish `catalog.json`, per-app manifests and `Package.zip` archives. OSDApps resolves the selected variant and verifies its SHA-256. |

The six built-ins are **Microsoft 365 Apps, Microsoft Teams, Adobe Acrobat Unified, Google Chrome Enterprise, Mozilla Firefox Enterprise and Cisco Webex**. Their supported architectures and configuration options differ; see [Built-in applications](docs/built-in-apps.md).

Repository apps use `Add-OSDApp -Name <Id>`. Configure your own `CatalogUri` first, or use a previously synchronized repository cache with `-SkipCacheRefresh`. Names such as Notepad++ and Omnissa Horizon Client in the test reports are **example repository packages**, not bundled built-ins. See [Repository applications](docs/repository.md).

Long-lived cache media can be audited without mutation using
`Get-OSDAppCacheHealth`. Repository owners can declare retired aliases, preview
complete desired-state reconciliation with
`Sync-OSDAppRepository -Prune -WhatIf`, and optionally retain valid canonical
packages with `-PinnedId`.
Replacements are hash-validated before the transactional commit; selective
synchronization remains non-destructive. See [cache health and
reconciliation](docs/repository.md#cache-health-and-reconciliation).

Built-in refreshes replace complete directories, not individual files in the
active cache. A sibling `.osdapps-new-<guid>` holds the candidate and
`.osdapps-old-<guid>` temporarily holds the previous generation. If a process
stops between the directory renames, the next full-Windows built-in sync or
PreInstall invocation can restore a validated old generation before attempting
downloads or offline restaging. Recovery never overwrites an existing active
directory or promotes unfinished `.new` content. If no old candidate validates,
or multiple candidates validate, it preserves them and reports the ambiguity.
Successful refresh removes obsolete transaction directories. Read-only cache
inspection does not perform recovery. This does not retry SetupComplete or
recover an interrupted Windows installation; use one writer per cache.

OSDApps does not bundle or redistribute vendor installer payloads. Built-ins are downloaded directly from their vendors; repository content is the repository owner's responsibility.

## OSDApps Viewer

The read-only Viewer has four tabs: **Staged for device · Apps · Cache · Logs**. It shows the actual manifest configuration, app sources and vendors, recorded cache versions, integrity/signature results, and structured log entries.

```powershell
# Full Windows: inspect the current Windows target and connected cache.
Show-OSDAppUI -Offline
```

`-Offline` disables online repository discovery; it does not disable Windows certificate trust/revocation traffic. On full Windows the Viewer checks supported built-in signatures by default. WinPE reports that signature checks are unavailable. `-TestMode` is only for an existing isolated GUI test folder, not normal deployment.

See the [Viewer guide](docs/viewer.md) for launch options and the meaning of each status. **Staged does not mean installed.**

## Security and offline use

Repository ZIPs are checked against their manifest SHA-256. Supported built-in MSI/EXE files must have a Windows-trusted signature and the expected publisher organization during full-Windows sync and PreInstall.

The checks have explicit boundaries: Office checks `setup.exe`, Teams checks its bootstrapper, and Chrome/Firefox/Webex check their MSI. The Office data tree, Teams MSIX and Adobe's outer ZIP are **not covered by those MSI/EXE signature checks**. Offline use also depends on the device's available certificate trust data; a populated cache alone is not a guarantee of a successful trust check.

Read the [built-in publisher policy](docs/built-in-apps.md#authenticode-and-publisher-policy-0340) and [FAQ](docs/faq.md). `-SkipSignatureVerification` skips **Viewer inspection only**; it does not weaken synchronization or SetupComplete enforcement.

## Results and troubleshooting

The OSDApps 0.35.0 release candidate completed a physical online deployment from a populated USB cache on 12 October 2026. Hard offline-readiness preflight passed before reboot, the correlated PreInstall and final JSON results reported **8/8 successful installations**, and `OnSuccess` removed temporary staging while preserving the result and log. This is installer/provisioning evidence, not proof of licensing or every application's interactive behavior.

Detailed results, timing limitations and older release history are preserved in the [validation matrix](docs/testing.md), [performance measurements](docs/performance.md) and [changelog](CHANGELOG.md).

The default persistent log is `%ProgramData%\OSDApps\Logs\Runtime.log`. The runtime also writes an atomic machine-readable result to `%ProgramData%\OSDApps\Results\Latest.json`; read it with `Get-OSDAppDeploymentResult`. Look for individual app outcomes and the final status—a successful staging command is not the final installation result. See [Runtime and cleanup](docs/runtime.md).

## Documentation and contribution

Start with the [documentation index](docs/README.md) for user guides, examples, architecture, public metadata and development/release instructions. Contributions and built-in requests are described in [CONTRIBUTING.md](CONTRIBUTING.md).

Reading a packaged copy of this README? The module package does not contain the full documentation/image tree; use the [online documentation](https://github.com/roryvossepoel/OSDApps/blob/main/docs/README.md).

OSDApps is licensed under the [MIT License](LICENSE).
