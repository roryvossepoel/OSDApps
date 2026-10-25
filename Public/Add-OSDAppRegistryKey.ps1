function Add-OSDAppRegistryKey {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Path,
        [switch]$Registry32,
        [switch]$Registry64,
        [string]$WindowsPath
    )
    $operation = New-OSDAppRegistryOperation -Action Key -Path $Path -Registry32:$Registry32 -Registry64:$Registry64
    if ($PSCmdlet.ShouldProcess($operation.Path, 'Stage a key-only change for SetupComplete')) {
        Save-OSDAppRegistryStaging -Operation $operation -WindowsPath $WindowsPath
    }
}
