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
