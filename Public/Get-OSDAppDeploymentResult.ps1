function Get-OSDAppDeploymentResult {
    [CmdletBinding()]
    param(
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = (Get-OSDAppConfiguration).ResultPath
    }

    $resolvedPath = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path))
    if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
        throw "OSDApps deployment result not found: $resolvedPath"
    }

    try {
        $result = Get-Content -LiteralPath $resolvedPath -Raw -Encoding UTF8 |
            ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "OSDApps deployment result '$resolvedPath' is not valid JSON: $($_.Exception.Message)"
    }

    if ($null -eq $result -or
        -not ($result.PSObject.Properties.Name -contains 'SchemaVersion') -or
        -not ($result.PSObject.Properties.Name -contains 'Status')) {
        throw "OSDApps deployment result '$resolvedPath' is missing required properties."
    }
    if ([string]$result.SchemaVersion -ne '1.0') {
        throw "OSDApps deployment result '$resolvedPath' uses unsupported schema version '$($result.SchemaVersion)'."
    }
    if ([string]$result.Status -notin @('Running','Succeeded','Failed')) {
        throw "OSDApps deployment result '$resolvedPath' has unsupported status '$($result.Status)'."
    }

    $result | Add-Member -NotePropertyName ResultPath -NotePropertyValue $resolvedPath -Force
    $result.PSObject.TypeNames.Insert(0, 'OSDApps.DeploymentResult')
    $result
}
