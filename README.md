# OSDApps

[![PowerShell Gallery Version](https://img.shields.io/powershellgallery/v/OSDApps?label=PowerShell%20Gallery)](https://www.powershellgallery.com/packages/OSDApps)
[![PowerShell Gallery Downloads (latest version)](https://img.shields.io/badge/dynamic/xml?url=https%3A%2F%2Fwww.powershellgallery.com%2Fapi%2Fv2%2FPackages%3F%2524filter%3DId%2Beq%2B%2527OSDApps%2527%2Band%2BIsAbsoluteLatestVersion%2Beq%2Btrue%26%2524select%3DVersion%252CVersionDownloadCount&query=%2F%2F*%5Blocal-name()%3D'VersionDownloadCount'%5D&label=downloads%20(latest)&color=blue&cacheSeconds=3600)](https://www.powershellgallery.com/packages/OSDApps)
[![Module CI](https://github.com/roryvossepoel/OSDApps/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/roryvossepoel/OSDApps/actions/workflows/ci.yml)
[![Windows PowerShell 5.1](https://img.shields.io/badge/Windows%20PowerShell-5.1-blue)](#install-from-powershell-gallery)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**Prepare applications with PowerShell. Install them through SetupComplete. Inspect the result with a read-only Viewer.**

OSDApps adds application deployment to OSDCloud v2: vendor-native built-ins, organization-managed repository packages, an optional USB cache, and one ordered installation queue before OOBE continues.

[Getting started](docs/getting-started.md) · [Examples](Examples/README.md) · [Viewer](docs/viewer.md) · [Documentation](docs/README.md) · [Changelog](CHANGELOG.md)

## How it works

![OSDApps end-to-end architecture](docs/images/osdapps-architecture.svg)

| Phase | Runs in | Responsibility |
| --- | --- | --- |
| Prepare cache, optionally | Full Windows | `Sync-OSDApp*` downloads content to an OSDCloud cache volume. |
| Stage | WinPE, after Windows is applied | `Add-OSDApp*` writes the device queue, copies available content and prepares SetupComplete. Repository packages are synchronized here when requested. |
| Acquire and install | First Windows boot | Standalone PreInstall refreshes built-ins or uses a usable local fallback; Runner installs the queue from local staging. |
| Validate and inspect | WinPE or Windows | `Test-OSDAppDeployment` checks staged readiness before reboot; `Show-OSDAppUI` displays state; `Get-OSDAppDeploymentResult` reads the final machine result. |

The CLI owns configuration and automation. The Viewer does not add or remove apps. The OSDApps module does **not** need to be installed in the deployed Windows installation: the required runtime scripts are staged automatically.

## Install from PowerShell Gallery

**Run on a full Windows preparation machine**, or in an online WinPE session with PowerShellGet available. These examples pin the published **0.34.1** release:

```powershell
Install-Module OSDApps -RequiredVersion 0.34.1 -Scope CurrentUser -Force -SkipPublisherCheck
Import-Module OSDApps -RequiredVersion 0.34.1 -Force
```

For offline WinPE, save the module to USB first; see [Prepare a USB cache](Examples/Prepare-UsbCache.md). PowerShellGet is the documented WinPE/Windows PowerShell 5.1 installation path. `Install-PSResource` is an alternative only on a machine where PSResourceGet is already available.

`Test-OSDAppDeployment`, `Test-OSDAppCache` and `Get-OSDAppDeploymentResult` are currently documented from the Unreleased development source and are not part of the published 0.34.1 package yet.

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

For a complete workflow, use the [online WinPE example](Examples/WinPE-Online.md) or the [offline WinPE example](Examples/WinPE-Offline.md). Neither example formats a disk or reboots automatically.

## Application sources

| Source | Content owner | Version and acquisition |
| --- | --- | --- |
| Built-in | Software vendor | OSDApps uses a vendor-native acquisition path and refreshes content in full Windows. |
| Repository | Your organization | You publish `catalog.json`, per-app manifests and `Package.zip` archives. OSDApps resolves the selected variant and verifies its SHA-256. |

The six built-ins are **Microsoft 365 Apps, Microsoft Teams, Adobe Acrobat Unified, Google Chrome Enterprise, Mozilla Firefox Enterprise and Cisco Webex**. Their supported architectures and configuration options differ; see [Built-in applications](docs/built-in-apps.md).

Repository apps use `Add-OSDApp -Name <Id>`. Configure your own `CatalogUri` first, or use a previously synchronized repository cache with `-SkipCacheRefresh`. Names such as Notepad++ and Omnissa Horizon Client in the test reports are **example repository packages**, not bundled built-ins. See [Repository applications](docs/repository.md).

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

OSDApps 0.34.1 completed a new cold/warm physical pair on 12 October 2026 with **8/8 successful installations in both runs**. The cold run populated the cache; the warm run recorded zero acquisitions and zero updated packages. Both runs completed `OnSuccess` cleanup. This is installer/provisioning evidence, not proof of licensing or every application's interactive behavior.

Detailed results, timing limitations and older release history are preserved in the [validation matrix](docs/testing.md), [performance measurements](docs/performance.md) and [changelog](CHANGELOG.md).

The default persistent log is `%ProgramData%\OSDApps\Logs\Runtime.log`. The runtime also writes an atomic machine-readable result to `%ProgramData%\OSDApps\Results\Latest.json`; read it with `Get-OSDAppDeploymentResult`. Look for individual app outcomes and the final status—a successful staging command is not the final installation result. See [Runtime and cleanup](docs/runtime.md).

## Documentation and contribution

Start with the [documentation index](docs/README.md) for user guides, examples, architecture, public metadata and development/release instructions. Contributions and built-in requests are described in [CONTRIBUTING.md](CONTRIBUTING.md).

Reading a packaged copy of this README? The module package does not contain the full documentation/image tree; use the [online documentation](https://github.com/roryvossepoel/OSDApps/blob/main/docs/README.md).

OSDApps is licensed under the [MIT License](LICENSE).
