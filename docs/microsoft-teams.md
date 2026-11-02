# Microsoft Teams

[Documentation](README.md) · [Built-in apps](built-in-apps.md) · [Release availability](release-status.md)

**Stage in WinPE after OSDCloud; install during SetupComplete.** Sync examples are optional cache preparation on full Windows.

```powershell
Add-OSDStageMicrosoftTeams -Architecture x64
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

## Optional cache preparation

Run on full Windows with the OSDCloud cache volume connected:

```powershell
Sync-OSDStageMicrosoftTeams -Architecture x64
```

[Cache and validation details](built-in-acquisition.md) · [Troubleshooting](faq.md)
