function Test-OSDAppSourceEnabled {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('BuiltIn','Repository')]
        [string]$Source,
        $Configuration
    )

    if (-not $Configuration) { $Configuration = Get-OSDAppConfiguration }
    $propertyName = if ($Source -eq 'BuiltIn') { 'EnableBuiltIns' } else { 'EnableRepository' }
    if (-not ($Configuration.PSObject.Properties.Name -contains $propertyName)) {
        return $true
    }
    [bool]$Configuration.$propertyName
}

function Assert-OSDAppSourceEnabled {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('BuiltIn','Repository')]
        [string]$Source
    )

    if (Test-OSDAppSourceEnabled -Source $Source) { return }

    if ($Source -eq 'BuiltIn') {
        throw 'Built-in apps and OSDApps-owned staging features are disabled in the current OSDApps configuration.'
    }
    throw 'Repository packages are disabled in the current OSDApps configuration.'
}
