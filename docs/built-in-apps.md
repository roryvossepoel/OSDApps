# Built-in applications

[Documentation](README.md) · [Getting started](getting-started.md) · [Repository apps and scripts](repository.md)

Built-in applications use vendor-native acquisition and installation instead of the repository package contract.

All built-ins default to x64. Supported choices differ by product; support in the interface is separate from [field validation](testing.md#validated-built-ins-and-remaining-variants).

| Built-in | Architectures | Main configuration choices |
| --- | --- | --- |
| [Microsoft 365 Apps](#microsoft-365-apps) | x64, x86 | Channel, languages, products, licensing flags or custom XML |
| [Microsoft Teams](#microsoft-teams) | x64, x86, arm64 | Architecture |
| [Adobe Acrobat Unified](#adobe-acrobat-unified) | x64, x86 | Architecture and installation timeout |
| [Google Chrome Enterprise](#google-chrome-enterprise) | x64, x86 | Architecture |
| [Mozilla Firefox Enterprise](#mozilla-firefox-enterprise) | x64, x86 | Rapid/ESR channel and language |
| [Cisco Webex](#cisco-webex) | x64, arm64 | Architecture and supported MSI options |

## Machine-readable metadata

The current built-in application catalog is also published as:

[`metadata/builtins.json`](../metadata/builtins.json)

This JSON is intended for external tooling and includes the application Id, display name, vendor, supported architectures/channels, Add/Sync commands, acquisition model, cache path and synchronization phase.

CI validates the file against the module's exported built-in Add commands so a new built-in cannot be added without updating the metadata.

## Vendor-only source policy

Built-in applications are always sourced directly from their software vendor.

OSDApps does not contain, embed, mirror, redistribute, or publish built-in application installers or payloads. The module only contains acquisition and installation logic plus vendor-owned URLs or supported endpoints.

```text
Vendor
→ download at cache/deployment time
→ optional OSDCloud USB cache
→ local staging
→ installation
```

The OSDCloud USB cache is only a local deployment cache of vendor content. It is never a distribution source maintained by OSDApps.

This rule is absolute for built-ins: if a product cannot be obtained directly and maintainably from the vendor, it is not eligible for built-in support.

Repository applications are different. Repository content is controlled by the repository owner, and OSDApps does not prescribe where that organization obtains or hosts those packages.

## Authenticode and publisher policy (0.34.0)

On full Windows, built-in cache synchronization for Microsoft 365 Apps,
Microsoft Teams, Google Chrome Enterprise, Cisco Webex and Mozilla Firefox
Enterprise requires:

1. a valid Windows Authenticode signature on the selected MSI/EXE;
2. the signer certificate's `O=` organization to match the expected publisher.

| Built-in | Signable file checked | Expected organization |
| --- | --- | --- |
| Microsoft 365 Apps | `setup.exe` | Microsoft Corporation |
| Microsoft Teams | `teamsbootstrapper.exe` | Microsoft Corporation |
| Google Chrome Enterprise | `Package.msi` | Google LLC |
| Cisco Webex | `Package.msi` | Cisco Systems, Inc. |
| Mozilla Firefox Enterprise | `Package.msi` | Mozilla Corporation |
| Adobe Acrobat Unified | Outer `Package.zip` not assessed | N/A |

For MSI/EXE synchronization, candidate downloads are checked **before**
replacing an existing cached file. A rejected candidate leaves the previous
cache package in place and raises an error. An existing cache hit is also
verified even when its remote ETag matches. The standalone SetupComplete
PreInstall runtime validates the corresponding files when refreshing, using
a staged cache, or falling back after a network error. This can cause
deployment to fail closed when the trust chain cannot be established.

This is a publisher organization allowlist, not certificate thumbprint
pinning. It does not prove that every nested payload is signed or malware-free;
the Teams MSIX and Microsoft 365 Apps content tree are **not covered** by
the limited bootstrapper/ODT EXE checks. Adobe ZIP is **not** reported as
having a verified Authenticode signature. Certificate trust/revocation
may require network access independently of vendor URL availability.

The read-only OSDApps Viewer enables signature inspection by default on
full Windows, reports it as unavailable in WinPE, and permits the optional
`-SkipSignatureVerification` for isolated viewing only. This flag does not
relax built-in sync or SetupComplete security policy. The existing
`Get-OSDAppCache` CLI remains opt-in with `-VerifySignatures`.

## Configuration and synchronization

Each built-in has its own cmdlet and parameter set. Run `Sync-OSDApp*` on the full-Windows preparation machine and `Add-OSDApp*` in WinPE after Windows has been applied. Examples below show configuration alternatives; they are not a single script to run in one environment.

### Microsoft 365 Apps

```powershell
Sync-OSDAppMicrosoft365Apps `
    -Channel Current `
    -Architecture x64 `
    -ProductId O365ProPlusRetail `
    -Language nl-nl,en-us `
    -SharedComputerLicensing $true
```

A sync is also a configuration action. Changing parameters rewrites the desired Office configuration and refreshes the cache.

Supported channels:

```text
Current
MonthlyEnterprise
SemiAnnual
CurrentPreview
SemiAnnualPreview
BetaChannel
```

Supported product IDs:

```text
O365ProPlusRetail
O365BusinessRetail
```

Supported architectures:

```text
x64 (default)
x86
```

ODT configuration XML still uses OfficeClientEdition=64/32.

The Office cache contains the Office Deployment Tool, `configuration.xml`, and `Office\Data`.

The built-in Office configuration uses a shared XML generator for `Add-OSDAppMicrosoft365Apps` and `Sync-OSDAppMicrosoft365Apps`. The common parameters are `Architecture` (x86/x64, x64 by default), `Channel`, `ProductId`, `Language`, `UpdatesEnabled`, `AcceptEula`, `SharedComputerLicensing`, `DeviceBasedLicensing`, and `ExcludeApp`. Optional `IncludeVisio` and `IncludeProject` switches include `VisioProRetail` and `ProjectProRetail` as separate Office Deployment Tool products. Each product gets the requested languages; exclusions apply only to Microsoft 365 Apps. The respective licenses must be assigned separately.

```powershell
# Without cached configuration: Enterprise x64, Current channel, en-us, updates on
Add-OSDAppMicrosoft365Apps

# Typical Dutch Office with monthly enterprise updates and Visio/Project
Add-OSDAppMicrosoft365Apps -Channel MonthlyEnterprise -Language nl-nl -IncludeVisio -IncludeProject

# Shared workstation with licensed individual users
Add-OSDAppMicrosoft365Apps -SharedComputerLicensing $true

# Specialized device-based licensing, requiring an eligible device license
Add-OSDAppMicrosoft365Apps -DeviceBasedLicensing $true

# Disable Office updates (manage Office updates separately)
Add-OSDAppMicrosoft365Apps -UpdatesEnabled $false
```

When no Office configuration parameter is supplied to `Add-OSDAppMicrosoft365Apps`, a usable cached configuration can be retained. Specify the channel, language and other required choices explicitly when you want to override it. The README does this for MonthlyEnterprise/en-us.

For advanced or unusual configurations, export XML from Microsoft's Office Customization Tool and pass `-ConfigurationXml <path>`. The supplied XML is checked only for file existence and well-formed XML syntax (without DTD or external entity resolution), then preserved without modification. Office Deployment Tool validates its own products, channels, languages and other configuration semantics. Do not simultaneously supply conflicting generated configuration switches; the custom XML takes precedence.

### Microsoft Teams

```powershell
Sync-OSDAppMicrosoftTeams -Architecture x64
```

Supported architectures:

```text
x64 (default)
x86
arm64
```

The Teams cache contains:
- `teamsbootstrapper.exe`
- `teams.msix`
- `CacheInfo.json`

The canonical built-in ID is `MicrosoftTeams`. Its USB cache and WinPE staging location is `BuiltIn\MicrosoftTeams`, containing `teamsbootstrapper.exe`, `teams.msix` and `CacheInfo.json`. The 0.31.0 rename intentionally introduced no legacy commands or runtime identity. From 0.36.0, metadata recognizes `Teams` only as a retired **cache alias**: full-Windows `Sync-OSDAppMicrosoftTeams` and standalone PreInstall remove the old folder only after the canonical payload is complete and the bootstrapper passes the Microsoft trust gate. A PreInstall cleanup failure is logged as a warning rather than failing an otherwise usable deployment. The old cmdlet names and SetupComplete identity remain unsupported. Re-synchronize existing media before booting WinPE for an offline deployment.

Teams freshness is checked using HTTP metadata. ETag is preferred; Last-Modified plus Content-Length is the fallback.

### Adobe Acrobat Unified

Adobe Acrobat Unified supports Adobe's official x64 and x86 unified Acrobat/Reader packages. x64 is the default.

```powershell
# x64 is the default
Sync-OSDAppAdobeAcrobatUnified
Add-OSDAppAdobeAcrobatUnified

# optional x86
Sync-OSDAppAdobeAcrobatUnified -Architecture x86
Add-OSDAppAdobeAcrobatUnified -Architecture x86
```

The cache contains:

```text
BuiltIn\AdobeAcrobatUnified\
├── x64\
│   ├── Package.zip
│   └── CacheInfo.json
└── x86\
    ├── Package.zip
    └── CacheInfo.json
```

The ZIP remains compressed while cached and staged. During installation the standalone runner extracts it to the local work directory, locates `Setup.exe`, and runs the Adobe-supported silent installation command:

```text
Setup.exe /sAll /msi ADDLOCAL=ALL
```

The Adobe installation timeout defaults to 15 minutes. While Setup.exe is running, the runner logs a heartbeat every 60 seconds. Override the timeout when needed:

```powershell
Add-OSDAppAdobeAcrobatUnified -InstallTimeoutMinutes 20
```

x64 is used when `-Architecture` is omitted. x86 and x64 caches are kept separately so a single OSDCloud USB can hold both variants.

During WinPE, a populated USB cache is staged to the **same architecture-specific relative path** on the Windows disk: `Windows\Temp\OSDApps\BuiltIn\AdobeAcrobatUnified\x64\Package.zip` (or `x86`). `DeviceManifest.json` and the SetupComplete runner reference that exact path. If the cache is empty, the runtime downloads it later; if a cached archive is copied, staging verifies that the expected file exists and its size matches the USB source.

### Google Chrome Enterprise

Google Chrome Enterprise uses Google's official Enterprise MSI directly from Google's download infrastructure. x64 is the default and x86 is optional. Google documents Windows Enterprise deployment with both 64-bit and 32-bit MSI packages.

```powershell
# x64 default
Sync-OSDAppGoogleChromeEnterprise
Add-OSDAppGoogleChromeEnterprise

# optional x86
Sync-OSDAppGoogleChromeEnterprise -Architecture x86
Add-OSDAppGoogleChromeEnterprise -Architecture x86
```

Cache layout:

```text
BuiltIn\GoogleChromeEnterprise\
├── x64\
│   ├── Package.msi
│   └── CacheInfo.json
└── x86\
    ├── Package.msi
    └── CacheInfo.json
```

Installation uses Windows Installer:

```text
msiexec.exe /i Package.msi /qn /norestart
```

### Mozilla Firefox Enterprise

Mozilla Firefox Enterprise uses Mozilla's official MSI redirect endpoint. Both Rapid Release and ESR are supported, with x64 as the default architecture and `en-US` as the default language.

```powershell
# Rapid Release, x64, en-US
Sync-OSDAppMozillaFirefoxEnterprise
Add-OSDAppMozillaFirefoxEnterprise

# ESR
Sync-OSDAppMozillaFirefoxEnterprise -Channel ESR
Add-OSDAppMozillaFirefoxEnterprise -Channel ESR

# x86 or another Mozilla locale
Sync-OSDAppMozillaFirefoxEnterprise -Architecture x86 -Language nl
Add-OSDAppMozillaFirefoxEnterprise -Architecture x86 -Language nl
```

Cache layout keeps channel, architecture, and language isolated:

```text
BuiltIn\MozillaFirefoxEnterprise\
└── <Rapid|ESR>\
    └── <x64|x86>\
        └── <language>\
            ├── Package.msi
            └── CacheInfo.json
```

Installation uses:

```text
msiexec.exe /i Package.msi /qn /norestart
```

Mozilla notes that its MSI is a signed wrapper around the full Firefox installer, but it supports the standard MSI deployment options needed here.

### Cisco Webex

Cisco Webex App is a vendor-native MSI built-in for Windows x64 and ARM64. It uses Cisco's **non-localized Webex App-only package**, as Cisco recommends for bulk deployment, not the localized MSI, Meetings bundle or VDI client.

Official evergreen package sources:

```text
x64:   https://binaries.webex.com/WebexOfclDesktop-Win-64-Gold/Webex_en.msi
arm64: https://binaries.webex.com/WebexOfclDesktop-Win-Arm-64-Gold/Webex_en.msi
```

The x64 URL was verified in practice on 10 October 2026 (Cisco-signed MSI, version 46.9.0.35800, 259.9 MiB); both online and fully offline SetupComplete installations succeeded. **ARM64 has not yet been field-validated.**

These x64/ARM64 URLs are listed in Cisco's [Webex App installation guide](https://help.webex.com/en-US/article/nw5p67g/Webex-%7C-Installation-and-Automatic-Upgrade). That page also contains an alternate older non-localized x64 URL in its package table; verify the actual current MSI delivery before production use. `-PackageUri` can override the source.

```powershell
# Full Windows: prepare a warm OSDCloud USB cache (optional)
Sync-OSDAppCiscoWebex
Sync-OSDAppCiscoWebex -Architecture arm64

# WinPE: stage installation intent + any existing cached MSI
Add-OSDAppCiscoWebex
Add-OSDAppCiscoWebex -Architecture arm64

# Configure installation only when needed
Add-OSDAppCiscoWebex -PreventPreLoginUpdates $true -EnableOutlookIntegration $true -EmailHint '$userPrincipalName'
Add-OSDAppCiscoWebex -DefaultTheme Light -AdditionalMsiProperties 'INSTALLWV2=1'
```

Cache and WinPE destination (the same relative path, preventing staging mismatches):

```text
BuiltIn\CiscoWebex\
├── x64\
│   ├── Package.msi
│   └── CacheInfo.json
└── arm64\
    ├── Package.msi
    └── CacheInfo.json
```

The generic `VendorMsi` runner uses `msiexec.exe /i Package.msi /qn /norestart` plus the manifest's `MsiProperties`, accepts exit codes 0 and 3010, and honors `-InstallTimeoutMinutes` (default 10). OSDApps caches the installer for **future OS deployments**; Webex's own user-session update mechanism is independent of the MSI cache.

| Add parameter | Default | MSI behavior |
| --- | --- | --- |
| `-Architecture` | `x64` | `x64` / `arm64`, selecting the Cisco MSI and cache folder |
| `-AutoStartWithWindows` | `$false` | Explicitly sets `AUTOSTART_WITH_WINDOWS=FALSE`; users may change this in Webex |
| `-AcceptEula` | `$true` | Sets `ACCEPT_EULA=TRUE` on behalf of users; organization must approve Cisco's agreement |
| `-PreventPreLoginUpdates` | `$false` | When true, sets `PREVENT_PRELOGIN_UPDATES=1`; updates **after sign-in** remain managed by Cisco/Control Hub |
| `-EnableOutlookIntegration` | Not set | When explicitly set, passes `ENABLEOUTLOOKINTEGRATION=1` or `0`. Beware: explicitly disabling also disables the Webex Outlook preference control |
| `-EmailHint` | Not set | `EMAIL=$userPrincipalName`, `$mail` or `$SAMAccountName` only. Fixed addresses are rejected for all-users installation; Cisco notes users cannot change this sign-in identity |
| `-DefaultTheme` | Not set | Optional `DEFAULT_THEME=Light` or `Dark` |
| `-AdditionalMsiProperties` | None | Advanced validated `NAME=VALUE` properties, e.g. `INSTALLWV2=1`; cannot override managed properties |
| `-InstallTimeoutMinutes` | `10` | Shared `VendorMsi` installer timeout |
| `-PackageUri` | Official Cisco URL | Override source when necessary |

The MSI always receives `ALLUSERS=1` for per-computer installation. Webex requires Microsoft Edge WebView2; for Windows 11 it is normally present, but an image without WebView2 may need the separate dependency or Cisco's `INSTALLWV2=1` option. `-AdditionalMsiProperties` validates names, duplicates, reserved managed properties and control/quote characters, and quotes property values containing spaces.

The Webex glyph in `metadata/icons/ciscowebex.svg` is from [Simple Icons](https://github.com/simple-icons/simple-icons) (CC0); Webex is a Cisco trademark.

## How update freshness is determined

Built-in applications use evergreen vendor sources. Most integrations can reuse payloads after an HTTP metadata check; Office deliberately builds a fresh complete generation for an online refresh.

The freshness mechanism is product-specific:

| Application | Update check | Download behavior |
| --- | --- | --- |
| Microsoft 365 Apps | Office Deployment Tool `/download` synchronizes the configured channel/product/languages | ODT downloads into a separate new generation. OSDApps validates it before replacing the active directory; an unchanged version does not mean the download was skipped. |
| Microsoft Teams | HTTP metadata for the official MSIX: `ETag` preferred, otherwise `Last-Modified + Content-Length` | MSIX is downloaded only when the metadata changed or no valid cached MSIX exists. The Teams bootstrapper is refreshed on every online sync. |
| Adobe Acrobat Unified | HTTP metadata for the official Adobe ZIP: `ETag` preferred, otherwise `Last-Modified + Content-Length` | `Package.zip` is downloaded only when the remote metadata changed or no cached ZIP exists. |
| Google Chrome Enterprise | HTTP metadata for the official Enterprise MSI: `ETag` preferred, otherwise `Last-Modified + Content-Length` | `Package.msi` is downloaded only when the remote metadata changed or no cached MSI exists. |
| Mozilla Firefox Enterprise | HTTP metadata for the Mozilla latest MSI endpoint: `ETag` preferred, otherwise `Last-Modified + Content-Length` | `Package.msi` is downloaded only when the remote metadata changed or no cached MSI exists. Channel, architecture, and language are cached separately. |
| Cisco Webex | Cisco MSI HTTP metadata, `ETag` preferred, otherwise `Last-Modified + Content-Length` | Reuse the MSI when unchanged; download when missing or changed. Separate x64/ARM64 cache folders. |

### HTTP metadata comparison

For Teams, Adobe Acrobat Unified, Google Chrome Enterprise, Mozilla Firefox Enterprise, and Cisco Webex, OSDApps first asks the vendor endpoint for remote file metadata.

The comparison order is:

1. Compare `ETag` when both remote and saved values are present.
2. Otherwise compare `Last-Modified` and `Content-Length`.
3. Download when no usable match exists or the cached payload is missing.

`CacheInfo.json` stores the previous `RemoteETag`, `RemoteLastModified`,
`RemoteContentLength`, `RemoteFinalUri` and `SyncedAt` values. This avoids opening
an MSI or extracting a ZIP just to decide whether the remote metadata changed.
A metadata match still requires the applicable local content and publisher
checks; it is not an independent guarantee of vendor freshness or file identity.

A replacement is prepared and validated in a separate directory before it becomes
active. See [cache generation recovery](architecture.md#cache-generation-recovery)
for swap and interruption handling. `AcquisitionOutcome` distinguishes download,
reuse and fallback for the current deployment; see [acquisition reporting](runtime.md#acquisition-and-installation-are-separate-results).

### Microsoft 365 Apps is different

Microsoft 365 Apps does not use the generic HTTP metadata comparison for the Office payload.

OSDApps runs the Office Deployment Tool in download mode with the staged configuration:

```text
setup.exe /download configuration.xml
```

ODT acquires the requested channel, architecture, products and languages into a new sibling directory. OSDApps does not seed that directory with the active Office data tree. It validates the complete candidate, including version-folder and CAB consistency, before switching the active directory. The previous generation is removed as a whole only after successful promotion; individual old Office files are not selectively pruned.

This also requires free space for the candidate alongside the current generation. See [transaction space checks](architecture.md#cache-transaction-space-checks).

OSDApps reads the concrete cached build from:

```text
Office\Data\<version>
```

and records that value in `CacheInfo.json`. Comparing the version before and after the ODT run allows the log to report whether the cached Office build actually changed.

### Choosing built-in Office or repository Office

The Microsoft 365 Apps built-in deliberately favors freshness over the shortest possible deployment time.

During full Windows, OSDApps lets the Office Deployment Tool synchronize the configured Office source before installation:

1. Run ODT `/download` into a new generation.
2. Validate the complete candidate and promote it.
3. Stage that content locally for installation.

If refresh fails, an acceptable previously staged fallback may still be used; the result records the refresh warning.

This has an important advantage: ODT is the authoritative Microsoft mechanism for acquiring Office content, so the same step that checks freshness can immediately update the cache when a newer build is available.

The trade-off is a fresh acquisition and additional temporary disk space even when the Office build is unchanged. Offline or failed-refresh fallback is a different path; it uses acceptable existing staged content.

If deployment speed is more important than checking Microsoft for a current Office build during SetupComplete, Microsoft 365 Apps can instead be packaged as a normal repository application.

In that model:

```text
self-maintained repository
→ organization decides which Office build is current
→ repository sync/update happens in WinPE
→ Package.zip is staged to the OS
→ full Windows installs the staged package
→ no built-in Office ODT freshness check
```

This is an intentional OSDApps design choice:

| Approach | Freshness owner | Sync moment | Full-Windows overhead | Best fit |
| --- | --- | --- | --- | --- |
| Built-in Microsoft 365 Apps | Microsoft / ODT | Full Windows | ODT synchronization before install | Evergreen Office with minimal package maintenance |
| Repository-packaged Microsoft 365 Apps | Repository owner | WinPE | No built-in ODT refresh step | Maximum deployment-time predictability and organization-controlled versioning |

Neither approach is inherently better. Built-ins optimize for vendor-native evergreen maintenance; repository applications optimize for organization-owned packaging, version control, and deterministic deployment behavior.

This same principle applies more broadly in OSDApps: a supported built-in is a convenience path, not a requirement. Any application can still be delivered through the self-maintained repository when that better matches the deployment strategy.

### Microsoft Teams bootstrapper

The Teams MSIX uses the normal metadata comparison and is skipped when the cached MSIX is still current.

The small `teamsbootstrapper.exe`, however, is intentionally downloaded again during an online synchronization so the provisioning bootstrapper itself remains current. This does not require re-downloading the much larger Teams MSIX when its metadata has not changed.

### Sync timing

Built-in freshness checks happen in **full Windows**: through a public Sync command on the preparation machine, or through PreInstall during SetupComplete.

```text
WinPE
→ stage built-in intent and available fallback cache

Full Windows
→ check vendor freshness
→ prepare a complete Office generation or reuse/replace other payloads as appropriate
→ stage current payload locally
→ Runner installs
```

Repository versions and hashes are controlled by the repository owner. Content can be synchronized on the preparation machine or during WinPE staging; Runner uses the staged package without refreshing it during SetupComplete.

## Deployment flow

The same commands are used with or without USB cache:

```powershell
Add-OSDAppMicrosoft365Apps
Add-OSDAppMicrosoftTeams
Add-OSDAppAdobeAcrobatUnified
Add-OSDAppGoogleChromeEnterprise
Add-OSDAppMozillaFirefoxEnterprise
```

In WinPE, the built-in Add cmdlets stage deployment intent and any already-available cached payload into Windows Temp. A USB cache is not required.

In full Windows, PreInstall resolves the source automatically:
- if an `OSDCloud` USB cache is present, it is used and updated;
- if no `OSDCloud` USB cache is present, content is acquired directly to the local Windows runtime;
- current content is staged locally before the runner starts;
- the runner installs from local content.

## No-USB mode

No alternate parameter or command is required.

When no `OSDCloud` volume is connected, PreInstall downloads the current built-in content directly into the local Windows runtime under `%SystemRoot%\Temp\OSDApps`. The runner then installs from that local source.

When an `OSDCloud` volume is connected, it is detected automatically. Existing cache content is used when available and the cache is refreshed/updated during SetupComplete.

A completely blank `OSDCloud` volume is supported. OSDApps creates the cache structure and populates it during the full-Windows pre-install phase.

## Fallback behavior

An ordinary refresh failure can use a complete acceptable staged fallback. If no usable source remains, PreInstall records the app-local failure and Runner skips that app while processing independent queue entries. The final deployment is still `Failed` and staging is retained. Invalid manifests, supported-publisher trust failures and other phase-level safety failures stop processing.

A successful fallback installation is recorded separately from the failed refresh. See [acquisition outcomes](runtime.md#acquisition-and-installation-are-separate-results).

The absence of an `OSDCloud` USB is not an error: when online, PreInstall acquires built-in content directly to the local Windows runtime.

Office refresh has a 20-minute timeout by default.

## USB cache behavior

USB is not required for built-in deployment.

If an `OSDCloud` USB volume is detected, cache functionality is enabled automatically. Keep that media connected until OOBE is displayed so SetupComplete can use and update the cache.

If no `OSDCloud` volume is present, built-ins are acquired directly to the local Windows runtime.


## Verbose staging diagnostics

Use:

```powershell
Add-OSDAppMicrosoft365Apps -Verbose
Add-OSDAppMicrosoftTeams -Verbose
Add-OSDAppAdobeAcrobatUnified -Verbose
Add-OSDAppGoogleChromeEnterprise -Verbose
Add-OSDAppMozillaFirefoxEnterprise -Verbose
```

Verbose output shows:
- offline Windows target detection;
- OSDCloud cache-volume detection;
- whether an existing built-in cache is complete;
- local staging decisions;
- SetupComplete integration;
- the selected acquisition path.

When OSDCloud cache media is detected, the Add cmdlet also emits a warning to keep the USB connected until OOBE is displayed.

The same decisions are written to the CMTrace-compatible logs.


## Validated deployment behavior

OSDApps has been validated with both blank-cache and warm-cache deployments using the same Add commands and installation queue.

Validated behavior includes:

- blank `OSDCloud` media being populated automatically during full-Windows PreInstall;
- existing built-in cache content being detected and staged as fallback;
- unchanged Teams, Chrome, and Adobe payloads being reused after lightweight freshness checks;
- Microsoft 365 Apps being synchronized by ODT and reporting whether the cached Office build changed;
- successful installation from local staged content;
- historical cold-cache versus warm-cache timing with similar Runner installation times in the recorded runs.

See [Validation matrix](testing.md) and [Performance](performance.md) for the tested versions and limits. Earlier Office incremental-refresh timings do not predict the current complete-generation refresh cost.

## Requesting a new built-in application

Built-ins are maintained as product-specific code in OSDApps, so they are deliberately selective. A request should only be considered when the application is a good fit for a generic, repeatable deployment path.

### Required characteristics

A built-in candidate should:

- be broadly used in enterprise or managed Windows environments;
- have a direct, deterministic vendor download source;
- be acquired from that vendor at runtime/cache time rather than being bundled, mirrored, or redistributed by OSDApps;
- use a stable URL, documented API/endpoint, or similarly maintainable vendor-supported acquisition method;
- support unattended installation with predictable exit codes;
- work without customer-specific credentials, tenant-specific portals, or interactive download flows;
- be maintainable without scraping HTML, browser automation, traffic sniffing, or reverse-engineering temporary download links.

### Download-source rule

OSDApps must be able to acquire the installer directly from the vendor in a predictable way.

A vendor using a CDN is not automatically a problem. The requirement is that the vendor exposes a stable, supported download URL or endpoint. A built-in will not be added when the installer must come from a third-party mirror, community package source, OSDApps itself, or when acquisition depends on techniques such as:

```text
scraping a download page
sniffing browser/network traffic
following undocumented JavaScript-generated links
capturing short-lived signed URLs
reusing session cookies or access tokens
bypassing CDN / anti-bot protections
reverse-engineering a protected download workflow
```

If the vendor changes a stable URL behind the scenes while keeping the published endpoint stable, that is fine. The module should not need to discover or reconstruct hidden CDN URLs itself.

### When to use the repository instead

The repository model is the default for applications that are:

- customer-specific;
- line-of-business or internally developed;
- uncommon or narrowly used;
- hosted internally;
- accessible only after authentication;
- distributed through portals with non-deterministic download links;
- unsuitable for a generic vendor-native maintenance flow.

Those applications belong in `catalog.json` / `Package.zip`, where the organization controls acquisition and packaging.

### What to include in a request

A useful built-in request should include:

- product name and vendor;
- vendor documentation URL;
- direct installer URL(s) or documented download endpoint;
- supported architectures;
- unattended installation command;
- evidence that the application is broadly used;
- expected update/freshness mechanism if known.

A request meeting these criteria can still be declined if the vendor's acquisition or installation model is too fragile to maintain safely.
