function Sync-OSDAppAdobeAcrobatUnified {
    [CmdletBinding(SupportsShouldProcess)]
    param([ValidateSet('x64','x86')][string]$Architecture='x64',[ValidateRange(0, [double]::MaxValue)][double]$MinimumFreeSpaceGB=3,[string]$PackageUri)
    if(Test-OSDAppWinPE){throw 'Sync-OSDAppAdobeAcrobatUnified is intended for full Windows. Built-in cache refresh is deferred until the pre-install phase.'}
    if(-not $PackageUri){$PackageUri=if($Architecture -eq 'x64'){'https://trials.adobe.com/AdobeProducts/APRO/Acrobat_HelpX/win32/Acrobat_DC_Web_x64_WWMUI.zip'}else{'https://trials.adobe.com/AdobeProducts/APRO/Acrobat_HelpX/win32/Acrobat_DC_Web_WWMUI.zip'}}
    $cachePath=Get-OSDAppCachePath;$log=Join-Path $cachePath 'Logs\Client.log';$root=Join-Path $cachePath (Join-Path 'BuiltIn\AdobeAcrobatUnified' $Architecture)
    if(-not $PSCmdlet.ShouldProcess($root,"Transactionally synchronize Adobe Acrobat Unified built-in cache ($Architecture)")){return}
    Write-OSDAppLog -LogPath $log -Component AdobeAcrobatUnified -Event BuiltInSyncStart -Message 'Synchronizing Adobe Acrobat Unified built-in cache.' -Data @{Architecture=$Architecture;Transactional=$true}
    $sync=Sync-OSDAppVendorBuiltInCache -MinimumFreeSpaceGB $MinimumFreeSpaceGB -Id AdobeAcrobatUnified -Root $root -PackageUri $PackageUri -Architecture $Architecture -PackageFileName Package.zip -Activity "Downloading Adobe Acrobat Unified $Architecture package" -LogPath $log -ZipPackage
    Write-OSDAppLog -LogPath $log -Component AdobeAcrobatUnified -Event BuiltInSyncComplete -Message 'Adobe Acrobat Unified built-in cache synchronized.' -Data @{Architecture=$Architecture;Updated=$sync.Updated;Path=$root;Transactional=$true}
    [pscustomobject]@{PSTypeName='OSDApps.BuiltInCache';Id='AdobeAcrobatUnified';Version=$sync.Version;Architecture=$Architecture;CachePath=$root;Cached=$true;Updated=$sync.Updated}
}
