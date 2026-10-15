function Sync-OSDAppMozillaFirefoxEnterprise {
    [CmdletBinding(SupportsShouldProcess)]
    param([ValidateSet('Rapid','ESR')][string]$Channel='Rapid',[ValidateSet('x64','x86')][string]$Architecture='x64',[ValidatePattern('^[A-Za-z]{2,3}(?:-[A-Za-z]{2,4})?$')][string]$Language='en-US',[double]$MinimumFreeSpaceGB=1,[string]$PackageUri)
    if(Test-OSDAppWinPE){throw 'Sync-OSDAppMozillaFirefoxEnterprise is intended for full Windows. Built-in cache refresh is deferred until the pre-install phase.'}
    if(-not $PackageUri){$product=if($Channel -eq 'ESR'){'firefox-esr-msi-latest-ssl'}else{'firefox-msi-latest-ssl'};$os=if($Architecture -eq 'x64'){'win64'}else{'win'};$PackageUri="https://download.mozilla.org/?product=$product&os=$os&lang=$Language"}
    $cachePath=Get-OSDAppCachePath;$log=Join-Path $cachePath 'Logs\Client.log';$root=Join-Path $cachePath (Join-Path 'BuiltIn\MozillaFirefoxEnterprise' (Join-Path $Channel (Join-Path $Architecture $Language)))
    if(-not $PSCmdlet.ShouldProcess($root,"Transactionally synchronize Mozilla Firefox Enterprise $Channel cache ($Architecture, $Language)")){return}
    Assert-OSDAppCacheFreeSpace -CachePath $cachePath -MinimumFreeSpaceGB $MinimumFreeSpaceGB -Operation "Mozilla Firefox Enterprise $Channel $Architecture cache synchronization" -LogPath $log|Out-Null
    Write-OSDAppLog -LogPath $log -Component MozillaFirefoxEnterprise -Event BuiltInSyncStart -Message 'Synchronizing Mozilla Firefox Enterprise built-in cache.' -Data @{Channel=$Channel;Architecture=$Architecture;Language=$Language;Transactional=$true}
    $sync=Sync-OSDAppVendorBuiltInCache -Id MozillaFirefoxEnterprise -Root $root -PackageUri $PackageUri -Architecture $Architecture -PackageFileName Package.msi -Activity "Downloading Mozilla Firefox Enterprise $Channel $Architecture MSI" -AdditionalMetadata @{Channel=$Channel;Language=$Language} -LogPath $log -SignedPackage
    Write-OSDAppLog -LogPath $log -Component MozillaFirefoxEnterprise -Event BuiltInSyncComplete -Message 'Mozilla Firefox Enterprise built-in cache synchronized.' -Data @{Channel=$Channel;Architecture=$Architecture;Language=$Language;Updated=$sync.Updated;Path=$root;Transactional=$true}
    [pscustomobject]@{PSTypeName='OSDApps.BuiltInCache';Id='MozillaFirefoxEnterprise';Version=$sync.Version;Channel=$Channel;Architecture=$Architecture;Language=$Language;CachePath=$root;Cached=$true;Updated=$sync.Updated}
}
