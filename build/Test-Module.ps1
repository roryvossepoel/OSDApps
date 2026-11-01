[CmdletBinding()]
param(
    [string]$ResultsPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'TestResults')
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Path $PSScriptRoot -Parent
if (-not (Get-Module -ListAvailable -Name Pester | Where-Object Version -ge ([version]'5.5.0'))) {
    throw 'Pester 5.5.0 or later is required.'
}
if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) { throw 'PSScriptAnalyzer is required.' }
Import-Module Pester -MinimumVersion 5.5.0 -Force
Import-Module PSScriptAnalyzer -ErrorAction Stop
New-Item -ItemType Directory -Path $ResultsPath -Force | Out-Null
$ResultsPath = (Resolve-Path -LiteralPath $ResultsPath).Path

$toolVersions = [ordered]@{
    PowerShell = $PSVersionTable.PSVersion.ToString()
    Edition = [string]$PSVersionTable.PSEdition
    Pester = (Get-Module Pester).Version.ToString()
    PSScriptAnalyzer = (Get-Module PSScriptAnalyzer).Version.ToString()
}
$toolVersions | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $ResultsPath 'tools.json') -Encoding UTF8

$settingsPath = Join-Path $root 'PSScriptAnalyzerSettings.psd1'
$analysisTargets = @(
    (Join-Path $root 'OSDStage.psm1'),
    (Join-Path $root 'Public'),
    (Join-Path $root 'Private'),
    (Join-Path $root 'Runtime'),
    (Join-Path $root 'build'),
    (Join-Path $root 'tools')
)
$analysis = @(
    foreach ($target in $analysisTargets) {
        if (Test-Path -LiteralPath $target) {
            Invoke-ScriptAnalyzer -Path $target -Recurse -Settings $settingsPath
        }
    }
)
$report = @($analysis | Select-Object Severity,RuleName,ScriptName,ScriptPath,Line,Column,Message)
ConvertTo-Json -InputObject $report -Depth 5 |
    Set-Content -LiteralPath (Join-Path $ResultsPath 'analyzer.json') -Encoding UTF8
if ($analysis.Count -gt 0) {
    $analysis | Sort-Object Severity,ScriptName,Line |
        Format-Table Severity,RuleName,ScriptName,Line,Message -AutoSize | Out-String | Write-Host
}
$analysisErrors = @($analysis | Where-Object Severity -eq 'Error')
if ($analysisErrors.Count -gt 0) { throw "PSScriptAnalyzer reported $($analysisErrors.Count) error finding(s)." }
Write-Host "PSScriptAnalyzer: $($analysis.Count) warning/informational finding(s), no blocking errors. Full report: $ResultsPath"

$config = New-PesterConfiguration
$config.Run.Path = Join-Path $root 'Tests'
$config.Run.PassThru = $true
$config.Run.Exit = $false
$config.Run.Throw = $false
$config.Output.Verbosity = 'Detailed'
$config.TestResult.Enabled = $true
$config.TestResult.OutputFormat = 'NUnitXml'
$config.TestResult.OutputPath = Join-Path $ResultsPath 'pester.xml'
$result = Invoke-Pester -Configuration $config

. (Join-Path $PSScriptRoot 'Assert-PesterSuccess.ps1')
Assert-PesterSuccess -Result $result
& (Join-Path $PSScriptRoot 'Build-Module.ps1') | Out-Host
