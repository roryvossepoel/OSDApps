function Add-OSDAppTimeZone {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Id, [string]$WindowsPath)
    $operation = [pscustomobject]@{Kind='TimeZone';Id=$Id}
    Assert-OSDAppDesktopOperation -Operation $operation
    if ($PSCmdlet.ShouldProcess('Offline Windows',('Stage time zone ' + $Id))) {
        Save-OSDAppDesktopStaging -Operation $operation -WindowsPath $WindowsPath -Confirm:$false
    }
}
