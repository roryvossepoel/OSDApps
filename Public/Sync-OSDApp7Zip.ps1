function Sync-OSDApp7Zip {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateSet('x64','x86','arm64')][string]$Architecture = 'x64',
        [ValidateRange(0, [double]::MaxValue)][double]$MinimumFreeSpaceGB = 1
    )
    if (Test-OSDAppWinPE) { throw 'Sync-OSDApp7Zip is intended for full Windows. Use Add-OSDApp7Zip in WinPE.' }
    $cachePath = Get-OSDAppCachePath
    $root = Join-Path $cachePath (Join-Path 'BuiltIn\7Zip' $Architecture)
    if (-not $PSCmdlet.ShouldProcess($root, "Transactionally synchronize 7Zip cache ($Architecture)")) { return }
    $cacheLock = Enter-OSDAppCacheLock -CachePath $cachePath -Operation '7Zip cache synchronization'
    try {
        $sync = Sync-OSDApp7ZipGeneration -Root $root -Architecture $Architecture -MinimumFreeSpaceGB $MinimumFreeSpaceGB -Log {
            param($record)
            Write-OSDAppLog -LogPath (Join-Path $cachePath 'Logs\Client.log') -Component CacheCleanup -Event $record.Event -Level $record.Level -Message $record.Message -Data $record.Data -ErrorAction Stop
        } -Download {
            param($uri, $destination)
            Save-OSDAppDownload -PreserveFileName -Uri $uri -DestinationPath $destination -Activity 'Downloading 7Zip'
        }
        Write-OSDAppLog -LogPath (Join-Path $cachePath 'Logs\Client.log') -Component 7Zip -Event BuiltInSyncComplete -Message '7Zip release SHA-256 validated and cache synchronized.' -Data @{Version=$sync.Version;Architecture=$Architecture;Updated=$sync.Updated}
        [pscustomobject]@{PSTypeName='OSDApps.BuiltInCache';Id='7Zip';Version=$sync.Version;Architecture=$Architecture;CachePath=$root;Cached=$true;Updated=$sync.Updated}
    }
    finally { $cacheLock.Dispose() }
}
