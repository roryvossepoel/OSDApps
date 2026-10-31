# Public built-in metadata for viewers

OSDStage publishes a stable, machine-readable **built-in catalog** at [`metadata/builtins.json`](../metadata/builtins.json). It is designed for external viewers, documentation pages and dashboards, without parsing the PowerShell module.

**Public raw endpoint:**

```text
https://raw.githubusercontent.com/roryvossepoel/OSDApps/main/metadata/builtins.json
```

This file is a **catalog of OSDStage' vendor-native built-in integrations**, **not** a listing of an organization's self-maintained app repository. For organization-managed apps, point a private or authorized viewer to that organization's own `catalog.json` and then resolve the linked package `manifest.json` files. The sample repository under `Examples/Repository` deliberately does not publish any private apps.

## Stable schema and fields

The current catalog uses `Apps[]`. This PR changes the OSDStage-owned field
contract and is not backward-compatible with earlier consumers. There are no
retired built-in cache aliases. Rebuild caches and update external consumers
before adopting this branch; do not mix it with previously staged manifests.

| Field | Viewer use |
| --- | --- |
| `Id`, `DisplayName`, `Vendor` | Stable key and human-readable label |
| `Source`, `Acquisition`, `SyncPhase` | Distinguish ownership and acquisition phase. `FullWindowsPreparation` means the cache must be prepared before WinPE; `FullWindowsPreInstall` permits first-boot acquisition. |
| `AddCommand`, `SyncCommand` | Show ready-to-copy PowerShell examples |
| `Architectures`, `DefaultArchitecture` | Selectable architectures, not necessarily field-validated ones. DefaultArchitecture is null when an explicit selection is required. |
| `ArchitectureRequired` | When true, the runtime Add/Sync commands require one explicit architecture. |
| `Channels`, `ChannelSupportEndDates` | Runtime channel choices and UTC support deadlines; expired channels are rejected even if still listed in this static metadata. |
| `Channels`, `DefaultChannel`, `ProductIds`, `DefaultLanguage` | Optional product-specific settings; check for presence before rendering |
| `CachePath` | Illustrate the USB cache layout (`<architecture>` and similar segments are placeholders) |
| `RepositoryAlternative` | Explain the organization-maintained alternative |
| `IconUrl` | Repository-hosted SVG icon for the card; see the relevant attribution |

For `MicrosoftCompanyPortal`, `Acquisition=MicrosoftPreinstallKit` covers the default automatic Microsoft download and the optional `-KitPath` local-kit fallback. Both prepare the cache on full Windows. Its `SyncPhase=FullWindowsPreparation` is intentional; it does not download during SetupComplete.

Use `Id` as the card key rather than display name. Render optional fields only when available. Coordinate schema changes with external consumers; old field aliases are not provided.

<a id="0320-cisco-webex"></a>

## Example: Cisco Webex

The public catalog includes 14 built-in integrations. This `CiscoWebex` entry illustrates the schema:

```json
{
  "Id": "CiscoWebex",
  "DisplayName": "Cisco Webex",
  "Source": "BuiltIn",
  "Vendor": "Cisco",
  "Acquisition": "VendorMsi",
  "SyncPhase": "FullWindowsPreInstall",
  "AddCommand": "Add-OSDStageCiscoWebex",
  "SyncCommand": "Sync-OSDStageCiscoWebex",
  "Architectures": ["x64", "arm64"],
  "DefaultArchitecture": "x64",
  "CachePath": "BuiltIn/CiscoWebex/<architecture>",
  "RepositoryAlternative": true,
  "IconUrl": "https://raw.githubusercontent.com/roryvossepoel/OSDApps/main/metadata/icons/ciscowebex.svg"
}
```

The JSON describes **supported choices**. In the 0.32.0 field tests, **x64** download, online SetupComplete, cold/warm USB caching and offline SetupComplete were validated; **ARM64 has not been field-tested yet**. Do not infer testing status from `Architectures`.

## Acquisition and deployment at a glance

```mermaid
flowchart TB
    A[Viewer consumes public builtins.json] --> B[Show built-in apps, commands, icons]
    R[Organization catalog.json] --> S[Organization packages and manifests]
    B --> C[WinPE: Add command stages intent]
    S --> D[WinPE: repository sync, SHA-256, staging]
    C --> E[Full Windows: vendor PreInstall / offline fallback]
    D --> F[Local SetupComplete Runner]
    E --> F
    F --> G[OOBE / Autopilot]
```

The two data sources must not be conflated: public built-ins do **not** expose or enumerate any organization's private repository.

## Viewer publication checklist

1. Merge and release the app with its icon under `metadata/icons/` and entry under `metadata/builtins.json`.
2. Verify JSON validity, required metadata keys, unique IDs, exported Add/Sync command names and icon files (covered by Pester).
3. Confirm the raw `main` JSON and corresponding icon URLs are available after merge.
4. Refresh the website/CDN cache. A viewer reading the raw `main` JSON dynamically needs no separate list update; a viewer using a compiled snapshot needs to refresh that snapshot.

See [Built-in apps](built-in-apps.md), [Repository apps and scripts](repository.md) and [Release process](releasing.md).
