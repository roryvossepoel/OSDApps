function Invoke-OSDAppOfflineSoftware {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$WindowsPath,[Parameter(Mandatory)][scriptblock]$Action,[ValidateSet('SOFTWARE','SYSTEM')][string]$HiveName='SOFTWARE')
    if (-not (Test-OSDAppWinPE)) { throw 'Offline desktop preparation requires WinPE.' }
    $hive=Join-Path $WindowsPath ('Windows\System32\Config\' + $HiveName)
    if (-not (Test-Path -LiteralPath $hive -PathType Leaf)) { throw 'The target Windows SOFTWARE hive is missing.' }
    $mount='OSDAppsDesktop_' + [guid]::NewGuid().ToString('N')
    $native=Join-Path $env:SystemRoot 'System32\reg.exe'
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { $native=Join-Path $env:SystemRoot 'Sysnative\reg.exe' }
    $loaded=$false;$base=$null;$key=$null
    try {
        $output=& $native load ('HKLM\' + $mount) $hive 2>&1
        if ($LASTEXITCODE -ne 0) { throw ('Unable to load target SOFTWARE hive: ' + ($output -join ' ')) }
        $loaded=$true
        $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,[Microsoft.Win32.RegistryView]::Registry64)
        $key=$base.OpenSubKey($mount,$true)
        if (-not $key) { throw 'Unable to open target SOFTWARE hive.' }
        & $Action $key
    }
    finally {
        if ($key) { $key.Dispose() };if ($base) { $base.Dispose() }
        if ($loaded) {
            $output=& $native unload ('HKLM\' + $mount) 2>&1
            if ($LASTEXITCODE -ne 0) { throw ('Unable to unload target SOFTWARE hive: ' + ($output -join ' ')) }
        }
    }
}
