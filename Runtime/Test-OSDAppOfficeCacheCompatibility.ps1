# Shared by WinPE staging and the standalone Windows PreInstall runtime.
function Get-OSDAppOfficePayloadProfile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $settings = [System.Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $document = [System.Xml.XmlDocument]::new()
    $document.XmlResolver = $null
    $reader = [System.Xml.XmlReader]::Create($Path, $settings)
    try { $document.Load($reader) } finally { $reader.Dispose() }
    $adds = @($document.SelectNodes('/Configuration/Add'))
    if ($adds.Count -ne 1) { throw 'Office payload comparison requires exactly one Add element.' }
    $add = $adds[0]
    $edition = $add.GetAttribute('OfficeClientEdition')
    $architecture = switch ($edition) { '64' { 'x64' } '32' { 'x86' } default { '' } }
    $channel = $add.GetAttribute('Channel')
    $version = $add.GetAttribute('Version')
    $products = @($add.SelectNodes('Product'))
    $languages = @($add.SelectNodes('Product/Language'))
    $static = ($architecture -ne '' -and $channel -ne '' -and $products.Count -gt 0 -and $languages.Count -gt 0)
    foreach ($product in $products) {
        if (-not $product.GetAttribute('ID') -or $product.HasAttribute('MSICondition') -or @($product.SelectNodes('Language')).Count -eq 0) { $static = $false }
    }
    foreach ($language in $languages) {
        if ($language.GetAttribute('ID') -notmatch '^[a-z]{2,3}-[a-z0-9]{2,4}$') { $static = $false }
    }
    if ($version -and $version -notmatch '^\d+\.\d+\.\d+\.\d+$') { $static = $false }

    # Compare the entire Add subtree conservatively. SourcePath is managed by
    # OSDApps; an explicit version is checked against the actual cached build.
    # Installation-only settings outside Add (licensing, updates, display) do
    # not change the downloaded payload. Unknown Add settings remain included.
    function ConvertTo-OfficePayloadNode {
        param([System.Xml.XmlElement]$Node)
        $attributes = @(
            foreach ($attribute in @($Node.Attributes | Sort-Object Name)) {
                if ($Node.Name -eq 'Add' -and $attribute.Name -in @('SourcePath','Version')) { continue }
                $value = $attribute.Value
                if (($Node.Name -eq 'Add' -and $attribute.Name -eq 'Channel') -or
                    ($Node.Name -in @('Product','Language','ExcludeApp') -and $attribute.Name -eq 'ID')) {
                    $value = $value.ToLowerInvariant()
                }
                @($attribute.Name, $value) -join '='
            }
        )
        $children = @(
            foreach ($child in $Node.ChildNodes) {
                if ($child -is [System.Xml.XmlElement]) { ConvertTo-OfficePayloadNode -Node $child }
                elseif ($child -is [System.Xml.XmlText] -or $child -is [System.Xml.XmlCDataSection]) { $child.Value }
            }
        )
        # Preserve element order: unsupported custom constructs must never be
        # treated as equivalent merely because their values can be sorted.
        [ordered]@{ Name=$Node.Name; Attributes=$attributes; Children=$children } | ConvertTo-Json -Depth 50 -Compress
    }
    $canonical = ConvertTo-OfficePayloadNode -Node $add
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $key = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($canonical)))).Replace('-', '') }
    finally { $sha.Dispose() }
    [pscustomobject]@{
        SchemaVersion = 1
        Architecture = $architecture
        Channel = $channel
        Version = $version
        Products = @($products | ForEach-Object { $_.GetAttribute('ID') })
        Languages = @($languages | ForEach-Object { $_.GetAttribute('ID') })
        CustomDownloadSource = $add.HasAttribute('DownloadPath')
        Static = [bool]$static
        PayloadKey = $key
    }
}

