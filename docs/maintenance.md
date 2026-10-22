# Maintenance checks and diagnostics

Use [`tools/Test-OSDAppsMaintenance.ps1`](../tools/Test-OSDAppsMaintenance.ps1) on the Windows preparation PC when reviewing a USB flash drive, a release or a saved deployment result. Use Diagnostics mode on the deployed PC (including OOBE PowerShell) to collect its results and logs. This optional repository tool is separate from the Gallery module: it adds no exported commands and is not part of SetupComplete.

Download the script from the repository, or run it from a checkout. Windows PowerShell 5.1 and PowerShell 7 are supported. The examples below assume the repository root is the current directory.

## Check a USB flash drive

```powershell
$report = & .\tools\Test-OSDAppsMaintenance.ps1 -Mode Usb -UsbRoot D:\
$report.Checks | Format-Table -Wrap
$report.Details.CacheHealth | Format-List
```

Omit `-UsbRoot` to detect exactly one volume labelled `OSDCloud`. Specify `-ExpectedVersion 0.42.0` if you want to check a particular rollout. The script inspects the newest version directory; it does not silently select an older version to meet that expectation.

This checks the module manifest, import, exported functions, required runtime files and existing offline cache-health rules. It does not download vendor metadata or validate every publisher signature. A pass is not proof that every package is the newest vendor release, or that the module bytes match the Gallery package.

Run while no synchronization or other cache writer is active. The read-only health check does not take a writer lock or provide an atomic snapshot. The module is imported into the script session; use a separate PowerShell process if you want to keep your current session untouched:

```powershell
powershell.exe -NoProfile -File .\tools\Test-OSDAppsMaintenance.ps1 -Mode Usb -UsbRoot D:\ -ThrowOnFailure
```

## What a cache check proves

`Healthy`, `Valid`, configuration compatibility and vendor freshness answer different questions. Read the per-entry details as well as the summary. These inspection commands do not synchronize, repair or prune the cache.

| Inspection | Evidence and limits |
| --- | --- |
| `Get-OSDAppCacheHealth -Offline` | Checks local repository metadata and archive hashes, built-in identity/layout and the app-specific checks below. Reports missing, corrupt, orphaned and renamed content. It does not query vendor releases or compare an Office deployment request. |
| `Get-OSDAppCacheHealth` with a configured repository catalog | Also compares repository packages with the selected catalog's versions, architectures and hashes. This is repository desired state, not a freshness query for built-ins. Check `DesiredStateAvailable` and `CatalogError`. |
| `Get-OSDAppCache` / `Test-OSDAppCache` | Inspect discovered entries using the app-specific rules below. They do not provide the same namespace/reconciliation report as cache health. `Test-OSDAppCache` summarizes these entries; a `-Name` filter limits that summary. |
| `-ResolveVersions` on the inventory/test commands | Resolves eligible cached package versions locally on full Windows. It does not ask the vendor whether those versions are latest. |
| `-VerifySignatures` on the inventory/test commands | Adds Windows Authenticode and expected-publisher inspection for supported files. Check each entry's `SignatureStatus` and `SignatureScope`; unsupported formats remain outside this check. Windows trust evaluation can use the network. |

### Local integrity checks by package

These are the checks used by cache inventory and inherited by cache health. They use existing local metadata; they do not fetch a new vendor manifest.

| Package | Local checks |
| --- | --- |
| Repository applications and scripts | `Package.zip` is hashed against the recorded SHA-256. Online desired-state health uses the selected catalog hash when available. This does not validate script behavior or installer success. |
| Microsoft 365 Apps | Required paths, exactly one version directory matching the recorded build, a nonempty payload directory, and equal SHA-256 hashes for the shared and version-specific CABs. This is generation consistency, not a hash check of every Office data file. |
| Microsoft Teams | Bootstrapper and resolved MSIX file presence. Optional Authenticode inspection covers the bootstrapper only. |
| Chrome, Firefox, Webex and Zoom | Resolved MSI file presence. Optional Authenticode inspection covers the MSI and expected publisher. |
| Adobe Acrobat Unified | Resolved ZIP file presence. The outer ZIP is not Authenticode-assessed by cache inspection. |
| 7Zip | Recorded release identity/source, file size, SHA-256 and executable architecture. Its digest comes from release metadata; Authenticode is not assessed. |
| Visual Studio Code | Recorded release identity/platform/source, file size and SHA-256. Optional Authenticode inspection adds the Microsoft publisher check. |
| VisualCRedist | Recorded variant/version/source, file size and SHA-256. Optional Authenticode inspection adds the Microsoft publisher check. |
| .NET runtimes | Recorded variant/channel/version/source, supported-channel policy, file size, SHA-256 and recorded release SHA-512. Optional Authenticode inspection adds the Microsoft publisher check. |

