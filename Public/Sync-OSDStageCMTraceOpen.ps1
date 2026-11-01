function Sync-OSDStageCMTraceOpen {
    [CmdletBinding(SupportsShouldProcess)]
    param([ValidateSet('x64','arm64')][string]$Architecture = 'x64')
    if (Test-OSDStageWinPE) { throw 'Run CMTraceOpen synchronization on full Windows.' }
    $cachePath = Get-OSDStageCachePath
    if (-not $PSCmdlet.ShouldProcess($cachePath, 'Synchronize CMTraceOpen cache')) { return }
    $lock = Enter-OSDStageCacheLock -CachePath $cachePath -Operation 'CMTraceOpen cache synchronization'
    try { Sync-OSDStageCMTraceOpenGeneration -CachePath $cachePath -Architecture $Architecture }
    finally { if ($lock) { $lock.Dispose() } }
}
