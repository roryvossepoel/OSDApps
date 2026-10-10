# Show-OSDAppUI — experimental WinForms preview

This feature is on a development branch only, not yet in PowerShell Gallery. The public module has no organization-specific repository URL or deployment profiles.

## First smoke test: full Windows (read-only)

Download the OSDApps artifact from the green CI run on PR #14 (do not download the 0.33.0 PowerShell Gallery module). Extract the OSDApps folder and run in Windows PowerShell 5.1:

    Import-Module 'C:\Temp\OSDApps\OSDApps.psd1' -Force
    Show-OSDAppUI -PreviewOnly

Check: window opens; six built-ins appear; checkbox selection works; Cache Management tab displays local cache if attached. The repository URL is shown as read-only status and is taken from Get-OSDAppConfiguration. Offline-only refresh uses local cache without querying that URL or changing the configured value.

## Staging tests on Windows 11 — without changing the active OS

Staging, DeviceManifest.json, SetupComplete script generation, SHA-256 checks and repeated UI selections can be tested entirely on full Windows 11. Use the explicit isolated test mode:

    Import-Module 'C:\Temp\OSDApps\OSDApps.psd1' -Force
    Show-OSDAppUI -TestMode -Offline

The module creates a dedicated staging target under:

    %TEMP%\OSDApps-GUI-Staging-Test

Select cached repository apps (start with one small app), click **Stage selected apps**, and inspect:

    $target = Join-Path $env:TEMP 'OSDApps-GUI-Staging-Test'
    Get-Content (Join-Path $target 'Windows\Temp\OSDApps\DeviceManifest.json') -Raw
    Get-Content (Join-Path $target 'Windows\Setup\Scripts\SetupComplete.cmd')

Run Stage again to verify no duplicate queue entries or SetupComplete blocks. This **does not** modify the live Windows SetupComplete script and **will not** actually install apps on reboot; only staging can be validated. Full Windows without `-TestMode` is still browse-only.

For an online repository sync-and-stage test, configure the URL in the SAME PowerShell session before launching the GUI:

    Set-OSDAppConfiguration -CatalogUri 'https://example.org/catalog.json'
    Show-OSDAppUI -TestMode

Offline testing:

    Show-OSDAppUI -TestMode -Offline

Offline mode skips repository network calls without removing or changing CatalogUri. It requires an already populated cache on the USB volume (default label OSDCloud). Configuration is session-scoped; a fresh PowerShell session must configure the repository again.

## Third smoke test: actual WinPE (read-only first)

After OSDCloud has applied Windows but before reboot:

    powershell.exe -STA -NoProfile
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

Copy the PR artifact's OSDApps folder to the USB and import it using the correct drive letter, for example:

    Import-Module 'E:\Modules\OSDApps\OSDApps.psd1' -Force
    Show-OSDAppUI -PreviewOnly

If the read-only form works, test selecting/staging on a disposable test device with:

    Set-OSDAppConfiguration -CatalogUri 'https://example.org/your-repository/catalog.json'
    Show-OSDAppUI

For real deployment, the Stage button becomes active in WinPE with a detected offline Windows target. On full Windows it can also be enabled explicitly using -TestMode (only for the isolated test target). It requests confirmation before it invokes the existing Add-OSDApp cmdlets. Built-ins use default parameters; repository apps are staged together in one batch. All apps install later via SetupComplete.

## Limitations of this MVP

- Cache tab is READ ONLY; GUI synchronization and clearing are for later iterations.
- No presets, SUUD/MUSD/KIOSK logic, embedded repository URLs or external GUI dependencies.
- Unchecking a staged app does not remove it; staging is additive.
- Advanced Office settings, Firefox language and other custom app options still require CLI.
- Staging happens synchronously; the GUI may be temporarily unresponsive while work is in progress.
- GUI requires an STA PowerShell 5.1 session and WinPE GUI/.NET dependencies.
- Public release 0.33.0 remains unchanged.

If the form cannot open, capture the error using:

    try { Show-OSDAppUI -PreviewOnly -ErrorAction Stop }
    catch { $_ | Format-List * -Force; $_.ScriptStackTrace }
