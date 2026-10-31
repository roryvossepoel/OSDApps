function Sync-OSDStageZoomWorkplace {
    [CmdletBinding(SupportsShouldProcess)]
    param([ValidateSet('x64','arm64')][string]$Architecture='x64',[ValidateRange(0, [double]::MaxValue)][double]$MinimumFreeSpaceGB=1,[string]$PackageUri)
    if(Test-OSDStageWinPE){throw 'Sync-OSDStageZoomWorkplace is intended for full Windows. Built-in refresh occurs during PreInstall.'}
    if(-not $PackageUri){$PackageUri=if($Architecture -eq 'x64'){'https://zoom.us/client/latest/ZoomInstallerFull.msi?archType=x64'}else{'https://zoom.us/client/latest/ZoomInstallerFull.msi?archType=winarm64'}}
    $cachePath=Get-OSDStageCachePath;$log=Join-Path $cachePath 'Logs\Client.log';$root=Join-Path $cachePath (Join-Path 'BuiltIn\ZoomWorkplace' $Architecture)
    if(-not $PSCmdlet.ShouldProcess($root,"Transactionally synchronize Zoom Workplace built-in cache ($Architecture)")){return}

    $cacheLock = Enter-OSDStageCacheLock -CachePath $cachePath -Operation 'built-in cache synchronization'
    try {
    Write-OSDStageLog -LogPath $log -Component ZoomWorkplace -Event BuiltInSyncStart -Message 'Synchronizing Zoom Workplace built-in cache.' -Data @{Architecture=$Architecture;Transactional=$true}
    $sync=Sync-OSDStageVendorBuiltInCache -MinimumFreeSpaceGB $MinimumFreeSpaceGB -Id ZoomWorkplace -Root $root -PackageUri $PackageUri -Architecture $Architecture -ExpectedExtension '.msi' -Activity "Downloading Zoom Workplace $Architecture MSI" -LogPath $log -SignedPackage
    Write-OSDStageLog -LogPath $log -Component ZoomWorkplace -Event BuiltInSyncComplete -Message 'Zoom Workplace built-in cache synchronized.' -Data @{Architecture=$Architecture;Updated=$sync.Updated;Path=$root;Transactional=$true}
    [pscustomobject]@{PSTypeName='OSDStage.BuiltInCache';Id='ZoomWorkplace';Version=$sync.Version;Architecture=$Architecture;CachePath=$root;Cached=$true;Updated=$sync.Updated}
    }
    finally { $cacheLock.Dispose() }
}
