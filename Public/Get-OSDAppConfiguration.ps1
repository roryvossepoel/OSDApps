function Get-OSDAppConfiguration {
    [CmdletBinding()]
    param()

    if (-not $script:OSDAppConfiguration) {
        $script:OSDAppConfiguration = [pscustomobject]@{
            CatalogUri       = $null
            CleanupMode      = 'OnSuccess'
            PreventSleep     = $true
            CacheVolumeLabel = 'OSDCloud'
            LogPath          = '%ProgramData%\OSDApps\Logs\Runtime.log'
            ResultPath       = '%ProgramData%\OSDApps\Results\Latest.json'
        }
    }

    [pscustomobject]@{
        PSTypeName       = 'OSDApps.Configuration'
        CatalogUri       = $script:OSDAppConfiguration.CatalogUri
        CleanupMode      = $script:OSDAppConfiguration.CleanupMode
        PreventSleep     = $script:OSDAppConfiguration.PreventSleep
        CacheVolumeLabel = $script:OSDAppConfiguration.CacheVolumeLabel
        LogPath          = $script:OSDAppConfiguration.LogPath
        ResultPath       = $script:OSDAppConfiguration.ResultPath
        Scope            = 'Session'
    }
}
