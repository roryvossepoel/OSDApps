function Test-OSDStageSourceEnabled {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('BuiltIn','Repository')]
        [string]$Source,
        $Configuration
    )

    if (-not $Configuration) { $Configuration = Get-OSDStageConfiguration }
    $propertyName = if ($Source -eq 'BuiltIn') { 'EnableBuiltIns' } else { 'EnableRepository' }
    if (-not ($Configuration.PSObject.Properties.Name -contains $propertyName)) {
        return $true
    }
    [bool]$Configuration.$propertyName
}

function Assert-OSDStageSourceEnabled {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('BuiltIn','Repository')]
        [string]$Source
    )

    if (Test-OSDStageSourceEnabled -Source $Source) { return }

    if ($Source -eq 'BuiltIn') {
        throw 'Built-in apps and OSDStage-owned staging features are disabled in the current OSDStage configuration.'
    }
    throw 'Repository packages are disabled in the current OSDStage configuration.'
}
