function Get-OSDStageConfiguration {
    [CmdletBinding()]
    param()

    if (-not $script:OSDStageConfiguration) {
        $script:OSDStageConfiguration = [pscustomobject]@{
            CatalogUri       = $null
            EnableBuiltIns   = $true
            EnableRepository = $true
            CleanupMode      = 'OnSuccess'
            PreventSleep     = $true
            CacheVolumeLabel = 'OSDCloud'
            LogPath          = '%ProgramData%\OSDStage\Logs\Runtime.log'
            ResultPath       = '%ProgramData%\OSDStage\Results\Latest.json'
        }
    }

    [pscustomobject]@{
        PSTypeName       = 'OSDStage.Configuration'
        CatalogUri       = $script:OSDStageConfiguration.CatalogUri
        EnableBuiltIns   = [bool]$script:OSDStageConfiguration.EnableBuiltIns
        EnableRepository = [bool]$script:OSDStageConfiguration.EnableRepository
        CleanupMode      = $script:OSDStageConfiguration.CleanupMode
        PreventSleep     = $script:OSDStageConfiguration.PreventSleep
        CacheVolumeLabel = $script:OSDStageConfiguration.CacheVolumeLabel
        LogPath          = $script:OSDStageConfiguration.LogPath
        ResultPath       = $script:OSDStageConfiguration.ResultPath
        Scope            = 'Session'
    }
}
