# Zoom Workplace

[Documentation](README.md) · [Built-in apps](built-in-apps.md) · [Release availability](release-status.md)

**Stage in WinPE after OSDCloud; install during SetupComplete.** Sync examples are optional cache preparation on full Windows.

Zoom uses the standard **machine-wide Workplace MSI**, not Zoom Rooms, the Outlook
plugin or a VDI package. The default architecture is x64; ARM64 is opt-in.

```powershell
# WinPE after OSDCloud, before the first Windows boot.
Add-OSDStageZoomWorkplace

# Optional installation settings. Replaces the existing Zoom queue entry.
Add-OSDStageZoomWorkplace -NoDesktopShortcut -SsoHost 'example.zoom.us' `
    -ZConfig @{ DisableZoomOnboarding = $true } `
    -ZRecommend @{ AudioAutoAdjust = $true }
```

## Optional cache preparation

Run on full Windows with the OSDCloud cache volume connected. Choose the architecture that matches your deployment:

```powershell
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

[Cache and validation details](built-in-acquisition.md) · [Troubleshooting](faq.md)
