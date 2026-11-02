# Visual Studio Code

[Documentation](README.md) · [Built-in apps](built-in-apps.md) · [Release availability](release-status.md)

**Stage in WinPE after OSDCloud; install during SetupComplete.** Sync examples are optional cache preparation on full Windows.

```powershell
# WinPE, after OSDCloud
Add-OSDStageVisualStudioCode
```

## Optional cache preparation

Run on full Windows with the OSDCloud cache volume connected. Choose the architecture that matches your deployment:

```powershell
Sync-OSDStageVisualStudioCode
```

Both commands accept `-Architecture x64` (default) or `arm64`.
`Add-OSDStageVisualStudioCode` also accepts `-InstallTimeoutMinutes` (default 10)
and the usual optional `-WindowsPath`. The built-in uses **Stable system setup**:
installation in Program Files for all users, not the per-user installer,
Insiders or a portable ZIP.

## Acquisition and validation

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

## Installation behavior

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

## Isolated deployment test

Run `tools/Test-OSDStageVisualStudioCode.ps1 -Phase Stage` from the candidate source
in WinPE on a fresh Windows deployment. It stages only VS Code and copies its
validator to `C:\ProgramData\OSDStage\Tests`. At OOBE, run that copied script with
`-Phase Validate`. It correlates deployment IDs, verifies the machine-wide
registration, executable version, successful result and cleanup, and checks
that the editor did not launch. It never reruns SetupComplete. Interactive
first-user behavior remains a separate check.

[Cache and validation details](built-in-acquisition.md) · [Troubleshooting](faq.md)
