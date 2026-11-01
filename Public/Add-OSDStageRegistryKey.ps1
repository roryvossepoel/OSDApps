function Add-OSDStageRegistryKey {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Path,
        [switch]$Registry32,
        [switch]$Registry64,
        [string]$WindowsPath
    )

    Assert-OSDStageSourceEnabled -Source BuiltIn
    $operation = New-OSDStageRegistryOperation -Action Key -Path $Path -Registry32:$Registry32 -Registry64:$Registry64
    if ($PSCmdlet.ShouldProcess($operation.Path, 'Stage a key-only change for SetupComplete')) {
        Save-OSDStageRegistryStaging -Operation $operation -WindowsPath $WindowsPath
    }
}
