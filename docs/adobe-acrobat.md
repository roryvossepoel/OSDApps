# Adobe Acrobat Unified

[Documentation](README.md) · [Built-in apps](built-in-apps.md) · [Release availability](release-status.md)

**Stage in WinPE after OSDCloud; install during SetupComplete.** Sync examples are optional cache preparation on full Windows.

Adobe Acrobat Unified supports Adobe's official x64 and x86 unified Acrobat/Reader packages. x64 is the default.

```powershell
# x64 is the default
Add-OSDStageAdobeAcrobatUnified

# optional x86
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

## Optional cache preparation

Run the matching Sync command on full Windows; choose the variant used by your deployment:

```powershell
Sync-OSDStageAdobeAcrobatUnified
Sync-OSDStageAdobeAcrobatUnified -Architecture x86
```

[Cache and validation details](built-in-acquisition.md) · [Troubleshooting](faq.md)
