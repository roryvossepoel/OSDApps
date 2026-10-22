function Sync-OSDAppVisualCRedist {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][ValidateSet('x86','x64')][string]$Architecture,
        [ValidateRange(0, [double]::MaxValue)][double]$MinimumFreeSpaceGB = 1
    )
    if (Test-OSDAppWinPE) { throw 'Use Add-OSDAppVisualCRedist in WinPE; synchronization requires full Windows.' }
    $cachePath = Get-OSDAppCachePath
    foreach ($arch in @($Architecture | Select-Object -Unique)) {
        $spec = Get-OSDAppPrerequisiteSpec -Family VisualCRedist -Architecture $arch
        $root = Join-Path $cachePath $spec.RelativeRoot
        if (-not $PSCmdlet.ShouldProcess($root, 'Synchronize verified runtime cache')) { continue }
        $lock = Enter-OSDAppCacheLock -CachePath $cachePath -Operation 'Runtime cache synchronization'
        try {
            $sync = Sync-OSDAppPrerequisiteGeneration -Root $root -Spec $spec -MinimumFreeSpaceGB $MinimumFreeSpaceGB -Log {
                param($record)
                Write-OSDAppLog -LogPath (Join-Path $cachePath 'Logs\Client.log') -Component CacheCleanup -Event $record.Event -Level $record.Level -Message $record.Message -Data $record.Data -ErrorAction Stop
            } -Download {
                param($uri,$destination)
                Save-OSDAppDownload -PreserveFileName -Uri $uri -DestinationPath $destination -Activity 'Downloading Microsoft runtime'
            }
            [pscustomobject]@{ PSTypeName='OSDApps.BuiltInCache'; Id=$spec.Id; Version=$sync.Version; Architecture=$arch; CachePath=$root; Cached=$true; Updated=$sync.Updated }
        } finally { $lock.Dispose() }
    }
}
