function Add-OSDStageCMTraceOpen {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateSet('x64','arm64')][string]$Architecture = 'x64',
        [bool]$DisableUpdateChecks = $true,
        [ValidateRange(1,120)][int]$InstallTimeoutMinutes = 10,
        [string]$WindowsPath
    )

    Add-OSDStageOnlineApp -Id CMTraceOpen @PSBoundParameters
}
