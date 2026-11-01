function Test-OSDStageWinPE {
    [CmdletBinding()]
    param()

    if (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT') {
        return $true
    }

    return (
        $env:SystemDrive -eq 'X:' -and
        $env:windir -like 'X:\Windows*'
    )
}
