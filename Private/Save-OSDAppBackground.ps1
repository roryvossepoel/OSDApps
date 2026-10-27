function Save-OSDAppBackground {
    [CmdletBinding()]
    param([ValidateSet('Wallpaper','LockScreen')][string]$Kind,[string]$Id,[switch]$Enforce,[switch]$SkipCacheRefresh,[string]$WindowsPath)
    $ErrorActionPreference='Stop'
    Assert-OSDAppSourceEnabled -Source Repository
    Assert-OSDAppSourceEnabled -Source BuiltIn
    if (-not (Test-OSDAppWinPE)) { throw 'Stage background images in WinPE after OSDCloud, not on the preparation PC.' }
    if ($Id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or $Id -match '\.\.') { throw 'Invalid image package Id.' }
    $target=Resolve-OSDAppWindowsPath -WindowsPath $WindowsPath
    # Check edition before downloading or changing the target.
    $request=[pscustomobject]@{Kind=$Kind;Enforce=[bool]$Enforce}
    $targetInfo=Get-OSDAppBackgroundTarget -WindowsPath $target -Operation $request
    $cache=$null
    try { $cache=Get-OSDAppCachePath } catch { Write-Verbose 'Using a temporary repository cache on the Windows target.' }
    if (-not $cache) { $cache=Join-Path $target 'Windows\Temp\OSDApps\RepositoryCache' }
    $uri=(Get-OSDAppConfiguration).CatalogUri
    if ($uri -and -not $SkipCacheRefresh) {
        try { Sync-OSDAppCache -CatalogUri $uri -CachePath $cache -Name @($Id) -Confirm:$false | Out-Null }
        catch {
            if ($_.Exception.Data.Contains('OSDAppsCacheLockFailure')) { throw }
            Write-Warning ('Repository refresh failed; attempting validated cached image: ' + $_.Exception.Message)
        }
    }
    $cacheLock=Enter-OSDAppCacheLock -CachePath $cache -Operation 'read image package for staging'
    try {
    $ids=@(Resolve-OSDAppCachedPackageId -CachePath $cache -Name @($Id))
    if ($ids.Count -ne 1) { throw 'Image package was not resolved uniquely.' }
    $canonical=$ids[0]
    $catalog=Get-OSDAppManifest -Path (Join-Path $cache 'CacheCatalog.json')
    $packages=@($catalog.Packages | Where-Object Id -eq $canonical)
    if ($packages.Count -ne 1 -or [string]$packages[0].PackageType -ne 'Image' -or [string]$packages[0].Architecture -ne 'any') { throw 'Background commands require a repository Image package with Architecture any.' }
    $checks=@(Test-OSDAppRepositoryCache -CachePath $cache -Name @($canonical))
    if ($checks.Count -ne 1 -or -not $checks[0].Valid) { throw 'No SHA-256 validated image archive is available.' }
    $archive=[string]$checks[0].Path
    Assert-OSDAppImageArchive -Path $archive
    $temporary=Join-Path ([IO.Path]::GetTempPath()) ('OSDAppsImage-' + [guid]::NewGuid().ToString('N'))
    try {
        [IO.Compression.ZipFile]::ExtractToDirectory($archive,$temporary)
        $file=Get-OSDAppImageFile -PayloadRoot (Join-Path $temporary 'Package')
        $hash=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        $extension=$file.Extension.ToLowerInvariant()
        $operation=[pscustomobject]@{Kind=$Kind;Id=$canonical;FutureSystemRoot=$targetInfo.SystemRoot;Enforce=[bool]$Enforce;ImageSha256=$hash;Extension=$extension;ImageRelativePath=('OEM\OSDApps\Branding\'+$canonical+'\'+$hash+$extension)}
        Save-OSDAppDesktopStaging -Operation $operation -WindowsPath $target -BackgroundSourcePath $file.FullName -Confirm:$false
    }
    finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force } }
    }
    finally { $cacheLock.Dispose() }
}
