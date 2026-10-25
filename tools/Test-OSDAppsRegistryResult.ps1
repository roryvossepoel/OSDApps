#Requires -Version 5.1
[CmdletBinding()]
param([string]$ResultsPath = "$env:ProgramData\OSDApps\Results")
$ErrorActionPreference='Stop'
$latest=Get-Content -LiteralPath (Join-Path $ResultsPath 'Latest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$registry=Get-Content -LiteralPath (Join-Path $ResultsPath 'Registry-Result.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($latest.Status -ne 'Succeeded' -or $latest.ExpectedAppCount -ne 1 -or $latest.SuccessfulAppCount -ne 1 -or
    $latest.FailedAppCount -ne 0 -or $latest.SkippedAppCount -ne 0 -or @($latest.Apps).Count -ne 1 -or
    $latest.Apps[0].Id -ne 'RegistrySettings' -or $registry.DeploymentId -ne $latest.DeploymentId -or
    $registry.Status -ne 'Succeeded' -or $registry.OperationCount -ne 9 -or $registry.SuccessfulOperationCount -ne 9 -or
    $registry.FailedOperationCount -ne 0 -or @($registry.Items).Count -ne 9) {
    throw 'Registry-only deployment evidence is incomplete, failed or belongs to another run.'
}
$subKey='SOFTWARE\OSDApps\Tests\RegistryStaging\Level1\Level2\Level3'
foreach ($view in @('Registry64','Registry32','Default')) {
    $resolved=if ($view -eq 'Default') {if($registry.Process64Bit){'Registry64'}else{'Registry32'}} else {$view}
    $path=if ($view -eq 'Default') {$subKey+'\Default'}else{$subKey}
    $expected=if ($view -eq 'Registry64') {'CreatedIn64BitView'}elseif($view -eq 'Registry32'){'CreatedIn32BitView'}else{'HostDefault'}
    $number=if($view -eq 'Registry64'){64}elseif($view -eq 'Registry32'){32}else{0}
    $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,[Microsoft.Win32.RegistryView]([Enum]::Parse([Microsoft.Win32.RegistryView],$resolved)))
    $key=$null; $empty=$null
    try {
        $key=$base.OpenSubKey($path,$false)
        if ($null -eq $key) { throw "Test key missing in $resolved." }
        if ($key.GetValue('Marker') -cne $expected -or $key.GetValueKind('Marker') -ne [Microsoft.Win32.RegistryValueKind]::String -or
            $key.GetValue('TestNumber') -ne $number -or $key.GetValueKind('TestNumber') -ne [Microsoft.Win32.RegistryValueKind]::DWord) { throw "Unexpected registry data/type in $resolved." }
        $empty=$key.OpenSubKey('EmptyKey',$false)
        if ($null -eq $empty -or $empty.ValueCount -ne 0 -or $empty.SubKeyCount -ne 0) { throw "EmptyKey is absent or not empty in $resolved." }
        [pscustomobject]@{RequestedView=$view;ResolvedView=$resolved;Marker=$expected;TestNumber=$number;EmptyKeyVerified=$true;Valid=$true}
    } finally {if($null -ne $empty){$empty.Dispose()};if($null -ne $key){$key.Dispose()};$base.Dispose()}
}
$registry.Items | Format-Table Action,Path,Name,RequestedView,ResolvedView,Outcome,Status -AutoSize -Wrap
Write-Host 'PASSED: one Script entry, nine registry operations and independent read-back in both views plus Default.'
