# Built-in apps

[Documentation](README.md) · [Getting started](getting-started.md) · [Release availability](release-status.md)

Choose an app, run its Add command in WinPE after OSDCloud, and let SetupComplete install it before OOBE. Built-ins obtain installers from the vendor; no custom repository is needed.

## Start with two apps

**On the target PC in WinPE, with OSDStage loaded:**

```powershell
Add-OSDStageGoogleChromeEnterprise
Add-OSDStage7Zip
Test-OSDStageDeployment -ThrowOnFailure
```

Keep the target online for first-boot acquisition. An attached volume labeled `OSDCloud` is detected and used as an optional cache. You do not need a drive-letter detection script or a Sync call for a normal online deployment.

**RC2:** Company Portal and CMTrace Open use the same automatic online acquisition flow. RC1 users must upgrade or prepare those two caches first; see [release availability](release-status.md).

## Choose an app

App installers default to x64. Visual C++ and .NET require an explicit architecture. Listed options describe the command interface; [physical validation](testing.md#validated-built-ins-and-remaining-variants) is narrower.

| App | Architectures | Configuration guide |
| --- | --- | --- |
| [Microsoft 365 Apps](microsoft-365-apps.md) | x64, x86 | Channel, language, products and licensing |
| [Microsoft Teams](microsoft-teams.md) | x64, x86, arm64 | Architecture |
| [Microsoft Company Portal](microsoft-company-portal.md) | x64, arm64 | Preinstall Kit and provisioning |
| [CMTrace Open](cmtrace-open.md) | x64, arm64 | Update-check setting and timeout |
| [Adobe Acrobat Unified](adobe-acrobat.md) | x64, x86 | Architecture and timeout |
| [Google Chrome Enterprise](google-chrome.md) | x64, x86 | Architecture |
| [Mozilla Firefox Enterprise](mozilla-firefox.md) | x64, x86 | Rapid/ESR channel and language |
| [Cisco Webex](cisco-webex.md) | x64, arm64 | MSI options and sign-in hints |
| [Zoom Workplace](zoom-workplace.md) | x64, arm64 | SSO host, shortcut and settings |
| [7Zip](7zip.md) | x64, x86, arm64 | Architecture and timeout |
| [Visual Studio Code](visual-studio-code.md) | x64, arm64 | Stable system installer |
| [Visual C++ v14](runtime-prerequisites.md) | x64, x86 | Explicit architecture |
| [.NET Runtime / Desktop Runtime](runtime-prerequisites.md) | x64, x86 | Runtime type, channel and explicit architecture |

## Optional cache preparation

Use Sync on a **full Windows preparation PC** to pre-download content. It installs nothing on that PC.

```powershell
Sync-OSDStageGoogleChromeEnterprise
Sync-OSDStage7Zip
```

For offline deployment, prepare all matching variants first and require a successful offline preflight in WinPE:

```powershell
Test-OSDStageDeployment -RequireOfflineReady -ThrowOnFailure
```

Keep the cache USB connected until OOBE appears. See [offline deployment](../Examples/WinPE-Offline.md) for the complete sequence.

## Windows components and settings

These use separate commands and are not vendor app installers:

| Task | Guide |
| --- | --- |
| Enable or disable optional features | [Windows features](windows-features.md) |
| Add or remove Features on Demand | [Windows capabilities](windows-capabilities.md) |
| Remove selected provisioned apps | [Windows inbox cleanup](windows-inbox-cleanup.md) |
| Configure the device | [Registry, files, Wi-Fi, certificates and other settings](README.md#user-guides) |

## More detail

- [Acquisition and validation](built-in-acquisition.md): cache freshness, fallback, vendor sources and signature scope.
- [Repository packages](repository.md): your own versions, installers and configuration.
- [Request a built-in](built-in-acquisition.md#requesting-a-new-built-in-app): requirements and information to supply.
- [Public metadata](public-metadata.md): machine-readable app and command inventory.
- [Troubleshooting](faq.md): logs, network, cache and deployment results.

<details>
<summary>Previously linked sections</summary>

<a id="windows-optional-features"></a>

[Continue to windows optional features](windows-features.md#windows-optional-features).

<a id="windows-inbox-cleanup"></a>

[Continue to windows inbox cleanup](windows-inbox-cleanup.md#windows-inbox-cleanup).

<a id="microsoft-365-apps"></a>

[Continue to microsoft 365 apps](microsoft-365-apps.md#microsoft-365-apps).

<a id="microsoft-teams"></a>

[Continue to microsoft teams](microsoft-teams.md#microsoft-teams).

<a id="adobe-acrobat-unified"></a>

[Continue to adobe acrobat unified](adobe-acrobat.md#adobe-acrobat-unified).

<a id="google-chrome-enterprise"></a>

[Continue to google chrome enterprise](google-chrome.md#google-chrome-enterprise).

<a id="mozilla-firefox-enterprise"></a>

[Continue to mozilla firefox enterprise](mozilla-firefox.md#mozilla-firefox-enterprise).

<a id="cisco-webex"></a>

[Continue to cisco webex](cisco-webex.md#cisco-webex).

<a id="zoom-workplace"></a>

[Continue to zoom workplace](zoom-workplace.md#zoom-workplace).

<a id="7zip"></a>

[Continue to 7zip](7zip.md#7zip).

<a id="visual-studio-code"></a>

[Continue to visual studio code](visual-studio-code.md#visual-studio-code).

<a id="acquisition-and-validation"></a>

[Continue to acquisition and validation](visual-studio-code.md#acquisition-and-validation).

<a id="installation-behavior"></a>

[Continue to installation behavior](visual-studio-code.md#installation-behavior).

<a id="isolated-deployment-test"></a>

[Continue to isolated deployment test](visual-studio-code.md#isolated-deployment-test).

<a id="microsoft-runtime-prerequisites"></a>

[Continue to microsoft runtime prerequisites](runtime-prerequisites.md#microsoft-runtime-prerequisites).

<a id="why-visual-c-has-one-evergreen-family"></a>

[Continue to why visual c has one evergreen family](runtime-prerequisites.md#why-visual-c-has-one-evergreen-family).

<a id="acquisition-and-verification"></a>

[Continue to acquisition and verification](runtime-prerequisites.md#acquisition-and-verification).

<a id="supported-net-channels"></a>

[Continue to supported net channels](runtime-prerequisites.md#supported-net-channels).

<a id="cache-and-preparation-computer"></a>

[Continue to cache and preparation computer](runtime-prerequisites.md#cache-and-preparation-computer).

<a id="installer-filenames"></a>

[Continue to installer filenames](built-in-acquisition.md#installer-filenames).

<a id="machine-readable-metadata"></a>

[Continue to machine readable metadata](built-in-acquisition.md#machine-readable-metadata).

<a id="vendor-only-source-policy"></a>

[Continue to vendor only source policy](built-in-acquisition.md#vendor-only-source-policy).

<a id="authenticode-and-publisher-policy-0340"></a>

[Continue to authenticode and publisher policy 0340](built-in-acquisition.md#authenticode-and-publisher-policy-0340).

<a id="how-update-freshness-is-determined"></a>

[Continue to how update freshness is determined](built-in-acquisition.md#how-update-freshness-is-determined).

<a id="http-metadata-comparison"></a>

[Continue to http metadata comparison](built-in-acquisition.md#http-metadata-comparison).

<a id="microsoft-365-apps-is-different"></a>

[Continue to microsoft 365 apps is different](built-in-acquisition.md#microsoft-365-apps-is-different).

<a id="office-cache-compatibility-with-deployment-configuration"></a>

[Continue to office cache compatibility with deployment configuration](built-in-acquisition.md#office-cache-compatibility-with-deployment-configuration).

<a id="what-is-checked-in-the-office-files"></a>

[Continue to what is checked in the office files](built-in-acquisition.md#what-is-checked-in-the-office-files).

<a id="one-active-office-cache-configuration-changes"></a>

[Continue to one active office cache configuration changes](built-in-acquisition.md#one-active-office-cache-configuration-changes).

<a id="choosing-built-in-office-or-repository-office"></a>

[Continue to choosing built in office or repository office](built-in-acquisition.md#choosing-built-in-office-or-repository-office).

<a id="microsoft-teams-bootstrapper"></a>

[Continue to microsoft teams bootstrapper](built-in-acquisition.md#microsoft-teams-bootstrapper).

<a id="sync-timing"></a>

[Continue to sync timing](built-in-acquisition.md#sync-timing).

<a id="deployment-flow"></a>

[Continue to deployment flow](built-in-acquisition.md#deployment-flow).

<a id="no-usb-mode"></a>

[Continue to no usb mode](built-in-acquisition.md#no-usb-mode).

<a id="fallback-behavior"></a>

[Continue to fallback behavior](built-in-acquisition.md#fallback-behavior).

<a id="usb-cache-behavior"></a>

[Continue to usb cache behavior](built-in-acquisition.md#usb-cache-behavior).

<a id="verbose-staging-diagnostics"></a>

[Continue to verbose staging diagnostics](built-in-acquisition.md#verbose-staging-diagnostics).

<a id="validated-deployment-behavior"></a>

[Continue to validated deployment behavior](built-in-acquisition.md#validated-deployment-behavior).

<a id="requesting-a-new-built-in-app"></a>

[Continue to requesting a new built in app](built-in-acquisition.md#requesting-a-new-built-in-app).

<a id="required-characteristics"></a>

[Continue to required characteristics](built-in-acquisition.md#required-characteristics).

<a id="download-source-rule"></a>

[Continue to download source rule](built-in-acquisition.md#download-source-rule).

<a id="when-to-use-the-repository-instead"></a>

[Continue to when to use the repository instead](built-in-acquisition.md#when-to-use-the-repository-instead).

<a id="what-to-include-in-a-request"></a>

[Continue to what to include in a request](built-in-acquisition.md#what-to-include-in-a-request).

<a id="configuration-and-synchronization"></a>

[Continue to configuration and synchronization](built-in-apps.md#choose-an-app).

<a id="windows-capabilities-features-on-demand"></a>

[Continue to windows capabilities features on demand](windows-capabilities.md).

</details>
