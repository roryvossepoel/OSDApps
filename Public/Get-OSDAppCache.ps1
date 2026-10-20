function Get-OSDAppCache {
    [CmdletBinding()]
    param(
        [string[]]$Name,
        [switch]$ResolveVersions,
        [switch]$VerifySignatures,
        [ValidateNotNullOrEmpty()]
        [string]$CachePath
    )

    # Cache inspection is optional when no OSDCloud media is attached.
    if ($PSBoundParameters.ContainsKey('CachePath')) {
        $cachePath = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($CachePath))
        if (-not (Test-Path -LiteralPath $cachePath -PathType Container)) {
            throw "OSDApps cache path does not exist: $cachePath"
        }
    }
    else {
        try {
            $cachePath = Get-OSDAppCachePath
        }
        catch {
            Write-Verbose 'No OSDCloud cache volume is available.'
            return
        }
    }
    $results = [System.Collections.Generic.List[object]]::new()

    $cacheCatalogPath = Join-Path $cachePath 'CacheCatalog.json'
    if (Test-Path -LiteralPath $cacheCatalogPath -PathType Leaf) {
        try {
            $catalog = Get-OSDAppManifest -Path $cacheCatalogPath
            foreach ($package in @($catalog.Packages)) {
                $archivePath = Join-Path $cachePath (Join-Path 'Packages' (Join-Path $package.Id 'Package.zip'))
                $exists = Test-Path -LiteralPath $archivePath -PathType Leaf
                $valid = $false
                $sizeMB = $null

                if ($exists) {
                    $sizeMB = [math]::Round((Get-Item -LiteralPath $archivePath).Length / 1MB, 1)
                    if ($package.Archive -and $package.Archive.Sha256) {
                        $valid = Test-OSDAppFileHash -Path $archivePath -ExpectedSha256 $package.Archive.Sha256
                    }
                }

                $results.Add([pscustomobject]@{
                    PSTypeName   = 'OSDApps.CacheEntry'
                    Id           = [string]$package.Id
                    DisplayName  = if ($package.DisplayName) { [string]$package.DisplayName } else { [string]$package.Id }
                    Vendor       = if ($package.Vendor) { [string]$package.Vendor } else { $null }
                    Source       = 'Repository'
                    PackageType  = if ($package.PackageType) { [string]$package.PackageType } else { 'Application' }
                    Version      = [string]$package.Version
                    Architecture = [string]$package.Architecture
                    Channel      = $null
                    Language     = $null
                    SourcePolicy = 'RepositoryManaged'
                    SyncMethod   = 'ManifestSha256'
                    LastSynced   = $catalog.GeneratedAt
                    SizeMB       = $sizeMB
                    Valid        = $valid
                    CachePath    = if ($exists) { $archivePath } else { Join-Path $cachePath (Join-Path 'Packages' $package.Id) }
                    SignatureStatus = 'Not assessed'
                    SignatureScope = 'Repository ZIP (SHA-256 checked separately)'
                    SignatureFile = $null
                    SignatureSigner = $null
                    SignatureDetail = 'Authenticode is not evaluated for custom repository ZIPs.'
                })
            }
        }
        catch {
            Write-Warning "Failed to read repository cache catalog '$cacheCatalogPath': $($_.Exception.Message)"
        }
    }

    $builtInRoot = Join-Path $cachePath 'BuiltIn'
    if (Test-Path -LiteralPath $builtInRoot -PathType Container) {
        foreach ($cacheInfoFile in @(Get-ChildItem -LiteralPath $builtInRoot -Filter 'CacheInfo.json' -File -Recurse -ErrorAction SilentlyContinue)) {
            try {
                $info = Get-Content -LiteralPath $cacheInfoFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                $entryRoot = Split-Path -Path $cacheInfoFile.FullName -Parent
                $files = @(Get-ChildItem -LiteralPath $entryRoot -File -Recurse -ErrorAction SilentlyContinue)
                $bytes = ($files | Measure-Object -Property Length -Sum).Sum
                if ($null -eq $bytes) { $bytes = 0 }

                $payloadValid = switch ([string]$info.Id) {
                    'Microsoft365Apps' {
                        $officeArchitecture = if ([string]$info.Architecture -eq 'x86') { 'x86' } else { 'x64' }
                        $officeValidation = Test-OSDAppOfficeCacheGeneration `
                            -OfficeRoot $entryRoot `
                            -ExpectedVersion ([string]$info.Version) `
                            -Architecture $officeArchitecture `
                            -PassThru
                        $officeValidation.Valid
                    }
                    'MicrosoftTeams' {
                        (Test-Path -LiteralPath (Join-Path $entryRoot 'teamsbootstrapper.exe') -PathType Leaf) -and
                        (Test-Path -LiteralPath (Join-Path $entryRoot 'teams.msix') -PathType Leaf)
                    }
                    'AdobeAcrobatUnified' {
                        Test-Path -LiteralPath (Join-Path $entryRoot 'Package.zip') -PathType Leaf
                    }
                    'GoogleChromeEnterprise' {
                        Test-Path -LiteralPath (Join-Path $entryRoot 'Package.msi') -PathType Leaf
                    }
                    'VisualStudioCode' {
                        try { Assert-OSDAppVisualStudioCodeGeneration -Root $entryRoot -Architecture ([string]$info.Architecture) | Out-Null; $true } catch { $false }
                    }
                    '7Zip' {
                        try { Assert-OSDApp7ZipGeneration -Root $entryRoot -Architecture ([string]$info.Architecture) | Out-Null; $true } catch { $false }
                    }
                    'ZoomWorkplace' {
                        Test-Path -LiteralPath (Join-Path $entryRoot 'Package.msi') -PathType Leaf
                    }
                    'CiscoWebex' {
                        Test-Path -LiteralPath (Join-Path $entryRoot 'Package.msi') -PathType Leaf
                    }
                    'MozillaFirefoxEnterprise' {
                        Test-Path -LiteralPath (Join-Path $entryRoot 'Package.msi') -PathType Leaf
                    }
                    default {
                        $files.Count -gt 0
                    }
                }

                $cachedVersion = if ($null -ne $info.Version) { ([string]$info.Version).Trim() } else { $null }
                $resolvedVersion = if ($cachedVersion -and $cachedVersion -ne 'Current') { $cachedVersion } else { $null }
                $versionSource = if ($info.VersionSource) { [string]$info.VersionSource } else { $null }
                if ($ResolveVersions -and $payloadValid -and -not (Test-OSDAppWinPE) -and -not $resolvedVersion) {
                    $inspected = Get-OSDAppCachedPackageVersion -Id ([string]$info.Id) -CacheEntryPath $entryRoot
                    if ($inspected.Version) {
                        $resolvedVersion = [string]$inspected.Version
                        $versionSource = [string]$inspected.VersionSource
                    }
                }

                # Signature inspection is opt-in. It is separate from Valid:
                # Valid still describes required file presence, never signer trust.
                $signature = $null
                if ($VerifySignatures -and $payloadValid) {
                    $signature = Get-OSDAppBuiltInSignature -Id ([string]$info.Id) -CacheEntryPath $entryRoot -CheckPublisher
                }

                $results.Add([pscustomobject]@{
                    PSTypeName   = 'OSDApps.CacheEntry'
                    Id           = [string]$info.Id
                    Source       = 'BuiltIn'
                    PackageType  = 'Application'
                    Version      = if ($resolvedVersion) { $resolvedVersion } else { $cachedVersion }
                    VersionSource = $versionSource
                    Architecture = if ($info.Architecture) { [string]$info.Architecture } else { $null }
                    Channel      = if ($info.Channel) { [string]$info.Channel } else { $null }
                    Language     = if ($info.Language -is [System.Collections.IEnumerable] -and $info.Language -isnot [string]) { @($info.Language) -join ',' } elseif ($info.Language) { [string]$info.Language } else { $null }
                    SourcePolicy = if ($info.SourcePolicy) { [string]$info.SourcePolicy } else { 'Evergreen' }
                    SyncMethod   = if ($info.SyncMethod) { [string]$info.SyncMethod } else { $null }
                    LastSynced   = $info.SyncedAt
                    SizeMB       = [math]::Round([double]$bytes / 1MB, 1)
                    Valid        = [bool]$payloadValid
                    CachePath    = $entryRoot
                    SignatureStatus = if (-not $payloadValid) { 'File missing' } elseif ($signature) { [string]$signature.Status } else { 'Not checked' }
                    SignatureScope = if ($signature) { [string]$signature.Scope } else { $null }
                    SignatureFile = if ($signature) { $signature.File } else { $null }
                    SignatureSigner = if ($signature) { $signature.Signer } else { $null }
                    SignatureDetail = if ($signature) { $signature.Detail } else { $null }
                })
            }
            catch {
                Write-Warning "Failed to inspect built-in cache '$($cacheInfoFile.FullName)': $($_.Exception.Message)"
            }
        }
    }

    $output = @($results)
    if ($Name) {
        $output = @($output | Where-Object {
            $entry = $_
            @($Name | Where-Object { $entry.Id -like $_ }).Count -gt 0
        })
    }

    $output | Sort-Object Source, Id, Architecture, Channel, Language
}