`SizeMB` and `TotalSizeMB` report observed disk usage. They are not universal completeness checks. The explicit recorded-size comparisons for 7Zip, VS Code and runtimes are separate checks. A hash match proves equality with the referenced metadata, not that the local metadata itself was independently revalidated online.

### Reading the summary safely

- `Healthy=True` means no failing health condition was found under those rules. It is not proof of vendor freshness, all publisher signatures or compatibility with a future app selection. Check `CacheAvailable`, `EntryCount` and the individual entries; an existing empty cache can be healthy without containing deployable apps.
- An entry's `Valid=True` means its app-specific local checks passed. `Get-OSDAppCache -VerifySignatures` reports the signature separately; it does not turn the entry's `Valid` field into a publisher result. `Test-OSDAppCache -VerifySignatures` also requires supported signature checks to complete for its overall `Valid` result.
- `SignatureChecksComplete=True` covers the supported signature candidates, not every cached file. Repository ZIPs, Adobe's outer ZIP and 7Zip are outside that Authenticode scope. WinPE cannot complete supported Authenticode inspection.
- `Version=Current` is a policy/metadata value, not confirmation that the vendor still advertises that release.

For a local inspection on full Windows:

```powershell
$health = Get-OSDAppCacheHealth -Offline
$health | Select-Object CacheAvailable, EntryCount, Healthy
$health.Entries | Format-Table Id, State, Integrity, Reason -Wrap

Get-OSDAppCache -VerifySignatures |
    Select-Object Id, Version, Valid, SignatureStatus, SignatureScope
```

