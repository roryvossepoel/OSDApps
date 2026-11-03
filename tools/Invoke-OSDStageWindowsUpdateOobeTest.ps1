#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [switch]$Install,
    [switch]$IncludeDrivers,
    [ValidateNotNullOrEmpty()][string[]]$DriverClass=@(),
    [ValidateRange(5,180)][int]$TimeoutMinutes=30,
    [string]$ResultPath=(Join-Path $env:ProgramData ('OSDStage\Tests\WindowsUpdate-' + [guid]::NewGuid().ToString('N') + '.json'))
)

$ErrorActionPreference='Stop'
if ($PSBoundParameters.ContainsKey('DriverClass') -and -not $IncludeDrivers) {
    throw 'DriverClass requires IncludeDrivers.'
}
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'Runtime\Invoke-OSDStageWindowsUpdate.ps1')

# Explicit manual test only. Does not register SetupComplete, alter OOBE state,
# overwrite deployment results, set update policies or schedule a restart.
# The installation invocation performs a fresh scan; it can see newer offers.
$configuration=[pscustomobject]@{
    SchemaVersion=2
    DeploymentId=[guid]::NewGuid().Guid
    ResultPath=$ResultPath
    IncludeDrivers=[bool]$IncludeDrivers
    DriverClass=@($DriverClass)
    ScanOnly=(-not [bool]$Install)
    TimeoutMinutes=$TimeoutMinutes
}
Assert-OSDStageWindowsUpdateConfiguration $configuration
Assert-OSDStageWindowsUpdateContext -OobeTest
if ($Install -and $IncludeDrivers -and ($DriverClass.Count -eq 0 -or 'Firmware' -in $DriverClass)) {
    Write-OSDStageWindowsUpdateMessage 'All requested driver classes include firmware. Firmware may be applied at a later restart; this test never requests a restart.' WARN
}
$result=Invoke-OSDStageWindowsUpdateConfiguration -Configuration $configuration -OobeTest
$result | Add-Member -NotePropertyName ResultPath -NotePropertyValue $ResultPath -Force
$result
