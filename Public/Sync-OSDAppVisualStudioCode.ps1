function Sync-OSDAppVisualStudioCode {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateSet('x64','arm64')][string]$Architecture = 'x64',
        [ValidateRange(0, [double]::MaxValue)][double]$MinimumFreeSpaceGB = 1
    )
    if (Test-OSDAppWinPE) { throw 'Sync-OSDAppVisualStudioCode is intended for full Windows. Use Add-OSDAppVisualStudioCode in WinPE.' }
    $cachePath = Get-OSDAppCachePath
    $root = Join-Path $cachePath (Join-Path 'BuiltIn\VisualStudioCode' $Architecture)
    if (-not $PSCmdlet.ShouldProcess($root, "Transactionally synchronize VisualStudioCode cache ($Architecture)")) { return }
    $cacheLock = Enter-OSDAppCacheLock -CachePath $cachePath -Operation 'VisualStudioCode cache synchronization'
    try {
        $sync = Sync-OSDAppVisualStudioCodeGeneration -Root $root -Architecture $Architecture -MinimumFreeSpaceGB $MinimumFreeSpaceGB -Download {
            param($uri, $destination)
            Save-OSDAppDownload -Uri $uri -DestinationPath $destination -Activity 'Downloading VisualStudioCode'
        }
        Write-OSDAppLog -LogPath (Join-Path $cachePath 'Logs\Client.log') -Component VisualStudioCode -Event BuiltInSyncComplete -Message 'VisualStudioCode release SHA-256 validated and cache synchronized.' -Data @{Version=$sync.Version;Architecture=$Architecture;Updated=$sync.Updated}
        [pscustomobject]@{PSTypeName='OSDApps.BuiltInCache';Id='VisualStudioCode';Version=$sync.Version;Architecture=$Architecture;CachePath=$root;Cached=$true;Updated=$sync.Updated}
    }
    finally { $cacheLock.Dispose() }
}
