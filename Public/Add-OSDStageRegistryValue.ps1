function Add-OSDStageRegistryValue {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Name,
        [Parameter(Mandatory)][ValidateSet('String','ExpandString','MultiString','Binary','DWord','QWord')][string]$Type,
        [Parameter(Mandatory)][AllowEmptyString()][AllowEmptyCollection()][object]$Value,
        [switch]$Registry32,
        [switch]$Registry64,
        [string]$WindowsPath
    )

    Assert-OSDStageSourceEnabled -Source BuiltIn
    $operation = New-OSDStageRegistryOperation -Action Value -Path $Path -Name $Name -Type $Type -Value $Value -Registry32:$Registry32 -Registry64:$Registry64
    if ($PSCmdlet.ShouldProcess(($operation.Path + ' [' + $Name + ']'), 'Stage a registry value for SetupComplete')) {
        Save-OSDStageRegistryStaging -Operation $operation -WindowsPath $WindowsPath
    }
}
