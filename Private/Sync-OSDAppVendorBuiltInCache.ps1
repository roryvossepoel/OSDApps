function Sync-OSDAppVendorBuiltInCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('GoogleChromeEnterprise','MozillaFirefoxEnterprise','CiscoWebex','AdobeAcrobatUnified')][string]$Id,
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][uri]$PackageUri,
        [Parameter(Mandatory)][string]$Architecture,
        [Parameter(Mandatory)][string]$PackageFileName,
        [Parameter(Mandatory)][string]$Activity,
        [hashtable]$AdditionalMetadata = @{},
        [switch]$SignedPackage,
        [switch]$ZipPackage
    )

    $activePackage = Join-Path $Root $PackageFileName
    $activeCacheInfo = Join-Path $Root 'CacheInfo.json'
    $previousCacheInfo = $null
    if (Test-Path -LiteralPath $activeCacheInfo -PathType Leaf) {
        try { $previousCacheInfo = Get-Content -LiteralPath $activeCacheInfo -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
    }

    $remoteMetadata = Get-OSDAppRemoteFileMetadata -Uri $PackageUri
    $metadataMatches = $false
    if ((Test-Path -LiteralPath $activePackage -PathType Leaf) -and $previousCacheInfo) {
        if ($remoteMetadata.ETag -and $previousCacheInfo.RemoteETag) {
            $metadataMatches = $remoteMetadata.ETag -eq [string]$previousCacheInfo.RemoteETag
        }
        elseif ($remoteMetadata.LastModified -and $previousCacheInfo.RemoteLastModified -and
            $remoteMetadata.ContentLength -and $previousCacheInfo.RemoteContentLength) {
            $metadataMatches = (
                $remoteMetadata.LastModified -eq [string]$previousCacheInfo.RemoteLastModified -and
                [int64]$remoteMetadata.ContentLength -eq [int64]$previousCacheInfo.RemoteContentLength
            )
        }
    }

    if ($metadataMatches) {
        if ($SignedPackage) { Assert-OSDAppBuiltInSignature -Id $Id -FilePath $activePackage | Out-Null }
        Test-OSDAppBuiltInCacheGeneration -Id $Id -Root $Root -RequiredFile $PackageFileName -ValidateZip:$ZipPackage | Out-Null
        $inspectedVersion = Get-OSDAppCachedPackageVersion -Id $Id -CacheEntryPath $Root
        return [pscustomobject]@{
            Id=$Id; Root=$Root; Version=if($inspectedVersion.Version){[string]$inspectedVersion.Version}else{[string]$previousCacheInfo.Version};
            VersionSource=$inspectedVersion.VersionSource; Updated=$false; RemoteMetadata=$remoteMetadata
        }
    }

    Invoke-OSDAppBuiltInCacheTransaction -Root $Root -Build {
        param($candidateRoot)
        $candidatePackage = Join-Path $candidateRoot $PackageFileName
        if ($SignedPackage) {
            Save-OSDAppVerifiedBuiltInDownload -Id $Id -Uri $PackageUri -DestinationPath $candidatePackage -Activity $Activity | Out-Null
        }
        else {
            Save-OSDAppDownload -Uri $PackageUri -DestinationPath $candidatePackage -Activity $Activity | Out-Null
        }

        $inspectedVersion = Get-OSDAppCachedPackageVersion -Id $Id -CacheEntryPath $candidateRoot
        $candidateVersion = if ($inspectedVersion.Version) { [string]$inspectedVersion.Version } else { 'Current' }
        $candidateVersionSource = $inspectedVersion.VersionSource
        $cacheRecord = [ordered]@{
            Id=$Id; Cached=$true; Version=$candidateVersion; VersionSource=$candidateVersionSource; Architecture=$Architecture;
            SourcePolicy='Evergreen'; SyncMethod='HttpMetadata'; Updated=$true; PackageUri=[string]$PackageUri;
            RemoteETag=$remoteMetadata.ETag; RemoteLastModified=$remoteMetadata.LastModified;
            RemoteContentLength=$remoteMetadata.ContentLength; RemoteFinalUri=$remoteMetadata.FinalUri;
            SyncedAt=(Get-Date).ToUniversalTime().ToString('o')
        }
        foreach ($key in $AdditionalMetadata.Keys) { $cacheRecord[$key] = $AdditionalMetadata[$key] }
        $cacheRecord | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $candidateRoot 'CacheInfo.json') -Encoding UTF8
    } -Validate {
        param($candidateRoot)
        $candidatePackage = Join-Path $candidateRoot $PackageFileName
        if ($SignedPackage) { Assert-OSDAppBuiltInSignature -Id $Id -FilePath $candidatePackage | Out-Null }
        Test-OSDAppBuiltInCacheGeneration -Id $Id -Root $candidateRoot -RequiredFile $PackageFileName -ValidateZip:$ZipPackage
    } | Out-Null

    $committedCacheInfo = Get-Content -LiteralPath (Join-Path $Root 'CacheInfo.json') -Raw -Encoding UTF8 | ConvertFrom-Json

    [pscustomobject]@{
        Id=$Id; Root=$Root; Version=[string]$committedCacheInfo.Version; VersionSource=[string]$committedCacheInfo.VersionSource; Updated=$true; RemoteMetadata=$remoteMetadata
    }
}