function Test-OSDAppOfficeCacheCompatibility {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$OfficeRoot,
        [Parameter(Mandatory)][string]$ConfigurationPath,
        [switch]$AllowLegacyConfiguration
    )
    $reasons = [System.Collections.Generic.List[string]]::new()
    $cached = $null
    try {
        $requested = Get-OSDAppOfficePayloadProfile -Path $ConfigurationPath
        $info = Get-Content -LiteralPath (Join-Path $OfficeRoot 'CacheInfo.json') -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
        $profileProperty = $info.PSObject.Properties['PayloadProfile']
        if ($profileProperty) { $cached = $profileProperty.Value }
        elseif ($AllowLegacyConfiguration) {
            # Only the untouched USB cache XML may describe a legacy payload.
            # The staged XML is deployment intent and may have been replaced.
            $cached = Get-OSDAppOfficePayloadProfile -Path (Join-Path $OfficeRoot 'configuration.xml')
        }
        if (-not $cached -or $cached.SchemaVersion -ne 1) { throw 'Office cache has no supported payload configuration record.' }
        if (-not $requested.Static -or -not $cached.Static) { $reasons.Add('Dynamic or implicit Office configuration cannot be proven compatible for fallback.') }
        if ($requested.Architecture -ne $cached.Architecture) { $reasons.Add('Office architecture differs.') }
        if ($requested.Channel -ne $cached.Channel) { $reasons.Add('Office channel differs.') }
        if (($requested.Products -join ',') -ne ($cached.Products -join ',')) { $reasons.Add('Office products or their order differ.') }
        if (($requested.Languages -join ',') -ne ($cached.Languages -join ',')) { $reasons.Add('Office languages or their order differ.') }
        if ($requested.Version -and $requested.Version -ne [string]$info.Version) { $reasons.Add('The requested Office version is not the cached version.') }
        if ($requested.PayloadKey -cne $cached.PayloadKey) { $reasons.Add('Office download settings differ; a fresh acquisition is required.') }
        if ([string]$info.Architecture -ne [string]$cached.Architecture) { $reasons.Add('Office cache architecture metadata is inconsistent.') }
    }
    catch {
        # Do not include XML values, paths or licensing keys in diagnostics.
        $reasons.Add('Office payload configuration could not be verified. Refresh the cache for this configuration.')
    }
    [pscustomobject]@{ Compatible=($reasons.Count -eq 0); Reasons=@($reasons); CachedProfile=$cached }
}

# Read only the selected architecture's advertised build. Available/@Build can
# refer to an old Windows release even when I640Version advertises a current build.
function Get-OSDAppOfficeDescriptorVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][ValidateSet('x64','x86')][string]$Architecture,
        [Parameter(Mandatory)][string]$ChannelId
    )
    $settings = [System.Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $settings.MaxCharactersInDocument = 1MB
    $document = [System.Xml.XmlDocument]::new()
    $document.XmlResolver = $null
    $reader = [System.Xml.XmlReader]::Create($Path, $settings)
    try { $document.Load($reader) } finally { $reader.Dispose() }
    $available = @($document.SelectNodes('/Version/Available'))
    $delivery = @($document.SelectNodes('/Version/DeliveryMechanism'))
    if ($available.Count -ne 1 -or $delivery.Count -ne 1 -or
        $delivery[0].GetAttribute('FFNRoot') -ne $ChannelId) {
        throw 'Office CDN descriptor has an ambiguous version or unexpected channel.'
    }
    $attribute = if ($Architecture -eq 'x86') { 'I320Version' } else { 'I640Version' }
    $build = $available[0].GetAttribute($attribute)
    if ($build -notmatch '^\d+\.\d+\.\d+\.\d+$') {
        throw 'Office CDN descriptor does not advertise a concrete build for the requested architecture.'
    }
    $defaults = @($document.SelectNodes('/Version/AvailableBuilds/AvailableBuild[@RestrictionType="Default"]'))
    if ($defaults.Count -gt 1 -or ($defaults.Count -eq 1 -and $defaults[0].GetAttribute('Version') -ne $build)) {
        throw 'Office CDN descriptor advertises conflicting default and architecture builds.'
    }
    return $build
}

function Expand-OSDAppOfficeDescriptor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CabPath,
        [Parameter(Mandatory)][string]$DestinationPath
    )
    $expand = Join-Path $env:SystemRoot 'System32\expand.exe'
    $extractedPath = Join-Path $DestinationPath 'Extracted'
    New-Item -ItemType Directory -Path $extractedPath -ErrorAction Stop | Out-Null
    # -R preserves the archived XML name even for a single-file cabinet.
    $arguments = '-R "{0}" -F:VersionDescriptor.xml "{1}"' -f $CabPath,$extractedPath
    # Own the process handle directly: Start-Process -NoNewWindow can lose
    # ExitCode on Windows PowerShell 5.1 after a bounded WaitForExit call.
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $expand
    $startInfo.Arguments = $arguments
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $process = [System.Diagnostics.Process]::Start($startInfo)
    try {
        if (-not $process.WaitForExit(10000)) {
            try { $process.Kill() } catch { Write-Verbose 'Office descriptor expansion could not be terminated.' }
            throw 'Office descriptor expansion exceeded its 10 second timeout.'
        }
        if ($process.ExitCode -ne 0) { throw ('Office CDN version descriptor extraction failed with exit code {0}.' -f $process.ExitCode) }
        $xmlPath = Join-Path $extractedPath 'VersionDescriptor.xml'
        if (-not (Test-Path -LiteralPath $xmlPath -PathType Leaf)) { throw 'Office CDN version descriptor XML is missing.' }
        return $xmlPath
    }
    finally { $process.Dispose() }
}

