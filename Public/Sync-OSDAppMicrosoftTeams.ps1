function Sync-OSDAppMicrosoftTeams {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateSet('x86','x64','arm64')]
        [string]$Architecture = 'x64',
        [double]$MinimumFreeSpaceGB = 2,
        [string]$BootstrapperUri = 'https://go.microsoft.com/fwlink/?clcid=0x409&linkid=2243204'
    )

    if (Test-OSDAppWinPE) {
        throw 'Sync-OSDAppMicrosoftTeams is intended for full Windows. Built-in cache refresh is deferred until the pre-install phase.'
    }

    $cachePath = Get-OSDAppCachePath
    $clientLogPath = Join-Path $cachePath 'Logs\Client.log'
    $root = Join-Path $cachePath 'BuiltIn\MicrosoftTeams'
    $bootstrapperPath = Join-Path $root 'teamsbootstrapper.exe'
    $msixPath = Join-Path $root 'teams.msix'
    $cacheInfoPath = Join-Path $root 'CacheInfo.json'
    New-Item -ItemType Directory -Path $root -Force | Out-Null

    $resolvedArchitecture = $Architecture

    $msixUri = switch ($resolvedArchitecture) {
        'x86' { 'https://go.microsoft.com/fwlink/?clcid=0x409&linkid=2196060' }
        'x64' { 'https://go.microsoft.com/fwlink/?linkid=2196106' }
        'arm64' { 'https://go.microsoft.com/fwlink/?clcid=0x409&linkid=2196207' }
    }

    if (-not $PSCmdlet.ShouldProcess($root, "Configure and synchronize Microsoft Teams built-in cache ($resolvedArchitecture)")) { return }

    Assert-OSDAppCacheFreeSpace -CachePath $cachePath -MinimumFreeSpaceGB $MinimumFreeSpaceGB -Operation 'Microsoft Teams cache synchronization' -LogPath $clientLogPath | Out-Null
    Write-OSDAppLog -LogPath $clientLogPath -Component 'MicrosoftTeams' -Event 'BuiltInSyncStart' -Message 'Synchronizing Microsoft Teams built-in cache.' -Data @{ Architecture = $resolvedArchitecture }

    Write-Progress -Id 10 -Activity 'Synchronizing Microsoft Teams cache' -Status 'Checking current Microsoft package metadata...' -PercentComplete 5
    $remoteMetadata = Get-OSDAppRemoteFileMetadata -Uri $msixUri

    $previousCacheInfo = $null
    if (Test-Path -LiteralPath $cacheInfoPath -PathType Leaf) { try { $previousCacheInfo = Get-Content -LiteralPath $cacheInfoPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { } }

    $metadataMatches = $false
    if ((Test-Path -LiteralPath $msixPath -PathType Leaf) -and $previousCacheInfo) {
        if ($remoteMetadata.ETag -and $previousCacheInfo.RemoteETag) { $metadataMatches = $remoteMetadata.ETag -eq $previousCacheInfo.RemoteETag }
        elseif ($remoteMetadata.LastModified -and $previousCacheInfo.RemoteLastModified -and $remoteMetadata.ContentLength -and $previousCacheInfo.RemoteContentLength) {
            $metadataMatches = ($remoteMetadata.LastModified -eq $previousCacheInfo.RemoteLastModified -and [int64]$remoteMetadata.ContentLength -eq [int64]$previousCacheInfo.RemoteContentLength)
        }
    }

    Write-Progress -Id 10 -Activity 'Synchronizing Microsoft Teams cache' -Status 'Downloading bootstrapper...' -PercentComplete 10
    Save-OSDAppVerifiedBuiltInDownload -Id 'MicrosoftTeams' -Uri $BootstrapperUri -DestinationPath $bootstrapperPath -Activity 'Downloading Microsoft Teams bootstrapper' -ProgressId 11 -ParentProgressId 10 | Out-Null

    # Validate the cached installer before it can be launched or reused.
    Assert-OSDAppBuiltInSignature -Id 'MicrosoftTeams' -FilePath $bootstrapperPath | Out-Null

    if ($metadataMatches) {
        $resolvedVersion = [string]$previousCacheInfo.Version
        $updated = $false
        Write-Progress -Id 10 -Activity 'Synchronizing Microsoft Teams cache' -Status "Cached Teams $resolvedVersion is current. No MSIX download required." -PercentComplete 90
    }
    else {
        Write-Progress -Id 10 -Activity 'Synchronizing Microsoft Teams cache' -Status 'Downloading Teams MSIX...' -PercentComplete 15
        Save-OSDAppDownload -Uri $msixUri -DestinationPath $msixPath -Activity "Downloading Microsoft Teams $resolvedArchitecture MSIX" -ProgressId 12 -ParentProgressId 10 | Out-Null
        Write-Progress -Id 10 -Activity 'Synchronizing Microsoft Teams cache' -Status 'Reading MSIX package metadata...' -PercentComplete 85
        $metadataStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        Write-OSDAppLog -LogPath $clientLogPath -Component 'MicrosoftTeams' -Event 'MsixMetadataReadStart' -Message 'Reading Teams MSIX package metadata.' -Data @{ Path = $msixPath }
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        $archive = [System.IO.Compression.ZipFile]::OpenRead($msixPath)
        try {
            $manifestEntry = $archive.Entries | Where-Object { $_.FullName -eq 'AppxManifest.xml' } | Select-Object -First 1
            if (-not $manifestEntry) { throw 'AppxManifest.xml was not found in the downloaded Teams MSIX.' }
            $reader = New-Object System.IO.StreamReader($manifestEntry.Open())
            try { [xml]$appxManifest = $reader.ReadToEnd() } finally { $reader.Dispose() }
            $resolvedVersion = [string]$appxManifest.Package.Identity.Version
        }
        finally { $archive.Dispose() }
        $metadataStopwatch.Stop()
        Write-OSDAppLog -LogPath $clientLogPath -Component 'MicrosoftTeams' -Event 'MsixMetadataReadComplete' -Message 'Teams MSIX package metadata read completed.' -Data @{ Version = $resolvedVersion; DurationMs = $metadataStopwatch.ElapsedMilliseconds }
        $updated = $true
    }

    Write-Progress -Id 10 -Activity 'Synchronizing Microsoft Teams cache' -Status 'Updating cache metadata...' -PercentComplete 95
    [ordered]@{
        Id='MicrosoftTeams'; Cached=$true; Version=$resolvedVersion; Architecture=$resolvedArchitecture; SourcePolicy='Evergreen'; SyncMethod='HttpMetadata'; Updated=$updated; BootstrapperUri=$BootstrapperUri;
        RemoteETag=$remoteMetadata.ETag; RemoteLastModified=$remoteMetadata.LastModified; RemoteContentLength=$remoteMetadata.ContentLength;
        RemoteFinalUri=$remoteMetadata.FinalUri; SyncedAt=(Get-Date).ToUniversalTime().ToString('o')
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $cacheInfoPath -Encoding UTF8

    Write-OSDAppLog -LogPath $clientLogPath -Component 'MicrosoftTeams' -Event 'BuiltInSyncComplete' -Message 'Microsoft Teams built-in cache synchronized.' -Data @{ Version=$resolvedVersion; Architecture=$resolvedArchitecture; Updated=$updated; Path=$root; SourcePolicy='Evergreen'; SyncMethod='HttpMetadata' }
    Write-Progress -Id 10 -Activity 'Synchronizing Microsoft Teams cache' -Status 'Completed.' -PercentComplete 100
    Start-Sleep -Milliseconds 350
    Write-Progress -Id 10 -Activity 'Synchronizing Microsoft Teams cache' -Completed
    [pscustomobject]@{ PSTypeName='OSDApps.BuiltInCache'; Id='MicrosoftTeams'; Version=$resolvedVersion; Architecture=$resolvedArchitecture; CachePath=$root; Cached=$true; Updated=$updated }
}