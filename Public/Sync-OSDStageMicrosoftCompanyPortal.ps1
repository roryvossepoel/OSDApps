function Sync-OSDStageMicrosoftCompanyPortal {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$KitPath,
        [ValidateSet('x64','arm64')][string]$Architecture = 'x64')
    if (Test-OSDStageWinPE) { throw 'Run MicrosoftCompanyPortal synchronization on full Windows.' }
    $cachePath = Get-OSDStageCachePath
    if (-not $PSCmdlet.ShouldProcess($cachePath, 'Synchronize MicrosoftCompanyPortal cache')) { return }
    $lock = Enter-OSDStageCacheLock -CachePath $cachePath -Operation 'MicrosoftCompanyPortal cache synchronization'
    try { Sync-OSDStageMicrosoftCompanyPortalGeneration -CachePath $cachePath -Architecture $Architecture -KitPath $KitPath }
    finally { if ($lock) { $lock.Dispose() } }
}