# Freshness only: callers must separately validate the generation and installer.
# Never write a CDN descriptor into the active cache or repair individual CABs.
function Test-OSDAppOfficeCacheCurrent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$OfficeRoot,
        [Parameter(Mandatory)][string]$ConfigurationPath
    )
    $compatibility = Test-OSDAppOfficeCacheCompatibility -OfficeRoot $OfficeRoot -ConfigurationPath $ConfigurationPath
    if (-not $compatibility.Compatible) { return $false }
    $payloadProfile = Get-OSDAppOfficePayloadProfile -Path $ConfigurationPath
    if ($payloadProfile.CustomDownloadSource) { return $false }
    # Compatibility already proved that an explicit build pin matches the cache.
    if ($payloadProfile.Version -match '^\d+\.\d+\.\d+\.\d+$') { return $true }

    $channels = @{
        Current = '492350f6-3a01-4f97-b9c0-c7c6ddf67d60'
        MonthlyEnterprise = '55336b82-a18d-4dd6-b5f6-9e5095c314a6'
        SemiAnnual = '7ffbc6bf-bc32-4f92-8982-f9dd17fd3114'
        CurrentPreview = '64256afe-f5d9-4f86-8936-8840a6a4f5be'
        SemiAnnualPreview = 'b8f9b850-328d-4355-9145-c59439a0c4cf'
        BetaChannel = '5440fd1f-7ecb-4221-8110-145efaa6372f'
    }
    if (-not $channels.ContainsKey($payloadProfile.Channel)) { return $false }
    $cabName = if ($payloadProfile.Architecture -eq 'x86') { 'v32.cab' } else { 'v64.cab' }
    $cachedCab = Join-Path (Join-Path $OfficeRoot 'Office\Data') $cabName
    if (-not (Test-Path -LiteralPath $cachedCab -PathType Leaf)) { return $false }
    $probeRoot = Join-Path ([IO.Path]::GetTempPath()) ("OSDApps-OfficeFreshness-{0}" -f [guid]::NewGuid().ToString('N'))
    $probe = Join-Path $probeRoot $cabName
    try {
        New-Item -ItemType Directory -Path $probeRoot -ErrorAction Stop | Out-Null
        $uri = 'https://officecdn.microsoft.com/pr/{0}/Office/Data/{1}' -f $channels[$payloadProfile.Channel],$cabName
        Invoke-WebRequest -Uri $uri -OutFile $probe -UseBasicParsing -TimeoutSec 30 -Headers @{ 'Cache-Control'='no-cache' } -ErrorAction Stop | Out-Null
        if ((Get-Item -LiteralPath $probe).Length -eq 0) { throw 'Office CDN returned an empty version descriptor.' }
        if ((Get-Item -LiteralPath $probe).Length -gt 1MB) { throw 'Office CDN version descriptor exceeds the supported size.' }
        $descriptorPath = Expand-OSDAppOfficeDescriptor -CabPath $probe -DestinationPath $probeRoot
        $advertisedVersion = Get-OSDAppOfficeDescriptorVersion -Path $descriptorPath -Architecture $payloadProfile.Architecture -ChannelId $channels[$payloadProfile.Channel]
        $cacheInfo = Get-Content -LiteralPath (Join-Path $OfficeRoot 'CacheInfo.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        Write-Verbose ("Office advertised build: {0}; cached build: {1}." -f $advertisedVersion,$cacheInfo.Version)
        return ($advertisedVersion -eq [string]$cacheInfo.Version)
    }
    finally {
        if (Test-Path -LiteralPath $probeRoot) { Remove-Item -LiteralPath $probeRoot -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
