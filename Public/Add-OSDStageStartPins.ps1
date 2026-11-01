function Add-OSDStageStartPins {
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName='Pins')]
    param(
        [Parameter(Mandatory,ParameterSetName='Pins')][AllowEmptyCollection()][object[]]$Pins,
        [Parameter(Mandatory,ParameterSetName='Json')][ValidateNotNullOrEmpty()][string]$JsonPath,
        [string]$WindowsPath
    )
    Assert-OSDStageSourceEnabled -Source BuiltIn
    if (-not (Test-OSDStageWinPE)) { throw 'Stage desktop settings in WinPE after OSDCloud, not on the preparation PC.' }
    if ($PSCmdlet.ParameterSetName -eq 'Json') {
        $json = Get-Content -LiteralPath $JsonPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $json -or $json.PSObject.Properties.Name -notcontains 'pinnedList' -or $null -eq $json.pinnedList) { throw 'Start JSON must contain a pinnedList array.' }
        if (@($json.PSObject.Properties.Name | Where-Object { $_ -notin @('applyOnce','pinnedList') }).Count) { throw 'Only applyOnce and pinnedList are supported in Start JSON.' }
        if ($json.PSObject.Properties.Name -contains 'applyOnce' -and ($json.applyOnce -isnot [bool] -or -not $json.applyOnce)) { throw 'Start JSON must omit applyOnce or set it to true.' }
        if ($json.pinnedList -isnot [System.Collections.IList]) { throw 'pinnedList must be an array.' }
        $Pins = @($json.pinnedList)
    }
    $normalized = @(ConvertTo-OSDStageDesktopPins -Pins $Pins)
    $operation = [pscustomobject]@{Kind='StartPins';Pins=$normalized}
    Assert-OSDStageDesktopOperation -Operation $operation
    if ($PSCmdlet.ShouldProcess('Offline Windows','Configure StartPins for first use')) {
        Save-OSDStageDesktopStaging -Operation $operation -WindowsPath $WindowsPath -Confirm:$false
    }
}
