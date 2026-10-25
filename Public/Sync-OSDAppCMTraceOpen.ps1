function Sync-OSDAppCMTraceOpen {
    [CmdletBinding(SupportsShouldProcess)]
    param([ValidateSet('x64','arm64')][string]$Architecture='x64')

    if (Test-OSDAppWinPE) { throw 'Run CMTrace Open synchronization on full Windows.' }
    $cachePath = Get-OSDAppCachePath
    $target = Join-Path $cachePath ('BuiltIn\CMTraceOpen\' + $Architecture)
    if (-not $PSCmdlet.ShouldProcess($target, 'Synchronize official CMTrace Open MSI')) { return }

    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/adamgell/cmtraceopen/releases/latest' -Headers @{ 'User-Agent'='OSDApps'; Accept='app/vnd.github+json' } -ErrorAction Stop
    if ($release.draft -or $release.prerelease -or [string]$release.tag_name -notmatch '^v(?<Version>\d+\.\d+\.\d+)$') {
        throw 'CMTrace Open latest release is not a supported stable release.'
    }
    $version = $Matches.Version
    $name = 'CMTrace-Open_{0}_{1}.msi' -f $version,$Architecture
    $assets = @($release.assets | Where-Object { $_.name -ceq $name })
    if ($assets.Count -ne 1) { throw ('Expected one MSI asset: {0}' -f $name) }
    $asset = $assets[0]
    $uri = 'https://github.com/adamgell/cmtraceopen/releases/download/v' + $version + '/' + $name
    if ([string]$asset.browser_download_url -cne $uri -or
        [string]$asset.digest -notmatch '^sha256:(?<Hash>[a-fA-F0-9]{64})$') {
        throw 'Unexpected release asset URI or missing official SHA-256 digest.'
    }
    $expected = $Matches.Hash.ToUpperInvariant()

    $active = Join-Path $target $name
    $legacy = Join-Path $target 'Package.msi'
    $infoPath = Join-Path $target 'CacheInfo.json'
    $info = if (Test-Path -LiteralPath $infoPath -PathType Leaf) {
        try { Get-Content -LiteralPath $infoPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $null }
    } else { $null }
    # Migrate an earlier OSDApps cache that renamed the vendor MSI to Package.msi.
    # Keep the verified bytes and metadata; only restore the publisher's filename.
    $existing = if (Test-Path -LiteralPath $active -PathType Leaf) { $active }
                elseif (Test-Path -LiteralPath $legacy -PathType Leaf) { $legacy }
                else { $null }
    if ($info -and $info.Version -eq $version -and $info.Sha256 -eq $expected -and
        [string]$info.AssetName -ceq $name -and $existing -and
        (Get-FileHash -LiteralPath $existing -Algorithm SHA256).Hash -eq $expected) {
        $signature = Get-AuthenticodeSignature -FilePath $existing
        if ($signature.Status -ne 'Valid') { throw 'CMTrace Open cached MSI signature invalid.' }
        if ($existing -eq $legacy) {
            $renameLock = Enter-OSDAppCacheLock -CachePath $cachePath -Operation 'CMTrace Open vendor filename migration'
            try {
                if (Test-Path -LiteralPath $active -PathType Leaf) {
                    throw 'Cannot migrate CMTrace Open: both legacy and vendor MSI files exist.'
                }
                Rename-Item -LiteralPath $legacy -NewName $name -ErrorAction Stop
            }
            finally { if ($renameLock) { $renameLock.Dispose() } }
        }
        return [pscustomobject]@{Id='CMTraceOpen';Version=$version;Architecture=$Architecture;Updated=$false;CachePath=$target}
    }
    $lock = Enter-OSDAppCacheLock -CachePath $cachePath -Operation 'CMTrace Open cache synchronization'
    $candidate = $target + '.osdapps-new-' + [guid]::NewGuid().ToString('N')
    $backup = $target + '.osdapps-old-' + [guid]::NewGuid().ToString('N')
    try {
        New-Item -ItemType Directory -Path $candidate -Force -ErrorAction Stop | Out-Null
        $msi = Join-Path $candidate $name
        Invoke-WebRequest -Uri $uri -UseBasicParsing -OutFile $msi -ErrorAction Stop
        if ((Get-FileHash -LiteralPath $msi -Algorithm SHA256).Hash -ne $expected) {
            throw 'Downloaded CMTrace Open MSI hash does not match GitHub release digest.'
        }
        $signature = Get-AuthenticodeSignature -FilePath $msi
        if ($signature.Status -ne 'Valid') {
            throw ('MSI Authenticode validation failed: {0}' -f $signature.Status)
        }
        [ordered]@{
            Id='CMTraceOpen'; Version=$version; Architecture=$Architecture
            Sha256=$expected; AssetName=$name; SourceUri=$uri
            Signer=[string]$signature.SignerCertificate.Subject
            SyncedAt=(Get-Date).ToUniversalTime().ToString('o')
        } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $candidate 'CacheInfo.json') -Encoding UTF8

        if (Test-Path -LiteralPath $target) { Move-Item -LiteralPath $target -Destination $backup -ErrorAction Stop }
        try { Move-Item -LiteralPath $candidate -Destination $target -ErrorAction Stop }
        catch {
            if (Test-Path -LiteralPath $backup) {
                Move-Item -LiteralPath $backup -Destination $target -ErrorAction SilentlyContinue
            }
            throw
        }
        if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Recurse -Force }
        [pscustomobject]@{Id='CMTraceOpen';Version=$version;Architecture=$Architecture;Updated=$true;CachePath=$target}
    }
    finally {
        if (Test-Path -LiteralPath $candidate) { Remove-Item -LiteralPath $candidate -Recurse -Force -ErrorAction SilentlyContinue }
        if ($lock) { $lock.Dispose() }
    }
}
