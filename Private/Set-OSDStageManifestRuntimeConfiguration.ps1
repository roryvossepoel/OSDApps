function Set-OSDStageManifestRuntimeConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Manifest
    )

    $configuration = Get-OSDStageConfiguration

    $moduleData = Import-PowerShellDataFile (Join-Path (Split-Path $PSScriptRoot -Parent) 'OSDStage.psd1')
    $moduleVersion = [string]$moduleData.ModuleVersion
    if ($moduleData.PrivateData.PSData.Prerelease) {
        $moduleVersion += '-' + [string]$moduleData.PrivateData.PSData.Prerelease
    }
    $runtime = [pscustomobject]@{
        ModuleVersion    = $moduleVersion
        EnableBuiltIns   = Test-OSDStageSourceEnabled -Source BuiltIn -Configuration $configuration
        EnableRepository = Test-OSDStageSourceEnabled -Source Repository -Configuration $configuration
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
