function Sync-OSDStageMicrosoftTeams {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateSet('x86','x64','arm64')][string]$Architecture='x64',
        [ValidateRange(0,[double]::MaxValue)][double]$MinimumFreeSpaceGB=2,
        [string]$BootstrapperUri='https://go.microsoft.com/fwlink/?clcid=0x409&linkid=2243204'
    )
    if (Test-OSDStageWinPE) { throw 'Sync-OSDStageMicrosoftTeams requires full Windows; use Add in WinPE.' }
    $cachePath = Get-OSDStageCachePath
    $log = Join-Path $cachePath 'Logs\Client.log'
    $root = Join-Path $cachePath 'BuiltIn\MicrosoftTeams'
    $msixUri = switch ($Architecture) {
        'x86' { 'https://go.microsoft.com/fwlink/?clcid=0x409&linkid=2196060' }
        'x64' { 'https://go.microsoft.com/fwlink/?linkid=2196106' }
        'arm64' { 'https://go.microsoft.com/fwlink/?clcid=0x409&linkid=2196207' }
    }
    if (-not $PSCmdlet.ShouldProcess($root,"Synchronize Microsoft Teams ($Architecture)")) { return }
    $cacheLock = Enter-OSDStageCacheLock -CachePath $cachePath -Operation 'built-in cache synchronization'
    try {
        Write-OSDStageLog -LogPath $log -Component MicrosoftTeams -Event BuiltInSyncStart -Message 'Synchronizing Microsoft Teams cache.' -Data @{Architecture=$Architecture;Transactional=$true}
        Restore-OSDStageBuiltInCache -Root $root -Id MicrosoftTeams -LogPath $log
        $remote = Get-OSDStageRemoteFileMetadata -Uri $msixUri
        $previous = $null; $activeMsix = $null; $matches = $false
        if (Test-OSDStageBuiltInPayload -Root $root -ExpectedExtension '.msix') {
            $activeMsix = Resolve-OSDStageBuiltInPayloadPath -Root $root -ExpectedExtension '.msix'
            $previous = Get-Content -LiteralPath (Join-Path $root 'CacheInfo.json') -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($previous.Id -eq 'MicrosoftTeams' -and $previous.Architecture -eq $Architecture) {
                if ($remote.ETag -and $previous.RemoteETag) { $matches = $remote.ETag -eq [string]$previous.RemoteETag }
                elseif ($remote.LastModified -and $previous.RemoteLastModified -and $remote.ContentLength -and $previous.RemoteContentLength) {
                    $matches = ($remote.LastModified -eq [string]$previous.RemoteLastModified -and [long]$remote.ContentLength -eq [long]$previous.RemoteContentLength)
                }
            }
            if ($matches) { Test-OSDStageBuiltInCacheGeneration -Id MicrosoftTeams -Root $root -RequiredFile @('teamsbootstrapper.exe',[string]$previous.PayloadFileName) | Out-Null }
        }
        Invoke-OSDStageBuiltInCacheTransaction -Root $root -ExpectedBytes ([double]$remote.ContentLength) -MinimumFreeSpaceGB $MinimumFreeSpaceGB -Build {
            param($candidate)
            Save-OSDStageVerifiedBuiltInDownload -Id MicrosoftTeams -Uri $BootstrapperUri -DestinationPath (Join-Path $candidate 'teamsbootstrapper.exe') -Activity 'Downloading Microsoft Teams bootstrapper' | Out-Null
            if ($matches) {
                Copy-OSDStageBuiltInPayload -Path $activeMsix -DestinationDirectory $candidate
                $msix = Join-Path $candidate ([string]$previous.PayloadFileName)
                $updated = $false
            }
            else {
                $download = Save-OSDStageDownload -Uri $msixUri -DestinationDirectory $candidate -ExpectedExtension '.msix' -Activity "Downloading Microsoft Teams $Architecture MSIX"
                $msix = [string]$download.FullName
                $updated = $true
            }
            $version = Get-OSDStageMicrosoftTeamsPackageVersion -Path $msix
            if (-not $version) { throw 'Downloaded Teams MSIX version could not be verified.' }
            [ordered]@{
                Id='MicrosoftTeams';Cached=$true;Version=$version;Architecture=$Architecture
                PayloadFileName=(Split-Path -Path $msix -Leaf);Sha256=(Get-FileHash -LiteralPath $msix -Algorithm SHA256).Hash
                Size=(Get-Item -LiteralPath $msix).Length;SourcePolicy='Evergreen';SyncMethod='HttpMetadata';Updated=$updated
                BootstrapperUri=$BootstrapperUri;RemoteETag=$remote.ETag;RemoteLastModified=$remote.LastModified
                RemoteContentLength=$remote.ContentLength;RemoteFinalUri=$remote.FinalUri;SyncedAt=(Get-Date).ToUniversalTime().ToString('o')
            } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $candidate 'CacheInfo.json') -Encoding UTF8
        } -Validate {
            param($candidate)
            $msix = Resolve-OSDStageBuiltInPayloadPath -Root $candidate -ExpectedExtension '.msix'
            Test-OSDStageBuiltInCacheGeneration -Id MicrosoftTeams -Root $candidate -RequiredFile @('teamsbootstrapper.exe',(Split-Path -Path $msix -Leaf)) | Out-Null
            Assert-OSDStageBuiltInSignature -Id MicrosoftTeams -FilePath (Join-Path $candidate 'teamsbootstrapper.exe') | Out-Null
            Get-OSDStageMicrosoftTeamsPackageVersion -Path $msix | Out-Null
        } | Out-Null
        $committed = Get-Content -LiteralPath (Join-Path $root 'CacheInfo.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        Write-OSDStageLog -LogPath $log -Component MicrosoftTeams -Event BuiltInSyncComplete -Message 'Microsoft Teams cache synchronized.' -Data @{Version=$committed.Version;Architecture=$Architecture;Updated=$committed.Updated;Path=$root;PayloadFileName=$committed.PayloadFileName}
        [pscustomobject]@{PSTypeName='OSDStage.BuiltInCache';Id='MicrosoftTeams';Version=[string]$committed.Version;Architecture=$Architecture;CachePath=$root;Cached=$true;Updated=[bool]$committed.Updated}
    }
    finally { $cacheLock.Dispose() }
}
