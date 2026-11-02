# 7Zip

[Documentation](README.md) · [Built-in apps](built-in-apps.md) · [Release availability](release-status.md)

**Stage in WinPE after OSDCloud; install during SetupComplete.** Sync examples are optional cache preparation on full Windows.

```powershell
# WinPE, after OSDCloud has applied Windows:
Add-OSDStage7Zip
```

## Optional cache preparation

Run on full Windows with the OSDCloud cache volume connected. Choose the architecture that matches your deployment:

```powershell
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

[Cache and validation details](built-in-acquisition.md) · [Troubleshooting](faq.md)
