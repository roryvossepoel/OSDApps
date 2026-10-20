function Sync-OSDAppSevenZip {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateSet('x64','x86','arm64')][string]$Architecture = 'x64',
        [ValidateRange(0, [double]::MaxValue)][double]$MinimumFreeSpaceGB = 1
    )
    if (Test-OSDAppWinPE) { throw 'Sync-OSDAppSevenZip is intended for full Windows. Use Add-OSDAppSevenZip in WinPE.' }
    $cachePath = Get-OSDAppCachePath
    $root = Join-Path $cachePath (Join-Path 'BuiltIn\SevenZip' $Architecture)
    if (-not $PSCmdlet.ShouldProcess($root, "Transactionally synchronize 7-Zip cache ($Architecture)")) { return }
    $cacheLock = Enter-OSDAppCacheLock -CachePath $cachePath -Operation '7-Zip cache synchronization'
    try {
        $sync = Sync-OSDAppSevenZipGeneration -Root $root -Architecture $Architecture -MinimumFreeSpaceGB $MinimumFreeSpaceGB -Download {
            param($uri, $destination)
            Save-OSDAppDownload -Uri $uri -DestinationPath $destination -Activity 'Downloading 7-Zip'
        }
        Write-OSDAppLog -LogPath (Join-Path $cachePath 'Logs\Client.log') -Component SevenZip -Event BuiltInSyncComplete -Message '7-Zip release SHA-256 validated and cache synchronized.' -Data @{Version=$sync.Version;Architecture=$Architecture;Updated=$sync.Updated}
        [pscustomobject]@{PSTypeName='OSDApps.BuiltInCache';Id='SevenZip';Version=$sync.Version;Architecture=$Architecture;CachePath=$root;Cached=$true;Updated=$sync.Updated}
    }
    finally { $cacheLock.Dispose() }
}
