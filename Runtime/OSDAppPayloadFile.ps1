# One recorded vendor filename per payload. No inferred names or directory scans.
function Assert-OSDAppPayloadFileName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$FileName, [string]$ExpectedExtension)
    if ([string]::IsNullOrWhiteSpace($FileName) -or $FileName.Length -gt 240 -or
        $FileName -match '[\x00-\x1f<>:"/\\|?*]' -or $FileName -match '[. ]$' -or
        $FileName -in @('.','..') -or
        $FileName -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)' -or
        $FileName -match '^(?i:package[.](?:exe|msi|zip)|teams[.]msix)$' -or
        ($ExpectedExtension -and [IO.Path]::GetExtension($FileName) -ine $ExpectedExtension)) {
        throw [IO.InvalidDataException]::new("Invalid vendor payload filename '$FileName'.")
    }
    $FileName
}

function Resolve-OSDAppBuiltInPayloadPath {
    [CmdletBinding(DefaultParameterSetName='Exact')]
    param(
        [Parameter(Mandatory,ParameterSetName='Exact')][string]$Path,
        [Parameter(Mandatory,ParameterSetName='Cache')][string]$Root,
        [Parameter(ParameterSetName='Cache')][string]$ExpectedExtension
    )
    if ($PSCmdlet.ParameterSetName -eq 'Cache') {
        $info = Get-Content -LiteralPath (Join-Path $Root 'CacheInfo.json') -Raw -Encoding UTF8 -ErrorAction Stop |
            ConvertFrom-Json -ErrorAction Stop
        if (-not $info.PayloadFileName) {
            throw [IO.InvalidDataException]::new('CacheInfo.json must record PayloadFileName. Rebuild this cache.')
        }
        $leaf = Assert-OSDAppPayloadFileName -FileName ([string]$info.PayloadFileName) -ExpectedExtension $ExpectedExtension
        $Path = Join-Path $Root $leaf
    }
    else {
        Assert-OSDAppPayloadFileName -FileName (Split-Path -Path $Path -Leaf) | Out-Null
    }
    # A payload must not escape its owning directory through a reparse point.
    $probe = [IO.Path]::GetFullPath($Path)
    while ($probe) {
        if (Test-Path -LiteralPath $probe) {
            $item = Get-Item -LiteralPath $probe -Force -ErrorAction Stop
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw [IO.InvalidDataException]::new('Built-in payload links are not supported.')
            }
        }
        $parent = Split-Path -Path $probe -Parent
        if (-not $parent -or $parent -eq $probe) { break }
        $probe = $parent
    }
    $Path
}

function Test-OSDAppBuiltInPayload {
    [CmdletBinding()]
    param([AllowNull()][AllowEmptyString()][string]$Root, [string]$ExpectedExtension)
    if (-not $Root -or -not (Test-Path -LiteralPath (Join-Path $Root 'CacheInfo.json') -PathType Leaf)) { return $false }
    # Discovery is not the execution/commit gate. Old or unreadable metadata is
    # a cache miss so staging and refresh can acquire a new, validated generation.
    # Keep filesystem-link rejection outside the metadata compatibility catch.
    $infoPath = Resolve-OSDAppBuiltInPayloadPath -Path (Join-Path $Root 'CacheInfo.json')
    try {
        $info = Get-Content -LiteralPath $infoPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $info -or $info -is [array]) { throw 'Cache metadata must be one object.' }
        foreach ($field in @('PayloadFileName','Sha256','Size','Id','Architecture')) {
            if (-not $info.PSObject.Properties[$field] -or [string]::IsNullOrWhiteSpace([string]$info.$field)) {
                throw "Cache metadata lacks $field."
            }
        }
        $size = 0L
        if ([string]$info.Sha256 -notmatch '^[a-fA-F0-9]{64}$' -or
            -not [long]::TryParse([string]$info.Size,[ref]$size) -or $size -le 0) {
            throw 'Cache metadata has no supported hash and size record.'
        }
        $leaf = Assert-OSDAppPayloadFileName -FileName ([string]$info.PayloadFileName) -ExpectedExtension $ExpectedExtension
    }
    catch {
        Write-Verbose "Cache refresh required for '$Root': $($_.Exception.Message)"
        return $false
    }
    $path = Resolve-OSDAppBuiltInPayloadPath -Path (Join-Path $Root $leaf)
    Test-Path -LiteralPath $path -PathType Leaf
}

