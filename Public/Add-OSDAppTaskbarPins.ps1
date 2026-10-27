function Add-OSDAppTaskbarPins {
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName='Pins')]
    param(
        [Parameter(Mandatory,ParameterSetName='Pins')][AllowEmptyCollection()][object[]]$Pins,
        [string]$WindowsPath
    )
    Assert-OSDAppSourceEnabled -Source BuiltIn
    if (-not (Test-OSDAppWinPE)) { throw 'Stage desktop settings in WinPE after OSDCloud, not on the preparation PC.' }
    $normalized = @(ConvertTo-OSDAppDesktopPins -Pins $Pins)
    $operation = [pscustomobject]@{Kind='TaskbarPins';Pins=$normalized}
    Assert-OSDAppDesktopOperation -Operation $operation
    if ($PSCmdlet.ShouldProcess('Offline Windows','Configure TaskbarPins for first use')) {
        Save-OSDAppDesktopStaging -Operation $operation -WindowsPath $WindowsPath -Confirm:$false
    }
}
