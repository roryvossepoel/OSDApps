# Windows capabilities (Features on Demand)

`Add-OSDAppWindowsCapability` stages explicit capability changes in WinPE after
OSDCloud has applied Windows. One `WindowsCapabilities` built-in Script executes
the combined selections during SetupComplete as native 64-bit SYSTEM.

This is experimental until the physical deployment test passes. The runtime
checks the installed target OS: Windows 11 client 25H2 or later (build 26200+).
WinPE's build is not the target build and is not used for this check. Passing
staging/preflight validates configuration and files, not target applicability;
the OS/context and capability-availability checks happen during SetupComplete.

## Explicit selections

```powershell
Add-OSDAppWindowsCapability -Name 'XPS.Viewer~~~~0.0.1.0' -Action Add
Add-OSDAppWindowsCapability -Name 'OpenSSH.Client~~~~0.0.1.0' -Action Remove
Test-OSDAppDeployment -ThrowOnFailure |
    Format-List Valid,OfflineReady,NetworkRequired,AppCount
```

`-Name` accepts an array of exact capability identities. Obtain names from
`Get-WindowsCapability -Online` on a reference Windows installation. Names include
the tilde-separated locale/version fields; some identities end in `~~~~` rather
than a version. Names are data, never executable commands. Wildcards, path/command
delimiters and empty names are rejected. There is no fixed capability catalog,
bulk-removal preset or implicit selection. Across calls, the most recent action
for the same identity wins; unrelated selections remain. `-WhatIf` does not write
staging. Existing owned script/config hashes are checked before replacement.

Availability differs by OS release, edition and architecture. The runtime checks
for exactly the requested identity on the actual device. An unknown identity is
an error even for Remove. Windows resolves installation dependencies and may
reject a removal if another package depends on it. OSDApps does not remove those
dependents automatically. Installing OpenSSH Server does not request any OSDApps
service/firewall configuration. Capability support does not imply language-pack,
display-language or regional-settings orchestration.

## Source and cache behavior

No custom repository is needed. This first implementation provides the bundled
action, not Microsoft's FoD binaries. DISM selects sources using Windows servicing
policy and Windows Update when permitted. The device needs usable network access
at runtime when content is missing. OSDApps does not override update policies,
change service settings or populate its USB app cache from Windows servicing.
Custom `Source`, `LimitAccess` and repository `Package.zip` sources are not exposed
in this version.

Preflight conservatively reports `NetworkRequired=True` and `OfflineReady=False`
whenever any Add operation is queued, even if Windows might already have that
capability. Script/config integrity must still pass. Consequently, use
`Test-OSDAppDeployment -ThrowOnFailure` for this online test, without
`-RequireOfflineReady`. A valid remove-only capability entry is offline-ready.
Preflight `PayloadReady` describes the bundled script/config; it does not mean
Microsoft's installation payload has been cached.

## One attempt and results

The runtime reads the state, skips an already satisfied request, and otherwise
uses native `dism.exe /Online /Add-Capability` or `/Remove-Capability` with
`/NoRestart`. Native DISM is used because the PowerShell capability cmdlets do not
expose a `NoRestart` parameter. No automatic restart, scheduled task, login hook,
policy enforcement or later correction is installed.

Exit codes 0 and 3010 are checked, followed by an immediate state query. Success
with an unexpected nonpending state is reported as failure. Pending completion is
reported as `PendingRestart`, not as a verified completed state. An already-pending
initial state is reported as a failure requiring operator assessment; no servicing
is attempted on it. Ordinary per-capability failures are recorded and other
explicit operations continue. A DISM attempt is bounded to 30 minutes; after a
timeout remaining operations are marked `NotAttempted` because servicing may
still be active. No rollback or retry is attempted.

The configured result directory (normally `%ProgramData%\OSDApps\Results`) contains:

- `WindowsCapabilities-Result.json`: deployment ID, aggregate status/counts,
  per-capability action, before/after states, outcome, exit code, error and
  `RestartNeeded`. `RebootRequested` remains false.
- `WindowsCapabilities-<deployment-id>-<index>.log`: native DISM details for
  operations that actually ran. These remain outside disposable staging.

## First physical test

Run [the staging example](../Examples/Stage-OSDAppsCapabilitiesTest.ps1) in WinPE
after applying a fresh Windows 11 25H2+ image. Import the test module first. It
requests XPS Viewer Add and OpenSSH Client Remove, keeps logs with CleanupMode
Never and validates staging without requiring offline readiness. Keep network
available through SetupComplete and continue the normal Windows/OOBE flow.

The expected transitions are XPS `NotPresent` to `Installed`, and OpenSSH Client
`Installed` to `NotPresent`. The result file records the actual initial states;
an `AlreadyInstalled`/`AlreadyAbsent` result verifies idempotence but is not proof
of an install/removal transition. Share the result JSON and any failed operation's
DISM log for review. This does not install a post-login checking task or require
an additional reboot. No physical acceptance is claimed yet.

## Microsoft references

- [Capabilities and source/dependency handling](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/features-on-demand-v2--capabilities?view=windows-11)
- [Available non-language capabilities](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/features-on-demand-non-language-fod?view=windows-11)
- [Add-WindowsCapability](https://learn.microsoft.com/en-us/powershell/module/dism/add-windowscapability)

Optional Features are a separate Windows interface: use the existing
`Add-OSDAppWindowsFeature` for Enable/Disable feature names such as TelnetClient.
