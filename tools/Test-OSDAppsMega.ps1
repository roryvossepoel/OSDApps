[CmdletBinding()]
param(
    [string]$ResultsPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'TestResults\Mega'),
    [string]$DeploymentResultPath
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
New-Item -ItemType Directory -Path $ResultsPath -Force | Out-Null
$engines = @(
    @{ Name='Windows PowerShell 5.1'; Command='powershell.exe'; Folder='WindowsPowerShell51' }
    @{ Name='PowerShell 7'; Command='pwsh.exe'; Folder='PowerShell7' }
)
$checks = [System.Collections.Generic.List[object]]::new()
foreach ($engine in $engines) {
    $resolved = Get-Command $engine.Command -ErrorAction SilentlyContinue
    if (-not $resolved) {
        $checks.Add([pscustomobject]@{Name=$engine.Name;Status='Failed';Details='PowerShell host not found.'})
        continue
    }
    $output = Join-Path $ResultsPath $engine.Folder
    New-Item -ItemType Directory -Path $output -Force | Out-Null
    & $resolved.Source -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $root 'build\Test-Module.ps1') -ResultsPath $output
    $exit = $LASTEXITCODE
    $checks.Add([pscustomobject]@{Name=$engine.Name;Status=$(if($exit -eq 0){'Passed'}else{'Failed'});ExitCode=$exit;ResultsPath=$output})
}

$docs = Get-Command pwsh.exe -ErrorAction SilentlyContinue
if ($docs) {
    & $docs.Source -NoProfile -NonInteractive -File (Join-Path $root 'build\Test-Documentation.ps1') | Out-Host
    $docsExit = $LASTEXITCODE
    $checks.Add([pscustomobject]@{Name='Documentation';Status=$(if($docsExit -eq 0){'Passed'}else{'Failed'});ExitCode=$docsExit})
}

if (-not [string]::IsNullOrWhiteSpace($DeploymentResultPath)) {
    $deployment = Get-Content -LiteralPath $DeploymentResultPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    $required = @('DeploymentId','Status','ExpectedAppCount','SuccessfulAppCount','FailedAppCount','SkippedAppCount','Apps')
    $missing = @($required | Where-Object { $_ -notin $deployment.PSObject.Properties.Name })
    $entries = @($deployment.Apps)
    $ids = @($entries | ForEach-Object { [string]$_.Id })
    $deploymentId = [guid]::Empty
    $passed = (
        $missing.Count -eq 0 -and
        [guid]::TryParse([string]$deployment.DeploymentId,[ref]$deploymentId) -and
        $deployment.Status -eq 'Succeeded' -and
        [int]$deployment.ExpectedAppCount -gt 0 -and
        $entries.Count -eq [int]$deployment.ExpectedAppCount -and
        @($ids | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -eq 0 -and
        @($ids | Select-Object -Unique).Count -eq $entries.Count -and
        [int]$deployment.ExpectedAppCount -eq [int]$deployment.SuccessfulAppCount -and
        [int]$deployment.FailedAppCount -eq 0 -and
        [int]$deployment.SkippedAppCount -eq 0 -and
        @($entries | Where-Object { $_.Status -ne 'Succeeded' -or $_.PackageType -notin @('App','Script','Font','Certificate') }).Count -eq 0
    )
    $checks.Add([pscustomobject]@{Name='Physical deployment result';Status=$(if($passed){'Passed'}else{'Failed'});ResultPath=$DeploymentResultPath})
}

$report = [pscustomobject]@{
    CheckedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    Checks = @($checks)
    Scope = $(if($DeploymentResultPath){'Source validation and supplied deployment report'}else{'Source validation only; no physical deployment verified'})
    Status = $(if(@($checks | Where-Object Status -ne 'Passed').Count -eq 0){'Passed'}else{'Failed'})
}
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $ResultsPath 'MegaTest.json') -Encoding UTF8
$report | Format-List | Out-Host
if ($report.Status -ne 'Passed') {
    throw 'OSDApps megatest failed. See TestResults/Mega/MegaTest.json and engine reports.'
}
