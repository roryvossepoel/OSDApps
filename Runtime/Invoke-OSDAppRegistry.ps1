#Requires -Version 5.1
[CmdletBinding()]
param([string]$ConfigurationPath, [string]$ResultPath)
$ErrorActionPreference = 'Stop'
if (-not $ConfigurationPath) { $ConfigurationPath = Join-Path $PSScriptRoot 'config.json' }
. (Join-Path $PSScriptRoot 'OSDAppRegistry.ps1')
$started = (Get-Date).ToUniversalTime().ToString('o')
$rows = [System.Collections.Generic.List[object]]::new()
$fatal = $null
$config = $null
try {
    if ($env:OS -ne 'Windows_NT' -or (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT')) { throw 'Registry execution requires full Windows, not WinPE.' }
    $config = Get-Content -LiteralPath $ConfigurationPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    Assert-OSDAppRegistryConfiguration -Configuration $config
    if (-not $ResultPath) { $ResultPath = [Environment]::ExpandEnvironmentVariables([string]$config.ResultPath) }
    if ([string]::IsNullOrWhiteSpace($ResultPath) -or -not [IO.Path]::IsPathRooted($ResultPath)) { throw 'A rooted registry result path is required.' }
    # Validate the entire configuration before the first registry write.
    if (-not [Environment]::Is64BitOperatingSystem -and @($config.Operations | Where-Object View -eq 'Registry64').Count -gt 0) { throw 'Registry64 was requested on 32-bit Windows.' }
    foreach ($op in $config.Operations) {
        try { $rows.Add((Invoke-OSDAppRegistryOperation -Operation $op)) }
        catch { $rows.Add([pscustomobject]@{Action=$op.Action;Path=$op.Path;Name=$op.Name;Type=$op.Type;RequestedView=$op.View;ResolvedView=$null;Process64Bit=[Environment]::Is64BitProcess;Status='Failed';Outcome='Failed';Error=$_.Exception.Message}) }
    }
}
catch { $fatal = $_.Exception.Message }
$failed = @($rows | Where-Object Status -eq 'Failed').Count
$exitCode = if ($fatal -or $failed -gt 0 -or $rows.Count -eq 0) { 1 } else { 0 }
$report = [ordered]@{
    SchemaVersion=1; DeploymentId=$(if ($config) { $config.DeploymentId } else { $null })
    Status=$(if ($exitCode -eq 0) { 'Succeeded' } else { 'Failed' }); StartedAtUtc=$started
    CompletedAtUtc=(Get-Date).ToUniversalTime().ToString('o')
    Process64Bit=[Environment]::Is64BitProcess; OS64Bit=[Environment]::Is64BitOperatingSystem
    OperationCount=$rows.Count; SuccessfulOperationCount=@($rows | Where-Object Status -eq 'Succeeded').Count
    FailedOperationCount=$failed; Items=@($rows.ToArray()); Error=$fatal
}
try {
    if ($ResultPath) {
        New-Item -ItemType Directory -Path (Split-Path $ResultPath -Parent) -Force | Out-Null
        $tmp = $ResultPath + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
        try { $report | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $tmp -Encoding UTF8; Move-Item -LiteralPath $tmp -Destination $ResultPath -Force }
        finally { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force } }
    }
} catch { Write-Error -Message $_.Exception.Message -ErrorAction Continue; $exitCode=1 }
$report | ConvertTo-Json -Depth 15 | Write-Output
exit $exitCode
