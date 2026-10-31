# Integrate with a WinPE launcher

[Examples](README.md) · [Online staging](WinPE-Online.md) · [Results](../docs/getting-started.md#5-check-the-outcome)

Use this pattern in OSDT or another PowerShell-based WinPE launcher **after
OSDCloud has applied Windows and before the launcher reboots the target**.
It is an integration example, not a change to OSDT itself.

## Staging script

Include [Stage-OSDStage.ps1](Stage-OSDStage.ps1) in your launcher files. It loads
OSDStage from PowerShell Gallery, stages Office, Adobe Acrobat Unified and Chrome,
and calls `Test-OSDStageDeployment -ThrowOnFailure` after the last Add command.
Edit the queue and Office language in that file for your deployment. No module
version, USB module path or cache label is required.

Run the script in a **fresh child PowerShell process**. Do not dot-source it into
the UI process: the script uses `exit` to report its result. WinPE needs
PowerShellGet, Gallery access and the normal online deployment prerequisites.
The script does not prompt to choose a repository or install package providers.
Prepare those prerequisites in the WinPE image or launcher initialization.

## Gate the launcher's reboot

Adapt the local script path to where your launcher stores its files:

```powershell
$StagingScript = 'X:\OSDT\Scripts\Stage-OSDStage.ps1'
if (-not (Test-Path -LiteralPath $StagingScript -PathType Leaf)) {
    throw "Staging script not found: $StagingScript"
}

$process = Start-Process -FilePath 'powershell.exe' `
    -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$StagingScript`"" `
    -Wait -PassThru -ErrorAction Stop

if ($process.ExitCode -ne 0) {
    throw "OSDStage staging failed (exit $($process.ExitCode)). Reboot blocked."
}

# Only this success path may reach the launcher's existing reboot action.
# For a manual WinPE reboot, that action is: wpeutil.exe reboot
```

The staging script itself never reboots. Keep the launcher's reboot action after
this gate; do not put it in a `finally` block or an unconditional completion
handler. If the UI catches the error, show it and return to the operator without
continuing the deployment sequence. Waiting for the child process is essential;
starting it successfully is not evidence that staging succeeded.

| Outcome | Launcher action |
| --- | --- |
| Process fails to start, or any nonzero exit code | Stop and show the error; do not reboot. |
| Exit code `0` | Staging and preflight passed; continue to the launcher's normal reboot step. |

A staging failure can leave earlier queue entries and SetupComplete integration
on the target. This wrapper does not roll them back or make the whole queue a
single transaction. Inspect the error and staged state before retrying or
rebooting; a manual reboot would bypass the launcher gate.

## With or without a USB flash drive

The same script uses the default optional `OSDCloud` cache. With a matching USB
flash drive, keep it connected until OOBE. Without one, built-in content is
acquired on the Windows volume at first boot. Keep networking available in
both online scenarios.

`OfflineReady=False` and `NetworkRequired=True` can be normal without cached
payloads. This online example deliberately does not require offline readiness.
The preflight does not prove future vendor connectivity, product activation or
installation success. After SetupComplete, inspect the recorded deployment
results; exit code `0` here means **staged**, not **installed**.

The README quick start stays minimal. This separate wrapper supplies the error
handling and process contract needed by a launcher without adding module cmdlets.
