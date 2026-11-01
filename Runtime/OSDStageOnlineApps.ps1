function Sync-OSDStageMicrosoftCompanyPortalGeneration {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$CachePath,
        [ValidateSet('x64','arm64')][string]$Architecture = 'x64',
        [string]$KitPath,
        [switch]$NoFallback,
        [scriptblock]$Download = { param($uri,$destination) Save-OSDStageDownload -Uri $uri -DestinationDirectory $destination -ExpectedExtension '.zip' -Activity 'Downloading Microsoft Company Portal Preinstall Kit' })
    $target = Join-Path $CachePath ('BuiltIn\MicrosoftCompanyPortal\' + $Architecture)
    $automatic = [string]::IsNullOrWhiteSpace($KitPath)
    $downloadUri = 'https://download.microsoft.com/download/ac93b367-7b17-4838-a079-c6f3377bf582/CompanyPortal-Universal-Production_x64_x86_ARM_ARM64.appxupload_Windows10_PreinstallKit.zip'
    $remote = $null
    if ($automatic) {
        try {
            $response = Invoke-WebRequest -Uri $downloadUri -Method Head -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
            $remote = @{ ETag=[string]$response.Headers['ETag']; LastModified=[string]$response.Headers['Last-Modified']; Length=[string]$response.Headers['Content-Length'] }
        } catch { Write-Verbose 'Kit HTTP metadata unavailable; download and validate the complete kit.' }
        try {
            $current = Get-OSDStageOnlineAppCacheEntry -CachePath $CachePath -Id MicrosoftCompanyPortal -Architecture $Architecture
            $previous = Get-Content -LiteralPath (Join-Path $target 'CacheInfo.json') -Raw -Encoding UTF8 | ConvertFrom-Json
            $etag = $previous.PSObject.Properties['RemoteETag']
            $modified = $previous.PSObject.Properties['RemoteLastModified']
            $length = $previous.PSObject.Properties['RemoteContentLength']
            $matches = $remote -and (($etag -and $remote.ETag -and $etag.Value -ceq $remote.ETag) -or
                (-not $remote.ETag -and $modified -and $length -and $remote.LastModified -and $remote.Length -and
                $modified.Value -ceq $remote.LastModified -and [string]$length.Value -eq $remote.Length))
            if ($matches -and $previous.SourceUri -ceq $downloadUri) {
                return [pscustomobject]@{PSTypeName='OSDStage.BuiltInCache';Id='MicrosoftCompanyPortal';Version=$current.Version;Architecture=$Architecture;Cached=$true;Updated=$false;CacheReused=$false;CachePath=$target;Files=7}
            }
        } catch { Write-Verbose 'Company Portal cache requires a validated refresh.' }
    }
    $kit = $null
    $kitDirectory = $null
    Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    $candidate = $target + '.osdstage-new-' + [guid]::NewGuid().ToString('N')
    $backup = $target + '.osdstage-old-' + [guid]::NewGuid().ToString('N')
    try {
        if ($automatic) {
            $kitDirectory = Join-Path $cachePath ('.osdstage-kit-' + [guid]::NewGuid().ToString('N'))
            $downloadResult = & $Download $downloadUri $kitDirectory
            $kit = [string]$downloadResult.FullName
        } else {
            $kit = (Resolve-Path -LiteralPath $KitPath -ErrorAction Stop).Path
        }
        if ([IO.Path]::GetExtension($kit) -ne '.zip') { throw 'Expected the official Microsoft Preinstall Kit ZIP.' }
        $zip = [IO.Compression.ZipFile]::OpenRead($kit)
        try {
            # Only select vendor files at the ZIP root. Reject ambiguous versions.
            $entries = @($zip.Entries | Where-Object { $_.Name -eq $_.FullName -and $_.Length -gt 0 })
            $bundles = @($entries | Where-Object { $_.Name -match '^[a-zA-Z0-9_-]+\.appxbundle$' })
            $licenses = @($entries | Where-Object { $_.Name -match '^[a-zA-Z0-9_-]+_License[0-9]+\.xml$' })
            if ($bundles.Count -ne 1 -or $licenses.Count -ne 1) {
                throw 'The Preinstall Kit must contain exactly one root appxbundle and one offline license.'
            }
            $families = @(
                'Microsoft.NET.Native.Framework.2.2_',
                'Microsoft.NET.Native.Runtime.2.2_',
                'Microsoft.Services.Store.Engagement_',
                'Microsoft.UI.Xaml.2.7_',
                'Microsoft.VCLibs.140.00_'
            )
            $dependencies = @()
            foreach ($family in $families) {
                $matches = @($entries | Where-Object { $_.Name -like ($family + '*_' + $Architecture + '__*.appx') })
                if ($matches.Count -ne 1) {
                    throw ('Expected one {0} dependency for {1}; found {2}.' -f $family,$Architecture,$matches.Count)
                }
                $dependencies += $matches[0]
            }
            New-Item -ItemType Directory -Path $candidate -Force -ErrorAction Stop | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $candidate 'Dependencies') -Force -ErrorAction Stop | Out-Null

            $selected = @(
                @{ Entry=$bundles[0]; Relative=[string]$bundles[0].Name },
                @{ Entry=$licenses[0]; Relative=[string]$licenses[0].Name }
            )
            foreach ($dep in $dependencies) {
                $selected += @{ Entry=$dep; Relative=('Dependencies\' + $dep.Name) }
            }
            $files = @()
            foreach ($entry in $selected) {
                $destination = Join-Path $candidate $entry.Relative
                [IO.Compression.ZipFileExtensions]::ExtractToFile($entry.Entry, $destination, $true)
                $files += [pscustomobject]@{
                    Path = [string]$entry.Relative
                    Sha256 = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
                }
            }
        }
        finally { $zip.Dispose() }

        # Read app identity and version from the actual vendor-signed bundle metadata.
        $bundle = [IO.Compression.ZipFile]::OpenRead((Join-Path $candidate ([string]$bundles[0].Name)))
        try {
            $manifestEntry = $bundle.GetEntry('AppxMetadata/AppxBundleManifest.xml')
            if (-not $manifestEntry) { throw 'AppxBundleManifest.xml was not found.' }
            $reader = [IO.StreamReader]::new($manifestEntry.Open())
            try { [xml]$bundleXml = $reader.ReadToEnd() }
            finally { $reader.Dispose() }
            $identity = $bundleXml.SelectSingleNode("//*[local-name()='Identity']")
            if (-not $identity -or $identity.GetAttribute('Name') -ne 'Microsoft.CompanyPortal' -or
                $identity.GetAttribute('Publisher') -notmatch 'Microsoft Corporation') {
                throw 'Unexpected Microsoft Company Portal bundle identity or publisher.'
            }
            $version = $identity.GetAttribute('Version')
            if ($version -notmatch '^\d+\.\d+\.\d+\.\d+$') { throw 'Invalid Company Portal version.' }
        }
        finally { $bundle.Dispose() }

        [ordered]@{
            PSTypeName='OSDStage.BuiltInCache'
            Id='MicrosoftCompanyPortal'; Version=$version; Architecture=$Architecture
            PayloadFileName=[string]$bundles[0].Name; LicenseFileName=[string]$licenses[0].Name
            Sha256=[string]$files[0].Sha256; Size=(Get-Item -LiteralPath (Join-Path $candidate ([string]$bundles[0].Name))).Length
            Source=$(if($automatic){'Microsoft Download Center'}else{'Microsoft Preinstall Kit (operator supplied)'})
            SourceUri=$(if($automatic){$downloadUri}else{$null})
            RemoteETag=$(if($remote){$remote.ETag}else{$null})
            RemoteLastModified=$(if($remote){$remote.LastModified}else{$null})
            RemoteContentLength=$(if($remote){$remote.Length}else{$null})
            SourceKitSha256=(Get-FileHash -LiteralPath $kit -Algorithm SHA256).Hash
            Files=@($files); DependencyCount=$dependencies.Count
            SyncedAt=(Get-Date).ToUniversalTime().ToString('o')
        } | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath (Join-Path $candidate 'CacheInfo.json') -Encoding UTF8 -ErrorAction Stop

        $candidateInfo = Get-Content -LiteralPath (Join-Path $candidate 'CacheInfo.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        New-OSDStageCompanyPortalManifestEntry -CacheInfo $candidateInfo -Architecture $Architecture | Out-Null
        if (Test-Path -LiteralPath $target) {
            Move-Item -LiteralPath $target -Destination $backup -ErrorAction Stop
        }
        try { Move-Item -LiteralPath $candidate -Destination $target -ErrorAction Stop }
        catch {
            if (Test-Path -LiteralPath $backup) { Move-Item -LiteralPath $backup -Destination $target -ErrorAction SilentlyContinue }
            throw
        }
        if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction Stop }

        [pscustomobject]@{
            PSTypeName='OSDStage.BuiltInCache'
            Id='MicrosoftCompanyPortal'; Version=$version; Architecture=$Architecture
            Cached=$true; Updated=$true; CacheReused=$false; CachePath=$target; Files=$files.Count
        }
    }
    catch {
        $originalError = $_
        if ($automatic -and -not $NoFallback -and (Test-Path -LiteralPath (Join-Path $target 'CacheInfo.json') -PathType Leaf)) {
            try {
                $previous = Get-Content (Join-Path $target 'CacheInfo.json') -Raw | ConvertFrom-Json
                $entry = New-OSDStageCompanyPortalManifestEntry -CacheInfo $previous -Architecture $Architecture
                Assert-OSDStageCompanyPortalFiles -App $entry -StagedPath $cachePath
                $healthy = $true
                if ($healthy) {
                    Write-Warning ('Company Portal download failed; verified cache reused: {0}' -f $originalError.Exception.Message)
                    return [pscustomobject]@{PSTypeName='OSDStage.BuiltInCache';Id='MicrosoftCompanyPortal';Version=$previous.Version;Architecture=$Architecture;Cached=$true;Updated=$false;CacheReused=$true;CachePath=$target;Files=7}
                }
            } catch { }
        }
        throw $originalError
    }
    finally {
        if ($kitDirectory -and (Test-Path -LiteralPath $kitDirectory)) {
            Remove-Item -LiteralPath $kitDirectory -Recurse -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $candidate) { Remove-Item -LiteralPath $candidate -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

function Sync-OSDStageCMTraceOpenGeneration {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$CachePath,
        [ValidateSet('x64','arm64')][string]$Architecture = 'x64')
    $target = Join-Path $CachePath ('BuiltIn\CMTraceOpen\' + $Architecture)
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/adamgell/cmtraceopen/releases/latest' -Headers @{ 'User-Agent'='OSDStage'; Accept='application/vnd.github+json' } -TimeoutSec 60 -ErrorAction Stop
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
    $infoPath = Join-Path $target 'CacheInfo.json'
    $info = if (Test-Path -LiteralPath $infoPath -PathType Leaf) {
        try { Get-Content -LiteralPath $infoPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $null }
    } else { $null }
    $existing = if (Test-Path -LiteralPath $active -PathType Leaf) { $active } else { $null }
    if ($info -and [string]$info.Id -eq 'CMTraceOpen' -and [string]$info.Architecture -eq $Architecture -and $info.Version -eq $version -and $info.Sha256 -eq $expected -and
        [string]$info.PayloadFileName -ceq $name -and $existing -and
        (Get-FileHash -LiteralPath $existing -Algorithm SHA256).Hash -eq $expected) {
        $signature = Get-AuthenticodeSignature -FilePath $existing
        if ($signature.Status -eq 'Valid') { return [pscustomobject]@{PSTypeName='OSDStage.BuiltInCache';Id='CMTraceOpen';Version=$version;Architecture=$Architecture;Updated=$false;CachePath=$target} }
    }
    $candidate = $target + '.osdstage-new-' + [guid]::NewGuid().ToString('N')
    $backup = $target + '.osdstage-old-' + [guid]::NewGuid().ToString('N')
    try {
        New-Item -ItemType Directory -Path $candidate -Force -ErrorAction Stop | Out-Null
        $msi = Join-Path $candidate $name
        Invoke-WebRequest -Uri $uri -UseBasicParsing -OutFile $msi -TimeoutSec 1800 -ErrorAction Stop
        if ((Get-FileHash -LiteralPath $msi -Algorithm SHA256).Hash -ne $expected) {
            throw 'Downloaded CMTrace Open MSI hash does not match GitHub release digest.'
        }
        $signature = Get-AuthenticodeSignature -FilePath $msi
        if ($signature.Status -ne 'Valid') {
            throw ('MSI Authenticode validation failed: {0}' -f $signature.Status)
        }
        [ordered]@{
            Id='CMTraceOpen'; Version=$version; Architecture=$Architecture
            Sha256=$expected; PayloadFileName=$name; Size=(Get-Item -LiteralPath $msi).Length; SourceUri=$uri
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
        [pscustomobject]@{PSTypeName='OSDStage.BuiltInCache';Id='CMTraceOpen';Version=$version;Architecture=$Architecture;Updated=$true;CachePath=$target}
    }
    finally {
        if (Test-Path -LiteralPath $candidate) { Remove-Item -LiteralPath $candidate -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

function Get-OSDStageOnlineAppCacheEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CachePath,
        [Parameter(Mandatory)][ValidateSet('MicrosoftCompanyPortal','CMTraceOpen')][string]$Id,
        [Parameter(Mandatory)][ValidateSet('x64','arm64')][string]$Architecture,
        [switch]$VerifySignature
    )
    $relative = 'BuiltIn\' + $Id + '\' + $Architecture
    $root = Join-Path $CachePath $relative
    $info = Get-Content -LiteralPath (Join-Path $root 'CacheInfo.json') -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ($Id -eq 'MicrosoftCompanyPortal') {
        $entry = New-OSDStageCompanyPortalManifestEntry -CacheInfo $info -Architecture $Architecture
        Assert-OSDStageCompanyPortalFiles -App $entry -StagedPath $CachePath
        return $entry
    }
    $name = 'CMTrace-Open_{0}_{1}.msi' -f $info.Version,$Architecture
    if ([string]$info.Id -ne $Id -or [string]$info.Architecture -ne $Architecture -or
        [string]$info.Version -notmatch '^\d+\.\d+\.\d+$' -or
        [string]$info.PayloadFileName -cne $name -or [string]$info.Sha256 -notmatch '^[a-fA-F0-9]{64}$') {
        throw [IO.InvalidDataException]::new('Invalid CMTrace Open cache metadata or official release filename.')
    }
    $file = Join-Path $root $name
    if (-not (Test-Path -LiteralPath $file -PathType Leaf) -or
        (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne [string]$info.Sha256) {
        throw [IO.InvalidDataException]::new('CMTrace Open cached MSI is missing or failed SHA-256 verification.')
    }
    if ($VerifySignature -and (Get-AuthenticodeSignature -FilePath $file -ErrorAction Stop).Status -ne 'Valid') {
        throw [Security.SecurityException]::new('CMTrace Open cached MSI signature invalid.')
    }
    [pscustomobject]@{
        Id=$Id; DisplayName='CMTrace Open'; Source='BuiltIn'; PackageType='App'; Type='VendorMsi'
        Version=[string]$info.Version; Architecture=$Architecture; Vendor='CMTrace Open'
        Package=(Join-Path $relative $name); ExpectedSha256=[string]$info.Sha256
    }
}
