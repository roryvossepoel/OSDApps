function Sync-OSDAppCiscoWebex {
    [CmdletBinding(SupportsShouldProcess)]
    param([ValidateSet('x64','arm64')][string]$Architecture='x64',[ValidateRange(0, [double]::MaxValue)][double]$MinimumFreeSpaceGB=1,[string]$PackageUri)
    if(Test-OSDAppWinPE){throw 'Sync-OSDAppCiscoWebex is intended for full Windows. Built-in refresh occurs during PreInstall.'}
    if(-not $PackageUri){$PackageUri=if($Architecture -eq 'x64'){'https://binaries.webex.com/WebexOfclDesktop-Win-64-Gold/Webex_en.msi'}else{'https://binaries.webex.com/WebexOfclDesktop-Win-Arm-64-Gold/Webex_en.msi'}}
    $cachePath=Get-OSDAppCachePath;$log=Join-Path $cachePath 'Logs\Client.log';$root=Join-Path $cachePath (Join-Path 'BuiltIn\CiscoWebex' $Architecture)
    if(-not $PSCmdlet.ShouldProcess($root,"Transactionally synchronize Cisco Webex built-in cache ($Architecture)")){return}
    Write-OSDAppLog -LogPath $log -Component CiscoWebex -Event BuiltInSyncStart -Message 'Synchronizing Cisco Webex built-in cache.' -Data @{Architecture=$Architecture;Transactional=$true}
    $sync=Sync-OSDAppVendorBuiltInCache -MinimumFreeSpaceGB $MinimumFreeSpaceGB -Id CiscoWebex -Root $root -PackageUri $PackageUri -Architecture $Architecture -PackageFileName Package.msi -Activity "Downloading Cisco Webex $Architecture MSI" -LogPath $log -SignedPackage
    Write-OSDAppLog -LogPath $log -Component CiscoWebex -Event BuiltInSyncComplete -Message 'Cisco Webex built-in cache synchronized.' -Data @{Architecture=$Architecture;Updated=$sync.Updated;Path=$root;Transactional=$true}
    [pscustomobject]@{PSTypeName='OSDApps.BuiltInCache';Id='CiscoWebex';Version=$sync.Version;Architecture=$Architecture;CachePath=$root;Cached=$true;Updated=$sync.Updated}
}
