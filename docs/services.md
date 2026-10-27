# Windows services

`Add-OSDAppService` stages service configuration in WinPE after OSDCloud has applied Windows. A bundled `Services` Script executes once as SYSTEM during SetupComplete. It uses the same transaction, SHA-256 integrity, offline-readiness, runner and cleanup contract as environment variables. No repository package or cache is required.

```powershell
# A deployment which intentionally does not need printing:
Add-OSDAppService -Name Spooler -StartupType Disabled -State Stopped

# An existing vendor service (examples, not predefined built-ins):
Add-OSDAppService -Name VendorService -StartupType AutomaticDelayedStart
Add-OSDAppService -Name VendorService -State Running -TimeoutSeconds 60
```

Specify an exact service **Name**, not a display name or wildcard, and at least one of StartupType/State. Supported startup modes are Automatic, AutomaticDelayedStart, Manual and Disabled; states are Running and Stopped. Startup and running state are independent: Disabled alone does not stop an already running service. Disabled together with Running is rejected. An attempt to start an already disabled service without an explicit enabled StartupType fails.

Repeated calls for the same name merge explicitly supplied fields, case-insensitively. For example, setting StartupType and later State produces one combined operation. An omitted field preserves previously staged intent for that service, or otherwise leaves that system setting alone. Supply a compatible State explicitly when replacing a previously staged Running operation with Disabled. Execution follows staged service order; configure prerequisite services first. Services must already exist when this built-in executes; no installation ordering against arbitrary app packages is inferred.

The runtime validates the complete config before mutation. For each service it queries current state, applies a changed startup mode using native `sc.exe config`, and requests start/stop only when needed. It then waits for the requested state within the same run and records the observed result. A matching pending transition is awaited without issuing a second request. TimeoutSeconds defaults to 30 (1-300 allowed) and applies separately to each control-command process and the state-transition wait. Timing out reports failure; a requested change may still finish later, but OSDApps does not retry or correct it.

Missing services, denied changes, native failures and transition timeouts are reported per service while subsequent services continue. Successful changes are not rolled back if a later state request fails. Results include before/after snapshots and native command exit codes/stdout/stderr. Native localized output is preserved, not parsed to infer success. The overall package returns 1 when any service failed, otherwise 0.

There is no forced dependent-service stop: `sc.exe stop` is sent only to the explicitly named service, and Windows may reject it if running dependents exist. Starting a service can start prerequisites through the Windows Service Control Manager. OSDApps does not modify dependencies, service credentials, executable paths, recovery settings or service permissions. Driver services, service creation/deletion and pause/resume are outside scope. Existing trigger-start/recovery/management policies can subsequently change state; this feature is a one-shot setup action, not ongoing enforcement.

No reboot, scheduled task, delayed retry or post-reboot check is introduced. `%ProgramData%\OSDApps\Results\Services-Result.json` records the same DeploymentId as Latest.json and the other built-in results. Global CleanupMode applies to staged configuration.

Tests cover intent merging, WhatIf, offline readiness alongside environment variables, rollback, tamper detection, idempotency, partial failures, timeout/no retry, and native PreInstall/runner integration. Native tests create two uniquely named disposable services, exercise delayed/normal automatic startup, start/stop, dependency rejection and disabled handling, then delete their own fixtures. They do not change existing Windows services. Physical WinPE/deployment acceptance remains a separate test.

Reference: [sc.exe config](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/sc-config).
