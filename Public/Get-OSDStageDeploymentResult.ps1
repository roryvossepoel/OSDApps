function Get-OSDStageDeploymentResult {
    [CmdletBinding()]
    param(
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = (Get-OSDStageConfiguration).ResultPath
    }

    $resolvedPath = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path))
    if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
        throw "OSDStage deployment result not found: $resolvedPath"
    }

    try {
        $result = Get-Content -LiteralPath $resolvedPath -Raw -Encoding UTF8 |
            ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "OSDStage deployment result '$resolvedPath' is not valid JSON: $($_.Exception.Message)"
    }

    if ($null -eq $result -or
        -not ($result.PSObject.Properties.Name -contains 'SchemaVersion') -or
        -not ($result.PSObject.Properties.Name -contains 'Status')) {
        throw "OSDStage deployment result '$resolvedPath' is missing required properties."
    }
    if ([string]$result.SchemaVersion -ne '2.0') {
        throw "OSDStage deployment result '$resolvedPath' uses unsupported schema version '$($result.SchemaVersion)'."
    }
    if ([string]$result.Status -notin @('Running','Succeeded','Failed')) {
        throw "OSDStage deployment result '$resolvedPath' has unsupported status '$($result.Status)'."
    }

    $result | Add-Member -NotePropertyName ResultPath -NotePropertyValue $resolvedPath -Force
    $result.PSObject.TypeNames.Insert(0, 'OSDStage.DeploymentResult')
    $result
}
