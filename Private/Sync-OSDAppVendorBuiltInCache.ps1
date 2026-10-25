function Sync-OSDAppVendorBuiltInCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('GoogleChromeEnterprise','MozillaFirefoxEnterprise','CiscoWebex','ZoomWorkplace','AdobeAcrobatUnified')][string]$Id,
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][uri]$PackageUri,
        [Parameter(Mandatory)][string]$Architecture,
        [Parameter(Mandatory)][ValidateSet('.msi','.zip')][string]$ExpectedExtension,
        [Parameter(Mandatory)][string]$Activity,
        [string]$LogPath,
        [hashtable]$AdditionalMetadata = @{},
        [switch]$SignedPackage,
        [switch]$ZipPackage,
        [ValidateRange(0, [double]::MaxValue)][double]$MinimumFreeSpaceGB = 1
    )
    Restore-OSDAppBuiltInCache -Root $Root -Id $Id -LogPath $LogPath
    $activePackage = $null
    $previous = $null
    if (Test-OSDAppBuiltInPayload -Root $Root -ExpectedExtension $ExpectedExtension) {
        $activePackage = Resolve-OSDAppBuiltInPayloadPath -Root $Root -ExpectedExtension $ExpectedExtension
        $previous = Get-Content -LiteralPath (Join-Path $Root 'CacheInfo.json') -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    $remote = Get-OSDAppRemoteFileMetadata -Uri $PackageUri
    $matches = $false
    if ($activePackage -and $previous -and $previous.Id -eq $Id -and $previous.Architecture -eq $Architecture -and
        [string]$previous.PackageUri -ceq [string]$PackageUri) {
        if ($remote.ETag -and $previous.RemoteETag) { $matches = $remote.ETag -eq [string]$previous.RemoteETag }
        elseif ($remote.LastModified -and $previous.RemoteLastModified -and $remote.ContentLength -and $previous.RemoteContentLength) {
            $matches = ($remote.LastModified -eq [string]$previous.RemoteLastModified -and [long]$remote.ContentLength -eq [long]$previous.RemoteContentLength)
        }
        foreach ($key in $AdditionalMetadata.Keys) {
            if ([string]$previous.$key -cne [string]$AdditionalMetadata[$key]) { $matches = $false }
        }
    }
    if ($matches) {
        Test-OSDAppBuiltInCacheGeneration -Id $Id -Root $Root -RequiredFile @([string]$previous.PayloadFileName) -ValidateZip:$ZipPackage | Out-Null
        if ($SignedPackage) { Assert-OSDAppBuiltInSignature -Id $Id -FilePath $activePackage | Out-Null }
        $version = Get-OSDAppCachedPackageVersion -Id $Id -CacheEntryPath $Root -PayloadPath $activePackage
        return [pscustomobject]@{
            Id=$Id; Root=$Root; PayloadFileName=[string]$previous.PayloadFileName
            Version=$(if($version.Version){[string]$version.Version}else{[string]$previous.Version})
            VersionSource=$version.VersionSource; Updated=$false; RemoteMetadata=$remote
        }
    }
    Invoke-OSDAppBuiltInCacheTransaction -Root $Root -ExpectedBytes ([double]$remote.ContentLength) -MinimumFreeSpaceGB $MinimumFreeSpaceGB -Build {
        param($candidateRoot)
        if ($SignedPackage) {
            $downloaded = Save-OSDAppVerifiedBuiltInDownload -Id $Id -Uri $PackageUri -DestinationDirectory $candidateRoot -ExpectedExtension $ExpectedExtension -Activity $Activity
        }
        else {
            $downloaded = Save-OSDAppDownload -Uri $PackageUri -DestinationDirectory $candidateRoot -ExpectedExtension $ExpectedExtension -Activity $Activity
        }
        if (-not $downloaded -or -not $downloaded.FullName) { throw 'Vendor download did not return its payload path.' }
        $candidatePackage = Resolve-OSDAppBuiltInPayloadPath -Path ([string]$downloaded.FullName)
        $leaf = Assert-OSDAppPayloadFileName -FileName (Split-Path -Path $candidatePackage -Leaf) -ExpectedExtension $ExpectedExtension
        $version = Get-OSDAppCachedPackageVersion -Id $Id -CacheEntryPath $candidateRoot -PayloadPath $candidatePackage
        $record = [ordered]@{
            Id=$Id; Cached=$true; Architecture=$Architecture
            Version=$(if($version.Version){[string]$version.Version}else{'Current'}); VersionSource=$version.VersionSource
            PayloadFileName=$leaf; Sha256=(Get-FileHash -LiteralPath $candidatePackage -Algorithm SHA256).Hash
            Size=(Get-Item -LiteralPath $candidatePackage).Length
            SourcePolicy='Evergreen'; SyncMethod='HttpMetadata'; Updated=$true; PackageUri=[string]$PackageUri
            RemoteETag=$remote.ETag; RemoteLastModified=$remote.LastModified
            RemoteContentLength=$remote.ContentLength; RemoteFinalUri=$remote.FinalUri
            SyncedAt=(Get-Date).ToUniversalTime().ToString('o')
        }
        foreach ($key in $AdditionalMetadata.Keys) {
            if ($record.Contains($key)) { throw "Additional metadata cannot override reserved field '$key'." }
            $record[$key] = $AdditionalMetadata[$key]
        }
        $record | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $candidateRoot 'CacheInfo.json') -Encoding UTF8 -ErrorAction Stop
    } -Validate {
        param($candidateRoot)
        $path = Resolve-OSDAppBuiltInPayloadPath -Root $candidateRoot -ExpectedExtension $ExpectedExtension
        Test-OSDAppBuiltInCacheGeneration -Id $Id -Root $candidateRoot -RequiredFile @((Split-Path -Path $path -Leaf)) -ValidateZip:$ZipPackage | Out-Null
        if ($SignedPackage) { Assert-OSDAppBuiltInSignature -Id $Id -FilePath $path | Out-Null }
    } | Out-Null
    $info = Get-Content -LiteralPath (Join-Path $Root 'CacheInfo.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    [pscustomobject]@{Id=$Id;Root=$Root;PayloadFileName=$info.PayloadFileName;Version=[string]$info.Version;VersionSource=[string]$info.VersionSource;Updated=$true;RemoteMetadata=$remote}
}
