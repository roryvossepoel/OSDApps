# Cisco Webex

[Documentation](README.md) · [Built-in apps](built-in-apps.md) · [Release availability](release-status.md)

**Stage in WinPE after OSDCloud; install during SetupComplete.** Sync examples are optional cache preparation on full Windows.

Cisco Webex App is a vendor-native MSI built-in for Windows x64 and ARM64. It uses Cisco's **non-localized Webex App-only package**, as Cisco recommends for bulk deployment, not the localized MSI, Meetings bundle or VDI client.

Official evergreen package sources:

```text
x64:   https://binaries.webex.com/WebexOfclDesktop-Win-64-Gold/Webex_en.msi
arm64: https://binaries.webex.com/WebexOfclDesktop-Win-Arm-64-Gold/Webex_en.msi
```

The x64 URL was verified in practice on 10 October 2026 (Cisco-signed MSI, version 46.9.0.35800, 259.9 MiB); both online and fully offline SetupComplete installations succeeded. **ARM64 has not yet been field-validated.**

These x64/ARM64 URLs are listed in Cisco's [Webex App installation guide](https://help.webex.com/en-US/article/nw5p67g/Webex-%7C-Installation-and-Automatic-Upgrade). That page also contains an alternate older non-localized x64 URL in its package table; verify the actual current MSI delivery before production use. `-PackageUri` can override the source.

```powershell
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

## Optional cache preparation

Run on full Windows. Choose the target architecture:

```powershell
Sync-OSDStageCiscoWebex -Architecture x64
```

[Cache and validation details](built-in-acquisition.md) · [Troubleshooting](faq.md)
