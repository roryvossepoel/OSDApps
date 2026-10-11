function Sync-OSDAppCiscoWebex {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateSet('x64','arm64')][string]$Architecture = 'x64',
        [double]$MinimumFreeSpaceGB = 1,
        [string]$PackageUri
    )

    if (Test-OSDAppWinPE) {
        throw 'Sync-OSDAppCiscoWebex is intended for full Windows. Built-in refresh occurs during PreInstall.'
    }

    if (-not $PackageUri) {
        $PackageUri = switch ($Architecture) {
            'x64' { 'https://binaries.webex.com/WebexOfclDesktop-Win-64-Gold/Webex_en.msi' }
            'arm64' { 'https://binaries.webex.com/WebexOfclDesktop-Win-Arm-64-Gold/Webex_en.msi' }
        }
    }

    $cachePath = Get-OSDAppCachePath
    $clientLogPath = Join-Path $cachePath 'Logs\Client.log'
    $root = Join-Path $cachePath (Join-Path 'BuiltIn\CiscoWebex' $Architecture)
    $packagePath = Join-Path $root 'Package.msi'
    $cacheInfoPath = Join-Path $root 'CacheInfo.json'

    if (-not $PSCmdlet.ShouldProcess($root, "Synchronize Cisco Webex built-in cache ($Architecture)")) { return }
    New-Item -ItemType Directory -Path $root -Force | Out-Null

    Assert-OSDAppCacheFreeSpace -CachePath $cachePath -MinimumFreeSpaceGB $MinimumFreeSpaceGB -Operation "Cisco Webex $Architecture cache synchronization" -LogPath $clientLogPath | Out-Null
    Write-OSDAppLog -LogPath $clientLogPath -Component 'CiscoWebex' -Event 'BuiltInSyncStart' -Message 'Synchronizing Cisco Webex built-in cache.' -Data @{ Architecture=$Architecture }

    $remoteMetadata = Get-OSDAppRemoteFileMetadata -Uri $PackageUri
    $previousCacheInfo = $null
    if (Test-Path -LiteralPath $cacheInfoPath -PathType Leaf) {
        try { $previousCacheInfo = Get-Content -LiteralPath $cacheInfoPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
    }

    $metadataMatches = $false
    if ((Test-Path -LiteralPath $packagePath -PathType Leaf) -and $previousCacheInfo) {
        if ($remoteMetadata.ETag -and $previousCacheInfo.RemoteETag) {
            $metadataMatches = $remoteMetadata.ETag -eq $previousCacheInfo.RemoteETag
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
        Write-Verbose "Cached Cisco Webex $Architecture MSI is current. No download required."
    }
    else {
        Save-OSDAppVerifiedBuiltInDownload -Id 'CiscoWebex' -Uri $PackageUri -DestinationPath $packagePath -Activity "Downloading Cisco Webex $Architecture MSI" | Out-Null
        $updated = $true
    }

    # Also re-validate an existing cached MSI when HTTP metadata says unchanged.
    Assert-OSDAppBuiltInSignature -Id 'CiscoWebex' -FilePath $packagePath | Out-Null

    $inspectedVersion = Get-OSDAppCachedPackageVersion -Id 'CiscoWebex' -CacheEntryPath $root
    $resolvedVersion = if ($inspectedVersion.Version) { [string]$inspectedVersion.Version } else { 'Current' }

     [ordered]@{
        Id = 'CiscoWebex'
        Cached = $true
        Version             = $resolvedVersion
        VersionSource       = $inspectedVersion.VersionSource
        Architecture = $Architecture
        SourcePolicy = 'Evergreen'
        SyncMethod = 'HttpMetadata'
        Updated = $updated
        PackageUri = $PackageUri
        RemoteETag = $remoteMetadata.ETag
        RemoteLastModified = $remoteMetadata.LastModified
        RemoteContentLength = $remoteMetadata.ContentLength
        RemoteFinalUri = $remoteMetadata.FinalUri
        SyncedAt = (Get-Date).ToUniversalTime().ToString('o')
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $cacheInfoPath -Encoding UTF8

    Write-OSDAppLog -LogPath $clientLogPath -Component 'CiscoWebex' -Event 'BuiltInSyncComplete' -Message 'Cisco Webex built-in cache synchronized.' -Data @{ Architecture=$Architecture; Updated=$updated; Path=$root }

    [pscustomobject]@{
        PSTypeName = 'OSDApps.BuiltInCache'
        Id = 'CiscoWebex'
        Version=$resolvedVersion
        Architecture = $Architecture
        CachePath = $root
        Cached = $true
        Updated = $updated
    }
}
