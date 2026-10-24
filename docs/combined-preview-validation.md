# Combined OSDApps preview validation

This is an **unreleased**, draft test candidate combining Microsoft Company Portal (PR #67) and CMTrace Open (PR #68), intended for a disposable x64 Windows test deployment alongside the separately hosted `DisplayLinkGraphicsHotDesking` repository package.

- Prepare the OSDCloud USB cache on full Windows using the operator-supplied official Microsoft Company Portal Preinstall Kit (x64) and `Sync-OSDAppMicrosoftCompanyPortal`.
- Prepare CMTrace Open x64 from the upstream signed stable MSI using `Sync-OSDAppCMTraceOpen`.
- Set the Azure repository catalog and synchronize the independently packaged DisplayLink application using `Sync-OSDAppRepository -Name DisplayLinkGraphicsHotDesking -Architecture x64`.
- In WinPE after applying Windows, stage `Add-OSDAppWindowsInboxCleanup -Preset Tested13`, `Add-OSDAppMicrosoftCompanyPortal -Architecture x64`, `Add-OSDAppCMTraceOpen -Architecture x64`, and `Add-OSDApp -Name DisplayLinkGraphicsHotDesking -SkipCacheRefresh`.
- Require `Test-OSDAppDeployment -RequireOfflineReady -ThrowOnFailure` to succeed and show four staged entries.
- Verify actual SYSTEM execution, Company Portal provisioning/first-user registration, CMTrace Open MSI install, DisplayLink device behavior and runtime cleanup after OOBE/Autopilot.

Do not publish this combined candidate to PowerShell Gallery or merge it to `main` solely on staging or CI results. The individual feature PRs require their own review.
