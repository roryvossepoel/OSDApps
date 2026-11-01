[CmdletBinding()]
param(
    [string]$ModulePath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'dist\OSDStage'),
    [string]$HelpDataPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'help\CommandHelp.psd1')
)

$ErrorActionPreference = 'Stop'
$moduleRoot = (Resolve-Path -LiteralPath $ModulePath).Path
$data = Import-PowerShellDataFile -LiteralPath $HelpDataPath
$manifestPath = Join-Path $moduleRoot 'OSDStage.psd1'
$manifest = Import-PowerShellDataFile -LiteralPath $manifestPath
$helpPath = Join-Path $moduleRoot 'OSDStage-help.xml'
if (-not (Test-Path -LiteralPath $helpPath -PathType Leaf)) { throw 'The built package has no OSDStage-help.xml.' }
Remove-Module OSDStage -Force -ErrorAction SilentlyContinue
$module = Import-Module $manifestPath -Force -PassThru
if ($module.ModuleBase -ne $moduleRoot) { throw 'Wrong OSDStage module was imported.' }

$problems = [System.Collections.Generic.List[string]]::new()
$count = 0
foreach ($name in $manifest.FunctionsToExport) {
    $spec = $data.Commands[$name]
    $topic = Get-Help -Name ('OSDStage\' + $name) -Full -ErrorAction Stop
    if (([string]$topic.Synopsis).Trim() -ne ([string]$spec.Synopsis).Trim()) {
        $problems.Add("${name}: Get-Help did not load the packaged synopsis.")
    }
    $description = @($topic.Description | ForEach-Object { $_.Text }) -join ' '
    if ($description -notlike '*Execution environment:*') {
        $problems.Add("${name}: execution environment missing from actual Get-Help output.")
    }
    $documentedParameters = @($topic.Parameters.Parameter |
        Where-Object { $null -ne $_ -and -not [string]::IsNullOrWhiteSpace([string]$_.Name) } |
        ForEach-Object { [string]$_.Name })
    $excluded = @('Verbose','Debug','ErrorAction','WarningAction','InformationAction','ProgressAction',
        'ErrorVariable','WarningVariable','InformationVariable','OutVariable','OutBuffer','PipelineVariable')
    $actualParameters = @($module.ExportedFunctions[$name].Parameters.Keys | Where-Object { $_ -notin $excluded })
    foreach ($parameter in $actualParameters) {
        if ($parameter -notin $documentedParameters) { $problems.Add("${name}: missing parameter $parameter.") }
    }
    foreach ($parameter in $documentedParameters) {
        if ($parameter -notin $actualParameters) { $problems.Add("${name}: stale parameter $parameter.") }
    }
    $examples = @($topic.Examples.Example)
    if ($examples.Count -ne @($spec.Examples).Count) { $problems.Add("${name}: example count mismatch.") }
    if (@($topic.Syntax.SyntaxItem).Count -ne @($module.ExportedFunctions[$name].ParameterSets).Count) {
        $problems.Add("${name}: parameter-set syntax count mismatch.")
    }
    $count++
}
if ($problems.Count) { throw ($problems -join [Environment]::NewLine) }
Write-Host "Packaged Get-Help: $count/$($manifest.FunctionsToExport.Count) command topics, environments, parameter sets, parameters and examples resolved on PowerShell $($PSVersionTable.PSVersion)."
