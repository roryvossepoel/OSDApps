function Assert-OSDAppSourceEnabled {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('BuiltIn','Repository')]
        [string]$Source
    )

    $configuration = Get-OSDAppConfiguration
    if ($Source -eq 'BuiltIn' -and -not $configuration.EnableBuiltIns) {
        throw 'Built-in apps and OSDApps-owned staging features are disabled in the current OSDApps configuration.'
    }
    if ($Source -eq 'Repository' -and -not $configuration.EnableRepository) {
        throw 'Repository packages are disabled in the current OSDApps configuration.'
    }
}