function Get-OSDAppDownloadFileName {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Response, [Parameter(Mandatory)][string]$ExpectedExtension)
    $disposition = $Response.Content.Headers.ContentDisposition
    $name = $null
    if ($disposition) {
        if ($disposition.FileNameStar) { $name = [string]$disposition.FileNameStar }
        elseif ($disposition.FileName) { $name = ([string]$disposition.FileName).Trim('"') }
    }
    if (-not $name) {
        # Read OriginalString: Framework may normalize invalid trailing dots.
        $rawPath = [regex]::Match([string]$Response.RequestMessage.RequestUri.OriginalString,
            '^[a-zA-Z][a-zA-Z0-9+.-]*://[^/?#]*(?<path>/[^?#]*)?').Groups['path'].Value
        $name = [uri]::UnescapeDataString(($rawPath -split '/')[-1])
    }
    try { Assert-OSDAppPayloadFileName -FileName $name -ExpectedExtension $ExpectedExtension }
    catch { throw [IO.InvalidDataException]::new("The vendor response did not provide a safe $ExpectedExtension filename.", $_.Exception) }
}

function Copy-OSDAppBuiltInPayload {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$DestinationDirectory)
    $source = Get-Item -LiteralPath (Resolve-OSDAppBuiltInPayloadPath -Path $Path) -ErrorAction Stop
    New-Item -ItemType Directory -Path $DestinationDirectory -Force -ErrorAction Stop | Out-Null
    $destination = Resolve-OSDAppBuiltInPayloadPath -Path (Join-Path $DestinationDirectory $source.Name)
    if ([IO.Path]::GetFullPath($source.FullName) -eq [IO.Path]::GetFullPath($destination)) { return }
    $temporary = Join-Path $DestinationDirectory ('.osdapps-copy-' + [guid]::NewGuid().ToString('N'))
    try {
        Copy-Item -LiteralPath $source.FullName -Destination $temporary -ErrorAction Stop
        if ((Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash -ne
            (Get-FileHash -LiteralPath $source.FullName -Algorithm SHA256).Hash) {
            throw [IO.InvalidDataException]::new('Staged payload copy failed SHA-256 validation.')
        }
        # Retire only the previously recorded payload, not arbitrary same-extension files.
        $previousPath = $null
        if (Test-OSDAppBuiltInPayload -Root $DestinationDirectory) {
            $previousPath = Resolve-OSDAppBuiltInPayloadPath -Root $DestinationDirectory
        }
        Move-Item -LiteralPath $temporary -Destination $destination -Force -ErrorAction Stop
        if ($previousPath -and $previousPath -ne $destination -and (Test-Path -LiteralPath $previousPath -PathType Leaf)) {
            Remove-Item -LiteralPath $previousPath -Force -ErrorAction Stop
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
    }
}

function Get-OSDAppBuiltInPayloadSpec {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$App)
    $architecture = [string]$App.Architecture
    $id = [string]$App.Id
    $relative = $null
    $extension = $null
    $field = 'Package'
    switch ([string]$App.Type) {
        'MicrosoftTeamsBootstrapper' {
            if ($id -ne 'MicrosoftTeams' -or $architecture -notin @('x86','x64','arm64')) { throw 'Invalid Teams payload identity.' }
            $relative = 'BuiltIn\MicrosoftTeams'; $extension = '.msix'; $field = 'OfflinePackage'
        }
        'AdobeAcrobatUnifiedZip' {
            if ($id -ne 'AdobeAcrobatUnified' -or $architecture -notin @('x86','x64')) { throw 'Invalid Adobe payload identity.' }
            $relative = 'BuiltIn\AdobeAcrobatUnified\' + $architecture; $extension = '.zip'
        }
        '7ZipExe' {
            if ($id -ne '7Zip' -or $architecture -notin @('x86','x64','arm64')) { throw 'Invalid 7Zip payload identity.' }
            $relative = 'BuiltIn\7Zip\' + $architecture; $extension = '.exe'
        }
        'VisualStudioCodeExe' {
            if ($id -ne 'VisualStudioCode' -or $architecture -notin @('x64','arm64')) { throw 'Invalid VS Code payload identity.' }
            $relative = 'BuiltIn\VisualStudioCode\' + $architecture; $extension = '.exe'
        }
        'PrerequisiteExe' {
            $spec = Get-OSDAppPrerequisiteSpec -Family $App.Family -Architecture $architecture -RuntimeType $App.RuntimeType -Channel $App.Channel
            if ($id -ne $spec.Id) { throw 'Invalid runtime payload identity.' }
            $relative = [string]$spec.RelativeRoot; $extension = '.exe'
        }
        'VendorMsi' {
            if ($id -eq 'CMTraceOpen') { return }
            switch ($id) {
                'GoogleChromeEnterprise' {
                    if ($architecture -notin @('x86','x64')) { throw 'Invalid Chrome architecture.' }
                }
                'MozillaFirefoxEnterprise' {
                    if ($architecture -notin @('x86','x64') -or [string]$App.Channel -notin @('Rapid','ESR') -or
                        [string]$App.Language -notmatch '^[a-zA-Z0-9-]+$') { throw 'Invalid Firefox payload variant.' }
                }
                { $_ -in @('CiscoWebex','ZoomWorkplace') } {
                    if ($architecture -notin @('x64','arm64')) { throw 'Invalid MSI architecture.' }
                }
                default { throw 'Unsupported vendor MSI identity.' }
            }
            $relative = if ($id -eq 'MozillaFirefoxEnterprise') {
                'BuiltIn\MozillaFirefoxEnterprise\' + [string]$App.Channel + '\' + $architecture + '\' + [string]$App.Language
            } else { 'BuiltIn\' + $id + '\' + $architecture }
            $extension = '.msi'
        }
        default { return }
    }
    [pscustomobject]@{ RelativeRoot=$relative; Extension=$extension; Field=$field }
}

function Set-OSDAppManifestPayload {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$App, [Parameter(Mandatory)][string]$StagedPath, [switch]$AllowPending)
    $spec = Get-OSDAppBuiltInPayloadSpec -App $App
    if (-not $spec) { return }
    $root = Join-Path $StagedPath $spec.RelativeRoot
    $relative = $null
    $hash = $null
    if (Test-OSDAppBuiltInPayload -Root $root -ExpectedExtension $spec.Extension) {
        $path = Resolve-OSDAppBuiltInPayloadPath -Root $root -ExpectedExtension $spec.Extension
        $info = Get-Content -LiteralPath (Join-Path $root 'CacheInfo.json') -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash
        if ([string]$info.Sha256 -notmatch '^[0-9a-fA-F]{64}$' -or $hash -ne [string]$info.Sha256 -or
            [long]$info.Size -le 0 -or (Get-Item -LiteralPath $path).Length -ne [long]$info.Size) {
            throw [IO.InvalidDataException]::new('Cached vendor payload hash or size is invalid.')
        }
        $expectedId = if ($App.Type -eq 'PrerequisiteExe') { [string]$App.Family } else { [string]$App.Id }
        if ([string]$info.Id -ne $expectedId -or [string]$info.Architecture -ne [string]$App.Architecture) {
            throw [IO.InvalidDataException]::new('Cached vendor payload identity does not match the selected app.')
        }
        $relative = Join-Path $spec.RelativeRoot ([string]$info.PayloadFileName)
    }
    elseif (-not $AllowPending) {
        throw [IO.FileNotFoundException]::new("Vendor payload is not ready for '$($App.Id)'.")
    }
    $App | Add-Member -NotePropertyName PayloadRoot -NotePropertyValue $spec.RelativeRoot -Force
    $App | Add-Member -NotePropertyName PayloadExtension -NotePropertyValue $spec.Extension -Force
    $App | Add-Member -NotePropertyName PayloadSha256 -NotePropertyValue $hash -Force
    $App | Add-Member -NotePropertyName $spec.Field -NotePropertyValue $relative -Force
}

