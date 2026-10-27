# Machine environment variables

Run `Add-OSDAppEnvironmentVariable` in WinPE after Windows has been applied. It stages one bundled `EnvironmentVariables` Script with SHA-256 checked configuration and runtime. No repository package, cache, download or environment change on the preparation PC/WinPE is needed. SetupComplete executes it once as SYSTEM in the installed Windows.

```powershell
Add-OSDAppEnvironmentVariable -Name DeploymentRing -Value 'Pilot'
Add-OSDAppEnvironmentVariable -Name ToolsRoot -Value '%ProgramData%\Tools' -ExpandString
Add-OSDAppEnvironmentVariable -Name EmptySetting -Value ''
Add-OSDAppEnvironmentVariable -Name LegacySetting -Remove
Add-OSDAppEnvironmentVariable -AppendPath @('C:\Tools', '%ProgramData%\Tools\bin')
Test-OSDAppDeployment -RequireOfflineReady -ThrowOnFailure
```

Only **machine scope** is supported. Set/Remove for a name supersedes earlier staged intent for that name, case-insensitively. PATH appends run in staging order, after any preceding explicit PATH Set. Setting PATH via `-Name Path -Value ...` deliberately replaces it; use `-AppendPath` for additions. Removing a machine variable does not remove a same-named user variable.

Values are stored literally as REG_SZ by default. `-ExpandString` uses REG_EXPAND_SZ, retaining `%Variable%` references without expanding them on the preparation PC, in WinPE, or in the runtime's process environment. Use single-quoted PowerShell literals when preserving `$`, percent references or other literal text. Empty strings remain present; deletion is explicit and behaves the same in Windows PowerShell 5.1 and PowerShell 7. Names are limited to 255 characters and values to 32766 characters; NUL values, equals signs/control characters in names, unsupported registry kinds and invalid PATH lists fail explicitly.

PATH updates read the **raw machine registry value**, never `$env:Path` (which could contain user/process-only additions). Existing text, order, duplicates, references and registry kind are preserved. New entries are skipped when their lexical identity already exists: comparison ignores case, slash direction, outer quotes on existing entries and trailing separators (while retaining drive-root meaning). It does not resolve symlinks, short names, `..` segments or equivalence between `%SystemRoot%` and `C:\Windows`. New entries must be absolute drive/UNC paths or percent-variable references; no semicolons, quotes or control characters. They need not exist yet. A missing PATH is created as REG_EXPAND_SZ. An existing REG_SZ PATH remains REG_SZ, so appended percent references remain literal in that case. An oversized result fails without truncating PATH.

The runtime writes HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment. It validates the complete configuration before any writes, then attempts each operation once, continuing after individual failures. Failures yield exit code 1 and preserve successful operations; no rollback, retry, scheduled task or forced reboot is introduced.

After changes, a single bounded WM_SETTINGCHANGE/Environment notification is attempted. Notification failure is reported separately and does not invalidate successfully persisted values. **Existing processes and services, including the parent OSDApps runner and its subsequently inherited environment, are not refreshed.** Do not depend on these new variables in later app installers in the same run. Normal future sign-ins/new environment construction pick up the machine values; this feature does not restart services or promise immediate propagation to all processes.

`%ProgramData%\OSDApps\Results\EnvironmentVariables-Result.json` records deployment ID, name/action, outcome, changed state, registry kind, added PATH entry count, errors without values and notification outcome. `Latest.json` contains the normal package result. Environment **values are not emitted in runtime logs or results**, but are readable in the staged config and Windows registry. This is not a mechanism for deploying secrets. Cleanup follows the global CleanupMode; Never retains configuration for tests.

Validation covers real registry operations on an isolated test key (including PATH), validation-before-mutation, continuation, idempotency, transaction rollback and tamper detection. Native PreInstall/runner integration uses unique temporary machine variables and cleans them up; it never changes the test host's machine PATH. A physical WinPE/deployment test remains the acceptance step.

References: [Windows environment variables](https://learn.microsoft.com/en-us/windows/win32/procthread/environment-variables), [WM_SETTINGCHANGE](https://learn.microsoft.com/en-us/windows/win32/winmsg/wm-settingchange).
