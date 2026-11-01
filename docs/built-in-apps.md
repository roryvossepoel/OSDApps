# Built-in apps

[Documentation](README.md) · [Getting started](getting-started.md) · [Repository apps and scripts](repository.md)

Built-in **software installers** use vendor-native acquisition and installation instead of the repository package contract. Built-in scripts, such as Windows Inbox Cleanup, ship with OSDStage itself and are staged directly without network access or an app repository.

App built-ins default to x64. Runtime prerequisite cmdlets require one explicit architecture (x86 or x64). Supported choices differ by product; support in the interface is separate from [field validation](testing.md#validated-built-ins-and-remaining-variants).

| Built-in | Architectures | Main configuration choices |
| --- | --- | --- |
| [Microsoft 365 Apps](#microsoft-365-apps) | x64, x86 | Channel, languages, products, licensing flags or custom XML |
| [Microsoft Teams](#microsoft-teams) | x64, x86, arm64 | Architecture |
| [Microsoft Company Portal](microsoft-company-portal.md) | x64, arm64 | Automatic official Microsoft Preinstall Kit download or manual `-KitPath`; offline provisioning |
| [CMTrace Open](cmtrace-open.md) | x64, arm64 | Verified upstream MSI cache, installation timeout and optional update-check control |
| [Adobe Acrobat Unified](#adobe-acrobat-unified) | x64, x86 | Architecture and installation timeout |
| [Google Chrome Enterprise](#google-chrome-enterprise) | x64, x86 | Architecture |
| [Mozilla Firefox Enterprise](#mozilla-firefox-enterprise) | x64, x86 | Rapid/ESR channel and language |
| [Zoom Workplace](#zoom-workplace) | x64, arm64 | Architecture, desktop shortcut, SSO host and Zoom settings |
| [Cisco Webex](#cisco-webex) | x64, arm64 | Architecture and supported MSI options |
| [Windows Inbox Cleanup](#windows-inbox-cleanup) | any | Explicit app selection, tested preset, or diagnostic-only |
| [Windows optional features](#windows-optional-features) | any | Explicit feature names to enable or disable |


## Windows optional features

`Add-OSDStageWindowsFeature` stages explicit Windows optional feature names and applies them once during SetupComplete under SYSTEM. OSDStage does not maintain a feature-name catalog, offer feature-name autocomplete, infer dependencies, or select source media. The operator is responsible for supplying feature names that exist on the target Windows build.

```powershell
Add-OSDStageWindowsFeature -Enable @(
    'NetFx3',
    'Microsoft-Windows-Subsystem-Linux'
) -Disable @(
    'Printing-XPSServices-Features'
)
```

The staged `WindowsFeatures` built-in is a Script and requires no repository, USB cache, or network acquisition. Repeated Add calls build one operation set; the most recently staged desired state for a feature replaces its earlier state. Supplying the same feature to both `-Enable` and `-Disable` in one call is rejected.

SetupComplete queries the current state before changing anything. Already enabled/disabled features succeed idempotently. Remaining operations are still attempted when one feature fails. The aggregate script returns failure when any operation failed. Windows servicing is always called with `-NoRestart`; OSDStage records `RestartNeeded` and may return the normal 3010 success code to Runner, but does not reboot the device.

Results are written to `%ProgramData%\OSDStage\Results\WindowsFeatures-Result.json` by default. No DISM source/media management is included in this first implementation.

## Windows Inbox Cleanup

The optional **built-in script** is staged in WinPE and runs once in SetupComplete under SYSTEM, before OOBE. It removes **only the package names you select**, from provisioning and existing user registrations. Protected and Windows NonRemovable components are skipped. The script logs a per-app result and returns nonzero if a requested removal failed. Because Appx behavior can change between Windows builds, test your selection on your own image before broad deployment.

```powershell
# WinPE after OSDCloud. No CatalogUri or USB cache is needed.
Import-Module OSDStage
Add-OSDStageWindowsInboxCleanup -Preset Tested13
Test-OSDStageDeployment -RequireOfflineReady -ThrowOnFailure
```

The `Tested13` preset matches the 13 package names tested on Windows 11 25H2 during the repository proof of concept. The preset is opt-in: simply importing OSDStage never removes anything. For a custom list:

```powershell
Add-OSDStageWindowsInboxCleanup -Remove @(
    'Microsoft.BingWeather',
    'Microsoft.MicrosoftSolitaireCollection'
)
```

Use `-DiagnoseOnly` to inspect and log selected packages during SetupComplete without removing them. OSDStage copies the script plus `config.json` from the module to `BuiltIn\WindowsInboxCleanup` in the offline Windows staging folder, pins their SHA-256 hashes in `DeviceManifest.json`, and validates both before execution. The built-in script does not use Azure Blob Storage, package archives, publisher URLs or pre-install downloads. `Remove-OSDStageStaging -Name WindowsInboxCleanup` can remove it from the pending queue in WinPE.

The earlier standalone repository package is named `WindowsInboxAppCleanup`; the new built-in ID is `WindowsInboxCleanup`, so both identities remain distinct. Avoid selecting both on the same device.

After the first boot, check `%ProgramData%\OSDStage\Results\Latest.json`, `%ProgramData%\OSDStage\Results\InboxCleanup-Result.json`, and `%ProgramData%\OSDStage\Logs\InboxCleanup.log`. Additional early diagnostics are written to `%SystemRoot%\Temp\OSDStage-InboxCleanup-Diagnostics.log`. A successful OSDStage result is not a replacement for post-Autopilot verification.

## Installer filenames

Built-in downloads retain the filename supplied by the vendor: the HTTP
`Content-Disposition` filename when present, otherwise the final redirected URL's
filename. The same name is retained in the USB cache and local Windows staging.
Unsafe names or a file extension that differs from the expected payload format
are rejected before promotion. Downloads, signature/hash checks and complete
cache-generation replacement follow the existing validation policies.

Each cached variant records its exact vendor `PayloadFileName`, SHA-256 and byte
size in `CacheInfo.json`. Windows staging records that exact relative filename
and hash in `DeviceManifest.json`. PreInstall updates the manifest only after
acquiring and validating the selected payload; the runner validates the recorded
path and hash again. Unrelated files with the same extension are never selected.
Office keeps its ODT-managed layout and recorded payload profile.

**Start with a fresh cache.** There is no old-name lookup, cache migration,
filename conversion or compatibility alias. A cold online deployment records a
pending payload with a null filename until acquisition succeeds; it does not use
a fabricated package path. Old cache metadata is not repaired or guessed.

**Custom repository apps and scripts still use `Package.zip`.** That repository
archive contract is separate from built-in vendor installers.

## Machine-readable metadata

The current built-in app catalog is also published as:

[`metadata/builtins.json`](../metadata/builtins.json)

This JSON is intended for external tooling and includes the app Id, display name, vendor, supported architectures/channels, Add command, acquisition model, cache path and phase. Installer built-ins have a Sync command and USB cache path; module-bundled scripts have neither.

CI validates the file against the module's exported built-in Add commands so a new built-in cannot be added without updating the metadata.

## Vendor-only source policy

Built-in third-party software installers are always sourced directly from their software vendor. OSDStage-owned built-in scripts are bundled as text in the module and do not download installers.

OSDStage does not contain, embed, mirror, redistribute, or publish built-in app installers or payloads. The module only contains acquisition and installation logic plus vendor-owned URLs or supported endpoints.

```text
Vendor
→ download at cache/deployment time
→ optional OSDCloud USB cache
→ local staging
→ installation
```

The OSDCloud USB cache is only a local deployment cache of vendor content. It is never a distribution source maintained by OSDStage.

This rule is absolute for built-in **software products**: if an installer cannot be obtained directly and maintainably from the vendor, it is not eligible for built-in installer support. The Windows Inbox Cleanup script is a separate OSDStage-maintained configuration action, not a third-party redistributable.

Repository apps are different. Repository content is controlled by the repository owner, and OSDStage does not prescribe where that organization obtains or hosts those packages.

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
| Google Chrome Enterprise | Vendor MSI | Google LLC |
| Cisco Webex | Vendor MSI | Cisco Systems, Inc. |
| Zoom Workplace | Vendor MSI | Zoom Communications, Inc. |
| Mozilla Firefox Enterprise | Vendor MSI | Mozilla Corporation |
| Adobe Acrobat Unified | Outer vendor ZIP not assessed | N/A |

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

The read-only OSDStage Viewer enables signature inspection by default on
full Windows, reports it as unavailable in WinPE, and permits the optional
`-SkipSignatureVerification` for isolated viewing only. This flag does not
relax built-in sync or SetupComplete security policy. The existing
`Get-OSDStageCache` CLI remains opt-in with `-VerifySignatures`.

## Configuration and synchronization

Each built-in has its own cmdlet and parameter set. Run `Sync-OSDStage*` on the full-Windows preparation machine and `Add-OSDStage*` in WinPE after Windows has been applied. Examples below show configuration alternatives; they are not a single script to run in one environment.

### Microsoft 365 Apps

```powershell
Sync-OSDStageMicrosoft365Apps `
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

The built-in Office configuration uses a shared XML generator for `Add-OSDStageMicrosoft365Apps` and `Sync-OSDStageMicrosoft365Apps`. The common parameters are `Architecture` (x86/x64, x64 by default), `Channel`, `ProductId`, `Language`, `UpdatesEnabled`, `AcceptEula`, `SharedComputerLicensing`, `DeviceBasedLicensing`, and `ExcludeApp`. Optional `IncludeVisio` and `IncludeProject` switches include `VisioProRetail` and `ProjectProRetail` as separate Office Deployment Tool products. Each product gets the requested languages; exclusions apply only to Microsoft 365 Apps. The respective licenses must be assigned separately.

```powershell
# Without cached configuration: Enterprise x64, Current channel, en-us, updates on
Add-OSDStageMicrosoft365Apps

# Typical Dutch Office with monthly enterprise updates and Visio/Project
Add-OSDStageMicrosoft365Apps -Channel MonthlyEnterprise -Language nl-nl -IncludeVisio -IncludeProject

# Shared workstation with licensed individual users
Add-OSDStageMicrosoft365Apps -SharedComputerLicensing $true

# Specialized device-based licensing, requiring an eligible device license
Add-OSDStageMicrosoft365Apps -DeviceBasedLicensing $true

# Disable Office updates (manage Office updates separately)
Add-OSDStageMicrosoft365Apps -UpdatesEnabled $false
```

When no Office configuration parameter is supplied to `Add-OSDStageMicrosoft365Apps`, a usable cached configuration can be retained. Specify the channel, language and other required choices explicitly when you want to override it. The README does this for MonthlyEnterprise/en-us.

For advanced or unusual configurations, export XML from Microsoft's Office Customization Tool and pass `-ConfigurationXml <path>`. The supplied XML is checked only for file existence and well-formed XML syntax (without DTD or external entity resolution), then preserved without modification. Office Deployment Tool validates its own products, channels, languages and other configuration semantics. Do not simultaneously supply conflicting generated configuration switches; the custom XML takes precedence.

### Microsoft Teams

```powershell
Sync-OSDStageMicrosoftTeams -Architecture x64
```

Supported architectures:

```text
x64 (default)
x86
arm64
```

The Teams cache contains:
- `teamsbootstrapper.exe`
- The vendor-named Teams MSIX (for example, `MSTeams-x64.msix`)
- `CacheInfo.json`

The canonical built-in ID is `MicrosoftTeams`. Its cache and WinPE staging directory is `BuiltIn\MicrosoftTeams`, containing the native bootstrapper, vendor-named MSIX and `CacheInfo.json`. Use a freshly synchronized cache; no old Teams identity or cache is migrated.

Teams freshness is checked using HTTP metadata. ETag is preferred; Last-Modified plus Content-Length is the fallback.

### Adobe Acrobat Unified

Adobe Acrobat Unified supports Adobe's official x64 and x86 unified Acrobat/Reader packages. x64 is the default.

```powershell
# x64 is the default
Sync-OSDStageAdobeAcrobatUnified
Add-OSDStageAdobeAcrobatUnified

# optional x86
Sync-OSDStageAdobeAcrobatUnified -Architecture x86
Add-OSDStageAdobeAcrobatUnified -Architecture x86
```

The cache contains:

```text
BuiltIn\AdobeAcrobatUnified\
├── x64\
│   ├── Acrobat_DC_Web_x64_WWMUI.zip
│   └── CacheInfo.json
└── x86\
    ├── Acrobat_DC_Web_WWMUI.zip
    └── CacheInfo.json
```

The ZIP remains compressed while cached and staged. During installation the standalone runner extracts it to the local work directory, locates `Setup.exe`, and runs the Adobe-supported silent installation command:

```text
Setup.exe /sAll /msi ADDLOCAL=ALL
```

The Adobe installation timeout defaults to 15 minutes. While Setup.exe is running, the runner logs a heartbeat every 60 seconds. Override the timeout when needed:

```powershell
Add-OSDStageAdobeAcrobatUnified -InstallTimeoutMinutes 20
```

x64 is used when `-Architecture` is omitted. x86 and x64 caches are kept separately so a single OSDCloud USB can hold both variants.

During WinPE, a populated USB cache is staged to the same architecture-specific directory on the Windows disk, retaining the vendor ZIP filename. For example: `Windows\Temp\OSDStage\BuiltIn\AdobeAcrobatUnified\x64\Acrobat_DC_Web_x64_WWMUI.zip`. If the cache is empty, the runtime downloads it later. Staging verifies that the copied file exists and its size matches the USB source.

### Google Chrome Enterprise

Google Chrome Enterprise uses Google's official Enterprise MSI directly from Google's download infrastructure. x64 is the default and x86 is optional. Google documents Windows Enterprise deployment with both 64-bit and 32-bit MSI packages.

```powershell
# x64 default
Sync-OSDStageGoogleChromeEnterprise
Add-OSDStageGoogleChromeEnterprise

# optional x86
Sync-OSDStageGoogleChromeEnterprise -Architecture x86
Add-OSDStageGoogleChromeEnterprise -Architecture x86
```

Cache layout:

```text
BuiltIn\GoogleChromeEnterprise\
├── x64\
│   ├── googlechromestandaloneenterprise64.msi
│   └── CacheInfo.json
└── x86\
    ├── googlechromestandaloneenterprise.msi
    └── CacheInfo.json
```

Installation uses Windows Installer:

```text
msiexec.exe /i "<vendor-installer>.msi" /qn /norestart
```

### Mozilla Firefox Enterprise

Mozilla Firefox Enterprise uses Mozilla's official MSI redirect endpoint. Both Rapid Release and ESR are supported, with x64 as the default architecture and `en-US` as the default language.

```powershell
# Rapid Release, x64, en-US
Sync-OSDStageMozillaFirefoxEnterprise
Add-OSDStageMozillaFirefoxEnterprise

# ESR
Sync-OSDStageMozillaFirefoxEnterprise -Channel ESR
Add-OSDStageMozillaFirefoxEnterprise -Channel ESR

# x86 or another Mozilla locale
Sync-OSDStageMozillaFirefoxEnterprise -Architecture x86 -Language nl
Add-OSDStageMozillaFirefoxEnterprise -Architecture x86 -Language nl
```

Cache layout keeps channel, architecture, and language isolated:

```text
BuiltIn\MozillaFirefoxEnterprise\
└── <Rapid|ESR>\
    └── <x64|x86>\
        └── <language>\
            ├── Firefox <version>.msi
            └── CacheInfo.json
```

Installation uses:

```text
msiexec.exe /i "<vendor-installer>.msi" /qn /norestart
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
Sync-OSDStageCiscoWebex
Sync-OSDStageCiscoWebex -Architecture arm64

# WinPE: stage installation intent + any existing cached MSI
Add-OSDStageCiscoWebex
Add-OSDStageCiscoWebex -Architecture arm64

# Configure installation only when needed
Add-OSDStageCiscoWebex -PreventPreLoginUpdates $true -EnableOutlookIntegration $true -EmailHint '$userPrincipalName'
Add-OSDStageCiscoWebex -DefaultTheme Light -AdditionalMsiProperties 'INSTALLWV2=1'
```

Cache and WinPE destination (the same relative path, preventing staging mismatches):

```text
BuiltIn\CiscoWebex\
├── x64\
│   ├── Webex_en.msi
│   └── CacheInfo.json
└── arm64\
    ├── Webex_en.msi
    └── CacheInfo.json
```

The generic `VendorMsi` runner uses `msiexec.exe /i "<vendor-installer>.msi" /qn /norestart` plus the manifest's `MsiProperties`, accepts exit codes 0 and 3010, and honors `-InstallTimeoutMinutes` (default 10). OSDStage caches the installer for **future OS deployments**; Webex's own user-session update mechanism is independent of the MSI cache.

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

Built-in apps use evergreen vendor sources. Most integrations can reuse payloads after an HTTP metadata check; Office PreInstall compares the channel version descriptor before deciding whether a new complete generation is needed.

The freshness mechanism is product-specific:

| App | Update check | Download behavior |
| --- | --- | --- |
| Microsoft 365 Apps | PreInstall checks configuration compatibility, generation consistency and the channel version CAB (or an exact build pin) | A current compatible generation is reused. Otherwise ODT downloads into a separate new generation, validated before replacement. Explicit `Sync-OSDStageMicrosoft365Apps` still acquires a fresh generation. |
| Microsoft Teams | HTTP metadata for the official MSIX: `ETag` preferred, otherwise `Last-Modified + Content-Length` | MSIX is downloaded only when the metadata changed or no valid cached MSIX exists. The Teams bootstrapper is refreshed on every online sync. |
| Adobe Acrobat Unified | HTTP metadata for the official Adobe ZIP: `ETag` preferred, otherwise `Last-Modified + Content-Length` | The vendor ZIP is downloaded only when the remote metadata changed or no cached ZIP exists. |
| Google Chrome Enterprise | HTTP metadata for the official Enterprise MSI: `ETag` preferred, otherwise `Last-Modified + Content-Length` | The vendor MSI is downloaded only when the remote metadata changed or no cached MSI exists. |
| Mozilla Firefox Enterprise | HTTP metadata for the Mozilla latest MSI endpoint: `ETag` preferred, otherwise `Last-Modified + Content-Length` | The vendor MSI is downloaded only when the remote metadata changed or no cached MSI exists. Channel, architecture, and language are cached separately. |
| Cisco Webex | Cisco MSI HTTP metadata, `ETag` preferred, otherwise `Last-Modified + Content-Length` | Reuse the MSI when unchanged; download when missing or changed. Separate x64/ARM64 cache folders. |

### HTTP metadata comparison

For Teams, Adobe Acrobat Unified, Google Chrome Enterprise, Mozilla Firefox Enterprise, and Cisco Webex, OSDStage first asks the vendor endpoint for remote file metadata.

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

OSDStage runs the Office Deployment Tool in download mode with the staged configuration:

```text
setup.exe /download configuration.xml
```

Before online acquisition, PreInstall checks the staged generation and requested
configuration. For the six supported channels it downloads only the small
`v64.cab` or `v32.cab` descriptor from the channel's Microsoft CDN URL into a
temporary directory outside the cache. It extracts `VersionDescriptor.xml` and
compares the advertised architecture build (`I640Version` or `I320Version`) with
the cached build, also checking the channel identity and any default build.
A matching build permits reuse after the cached ODT publisher check. No ODT `/download` process
is started and no active USB cache files are changed on this path.

An exact requested build pin can reuse a matching generation without a current
channel probe. A different advertised build requires acquisition. CAB bytes can
change because of rollout metadata or legacy OS entries while the relevant build
stays unchanged; those changes alone do not require a new payload. The generic
`Available/@Build` can refer to a legacy OS and is not used for this decision. Custom
`DownloadPath`, unsupported channels and dynamic configurations do not use this
CDN shortcut. A failed metadata request is reported as `FallbackCacheUsed` only
if the existing source is acceptable; it is never reported as confirmed reuse.
The metadata request has a 30-second timeout and native CAB extraction has a
10-second timeout. Ambiguous or unreadable metadata is treated as a failed check.
The temporary descriptor is
removed on success and failure, and is never copied over a cached CAB.

When acquisition is needed, ODT acquires the requested channel, architecture, products and languages into a new sibling directory. OSDStage does not seed that directory with the active Office data tree. After ODT reports a successful download, OSDStage checks the candidate's version-folder and CAB consistency before switching the active directory. These checks are described below; they are not a full verification of every payload file. The previous generation is removed as a whole only after successful promotion; individual old Office files are not selectively pruned.

This also requires free space for the candidate alongside the current generation. See [transaction space checks](architecture.md#cache-transaction-space-checks).

OSDStage reads the concrete cached build from:

```text
Office\Data\<version>
```

and records that value in `CacheInfo.json`. Comparing the version before and after the ODT run allows the log to report whether the cached Office build actually changed.

### Office cache compatibility with deployment configuration

Office generation integrity and configuration compatibility are separate checks.
A valid version directory and matching CAB files do not establish that cached
content was downloaded for the requested products, languages or channel.

Before staging fallback content, OSDStage compares the selected XML with the
cache's recorded download configuration. PreInstall repeats this check before
USB restaging, offline use and failed-refresh fallback. The selected deployment
XML is never replaced by the USB cache XML during PreInstall.

- Architecture, channel, products, languages and the other `Add` settings must
  match. The comparison is deliberately conservative: changed exclusions or
  element order also require acquisition. It does not infer product/language
  subset coverage from the files in `Office\Data`.
- A pinned version must match the actual cached build. Without a pinned version,
  an older compatible generation remains eligible for failed-refresh fallback.
- Licensing, display and update settings outside `Add` do not change payload
  eligibility. The deployment still uses its selected settings.
- `SourcePath` is excluded from comparison because OSDStage manages the download
  and local installation locations.
- Dynamic languages such as `MatchOS`/`MatchInstalled`, conditional products,
  implicit architecture/channel and other unresolved configuration cannot prove
  offline compatibility. They require successful online acquisition.

Office cache metadata must contain a `PayloadProfile` derived from the acquisition
XML. The selected deployment XML cannot substitute for missing provenance.
Caches without the current metadata are not migrated; build a fresh cache.

An incompatible cache is left intact. WinPE stages the requested configuration
without copying unsuitable Office content and reports that online acquisition
is required. Online refresh still uses a complete isolated generation. If it
fails and no compatible staged fallback exists, PreInstall fails clearly and
SetupComplete does not start the runner. Structural cache health remains a
separate report; it does not promise compatibility with every future selection.

Custom XML still receives the documented syntax check; the payload comparison
additionally needs one `Add` element for the acquisition workflow.

#### What is checked in the Office files?

The configuration comparison is additional to physical generation checks. It
does not replace them, and matching XML alone does not make a cache valid.

| Check | What OSDStage verifies |
| --- | --- |
| Required paths | `setup.exe`, `configuration.xml` and `Office\Data` exist in the cache generation. |
| Version layout | Exactly one numerically named Office version directory exists; its version must match an explicitly requested version when one is supplied. |
| Payload presence | The active version directory contains files. The count is recorded, but is not compared with an expected inventory. |
| CAB consistency | The architecture-specific shared CAB and active version-specific CAB both exist and have identical SHA-256 hashes. |
| ODT executable | Separate signature checks validate Authenticode and the expected Microsoft publisher before OSDStage executes `setup.exe`. |
| Download result | A candidate download must complete successfully before it can be validated and promoted. |
| Configuration provenance | The recorded acquisition settings must be compatible with the requested deployment before existing content is accepted as fallback. |

The two CAB hashes are compared with each other, not with an independently
trusted Microsoft hash. Their equality establishes consistency between those
two files; it does not prove that every Office data file is authentic or intact.
OSDStage does not currently compare the payload against a complete expected file
list, expected individual file sizes, a known total size, or hashes for every
Office data file. A missing or damaged payload file can therefore escape these
checks if the version directory remains nonempty. Reported cache sizes and
free-space checks are not completeness checks.

Configuration compatibility records what the content was acquired for. It does
not independently inspect the Office files to prove product/language coverage
or license entitlement. ODT performs acquisition and installation; passing the
OSDStage checks is not a guarantee that a subsequent installation will succeed.

#### One active Office cache: configuration changes

The built-in maintains one active Office generation, not a collection of
configuration-specific caches. A successful replacement is promoted as a whole;
the previous generation is then removed as a whole. A failed acquisition or
validation leaves the existing generation intact.

| Requested change | Expected behavior |
| --- | --- |
| Dutch to German | The Dutch generation is incompatible. Acquire a new German generation; replace the active cache only after success. |
| German back to Dutch | Acquire Dutch content again. The previous Dutch generation is not retained as a second cache. |
| Add Visio, change channel or architecture | Existing content with different acquisition settings is incompatible and cannot serve as fallback. |
| Multiple languages to a subset | Conservative matching still requires acquisition; OSDStage does not infer subset coverage. |
| Only licensing, display or update settings outside `Add` change | Otherwise matching content can be reused after freshness checks; installation uses the selected deployment XML. |
| Refresh fails with an incompatible cache | Preserve that cache, but do not install the requested configuration from it. Without a compatible staged fallback, PreInstall fails. |

Online Office PreInstall reuses a compatible, consistent generation when its
build matches the architecture-specific build advertised by the channel CDN, or an explicit build pin matches. Missing,
incompatible or changed content takes the complete acquisition path. A compatible
older build remains eligible for offline or failed-refresh fallback unless a
requested version pin excludes it. An explicit `Sync-OSDStageMicrosoft365Apps` call
on the preparation PC still requests a fresh complete acquisition.

For multiple independently maintained Office configurations, use separate
packages in your own repository and manage their upstream acquisition there.
The built-in does not provide multiple retained configuration profiles.

### Choosing built-in Office or repository Office

The built-in checks freshness during full Windows before installation:

1. Validate the existing generation and compare the requested configuration.
2. Reuse it when the advertised channel build or explicit build pin matches.
3. Otherwise run ODT `/download` into a new generation, validate it, promote it,
   and stage that content locally for installation.

If the metadata check or acquisition fails, an acceptable previously staged
fallback may still be used; the result records the refresh warning. ODT remains
the acquisition mechanism when a replacement is needed. Replacements require
additional temporary disk space, but unchanged deployments avoid downloading
all Office content again.

If deployment speed is more important than checking Microsoft for a current Office build during SetupComplete, Microsoft 365 Apps can instead be packaged as a normal repository app.

In that model:

```text
self-maintained repository
→ organization decides which Office build is current
→ repository sync/update happens in WinPE
→ Package.zip is staged to the OS
→ full Windows installs the staged package
→ no built-in Office ODT freshness check
```

This is an intentional OSDStage design choice:

| Approach | Freshness owner | Sync moment | Full-Windows overhead | Best fit |
| --- | --- | --- | --- | --- |
| Built-in Microsoft 365 Apps | Microsoft / ODT | Full Windows | ODT synchronization before install | Evergreen Office with minimal package maintenance |
| Repository-packaged Microsoft 365 Apps | Repository owner | WinPE | No built-in ODT refresh step | Maximum deployment-time predictability and organization-controlled versioning |

Neither approach is inherently better. Built-ins optimize for vendor-native evergreen maintenance; repository apps optimize for organization-owned packaging, version control, and deterministic deployment behavior.

This same principle applies more broadly in OSDStage: a supported built-in is a convenience path, not a requirement. Any app can still be delivered through the self-maintained repository when that better matches the deployment strategy.

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
→ reuse current compatible payloads or prepare a complete replacement generation
→ stage current payload locally
→ Runner installs
```

Repository versions and hashes are controlled by the repository owner. Content can be synchronized on the preparation machine or during WinPE staging; Runner uses the staged package without refreshing it during SetupComplete.

## Deployment flow

The same commands are used with or without USB cache:

```powershell
Add-OSDStageMicrosoft365Apps
Add-OSDStageMicrosoftTeams
Add-OSDStageAdobeAcrobatUnified
Add-OSDStageGoogleChromeEnterprise
Add-OSDStageMozillaFirefoxEnterprise
```

In WinPE, the built-in Add cmdlets stage deployment intent and any already-available cached payload into Windows Temp. A USB cache is not required.

In full Windows, PreInstall resolves the source automatically:
- if an `OSDCloud` USB cache is present, it is used and updated;
- if no `OSDCloud` USB cache is present, content is acquired directly to the local Windows runtime;
- current content is staged locally before the runner starts;
- the runner installs from local content.

## No-USB mode

No alternate parameter or command is required.

When no `OSDCloud` volume is connected, PreInstall downloads the current built-in content directly into the local Windows runtime under `%SystemRoot%\Temp\OSDStage`. The runner then installs from that local source.

When an `OSDCloud` volume is connected, it is detected automatically. Existing cache content is used when available and the cache is refreshed/updated during SetupComplete.

A completely blank `OSDCloud` volume is supported. OSDStage creates the cache structure and populates it during the full-Windows pre-install phase.

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
Add-OSDStageMicrosoft365Apps -Verbose
Add-OSDStageMicrosoftTeams -Verbose
Add-OSDStageAdobeAcrobatUnified -Verbose
Add-OSDStageGoogleChromeEnterprise -Verbose
Add-OSDStageMozillaFirefoxEnterprise -Verbose
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

OSDStage has been validated with both blank-cache and warm-cache deployments using the same Add commands and installation queue.

Validated behavior includes:

- blank `OSDCloud` media being populated automatically during full-Windows PreInstall;
- existing built-in cache content being detected and staged as fallback;
- unchanged Teams, Chrome, and Adobe payloads being reused after lightweight freshness checks;
- Microsoft 365 Apps being synchronized by ODT and reporting whether the cached Office build changed;
- successful installation from local staged content;
- historical cold-cache versus warm-cache timing with similar Runner installation times in the recorded runs.

See [Validation matrix](testing.md) and [Performance](performance.md) for the tested versions and limits. Earlier Office incremental-refresh timings do not predict the current complete-generation refresh cost.

## Requesting a new built-in app

Built-ins are maintained as product-specific code in OSDStage, so they are deliberately selective. A request should only be considered when the app is a good fit for a generic, repeatable deployment path.

### Required characteristics

A built-in candidate should:

- be broadly used in enterprise or managed Windows environments;
- have a direct, deterministic vendor download source;
- be acquired from that vendor at runtime/cache time rather than being bundled, mirrored, or redistributed by OSDStage;
- use a stable URL, documented API/endpoint, or similarly maintainable vendor-supported acquisition method;
- support unattended installation with predictable exit codes;
- work without customer-specific credentials, tenant-specific portals, or interactive download flows;
- be maintainable without scraping HTML, browser automation, traffic sniffing, or reverse-engineering temporary download links.

### Download-source rule

OSDStage must be able to acquire the installer directly from the vendor in a predictable way.

A vendor using a CDN is not automatically a problem. The requirement is that the vendor exposes a stable, supported download URL or endpoint. A built-in will not be added when the installer must come from a third-party mirror, community package source, OSDStage itself, or when acquisition depends on techniques such as:

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

The repository model is the default for apps that are:

- customer-specific;
- line-of-business or internally developed;
- uncommon or narrowly used;
- hosted internally;
- accessible only after authentication;
- distributed through portals with non-deterministic download links;
- unsuitable for a generic vendor-native maintenance flow.

Those apps belong in `catalog.json` / `Package.zip`, where the organization controls acquisition and packaging.

### What to include in a request

A useful built-in request should include:

- product name and vendor;
- vendor documentation URL;
- direct installer URL(s) or documented download endpoint;
- supported architectures;
- unattended installation command;
- evidence that the app is broadly used;
- expected update/freshness mechanism if known.

A request meeting these criteria can still be declined if the vendor's acquisition or installation model is too fragile to maintain safely.

### Zoom Workplace

Zoom uses the standard **machine-wide Workplace MSI**, not Zoom Rooms, the Outlook
plugin or a VDI package. The default architecture is x64; ARM64 is opt-in.

```powershell
# WinPE after OSDCloud, before the first Windows boot.
Add-OSDStageZoomWorkplace

# Optional installation settings. Replaces the existing Zoom queue entry.
Add-OSDStageZoomWorkplace -NoDesktopShortcut -SsoHost 'example.zoom.us' `
    -ZConfig @{ DisableZoomOnboarding = $true } `
    -ZRecommend @{ AudioAutoAdjust = $true }

# Full Windows preparation machine only: optional cache preparation.
Sync-OSDStageZoomWorkplace
Sync-OSDStageZoomWorkplace -Architecture arm64
```

Downloads use Zoom's latest MSI endpoints:

- x64: <https://zoom.us/client/latest/ZoomInstallerFull.msi?archType=x64>
- ARM64: <https://zoom.us/client/latest/ZoomInstallerFull.msi?archType=winarm64>

Each architecture uses `BuiltIn/ZoomWorkplace/<architecture>/ZoomInstallerFull.msi` and
`CacheInfo.json`. HTTP metadata decides reuse versus acquisition. Windows checks
Authenticode and the expected organization **Zoom Communications, Inc.** before
accepting signed content. A candidate is validated before the active generation
is replaced; failed acquisition preserves the previous generation. Offline use
requires a valid staged MSI. The ordinary MSI runner installs silently with
`/qn /norestart ALLUSERS=1`, a timeout and runtime logging. No retry task is added.

`ZConfig` enforces settings; `ZRecommend` supplies defaults users may change.
Zoom gives enforced settings precedence. OSDStage serializes hashtables in a
stable order and converts Boolean values to `1`/`0`. Values must be strings,
integers or Booleans; quotes, semicolon separators, control characters and
trailing backslashes are rejected. Settings requiring those characters need a
custom repository package or management policy. Validation protects argument
syntax; it does not claim that every setting name/value is supported by Zoom.
Do not store credentials or enrollment tokens in these parameters: deployment
intent and MSI diagnostics are not secret stores.

The obsolete `EnableSilentAutoUpdate`, `AlwaysCheckLatestVersion`, `ZoomAutoUpdate`
and `SetUpdatingChannel` settings are rejected. Use Zoom's current Enterprise
Auto Update policies when needed. Omission preserves vendor behavior; OSDStage
does not disable updates, configure a user account or install plugins by default.
Changing these installation settings does not require a different MSI and does
not invalidate an otherwise reusable cache. A repeated Add call updates the
single Zoom queue entry.

Sources: [Zoom mass deployment and configuration](https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0064484)
and [Zoom administrator downloads](https://zoom.us/download/admin).
Physical SYSTEM/pre-OOBE installation and ARM64 device validation remain separate
from automated tests; see [the Zoom test procedure](zoom-validation.md).


## 7Zip

```powershell
# WinPE, after OSDCloud has applied Windows:
Add-OSDStage7Zip

# Optional: prepare the USB flash drive on a full Windows development PC:
Sync-OSDStage7Zip
```

Both commands accept `-Architecture x64`, `x86` or `arm64`; the default is `x64`.
`Add-OSDStage7Zip` also accepts `-InstallTimeoutMinutes` (default 10) and the
usual optional `-WindowsPath`. It stages deployment intent without downloading
in WinPE. The official EXE is installed silently, machine-wide, with `/S` during
the Windows phase before OOBE. File associations and user preferences are left
to Windows/vendor defaults. There is no automatic update service added by OSDStage.

The [vendor recommends the EXE installer](https://www.7-zip.org/download.html).
OSDStage resolves the latest stable release from the official
[`ip7z/7zip` GitHub repository](https://github.com/ip7z/7zip/releases/latest).
It requires a matching architecture asset, an expected official asset URL and a
published SHA-256 digest. Missing or unexpected metadata fails closed; there is
no unverified download fallback or custom `PackageUri` override for this built-in.

One active generation per architecture lives at `BuiltIn/7Zip/<architecture>`.
Each check reads release metadata, then compares version and SHA-256. An unchanged
package is reused without downloading the EXE. A new candidate must match the
release SHA-256, byte size and PE architecture before a complete directory swap.
Failed downloads or validation leave the previous active generation intact.
Runner checks the staged generation again before executing it.

This is **release SHA-256 validation, not Authenticode publisher validation**.
The trust anchor for a new download is the official repository metadata over HTTPS.
Offline validation compares against the locally recorded release digest; it does
not protect against an attacker changing both the installer and its local metadata.
`Get-OSDStageCache` also checks the recorded hash, size and architecture for 7Zip.

If the release API or download fails (including GitHub rate limits), PreInstall
may use a valid staged generation, reporting `FallbackCacheUsed` and the refresh
error. Without network it reports `OfflineCacheUsed`. With no valid fallback,
7Zip fails acquisition and is skipped; other queued apps can continue.
Keep access to `api.github.com`, `github.com` and GitHub's release asset CDN available.
Use a custom repository package when you require a pinned release or custom setup.


## Visual Studio Code

```powershell
# WinPE, after OSDCloud
Add-OSDStageVisualStudioCode

# Optional cache preparation on a full Windows computer
Sync-OSDStageVisualStudioCode
```

Both commands accept `-Architecture x64` (default) or `arm64`.
`Add-OSDStageVisualStudioCode` also accepts `-InstallTimeoutMinutes` (default 10)
and the usual optional `-WindowsPath`. The built-in uses **Stable system setup**:
installation in Program Files for all users, not the per-user installer,
Insiders or a portable ZIP.

### Acquisition and validation

PreInstall queries the official Microsoft update service:
`https://update.code.visualstudio.com/api/update/win32-<architecture>/stable/latest`.
The response must identify a concrete release version, commit, SHA-256 and the
matching system-installer URL on `vscode.download.prss.microsoft.com`.
An unexpected host, platform, user installer or missing digest is rejected.

One active generation per architecture is stored in
`BuiltIn/VisualStudioCode/<architecture>`. A matching generation is reused only
after checking its recorded length, full SHA-256 and Microsoft Corporation
Authenticode signature. Otherwise, a separate candidate is downloaded and
validated before replacing the active generation. Failed candidates do not
replace an existing active cache. Runner repeats the hash and publisher checks
before execution. The shared transaction helper also recovers verified previous
generations after an interrupted swap.

The API does not publish a file size. The cache records the downloaded length;
the release SHA-256 verifies the downloaded content. Architecture is selected
through the exact official platform and filename, not the PE machine type of the
Inno Setup bootstrapper. `Get-OSDStageCache` checks recorded metadata, length and
SHA-256 without requiring publisher evaluation in WinPE. Use `Get-OSDStageCache -VerifySignatures`
on full Windows for trust inspection; metadata alone is not a signature.

If acquisition fails, a fully verified staged generation of the requested
architecture can be used as fallback. Without one, acquisition fails and the
installation is skipped; other queued apps can continue.

### Installation behavior

The system installer runs with:

```text
/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /MERGETASKS=!runcode /RESTARTEXITCODE=3010
```

This prevents automatic editor launch and reboot. Other installer tasks keep
Microsoft's defaults, including PATH and supported-file registration. OSDStage
does not configure extensions, accounts, telemetry, editor settings or update
policies. System-install updates may require elevation; manage these separately
if your organization requires a specific policy.

Sources: [VS Code Windows setup](https://code.visualstudio.com/docs/setup/windows),
[official installer source](https://github.com/microsoft/vscode/blob/main/build/win32/code.iss),
and [Inno Setup command-line parameters](https://jrsoftware.org/ishelp/topic_setupcmdline.htm).

### Isolated deployment test

Run `tools/Test-OSDStageVisualStudioCode.ps1 -Phase Stage` from the candidate source
in WinPE on a fresh Windows deployment. It stages only VS Code and copies its
validator to `C:\ProgramData\OSDStage\Tests`. At OOBE, run that copied script with
`-Phase Validate`. It correlates deployment IDs, verifies the machine-wide
registration, executable version, successful result and cleanup, and checks
that the editor did not launch. It never reruns SetupComplete. Interactive
first-user behavior remains a separate check.

## Microsoft runtime prerequisites

Visual C++ v14 and modern .NET runtimes are optional built-ins. Add them in WinPE
after Windows is applied, just like apps:

```powershell
# Select exactly one architecture per command.
Add-OSDStageVisualCRedist -Architecture x64

# Standalone runtime for console apps and services.
Add-OSDStageDotNetRuntime -RuntimeType Runtime -Channel 10.0 -Architecture x64

# Desktop runtime for WPF/Windows Forms; includes the ordinary .NET runtime.
Add-OSDStageDotNetRuntime -RuntimeType Desktop -Channel 10.0 -Architecture x64
```

Normally choose Runtime **or** Desktop for the same channel and architecture;
Desktop already includes the ordinary runtime. Different .NET channels and
architectures may coexist. `-Channel` defaults to `10.0`; `-RuntimeType` defaults
to `Desktop`. All four runtime Add/Sync cmdlets require `-Architecture x86`
or `-Architecture x64`. There is no default or combined architecture selection.
Separate explicit calls remain separate deployment items. Native ARM64 runtimes are not included
in this addition. Legacy .NET Framework, ASP.NET Core, SDKs, Java and older
Visual C++ runtime families such as 2013 are separate products and are not installed.

Runtime staging puts these prerequisites before app entries while
preserving the relative order within each group. This is not a dependency engine:
OSDStage does not infer which apps need which runtimes, and its normal
continue-queue behavior still applies if a prerequisite fails.

### Why Visual C++ has one evergreen family

`Add-OSDStageVisualCRedist` and `Sync-OSDStageVisualCRedist` offer the latest supported
v14 redistributable through Microsoft's official evergreen endpoint. There is no
year or legacy-version selector. Visual Studio 2017, 2019, 2022 and 2026 use the
same v14 runtime family; the redistributable must be at least as recent as the
build tools used by the app. Microsoft also documents upgrading the
original 2015 redistributable in place to the current v14 runtime.

Separate 2017/2019/2022 built-ins would duplicate this selection. Some older v14
servicing branches remain supported, but this built-in deliberately follows the
latest supported release instead of pinning a servicing branch. Select exactly
one architecture explicitly per command; x64 does not satisfy an x86 app's
runtime requirement.

Visual C++ 2013 (v12), 2012 (v11), 2010 (v10), 2008 (v9) and 2005 (v8) are separate
legacy families outside general support. The latest v14 does not replace their
dependencies. Do not remove them from an existing computer simply because v14 is
installed. A legacy dependency, or a vendor-required pinned branch, belongs in an
explicitly maintained [repository package](repository.md) for the app
that needs it, rather than another evergreen built-in. Packaging it yourself does
not restore Microsoft support. Microsoft's limited product-specific support
exceptions do not make those old runtimes generally supported.

See Microsoft's [runtime lifecycle FAQ](https://learn.microsoft.com/en-us/lifecycle/faq/visual-c-faq)
and [latest supported downloads](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist).

### Acquisition and verification

- Visual C++ uses Microsoft's official `https://aka.ms/vc14/vc_redist.<architecture>.exe`
  links. A HEAD request checks the resolved Microsoft URL, length, ETag and/or
  Last-Modified before confirming reuse. The downloaded installer must be signed
  by Microsoft and report a v14 file version. Its locally recorded SHA-256 and
  size are checked on subsequent reuse. This is not a Microsoft-published SHA-256.
- .NET uses Microsoft's `builds.dotnet.microsoft.com/dotnet/release-metadata/<channel>/releases.json`.
  It selects the latest published stable patch within the requested channel and
  the exact Windows Runtime or Desktop EXE. Preview channels are rejected.
  Only channels `8.0`, `9.0` and `10.0` are currently offered, and only during their
  support lifecycle. Microsoft metadata must report active or maintenance support
  for online acquisition. EOL and preview status blocks acquisition and fallback.
  The requested channel is never silently upgraded to another major version.
  The official SHA-512 and Microsoft
  Authenticode signature are checked before promotion and execution.
- Each replacement is downloaded separately and validated before promotion.
  Download or validation failure preserves the previous generation. Offline or
  failed online acquisition can use a verified compatible staged fallback;
  this is reported separately from confirmed current cache reuse.
  Missing, corrupt, incompatible or untrusted fallback content is never executed.
  Without a usable fallback, that runtime fails and the deployment reports failure;
  independent queue entries follow the existing continue-queue policy. A direct
  `Sync` call reports acquisition errors and preserves the old generation rather
  than claiming it synchronized successfully. A metadata outage or missing support
  field may use verified staged content only while the bundled lifecycle policy
  still permits that channel; known EOL status never uses fallback.
- Runner checks the installed version for the requested architecture and runtime
  family/channel. A suitable equal or newer installation is retained. Otherwise
  the installer runs with `/install /quiet /norestart`; exit codes 0 and 3010
  require a successful post-install version check. Existing other channels are
  not removed. No machine reboot or global runtime/PATH configuration is requested.

### Supported .NET channels

The bundled offline policy permits .NET 8.0 and 9.0 through November 10, 2026,
and .NET 10.0 through November 14, 2028 (UTC dates). Staging, acquisition, cache
validation and execution reject these channels after their deadline, even without
internet access. The computer clock must be correct. Expired cache files and
existing installations are not deleted automatically. Microsoft release metadata
can reject a channel sooner; a module update is required to add a new major channel
or adopt a changed lifecycle date. These checks enforce supported channel lifetimes,
not a guarantee that an offline fallback is the newest available patch.

### Cache and preparation computer

```powershell
Sync-OSDStageVisualCRedist -Architecture x64
Sync-OSDStageDotNetRuntime -RuntimeType Desktop -Channel 10.0 -Architecture x64
Get-OSDStageCache -Name VisualCRedist,DotNetRuntime -VerifySignatures
```

Sync runs on full Windows, prepares the USB flash drive and installs nothing on
the preparation computer. Run Add in WinPE. Cache paths are
`BuiltIn/VisualCRedist/<architecture>` and
`BuiltIn/DotNetRuntime/<runtime-type>/<channel>/<architecture>`.
Only the active patch is retained per variant; a different channel or architecture
uses a different generation. Deployment IDs include the variant, for example
`VisualCRedist-x86` and `DotNetRuntime-Desktop-10.0-x64`.
`Get-OSDStageCache` exposes `VariantId` and `RuntimeType` to distinguish them.
The app list summarizes x64 Visual C++ and Desktop 10.0 x64; inspect the cache
inventory for all variants.

Sources: [Visual C++ downloads](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist),
[.NET installers and runtime types](https://learn.microsoft.com/en-us/dotnet/core/install/windows),
[.NET release metadata](https://github.com/dotnet/core/tree/main/release-notes).

## Windows capabilities (Features on Demand)

Use `Add-OSDStageWindowsCapability -Name <exact-identity> -Action Add|Remove` for capabilities, separately from optional-feature Enable/Disable. See [Windows capabilities](windows-capabilities.md) for Windows 11 25H2+ scope, online acquisition, result handling and the combined XPS/OpenSSH test.
