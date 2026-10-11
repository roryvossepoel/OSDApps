function Sync-OSDAppGoogleChromeEnterprise {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateSet('x64','x86')]
        [string]$Architecture = 'x64',

        [double]$MinimumFreeSpaceGB = 1,

        [string]$PackageUri
    )

    if (Test-OSDAppWinPE) {
        throw 'Sync-OSDAppGoogleChromeEnterprise is intended for full Windows. Built-in cache refresh is deferred until the pre-install phase.'
    }

    if (-not $PackageUri) {
        $PackageUri = switch ($Architecture) {
            'x64' { 'https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi' }
            'x86' { 'https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise.msi' }
        }
    }

    $cachePath = Get-OSDAppCachePath
    $clientLogPath = Join-Path $cachePath 'Logs\Client.log'
    $root = Join-Path $cachePath (Join-Path 'BuiltIn\GoogleChromeEnterprise' $Architecture)
    $packagePath = Join-Path $root 'Package.msi'
    $cacheInfoPath = Join-Path $root 'CacheInfo.json'

    New-Item -ItemType Directory -Path $root -Force | Out-Null

    if (-not $PSCmdlet.ShouldProcess($root, "Synchronize Google Chrome Enterprise built-in cache ($Architecture)")) { return }

    Assert-OSDAppCacheFreeSpace -CachePath $cachePath -MinimumFreeSpaceGB $MinimumFreeSpaceGB -Operation "Google Chrome Enterprise $Architecture cache synchronization" -LogPath $clientLogPath | Out-Null
    Write-OSDAppLog -LogPath $clientLogPath -Component 'GoogleChromeEnterprise' -Event 'BuiltInSyncStart' -Message 'Synchronizing Google Chrome Enterprise built-in cache.' -Data @{ Architecture=$Architecture }

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
        Write-Verbose "Cached Google Chrome Enterprise $Architecture MSI is current. No download required."
    }
    else {
        Save-OSDAppVerifiedBuiltInDownload -Id 'GoogleChromeEnterprise' -Uri $PackageUri -DestinationPath $packagePath -Activity "Downloading Google Chrome Enterprise $Architecture MSI" | Out-Null
        $updated = $true
    }

    # Also re-validate an existing cached MSI when HTTP metadata says unchanged.
    Assert-OSDAppBuiltInSignature -Id 'GoogleChromeEnterprise' -FilePath $packagePath | Out-Null

    $inspectedVersion = Get-OSDAppCachedPackageVersion -Id 'GoogleChromeEnterprise' -CacheEntryPath $root
    $resolvedVersion = if ($inspectedVersion.Version) { [string]$inspectedVersion.Version } else { 'Current' }

     [ordered]@{
        Id                  = 'GoogleChromeEnterprise'
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

    Write-OSDAppLog -LogPath $clientLogPath -Component 'GoogleChromeEnterprise' -Event 'BuiltInSyncComplete' -Message 'Google Chrome Enterprise built-in cache synchronized.' -Data @{ Architecture=$Architecture; Updated=$updated; Path=$root }

    [pscustomobject]@{
        PSTypeName='OSDApps.BuiltInCache'
        Id='GoogleChromeEnterprise'
        Version=$resolvedVersion
        Architecture=$Architecture
        CachePath=$root
        Cached=$true
        Updated=$updated
    }
}
