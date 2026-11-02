# Google Chrome Enterprise

[Documentation](README.md) · [Built-in apps](built-in-apps.md) · [Release availability](release-status.md)

**Stage in WinPE after OSDCloud; install during SetupComplete.** Sync examples are optional cache preparation on full Windows.

Google Chrome Enterprise uses Google's official Enterprise MSI directly from Google's download infrastructure. x64 is the default and x86 is optional. Google documents Windows Enterprise deployment with both 64-bit and 32-bit MSI packages.

```powershell
# x64 default
Add-OSDStageGoogleChromeEnterprise

# optional x86
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

## Optional cache preparation

Run the matching Sync command on full Windows; choose the variant used by your deployment:

```powershell
Sync-OSDStageGoogleChromeEnterprise
Sync-OSDStageGoogleChromeEnterprise -Architecture x86
```

[Cache and validation details](built-in-acquisition.md) · [Troubleshooting](faq.md)
