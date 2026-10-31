function Add-OSDStageTaskbarPins {
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName='Pins')]
    param(
        [Parameter(Mandatory,ParameterSetName='Pins')][AllowEmptyCollection()][object[]]$Pins,
        [string]$WindowsPath
    )
    Assert-OSDStageSourceEnabled -Source BuiltIn
    if (-not (Test-OSDStageWinPE)) { throw 'Stage desktop settings in WinPE after OSDCloud, not on the preparation PC.' }
    $normalized = @(ConvertTo-OSDStageDesktopPins -Pins $Pins)
    $operation = [pscustomobject]@{Kind='TaskbarPins';Pins=$normalized}
    Assert-OSDStageDesktopOperation -Operation $operation
    if ($PSCmdlet.ShouldProcess('Offline Windows','Configure TaskbarPins for first use')) {
        Save-OSDStageDesktopStaging -Operation $operation -WindowsPath $WindowsPath -Confirm:$false
    }
}
