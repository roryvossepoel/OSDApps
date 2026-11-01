function Sync-OSDStageVisualCRedist {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][ValidateSet('x86','x64')][string]$Architecture,
        [ValidateRange(0, [double]::MaxValue)][double]$MinimumFreeSpaceGB = 1
    )
    if (Test-OSDStageWinPE) { throw 'Use Add-OSDStageVisualCRedist in WinPE; synchronization requires full Windows.' }
    $cachePath = Get-OSDStageCachePath
    foreach ($arch in @($Architecture | Select-Object -Unique)) {
        $spec = Get-OSDStagePrerequisiteSpec -Family VisualCRedist -Architecture $arch
        $root = Join-Path $cachePath $spec.RelativeRoot
        if (-not $PSCmdlet.ShouldProcess($root, 'Synchronize verified runtime cache')) { continue }
        $lock = Enter-OSDStageCacheLock -CachePath $cachePath -Operation 'Runtime cache synchronization'
        try {
            $sync = Sync-OSDStagePrerequisiteGeneration -Root $root -Spec $spec -MinimumFreeSpaceGB $MinimumFreeSpaceGB -Log {
                param($record)
                Write-OSDStageLog -LogPath (Join-Path $cachePath 'Logs\Client.log') -Component CacheCleanup -Event $record.Event -Level $record.Level -Message $record.Message -Data $record.Data -ErrorAction Stop
            } -Download {
                param($uri,$destination)
                Save-OSDStageDownload -Uri $uri -DestinationDirectory $destination -ExpectedExtension '.exe' -Activity 'Downloading Microsoft runtime'
            }
            [pscustomobject]@{ PSTypeName='OSDStage.BuiltInCache'; Id=$spec.Id; Version=$sync.Version; Architecture=$arch; CachePath=$root; Cached=$true; Updated=$sync.Updated }
        } finally { $lock.Dispose() }
    }
}
