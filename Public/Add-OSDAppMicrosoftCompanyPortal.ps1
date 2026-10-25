function Add-OSDAppMicrosoftCompanyPortal {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateSet('x64','arm64')][string]$Architecture = 'x64',
        [string]$WindowsPath
    )

    $target = Resolve-OSDAppWindowsPath -WindowsPath $WindowsPath
    $cachePath = Get-OSDAppCachePath
    $source = Join-Path $cachePath ('BuiltIn\MicrosoftCompanyPortal\' + $Architecture)
    $cacheInfoPath = Join-Path $source 'CacheInfo.json'
    if (-not (Test-Path -LiteralPath $cacheInfoPath -PathType Leaf)) {
        throw ('Company Portal {0} is not cached. Run Sync-OSDAppMicrosoftCompanyPortal on full Windows first (automatic Microsoft download; optional -KitPath fallback).' -f $Architecture)
    }
    $info = Get-Content -LiteralPath $cacheInfoPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    if ($info.Id -ne 'MicrosoftCompanyPortal' -or $info.Architecture -ne $Architecture -or
        @($info.Files).Count -ne 7 -or $info.DependencyCount -ne 5) {
        throw 'Invalid Company Portal cache metadata.'
    }
    $stage = Join-Path $target 'Windows\Temp\OSDApps'
    $relativeRoot = 'BuiltIn\MicrosoftCompanyPortal\' + $Architecture
    $destination = Join-Path $stage $relativeRoot
    foreach ($file in @($info.Files)) {
        $relative = [string]$file.Path
        if ([string]::IsNullOrWhiteSpace($relative) -or
            [IO.Path]::IsPathRooted($relative) -or $relative -match '(^|[\\/])(\.|\.{2})([\\/]|$)' -or
            $relative -match '[:*?"<>|]' -or [string]$file.Sha256 -notmatch '^[a-fA-F0-9]{64}$') {
            throw ('Unsafe Company Portal cache entry: {0}' -f $relative)
        }
        $path = Join-Path $source $relative
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
            (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $file.Sha256) {
            throw ('Company Portal cache hash validation failed: {0}' -f $relative)
        }
    }
    if (-not $PSCmdlet.ShouldProcess($destination, 'Stage Company Portal for SetupComplete')) { return }
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    if (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination -Recurse -Force }
    New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Recurse -Force -ErrorAction Stop

    $manifestPath = Join-Path $stage 'DeviceManifest.json'
    $manifest = if (Test-Path -LiteralPath $manifestPath) {
        Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    } else {
        [pscustomobject]@{ SchemaVersion=1; StagedAt=(Get-Date).ToUniversalTime().ToString('o'); Apps=@() }
    }
    $fileHashes = @(
        foreach ($file in @($info.Files)) {
            [pscustomobject]@{
                Path = (Join-Path $relativeRoot ([string]$file.Path))
                Sha256 = [string]$file.Sha256
            }
        }
    )
    $depPaths = @($fileHashes | Where-Object { $_.Path -match '\\Dependencies\\' } | ForEach-Object { [string]$_.Path })
    $app = [pscustomobject]@{
        Id='MicrosoftCompanyPortal'; DisplayName='Microsoft Company Portal'
        Source='BuiltIn'; PackageType='Application'; Type='CompanyPortalAppxBundle'
        Version=[string]$info.Version; Architecture=$Architecture
        Package=(Join-Path $relativeRoot 'Bundle.appxbundle')
        License=(Join-Path $relativeRoot 'License.xml')
        Dependencies=$depPaths; FileHashes=$fileHashes
    }
    $manifest = Set-OSDAppManifestApp -Manifest $manifest -App $app
    $manifest = Set-OSDAppManifestRuntimeConfiguration -Manifest $manifest
    $manifest.StagedAt = (Get-Date).ToUniversalTime().ToString('o')
    $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    Add-OSDAppSetupComplete -WindowsPath $target -StagedRelativePath 'Windows\Temp\OSDApps' -Confirm:$false | Out-Null

    [pscustomobject]@{
        Name='MicrosoftCompanyPortal'; Source='BuiltIn'; PackageType='Application'
        Version=[string]$info.Version; Architecture=$Architecture
        WindowsPath=$target; StagedPath=$destination
    }
}
