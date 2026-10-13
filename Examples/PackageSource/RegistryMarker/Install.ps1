$ErrorActionPreference = 'Stop'

# Safe example of a machine-context configuration package. SetupComplete runs
# this entry point as SYSTEM, so keep settings under HKLM and never restart the
# device from inside the package.
$path = 'HKLM:\SOFTWARE\OSDApps\Examples'
New-Item -Path $path -Force | Out-Null
New-ItemProperty `
    -Path $path `
    -Name 'RegistryMarkerVersion' `
    -PropertyType String `
    -Value '1.0.0' `
    -Force |
    Out-Null

exit 0
