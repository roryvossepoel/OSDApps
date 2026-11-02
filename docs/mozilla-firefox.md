# Mozilla Firefox Enterprise

[Documentation](README.md) · [Built-in apps](built-in-apps.md) · [Release availability](release-status.md)

**Stage in WinPE after OSDCloud; install during SetupComplete.** Sync examples are optional cache preparation on full Windows.

Mozilla Firefox Enterprise uses Mozilla's official MSI redirect endpoint. Both Rapid Release and ESR are supported, with x64 as the default architecture and `en-US` as the default language.

```powershell
# Rapid Release, x64, en-US
Add-OSDStageMozillaFirefoxEnterprise

# ESR
Add-OSDStageMozillaFirefoxEnterprise -Channel ESR

# x86 or another Mozilla locale
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

## Optional cache preparation

Run the matching Sync command on full Windows; choose the variant used by your deployment:

```powershell
Sync-OSDStageMozillaFirefoxEnterprise
Sync-OSDStageMozillaFirefoxEnterprise -Channel ESR
Sync-OSDStageMozillaFirefoxEnterprise -Architecture x86 -Language nl
```

[Cache and validation details](built-in-acquisition.md) · [Troubleshooting](faq.md)
