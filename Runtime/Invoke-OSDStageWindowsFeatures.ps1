[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config.json')
)

$ErrorActionPreference = 'Stop'

function Assert-OSDStageWindowsFeatureConfiguration {
    param([Parameter(Mandatory)]$Configuration)

    if ([int]$Configuration.SchemaVersion -ne 2) { throw 'Unsupported Windows Features configuration schema.' }
    $id = [guid]::Empty
    if (-not [guid]::TryParse([string]$Configuration.DeploymentId,[ref]$id)) { throw 'Windows Features configuration has no valid DeploymentId.' }
    if ([string]::IsNullOrWhiteSpace([string]$Configuration.ResultPath)) { throw 'Windows Features configuration has no ResultPath.' }

    $operations = @($Configuration.Operations)
    if ($operations.Count -eq 0) { throw 'Windows Features configuration contains no operations.' }

    $seen = @{}
    foreach($operation in $operations) {
        $name = [string]$operation.Name
        $action = [string]$operation.Action
        if ($action -notin @('Enable','Disable')) { throw "Unsupported Windows Features action '$action'." }
        if ([string]::IsNullOrWhiteSpace($name) -or $name.Length -gt 256 -or $name -match '[\x00-\x1F]') {
            throw 'Windows feature names must be non-empty, at most 256 characters, and contain no control characters.'
        }
        $key = $name.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { throw "Duplicate Windows feature operation '$name'." }
        $seen[$key] = $true
    }
}

function Invoke-OSDStageWindowsFeatureOperation {
    param([Parameter(Mandatory)]$Operation)

    $name = [string]$Operation.Name
    $action = [string]$Operation.Action
    $before = Get-WindowsOptionalFeature -Online -FeatureName $name -ErrorAction Stop
    $stateBefore = [string]$before.State
    $restartNeeded = $false

    if ($action -eq 'Enable') {
        if ($stateBefore -in @('Enabled','EnablePending')) {
            return [pscustomobject]@{
                Name=$name;Action=$action;Status='Succeeded';Outcome='AlreadyEnabled'
                StateBefore=$stateBefore;StateAfter=$stateBefore
                RestartNeeded=($stateBefore -eq 'EnablePending');Error=$null
            }
        }
        $result = Enable-WindowsOptionalFeature -Online -FeatureName $name -All -NoRestart -ErrorAction Stop
        if ($result -and $result.PSObject.Properties.Name -contains 'RestartNeeded') { $restartNeeded=[bool]$result.RestartNeeded }
    }
    else {
        if ($stateBefore -in @('Disabled','DisablePending')) {
            return [pscustomobject]@{
                Name=$name;Action=$action;Status='Succeeded';Outcome='AlreadyDisabled'
                StateBefore=$stateBefore;StateAfter=$stateBefore
                RestartNeeded=($stateBefore -eq 'DisablePending');Error=$null
            }
        }
        $result = Disable-WindowsOptionalFeature -Online -FeatureName $name -NoRestart -ErrorAction Stop
        if ($result -and $result.PSObject.Properties.Name -contains 'RestartNeeded') { $restartNeeded=[bool]$result.RestartNeeded }
    }

    $after = Get-WindowsOptionalFeature -Online -FeatureName $name -ErrorAction Stop
    $stateAfter = [string]$after.State
    if ($stateAfter -in @('EnablePending','DisablePending')) { $restartNeeded=$true }

    [pscustomobject]@{
        Name=$name;Action=$action;Status='Succeeded'
        Outcome=if($action -eq 'Enable'){'Enabled'}else{'Disabled'}
        StateBefore=$stateBefore;StateAfter=$stateAfter
        RestartNeeded=[bool]$restartNeeded;Error=$null
    }
}

try {
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { throw "Windows Features configuration not found: $ConfigPath" }
    $configuration = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    Assert-OSDStageWindowsFeatureConfiguration -Configuration $configuration

    $items = [System.Collections.Generic.List[object]]::new()
    foreach($operation in @($configuration.Operations)) {
        try {
            $items.Add((Invoke-OSDStageWindowsFeatureOperation -Operation $operation))
        }
        catch {
            $items.Add([pscustomobject]@{
                Name=[string]$operation.Name;Action=[string]$operation.Action
                Status='Failed';Outcome='Failed';StateBefore=$null;StateAfter=$null
                RestartNeeded=$false;Error=$_.Exception.Message
            })
        }
    }

    $failed=@($items | Where-Object Status -eq 'Failed').Count
    $restart=@($items | Where-Object RestartNeeded).Count -gt 0
    $record=[ordered]@{
        SchemaVersion=2
        DeploymentId=[string]$configuration.DeploymentId
        Status=if($failed -gt 0){'Failed'}else{'Succeeded'}
        OperationCount=$items.Count
        SuccessfulOperationCount=@($items | Where-Object Status -eq 'Succeeded').Count
        FailedOperationCount=$failed
        RestartNeeded=[bool]$restart
        Items=@($items)
        Error=if($failed -gt 0){"$failed Windows feature operation(s) failed."}else{$null}
    }

    $resultPath=[Environment]::ExpandEnvironmentVariables([string]$configuration.ResultPath)
    New-Item -ItemType Directory -Path (Split-Path $resultPath -Parent) -Force | Out-Null
    $record | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resultPath -Encoding UTF8

    if ($failed -gt 0) { exit 1 }
    if ($restart) { exit 3010 }
    exit 0
}
catch {
    try {
        if ($configuration -and $configuration.ResultPath) {
            $resultPath=[Environment]::ExpandEnvironmentVariables([string]$configuration.ResultPath)
            New-Item -ItemType Directory -Path (Split-Path $resultPath -Parent) -Force | Out-Null
            [ordered]@{
                SchemaVersion=2;DeploymentId=[string]$configuration.DeploymentId;Status='Failed'
                OperationCount=0;SuccessfulOperationCount=0;FailedOperationCount=0;RestartNeeded=$false
                Items=@();Error=$_.Exception.Message
            } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resultPath -Encoding UTF8
        }
    } catch {}
    Write-Error $_.Exception.Message
    exit 1
}
