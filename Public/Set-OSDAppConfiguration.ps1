function Set-OSDAppConfiguration {
    [CmdletBinding()]
    param(
        [uri]$CatalogUri,

        [ValidateSet('OnSuccess','Never')]
        [string]$CleanupMode,

        [ValidateNotNullOrEmpty()]
        [string]$CacheVolumeLabel,

        [ValidateNotNullOrEmpty()]
        [string]$LogPath,

        [ValidateNotNullOrEmpty()]
        [string]$ResultPath,

        [switch]$PassThru
    )

    $current = Get-OSDAppConfiguration

    if ($PSBoundParameters.ContainsKey('CatalogUri')) {
        if ($CatalogUri -and $CatalogUri.Scheme -notin @('http','https')) {
            throw "OSD App Catalog must use HTTP or HTTPS. Unsupported URI scheme: $($CatalogUri.Scheme)"
        }
        $current.CatalogUri = $CatalogUri
    }

    if ($PSBoundParameters.ContainsKey('CleanupMode')) {
        $current.CleanupMode = $CleanupMode
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

    $script:OSDAppConfiguration = [pscustomobject]@{
        CatalogUri       = $current.CatalogUri
        CleanupMode      = $current.CleanupMode
        CacheVolumeLabel = $current.CacheVolumeLabel
        LogPath          = $current.LogPath
        ResultPath       = $current.ResultPath
    }

    if ($PassThru) {
        Get-OSDAppConfiguration
    }
}
