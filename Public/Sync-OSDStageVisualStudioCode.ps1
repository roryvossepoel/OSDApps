function Sync-OSDStageVisualStudioCode {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateSet('x64','arm64')][string]$Architecture = 'x64',
        [ValidateRange(0, [double]::MaxValue)][double]$MinimumFreeSpaceGB = 1
    )
    if (Test-OSDStageWinPE) { throw 'Sync-OSDStageVisualStudioCode is intended for full Windows. Use Add-OSDStageVisualStudioCode in WinPE.' }
    $cachePath = Get-OSDStageCachePath
    $root = Join-Path $cachePath (Join-Path 'BuiltIn\VisualStudioCode' $Architecture)
    if (-not $PSCmdlet.ShouldProcess($root, "Transactionally synchronize VisualStudioCode cache ($Architecture)")) { return }
    $cacheLock = Enter-OSDStageCacheLock -CachePath $cachePath -Operation 'VisualStudioCode cache synchronization'
    try {
        $sync = Sync-OSDStageVisualStudioCodeGeneration -Root $root -Architecture $Architecture -MinimumFreeSpaceGB $MinimumFreeSpaceGB -Download {
            param($uri, $destination)
            Save-OSDStageDownload -Uri $uri -DestinationDirectory $destination -ExpectedExtension '.exe' -Activity 'Downloading VisualStudioCode'
        }
        Write-OSDStageLog -LogPath (Join-Path $cachePath 'Logs\Client.log') -Component VisualStudioCode -Event BuiltInSyncComplete -Message 'VisualStudioCode release SHA-256 validated and cache synchronized.' -Data @{Version=$sync.Version;Architecture=$Architecture;Updated=$sync.Updated}
        [pscustomobject]@{PSTypeName='OSDStage.BuiltInCache';Id='VisualStudioCode';Version=$sync.Version;Architecture=$Architecture;CachePath=$root;Cached=$true;Updated=$sync.Updated}
    }
    finally { $cacheLock.Dispose() }
}
