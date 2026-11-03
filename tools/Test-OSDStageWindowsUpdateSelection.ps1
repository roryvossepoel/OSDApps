#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$ResultPath=(Join-Path $env:TEMP ('OSDStage-WindowsUpdate-Selection-' + [guid]::NewGuid().ToString('N') + '.json')),
    [ValidateRange(5,180)][int]$TimeoutMinutes=30,
    [ValidateNotNullOrEmpty()][string[]]$DriverClass=@()
)

$ErrorActionPreference='Stop'
if (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT') {
    throw 'Run this read-only selection check in full Windows, not WinPE.'
}
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'Runtime\Invoke-OSDStageWindowsUpdate.ps1')

# This diagnostic never invokes the installation/configuration entry point.
# Evaluate both policies against ONE scan, without accepting EULAs, downloading
# payloads, installing updates, writing deployment results or requesting reboot.
$session=New-OSDStageWindowsUpdateComObject 'Microsoft.Update.Session'
$searcher=$session.CreateUpdateSearcher()
$scan=Invoke-OSDStageWindowsUpdateAsync -Agent $searcher -Phase Search -TimeoutMinutes $TimeoutMinutes
if ($scan.TimedOut -or [int]$scan.Result.ResultCode -ne 2) {
    throw 'Selection diagnostic scan did not complete successfully.'
}
$driverDecisions=@(Get-OSDStageWindowsUpdateSelections -Updates @($scan.Result.Updates) -IncludeDrivers $true -DriverClass $DriverClass)
$items=@(foreach ($candidate in $driverDecisions) {
    $update=$candidate.Update
    $standard=Get-OSDStageWindowsUpdateSelection -Update $update
    $withDrivers=$candidate.Decision
    [pscustomobject]@{
        UpdateId=[string]$update.Identity.UpdateID;Title=[string]$update.Title;Type=[int]$update.Type
        BrowseOnly=$update.BrowseOnly;AutoSelectOnWebSites=$update.AutoSelectOnWebSites
        CanRequestUserInput=$update.InstallationBehavior.CanRequestUserInput
        RebootBehavior=$update.InstallationBehavior.RebootBehavior
        DefaultSelected=$standard.Selected;WithDriversSelected=$withDrivers.Selected
        DefaultReason=$standard.Reason;WithDriversReason=$withDrivers.Reason
        DriverClass=$(if ([int]$update.Type -eq 2) { [string]$update.DriverClass } else { $null })
        DriverHardwareId=$(if ([int]$update.Type -eq 2) { [string]$update.DriverHardwareID } else { $null })
        Categories=@($update.Categories | Select-Object Type,CategoryID,Name)
        BundleDecisions=$withDrivers.BundleDecisions
    }
})
$report=[pscustomobject]@{
    Phase='ReadOnlySelectionDiagnostic';SelectionPolicy='QualityAndDriversV5';DriverClass=@($DriverClass)
    CheckedAtUtc=[DateTime]::UtcNow.ToString('o');DurationSeconds=$scan.DurationSeconds
    FoundCount=$items.Count;DefaultSelectedCount=@($items | Where-Object DefaultSelected).Count
    WithDriversSelectedCount=@($items | Where-Object WithDriversSelected).Count
    DriverSelectedCount=@($items | Where-Object { $_.Type -eq 2 -and $_.WithDriversSelected }).Count
    Items=$items;ResultPath=$ResultPath
}
Save-OSDStageWindowsUpdateReport -Report $report -Path $ResultPath
$report
