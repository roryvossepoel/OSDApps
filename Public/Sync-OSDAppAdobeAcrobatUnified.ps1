function Sync-OSDAppAdobeAcrobatUnified {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateSet('x64','x86')]
        [string]$Architecture = 'x64',

        [double]$MinimumFreeSpaceGB = 3,

        [string]$PackageUri
    )

    if (Test-OSDAppWinPE) {
        throw 'Sync-OSDAppAdobeAcrobatUnified is intended for full Windows. Built-in cache refresh is deferred until the pre-install phase.'
    }

    if (-not $PackageUri) {
        $PackageUri = switch ($Architecture) {
            'x64' { 'https://trials.adobe.com/AdobeProducts/APRO/Acrobat_HelpX/win32/Acrobat_DC_Web_x64_WWMUI.zip' }
            'x86' { 'https://trials.adobe.com/AdobeProducts/APRO/Acrobat_HelpX/win32/Acrobat_DC_Web_WWMUI.zip' }
        }
    }

    $cachePath = Get-OSDAppCachePath
    $clientLogPath = Join-Path $cachePath 'Logs\Client.log'
    $root = Join-Path $cachePath (Join-Path 'BuiltIn\AdobeAcrobatUnified' $Architecture)
    $packagePath = Join-Path $root 'Package.zip'
    $cacheInfoPath = Join-Path $root 'CacheInfo.json'

    New-Item -ItemType Directory -Path $root -Force | Out-Null

    if (-not $PSCmdlet.ShouldProcess($root, "Synchronize Adobe Acrobat Unified built-in cache ($Architecture)")) { return }

    Assert-OSDAppCacheFreeSpace -CachePath $cachePath -MinimumFreeSpaceGB $MinimumFreeSpaceGB -Operation "Adobe Acrobat Unified $Architecture cache synchronization" -LogPath $clientLogPath | Out-Null
    Write-OSDAppLog -LogPath $clientLogPath -Component 'AdobeAcrobatUnified' -Event 'BuiltInSyncStart' -Message 'Synchronizing Adobe Acrobat Unified built-in cache.' -Data @{ Architecture=$Architecture }

    $remoteMetadata = Get-OSDAppRemoteFileMetadata -Uri $PackageUri

    $previousCacheInfo = $null
    if (Test-Path -LiteralPath $cacheInfoPath -PathType Leaf) {
        try { $previousCacheInfo = Get-Content -LiteralPath $cacheInfoPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
    }

    $metadataMatches = $false
    if ((Test-Path -LiteralPath $packagePath -PathType Leaf) -and $previousCacheInfo) {
        if ($remoteMetadata.ETag -and $previousCacheInfo.RemoteETag) {
            $metadataMatches = $remoteMetadata.ETag -eq [string]$previousCacheInfo.RemoteETag
        }
        elseif ($remoteMetadata.LastModified -and $previousCacheInfo.RemoteLastModified -and $remoteMetadata.ContentLength -and $previousCacheInfo.RemoteContentLength) {
            $metadataMatches = (
                $remoteMetadata.LastModified -eq [string]$previousCacheInfo.RemoteLastModified -and
                [int64]$remoteMetadata.ContentLength -eq [int64]$previousCacheInfo.RemoteContentLength
            )
        }
    }

    if ($metadataMatches) {
        $updated = $false
        Write-Verbose "Cached Adobe Acrobat Unified $Architecture package is current. No download required."
    }
    else {
        Save-OSDAppDownload -Uri $PackageUri -DestinationPath $packagePath -Activity "Downloading Adobe Acrobat Unified $Architecture package" | Out-Null
        $updated = $true
    }

    $inspectedVersion = Get-OSDAppCachedPackageVersion -Id 'AdobeAcrobatUnified' -CacheEntryPath $root
    $resolvedVersion = if ($inspectedVersion.Version) { [string]$inspectedVersion.Version } else { 'Current' }

     [ordered]@{
        Id                  = 'AdobeAcrobatUnified'
        Cached              = $true
        Version             = $resolvedVersion
        VersionSource       = $inspectedVersion.VersionSource
        Architecture        = $Architecture
        SourcePolicy        = 'Evergreen'
        SyncMethod          = 'HttpMetadata'
        Updated             = $updated
        PackageUri          = $PackageUri
        RemoteETag          = $remoteMetadata.ETag
        RemoteLastModified  = $remoteMetadata.LastModified
        RemoteContentLength = $remoteMetadata.ContentLength
        RemoteFinalUri      = $remoteMetadata.FinalUri
        SyncedAt            = (Get-Date).ToUniversalTime().ToString('o')
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $cacheInfoPath -Encoding UTF8

    Write-OSDAppLog -LogPath $clientLogPath -Component 'AdobeAcrobatUnified' -Event 'BuiltInSyncComplete' -Message 'Adobe Acrobat Unified built-in cache synchronized.' -Data @{
        Architecture=$Architecture
        Updated=$updated
        Path=$root
    }

    [pscustomobject]@{
        PSTypeName='OSDApps.BuiltInCache'
        Id='AdobeAcrobatUnified'
        Version=$resolvedVersion
        Architecture=$Architecture
        CachePath=$root
        Cached=$true
        Updated=$updated
    }
}