function Assert-OSDAppManifestPayload {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$App, [Parameter(Mandatory)][string]$StagedPath)
    $spec = Get-OSDAppBuiltInPayloadSpec -App $App
    if (-not $spec) { throw 'App has no single-file vendor payload contract.' }
    if ([string]$App.PayloadRoot -ne $spec.RelativeRoot -or [string]$App.PayloadExtension -ne $spec.Extension) {
        throw [IO.InvalidDataException]::new('Vendor payload intent is invalid.')
    }
    $root = Join-Path $StagedPath $spec.RelativeRoot
    $expectedId = if ([string]$App.Type -eq 'PrerequisiteExe') { [string]$App.Family } else { [string]$App.Id }
    $path = Assert-OSDAppCachedPayload -Root $root -ExpectedExtension $spec.Extension -Id $expectedId -Architecture ([string]$App.Architecture)
    $expected = Join-Path $spec.RelativeRoot (Split-Path -Path $path -Leaf)
    if ([string]$App.($spec.Field) -cne $expected -or [string]$App.PayloadSha256 -notmatch '^[a-fA-F0-9]{64}$') {
        throw [IO.InvalidDataException]::new('Device manifest does not reference the exact recorded vendor filename and hash.')
    }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash -ne [string]$App.PayloadSha256) {
        throw [IO.InvalidDataException]::new('Staged vendor payload failed SHA-256 validation.')
    }
    $path
}

