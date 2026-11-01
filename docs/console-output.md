# Console output

The next module build uses the Deploy-OSDCloud console style: a local timestamp,
`[INFO]`, `[WARN]` or `[ERROR]`, followed by a short message. Results appear on
consecutive lines, with no extra blank line per item. This is unreleased; the
published `1.0.0-rc1` still uses its earlier display.

```text
[2026-11-01T17:15:26] [INFO] Staged FileSystem: 9 operations queued on C:\
[2026-11-01T17:15:26] [INFO] Reused cache: GoogleChromeEnterprise (156.0.8078.80, x64)
[2026-11-01T17:15:27] [INFO] Deployment ready: 25 packages; offline ready, network not required.
[2026-11-01T17:30:00] [INFO] Deployment succeeded: 25/25 succeeded, 0 failed, 0 skipped.
```

Staged means queued for SetupComplete. Confirm installation with
`Get-OSDStageDeploymentResult` after Windows starts.

Success is green, warnings yellow and failed results red. Running/preview
messages are cyan; ordinary information uses the terminal's default foreground.
Colors are used only in an interactive terminal reporting virtual-terminal
support. Unsupported hosts and redirected process output use plain text.
`NO_COLOR` and PowerShell 7's `PlainText` output-rendering preference are respected.
Windows PowerShell 5.1 text capture with `Out-String` in a color-capable interactive
host can retain ANSI decoration; set `$env:NO_COLOR = '1'` for plain text there.
No console mode, background or global foreground setting is changed.

The timestamp is the local **display time**, including when you display a saved
object later. Original deployment timestamps remain available in the result.
The severity label describes the returned result; it does not convert a failed
validation object into a terminating error or change PowerShell's error streams.

## Keep the details when you need them

The lines are PowerShell **default formatting**, not replacement strings.
Assignments, filtering, properties and JSON export still receive full objects:

```powershell
$result = Test-OSDStageDeployment -WindowsPath 'C:\'
$result.Valid
$result | Format-List *
$result.Checks | Format-Table Name, Passed, Required, Message -Wrap
$result | ConvertTo-Json -Depth 20

Get-OSDStageCache | Format-Table Id, Version, Architecture, Valid -AutoSize
```

Use `-Verbose` for diagnostics supported by the command. Exceptions and warnings
remain visible. Default summaries omit catalog URLs, configuration values, file
content and raw error text; explicit full views and JSON still contain the
original details. A narrow terminal may wrap a long summary onto another line.

## Consistent across commands

| Commands | Default display |
| --- | --- |
| All deployment `Add-*` commands | Staged message, package/setting group, version when available, queued operation count when available and Windows target |
| Built-in `Sync-*` commands | Updated or reused cache when the result records it; otherwise synchronized cache. No inferred download/reuse counts |
| `Sync-OSDStageRepository` | Synchronized repository cache and catalog path; the result remains a `FileInfo` object |
| Inventory `Get-*` commands | One compact row per package, cache entry or status result |
| `Get-OSDStageDeploymentResult` | Saved deployment status and success/failure/skipped counts |
| `Test-*` commands | Readiness/validity plus failed check names or a short reason; full details remain on the object |
| `New-OSDStagePackage`, `New-OSDStageRepository`, `Add-OSDStagePackage` | Created package, ready repository or added repository entry |
| `Remove-OSDStageStaging` | Actual queue removals and remaining count; never claims to uninstall Windows software |
| `Clear-OSDStageCache` | Actual removed item count and preserved review count; logs are not included in the item count |
| `Set-OSDStageConfiguration` | Timestamped configuration confirmation on the information stream, preserving its normally empty success stream |
| `Show-OSDStageUI` | Opens the existing graphical viewer; no extra success-stream object |

Commands using `-WhatIf` retain PowerShell's preview messages. A repository or
cache cleanup preview returned as an object is described as not applied.
Empty inventory queries still return no objects and display no invented row.

Suppress the configuration message with `-InformationAction Ignore` or `6>$null`.
Its existing `-PassThru` switch returns the configuration object and displays the
same concise line instead, without a duplicate information message. Other
commands need no `-PassThru` switch to capture their results.

[Back to documentation](README.md)
