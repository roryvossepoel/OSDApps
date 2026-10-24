function Sync-OSDAppMicrosoftCompanyPortal {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$KitPath,
        [ValidateSet('x64','arm64')][string]$Architecture = 'x64'
    )

    if (Test-OSDAppWinPE) {
        throw 'Prepare the Company Portal cache on full Windows, not in WinPE.'
    }
    $cachePath = Get-OSDAppCachePath
    $target = Join-Path $cachePath ('BuiltIn\MicrosoftCompanyPortal\' + $Architecture)
    if (-not $PSCmdlet.ShouldProcess($target, 'Prepare Microsoft Company Portal from the supplied Preinstall Kit')) { return }

    $automatic = [string]::IsNullOrWhiteSpace($KitPath)
    $downloadUri = 'https://download.microsoft.com/download/ac93b367-7b17-4838-a079-c6f3377bf582/CompanyPortal-Universal-Production_x64_x86_ARM_ARM64.appxupload_Windows10_PreinstallKit.zip'
    $kit = $null
    Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    $lock = Enter-OSDAppCacheLock -CachePath $cachePath -Operation 'Microsoft Company Portal cache synchronization'
    $candidate = $target + '.osdapps-new-' + [guid]::NewGuid().ToString('N')
    $backup = $target + '.osdapps-old-' + [guid]::NewGuid().ToString('N')
    try {
        if ($automatic) {
            $kit = Join-Path $cachePath ('CompanyPortal-PreinstallKit-' + [guid]::NewGuid().ToString('N') + '.zip')
            Invoke-WebRequest -Uri $downloadUri -OutFile $kit -UseBasicParsing -TimeoutSec 900 -ErrorAction Stop
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
                @{ Entry=$bundles[0]; Relative='Bundle.appxbundle' },
                @{ Entry=$licenses[0]; Relative='License.xml' }
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
        $bundle = [IO.Compression.ZipFile]::OpenRead((Join-Path $candidate 'Bundle.appxbundle'))
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
            Id='MicrosoftCompanyPortal'; Version=$version; Architecture=$Architecture
            Source=$(if($automatic){'Microsoft Download Center'}else{'Microsoft Preinstall Kit (operator supplied)'})
            SourceUri=$(if($automatic){$downloadUri}else{$null})
            SourceKitSha256=(Get-FileHash -LiteralPath $kit -Algorithm SHA256).Hash
            Files=@($files); DependencyCount=$dependencies.Count
            SyncedAt=(Get-Date).ToUniversalTime().ToString('o')
        } | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath (Join-Path $candidate 'CacheInfo.json') -Encoding UTF8 -ErrorAction Stop

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
            Id='MicrosoftCompanyPortal'; Version=$version; Architecture=$Architecture
            Cached=$true; Updated=$true; CacheReused=$false; CachePath=$target; Files=$files.Count
        }
    }
    catch {
        $originalError = $_
        if ($automatic -and (Test-Path -LiteralPath (Join-Path $target 'CacheInfo.json') -PathType Leaf)) {
            try {
                $previous = Get-Content (Join-Path $target 'CacheInfo.json') -Raw | ConvertFrom-Json
                $healthy = ($previous.Id -eq 'MicrosoftCompanyPortal' -and $previous.Architecture -eq $Architecture -and @($previous.Files).Count -eq 7)
                foreach ($item in @($previous.Files)) {
                    $relative = [string]$item.Path
                    if ($relative -notmatch '^(Bundle\.appxbundle|License\.xml|Dependencies\\[A-Za-z0-9._-]+\.appx)$' -or
                        [string]$item.Sha256 -notmatch '^[0-9A-Fa-f]{64}$') { $healthy = $false; break }
                    $file = Join-Path $target $relative
                    if (-not (Test-Path -LiteralPath $file -PathType Leaf) -or
                        (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $item.Sha256) { $healthy = $false; break }
                }
                if ($healthy) {
                    Write-Warning ('Company Portal download failed; verified cache reused: {0}' -f $originalError.Exception.Message)
                    return [pscustomobject]@{Id='MicrosoftCompanyPortal';Version=$previous.Version;Architecture=$Architecture;Cached=$true;Updated=$false;CacheReused=$true;CachePath=$target;Files=7}
                }
            } catch { }
        }
        throw $originalError
    }
    finally {
        if ($automatic -and $kit -and (Test-Path -LiteralPath $kit -PathType Leaf)) {
            Remove-Item -LiteralPath $kit -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $candidate) { Remove-Item -LiteralPath $candidate -Recurse -Force -ErrorAction SilentlyContinue }
        if ($lock) { $lock.Dispose() }
    }
}