function Assert-OSDAppCachedPayload {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root, [string]$ExpectedExtension, [string]$Id, [string]$Architecture)
    $path = Resolve-OSDAppBuiltInPayloadPath -Root $Root -ExpectedExtension $ExpectedExtension
    $info = Get-Content -LiteralPath (Join-Path $Root 'CacheInfo.json') -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if (($Id -and [string]$info.Id -ne $Id) -or ($Architecture -and [string]$info.Architecture -ne $Architecture) -or
        [string]$info.Sha256 -notmatch '^[a-fA-F0-9]{64}$' -or [long]$info.Size -le 0) {
        throw [IO.InvalidDataException]::new('Vendor payload metadata is invalid or does not match the requested app.')
    }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw [IO.FileNotFoundException]::new("Vendor payload file is missing: $path") }
    if ((Get-Item -LiteralPath $path).Length -ne [long]$info.Size -or
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne [string]$info.Sha256) {
        throw [IO.InvalidDataException]::new('Vendor payload SHA-256 or size mismatch.')
    }
    $path
}

function Test-OSDAppCompanyPortalDefinition {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$App)
    if ([string]$App.Id -ne 'MicrosoftCompanyPortal' -or [string]$App.Type -ne 'CompanyPortalAppxBundle' -or
        [string]$App.PackageType -ne 'App' -or [string]$App.Architecture -notin @('x64','arm64') -or
        @($App.Dependencies).Count -ne 5 -or @($App.FileHashes).Count -ne 7) { return $false }
    $prefix = 'BuiltIn\MicrosoftCompanyPortal\' + [string]$App.Architecture + '\'
    $bundle = [string]$App.Package; $license = [string]$App.License
    if (-not $bundle.StartsWith($prefix,[StringComparison]::Ordinal) -or
        -not $license.StartsWith($prefix,[StringComparison]::Ordinal)) { return $false }
    if ($bundle.Substring($prefix.Length) -notmatch '^[A-Za-z0-9_-]+\.appxbundle$' -or
        $license.Substring($prefix.Length) -notmatch '^[A-Za-z0-9_-]+_License[0-9]+\.xml$') { return $false }
    $expected = @($bundle,$license) + @($App.Dependencies | ForEach-Object { [string]$_ })
    foreach ($dependency in @($App.Dependencies)) {
        if (-not ([string]$dependency).StartsWith($prefix + 'Dependencies\',[StringComparison]::Ordinal) -or
            ([string]$dependency).Substring(($prefix + 'Dependencies\').Length) -notmatch '^[A-Za-z0-9._-]+\.appx$') { return $false }
    }
    if (@($expected | Select-Object -Unique).Count -ne 7) { return $false }
    $actual = @($App.FileHashes | ForEach-Object { [string]$_.Path })
    if (@($actual | Select-Object -Unique).Count -ne 7 -or @($actual | Where-Object { $_ -cnotin $expected }).Count -gt 0) { return $false }
    foreach ($file in @($App.FileHashes)) {
        if ([string]$file.Sha256 -notmatch '^[a-fA-F0-9]{64}$') { return $false }
    }
    $true
}

function New-OSDAppCompanyPortalManifestEntry {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$CacheInfo, [Parameter(Mandatory)][ValidateSet('x64','arm64')][string]$Architecture)
    if ([string]$CacheInfo.Id -ne 'MicrosoftCompanyPortal' -or [string]$CacheInfo.Architecture -ne $Architecture -or
        [string]$CacheInfo.Version -notmatch '^\d+\.\d+\.\d+\.\d+$' -or
        @($CacheInfo.Files).Count -ne 7 -or [int]$CacheInfo.DependencyCount -ne 5) { throw 'Invalid Company Portal cache metadata.' }
    $bundle = Assert-OSDAppPayloadFileName -FileName ([string]$CacheInfo.PayloadFileName) -ExpectedExtension '.appxbundle'
    $license = Assert-OSDAppPayloadFileName -FileName ([string]$CacheInfo.LicenseFileName) -ExpectedExtension '.xml'
    $relativeRoot = 'BuiltIn\MicrosoftCompanyPortal\' + $Architecture
    $entry = [pscustomobject]@{
        Id='MicrosoftCompanyPortal';DisplayName='Microsoft Company Portal';Source='BuiltIn';PackageType='App';Type='CompanyPortalAppxBundle'
        Version=[string]$CacheInfo.Version;Architecture=$Architecture
        Package=(Join-Path $relativeRoot $bundle);License=(Join-Path $relativeRoot $license)
        Dependencies=@($CacheInfo.Files | Where-Object { [string]$_.Path -match '^Dependencies\\[A-Za-z0-9._-]+\.appx$' } | ForEach-Object { Join-Path $relativeRoot ([string]$_.Path) })
        FileHashes=@($CacheInfo.Files | ForEach-Object { [pscustomobject]@{Path=(Join-Path $relativeRoot ([string]$_.Path));Sha256=[string]$_.Sha256} })
    }
    if (-not (Test-OSDAppCompanyPortalDefinition -App $entry)) { throw [IO.InvalidDataException]::new('Company Portal cache does not contain exactly the recorded vendor bundle, license and five dependencies.') }
    $entry
}

function Assert-OSDAppCompanyPortalFiles {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$App, [Parameter(Mandatory)][string]$StagedPath)
    if (-not (Test-OSDAppCompanyPortalDefinition -App $App)) { throw [IO.InvalidDataException]::new('Invalid Company Portal manifest.') }
    foreach ($file in @($App.FileHashes)) {
        $path = Resolve-OSDAppBuiltInPayloadPath -Path (Join-Path $StagedPath ([string]$file.Path))
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
            (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne [string]$file.Sha256) {
            throw [IO.InvalidDataException]::new("Company Portal integrity validation failed: $($file.Path)")
        }
    }
}
