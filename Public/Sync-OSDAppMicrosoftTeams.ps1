function Sync-OSDAppMicrosoftTeams {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateSet('x86','x64','arm64')][string]$Architecture='x64',
        [ValidateRange(0, [double]::MaxValue)][double]$MinimumFreeSpaceGB=2,
        [string]$BootstrapperUri='https://go.microsoft.com/fwlink/?clcid=0x409&linkid=2243204'
    )
    if(Test-OSDAppWinPE){throw 'Sync-OSDAppMicrosoftTeams is intended for full Windows. Built-in cache refresh is deferred until the pre-install phase.'}
    $cachePath=Get-OSDAppCachePath;$log=Join-Path $cachePath 'Logs\Client.log';$root=Join-Path $cachePath 'BuiltIn\MicrosoftTeams'
    $msixUri=switch($Architecture){'x86'{'https://go.microsoft.com/fwlink/?clcid=0x409&linkid=2196060'}'x64'{'https://go.microsoft.com/fwlink/?linkid=2196106'}'arm64'{'https://go.microsoft.com/fwlink/?clcid=0x409&linkid=2196207'}}
    if(-not $PSCmdlet.ShouldProcess($root,"Transactionally synchronize Microsoft Teams built-in cache ($Architecture)")){return}
    Write-OSDAppLog -LogPath $log -Component MicrosoftTeams -Event BuiltInSyncStart -Message 'Synchronizing Microsoft Teams built-in cache.' -Data @{Architecture=$Architecture;Transactional=$true}
    Restore-OSDAppBuiltInCache -Root $root -Id MicrosoftTeams -LogPath $log
    $remote=Get-OSDAppRemoteFileMetadata -Uri $msixUri;$previous=$null;$activeInfo=Join-Path $root 'CacheInfo.json';$activeMsix=Join-Path $root 'teams.msix'
    if(Test-Path -LiteralPath $activeInfo -PathType Leaf){try{$previous=Get-Content -LiteralPath $activeInfo -Raw -Encoding UTF8|ConvertFrom-Json}catch{}}
    $matches=$false
    if((Test-Path -LiteralPath $activeMsix -PathType Leaf)-and $previous){if($remote.ETag -and $previous.RemoteETag){$matches=$remote.ETag -eq [string]$previous.RemoteETag}elseif($remote.LastModified -and $previous.RemoteLastModified -and $remote.ContentLength -and $previous.RemoteContentLength){$matches=($remote.LastModified -eq [string]$previous.RemoteLastModified -and [int64]$remote.ContentLength -eq [int64]$previous.RemoteContentLength)}}
    Invoke-OSDAppBuiltInCacheTransaction -Root $root -ExpectedBytes ([double]$remote.ContentLength) -MinimumFreeSpaceGB $MinimumFreeSpaceGB -Build {
        param($candidate)
        $bootstrapper=Join-Path $candidate 'teamsbootstrapper.exe';$msix=Join-Path $candidate 'teams.msix'
        Save-OSDAppVerifiedBuiltInDownload -Id MicrosoftTeams -Uri $BootstrapperUri -DestinationPath $bootstrapper -Activity 'Downloading Microsoft Teams bootstrapper'|Out-Null
        if($matches){Copy-Item -LiteralPath $activeMsix -Destination $msix -Force;$updated=$false;$version=if($previous.Version){[string]$previous.Version}else{Get-OSDAppMicrosoftTeamsPackageVersion -Path $msix}}
        else{Save-OSDAppDownload -Uri $msixUri -DestinationPath $msix -Activity "Downloading Microsoft Teams $Architecture MSIX"|Out-Null;$updated=$true;$version=Get-OSDAppMicrosoftTeamsPackageVersion -Path $msix}
        [ordered]@{Id='MicrosoftTeams';Cached=$true;Version=$version;Architecture=$Architecture;SourcePolicy='Evergreen';SyncMethod='HttpMetadata';Updated=$updated;BootstrapperUri=$BootstrapperUri;RemoteETag=$remote.ETag;RemoteLastModified=$remote.LastModified;RemoteContentLength=$remote.ContentLength;RemoteFinalUri=$remote.FinalUri;SyncedAt=(Get-Date).ToUniversalTime().ToString('o')}|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $candidate 'CacheInfo.json') -Encoding UTF8
    } -Validate {
        param($candidate)
        Test-OSDAppBuiltInCacheGeneration -Id MicrosoftTeams -Root $candidate -RequiredFile @('teamsbootstrapper.exe','teams.msix')|Out-Null
        Assert-OSDAppBuiltInSignature -Id MicrosoftTeams -FilePath (Join-Path $candidate 'teamsbootstrapper.exe')|Out-Null
        Get-OSDAppMicrosoftTeamsPackageVersion -Path (Join-Path $candidate 'teams.msix')|Out-Null
    }|Out-Null
    $committed=Get-Content -LiteralPath (Join-Path $root 'CacheInfo.json') -Raw -Encoding UTF8|ConvertFrom-Json
    $removedAliases=@(Remove-OSDAppBuiltInCacheAlias -CachePath $cachePath -CanonicalId MicrosoftTeams -Alias Teams -LogPath $log -Confirm:$false)
    Write-OSDAppLog -LogPath $log -Component MicrosoftTeams -Event BuiltInSyncComplete -Message 'Microsoft Teams built-in cache synchronized.' -Data @{Version=$committed.Version;Architecture=$Architecture;Updated=$committed.Updated;Path=$root;Transactional=$true;RemovedAliases=$removedAliases}
    [pscustomobject]@{PSTypeName='OSDApps.BuiltInCache';Id='MicrosoftTeams';Version=[string]$committed.Version;Architecture=$Architecture;CachePath=$root;Cached=$true;Updated=[bool]$committed.Updated;RemovedAliases=$removedAliases}
}
