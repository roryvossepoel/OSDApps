function Add-OSDStageMicrosoftCompanyPortal {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateSet('x64','arm64')][string]$Architecture = 'x64',
        [string]$WindowsPath
    )

    Add-OSDStageOnlineApp -Id MicrosoftCompanyPortal @PSBoundParameters
}
