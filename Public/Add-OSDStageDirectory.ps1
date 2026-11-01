function Add-OSDStageDirectory {
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName='Create')]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string[]]$Path,
        [Parameter(Mandatory,ParameterSetName='Remove')][switch]$Remove,
        [Parameter(ParameterSetName='Remove')][switch]$Recurse,
        [switch]$Force,
        [string]$WindowsPath
    )
    Assert-OSDStageSourceEnabled -Source BuiltIn
    if (-not (Test-OSDStageWinPE)) { throw 'Stage directory operations in WinPE after OSDCloud.' }
    if ($PSCmdlet.ParameterSetName -eq 'Remove' -and -not $Remove) { throw 'Remove must be explicitly enabled.' }
    $operations = @(foreach ($item in $Path) {
        $operation = [pscustomobject]@{Kind='Directory';Action=if($Remove){'Remove'}else{'Create'};Path=$item;Force=[bool]$Force;Recurse=[bool]$Recurse}
        Assert-OSDStageFileSystemOperation -Operation $operation
        $operation
    })
    if ($PSCmdlet.ShouldProcess(($Path -join ', '), 'Stage directory operations for SetupComplete')) {
        Save-OSDStageFileSystemStaging -Operations $operations -WindowsPath $WindowsPath
    }
}
