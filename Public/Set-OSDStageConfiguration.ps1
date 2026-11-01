function Set-OSDStageConfiguration {
    [CmdletBinding()]
    param(
        [uri]$CatalogUri,

        [bool]$EnableBuiltIns,

        [bool]$EnableRepository,

        [ValidateSet('OnSuccess','Never')]
        [string]$CleanupMode,

        [bool]$PreventSleep = $true,

        [ValidateNotNullOrEmpty()]
        [string]$CacheVolumeLabel,

        [ValidateNotNullOrEmpty()]
        [string]$LogPath,

        [ValidateNotNullOrEmpty()]
        [string]$ResultPath,

        [switch]$PassThru
    )

    $current = Get-OSDStageConfiguration

    if ($PSBoundParameters.ContainsKey('CatalogUri')) {
        if ($CatalogUri -and $CatalogUri.Scheme -notin @('http','https')) {
            throw "OSD App Catalog must use HTTP or HTTPS. Unsupported URI scheme: $($CatalogUri.Scheme)"
        }
        $current.CatalogUri = $CatalogUri
    }

    if ($PSBoundParameters.ContainsKey('EnableBuiltIns')) {
        $current.EnableBuiltIns = $EnableBuiltIns
    }

    if ($PSBoundParameters.ContainsKey('EnableRepository')) {
        $current.EnableRepository = $EnableRepository
    }

    if (-not $current.EnableBuiltIns -and -not $current.EnableRepository) {
        throw 'At least one app source must remain enabled.'
    }

    if ($PSBoundParameters.ContainsKey('CleanupMode')) {
        $current.CleanupMode = $CleanupMode
    }

    if ($PSBoundParameters.ContainsKey('PreventSleep')) {
        $current.PreventSleep = $PreventSleep
    }

    if ($PSBoundParameters.ContainsKey('CacheVolumeLabel')) {
        $current.CacheVolumeLabel = $CacheVolumeLabel
    }

    if ($PSBoundParameters.ContainsKey('LogPath')) {
        $current.LogPath = $LogPath
    }

    if ($PSBoundParameters.ContainsKey('ResultPath')) {
        $current.ResultPath = $ResultPath
    }

    $script:OSDStageConfiguration = [pscustomobject]@{
        CatalogUri       = $current.CatalogUri
        EnableBuiltIns   = [bool]$current.EnableBuiltIns
        EnableRepository = [bool]$current.EnableRepository
        CleanupMode      = $current.CleanupMode
        PreventSleep     = $current.PreventSleep
        CacheVolumeLabel = $current.CacheVolumeLabel
        LogPath          = $current.LogPath
        ResultPath       = $current.ResultPath
    }

    if ($PassThru) {
        Get-OSDStageConfiguration
    }
}
