function Set-OSDAppManifestRuntimeConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Manifest
    )

    $configuration = Get-OSDAppConfiguration

    $runtime = [pscustomobject]@{
        EnableBuiltIns   = Test-OSDAppSourceEnabled -Source BuiltIn -Configuration $configuration
        EnableRepository = Test-OSDAppSourceEnabled -Source Repository -Configuration $configuration
        CleanupMode      = $configuration.CleanupMode
        PreventSleep     = $configuration.PreventSleep
        CacheVolumeLabel = $configuration.CacheVolumeLabel
        LogPath          = $configuration.LogPath
        ResultPath       = $configuration.ResultPath
    }

    if ($Manifest.PSObject.Properties.Name -contains 'Runtime') {
        $Manifest.Runtime = $runtime
    }
    else {
        $Manifest | Add-Member -NotePropertyName Runtime -NotePropertyValue $runtime
    }

    if (-not ($Manifest.PSObject.Properties.Name -contains 'DeploymentId') -or
        [string]::IsNullOrWhiteSpace([string]$Manifest.DeploymentId)) {
        $Manifest | Add-Member -NotePropertyName DeploymentId -NotePropertyValue ([guid]::NewGuid().Guid) -Force
    }

    $Manifest
}
