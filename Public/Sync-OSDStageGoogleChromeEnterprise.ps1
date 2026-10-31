function Sync-OSDStageGoogleChromeEnterprise {
    [CmdletBinding(SupportsShouldProcess)]
    param([ValidateSet('x64','x86')][string]$Architecture='x64',[ValidateRange(0, [double]::MaxValue)][double]$MinimumFreeSpaceGB=1,[string]$PackageUri)
    if(Test-OSDStageWinPE){throw 'Sync-OSDStageGoogleChromeEnterprise is intended for full Windows. Built-in cache refresh is deferred until the pre-install phase.'}
    if(-not $PackageUri){$PackageUri=if($Architecture -eq 'x64'){'https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi'}else{'https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise.msi'}}
    $cachePath=Get-OSDStageCachePath;$log=Join-Path $cachePath 'Logs\Client.log';$root=Join-Path $cachePath (Join-Path 'BuiltIn\GoogleChromeEnterprise' $Architecture)
    if(-not $PSCmdlet.ShouldProcess($root,"Transactionally synchronize Google Chrome Enterprise built-in cache ($Architecture)")){return}

    $cacheLock = Enter-OSDStageCacheLock -CachePath $cachePath -Operation 'built-in cache synchronization'
    try {
    Write-OSDStageLog -LogPath $log -Component GoogleChromeEnterprise -Event BuiltInSyncStart -Message 'Synchronizing Google Chrome Enterprise built-in cache.' -Data @{Architecture=$Architecture;Transactional=$true}
    $sync=Sync-OSDStageVendorBuiltInCache -MinimumFreeSpaceGB $MinimumFreeSpaceGB -Id GoogleChromeEnterprise -Root $root -PackageUri $PackageUri -Architecture $Architecture -ExpectedExtension '.msi' -Activity "Downloading Google Chrome Enterprise $Architecture MSI" -LogPath $log -SignedPackage
    Write-OSDStageLog -LogPath $log -Component GoogleChromeEnterprise -Event BuiltInSyncComplete -Message 'Google Chrome Enterprise built-in cache synchronized.' -Data @{Architecture=$Architecture;Updated=$sync.Updated;Path=$root;Transactional=$true}
    [pscustomobject]@{PSTypeName='OSDStage.BuiltInCache';Id='GoogleChromeEnterprise';Version=$sync.Version;Architecture=$Architecture;CachePath=$root;Cached=$true;Updated=$sync.Updated}
    }
    finally { $cacheLock.Dispose() }
}