Office configuration matching happens separately during staging and PreInstall: the requested acquisition settings are compared with the recorded payload profile. Online acquisition then makes the vendor-freshness decision. A cache can pass local health checks yet need new content for another language/product selection or a newer advertised build. See [Office compatibility and file-check limits](built-in-apps.md#office-cache-compatibility-with-deployment-configuration) and [built-in update detection](built-in-apps.md#how-update-freshness-is-determined).

## Automatic retired-cache cleanup logs

After successful VisualCRedist or 7Zip synchronization, cleanup of the known `VisualCppRedist` or `SevenZip` predecessor records its decisions in the existing log:

- Public Sync commands: `<cache>\Logs\Client.log`, component `CacheCleanup`.
- Windows PreInstall: the deployment's `Runtime.log`, component `PreInstall`.

| Event | Meaning |
| --- | --- |
| `CacheRetiredVariantRemoved` | The matching old architecture directory was removed after validating the active replacement. |
| `CacheRetiredVariantRetained` | A guard prevented removal, such as mismatched metadata, a linked path or recovery content. |
| `CacheRetiredParentRemoved` | The retired app directory was empty after variant cleanup and was removed. |
| `CacheRetiredParentRetained` | Other content remains, or the requested architecture has no old variant. Other architectures are not removed by this operation. |
| `CacheRetiredCleanupFailed` | Inspection, replacement validation or removal raised an error. `Stage` and `Error` identify the failed operation. A removal error can leave partially removed content; this event does not promise rollback. |

Records include `Id`, `RetiredId`, `Architecture`, `ActivePath`, the affected `Path`, `Reason` and `Stage`. A parent-retained record does not validate the remaining files. A missing retired app directory produces no cleanup event. These messages describe this specific automatic cleanup, not all unmanaged content or explicit namespace pruning; Teams retains its existing alias-cleanup events.

Cleanup still runs under the writer lock and uses the same replacement, identity and recovery guards. Logging adds no cleanup pass, vendor query or download. A logger failure warns without changing the cleanup decision. Existing synchronization result objects remain unchanged.

Diagnostics mode includes available runtime records through its normal runtime-log collection. To also include USB maintenance history, explicitly add the client log (which may contain multiple deployments):

```powershell
$report = & .\tools\Test-OSDAppsMaintenance.ps1 -Mode Diagnostics `
    -AdditionalLogPath D:\OSDApps\Logs\Client.log `
    -OutputPath C:\Temp\OSDApps-Diagnostics.zip
```

Use the actual USB drive letter and a new ZIP path in an existing directory. The normal diagnostic size limits and sharing precautions apply.

## Check a published release

```powershell
$report = & .\tools\Test-OSDAppsMaintenance.ps1 -Mode Release
$report.Checks | Format-Table -Wrap
```

By default this checks the latest stable GitHub release. Add `-ExpectedVersion 0.42.0` to inspect that exact release. It resolves the release tag to a commit, checks the latest CI and publishing workflow runs for that commit, and asks PowerShell Gallery for the exact version. It requires internet access and `Find-Module` from PowerShellGet. Network errors, API rate limits, absent runs and pending jobs produce `ReviewRequired`, not a pass.

Gallery visibility confirms a listing, not package content. The [publishing workflow](releasing.md#gallery-verification-delays) downloads and compares package files during publication. This tool does not repeat that download. A manually dispatched workflow from a different commit is outside the release-commit query.

A failed publishing run remains visible even when the version is available in Gallery. For example, 0.42.0 was published but its original download-verification step failed; this check correctly reports `ReviewRequired` for that historical run. It does not republish or rewrite history.

## Inspect a saved deployment result

Copy the deployment's `Latest.json` to the preparation PC, then run:

```powershell
$report = & .\tools\Test-OSDAppsMaintenance.ps1 -Mode Result -ResultPath C:\Temp\Latest.json
$report.Checks | Format-Table -Wrap
$report.Details.Result.Applications | Format-Table Id, Status, AcquisitionOutcome
```

Optionally supply `-DeploymentId` to ensure you are inspecting the intended deployment. The tool validates the supported result schema, identity, application counts and final status. It surfaces recorded offline/fallback acquisition warnings separately from installation success. Older results without acquisition fields remain readable; missing historical fields do not establish whether an online refresh succeeded.

This examines recorded installer outcomes. It does not inspect the deployed machine, verify cleanup or activation, or rerun SetupComplete. A `Running` result or an empty successful queue requires review.

## Export a diagnostic bundle

Run on the affected PC after deployment, using an existing output directory:

```powershell
$report = & .\tools\Test-OSDAppsMaintenance.ps1 -Mode Diagnostics -OutputPath C:\Temp\OSDApps-Diagnostics.zip
$report.Details.Bundle | Format-List
```

This writes a local ZIP. It reads `%ProgramData%\OSDApps\Results\Latest.json`, follows its recorded `LogPath`, and includes available `.1`, `.2` and `.3` rotations. A standalone `PreInstall.json` is included only when its deployment ID matches. The embedded PreInstall result remains in Latest.json. If Runner never produced a readable result, the standalone PreInstall result supplies the identity and time window; the missing Runner result is still reported as a warning. Use `-DeploymentId` to require a particular deployment; a missing or different identity stops export.

The collector searches only the top level of the current temporary directory, Windows Temp, SystemTemp and SYSTEM profile Temp. It selects Office ODT machine/date logs and known Teams, Chrome, VC++ and Adobe log names modified within the recorded deployment period, with five minutes of padding. These are **installer log candidates**, not proof that a file belongs to the deployment. It does not recursively search all temporary files. No valid start/completion timestamps means automatic installer discovery is skipped with a warning.

For custom paths or logs saved elsewhere:

```powershell
$report = & .\tools\Test-OSDAppsMaintenance.ps1 -Mode Diagnostics `
    -ResultPath C:\Evidence\Latest.json `
    -LogPath C:\Evidence\Runtime.log `
    -InstallerLogDirectory C:\Evidence\InstallerLogs `
    -AdditionalLogPath C:\Evidence\OfficeDownload.log `
    -OutputPath C:\Evidence\Support.zip
```

`-LogPath` overrides the result's runtime log path. `-InstallerLogDirectory` replaces the default discovery directories; `-AdditionalLogPath` includes explicitly selected files without a filename or time filter. Nothing is downloaded or uploaded, and no OSDApps module import is required. Installers, cached payloads, scripts and Office configuration XML are not automatically collected.

The ZIP includes `Bundle.json` with source paths, file hashes, copy/skip outcomes and collection warnings. Files use numbered names to prevent collisions. Limits are 100 copied files, 20 MB per file and 100 MB total source data. Missing, inaccessible, oversized or linked files are reported and skipped; a bundle can still be created as `ReviewRequired`. An existing output file is never overwritten. Temporary collection files are removed afterwards.

A successful collection is not a successful deployment: a failed deployment can have a complete diagnostic bundle. The recorded deployment status is in `Bundle.json`. Use Result mode to validate deployment outcomes. Collection is not an atomic snapshot of live logs, and older rotated logs may contain other deployments. **Contents are not redacted; review the ZIP before sharing**, especially custom repository URLs, installer arguments and user/device information.

## Report and automation

| Status | Meaning |
| --- | --- |
| `Passed` | Every requested check completed successfully within the limits described above |
| `ReviewRequired` | A warning, unfinished check, acquisition fallback or unavailable external source needs attention |
| `Failed` | A module/cache check failed, a recorded deployment failed or the result is inconsistent |

The script returns one report object with `Mode`, `Status`, `Passed`, `CheckedAtUtc`, `Checks` and `Details`. It prints readable check messages as well. By default a report is returned without terminating the caller; `-ThrowOnFailure` throws after reporting whenever the status is not `Passed`, including `ReviewRequired`. Use that switch with `powershell.exe -File` when the process exit status is your automation gate.

The tool does not update modules, modify or prune cache content, install applications, remove backups or publish releases. Any corrective action is a separate decision.
