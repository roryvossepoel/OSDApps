[CmdletBinding()]
param([string]$OutputPath)

$ErrorActionPreference = 'Stop'

function Get-GalleryDownloadTotal {
    [CmdletBinding()]
    param(
        [scriptblock]$FetchPage = {
            param($Uri)
            (Invoke-WebRequest -Uri $Uri -UseBasicParsing -TimeoutSec 60).Content
        }
    )

    $uri = [uri]"https://www.powershellgallery.com/api/v2/FindPackagesById()?id='OSDApps'"
    $pages = [System.Collections.Generic.HashSet[string]]::new()
    $versions = [System.Collections.Generic.HashSet[string]]::new()
    [long]$total = 0
    while ($null -ne $uri) {
        if ($uri.Scheme -ne 'https' -or $uri.Host -ne 'www.powershellgallery.com') {
            throw 'Unexpected Gallery pagination host.'
        }
        if (-not $pages.Add($uri.AbsoluteUri)) { throw 'Repeated Gallery page.' }
        [xml]$feed = & $FetchPage $uri
        $ns = [System.Xml.XmlNamespaceManager]::new($feed.NameTable)
        $ns.AddNamespace('a', 'http://www.w3.org/2005/Atom')
        $ns.AddNamespace('m', 'http://schemas.microsoft.com/ado/2007/08/dataservices/metadata')
        $ns.AddNamespace('d', 'http://schemas.microsoft.com/ado/2007/08/dataservices')
        $entries = @($feed.SelectNodes('/a:feed/a:entry', $ns))
        if ($entries.Count -eq 0) { throw 'Gallery page contains no versions.' }
        foreach ($entry in $entries) {
            $properties = $entry.SelectSingleNode('m:properties | a:content/m:properties', $ns)
            if ($null -eq $properties) { throw 'Missing Gallery properties.' }
            $id = $properties.SelectSingleNode('d:Id', $ns)
            $version = $properties.SelectSingleNode('d:Version', $ns)
            $count = $properties.SelectSingleNode('d:VersionDownloadCount', $ns)
            [long]$downloads = 0
            if ($null -eq $id -or $id.InnerText -ne 'OSDApps' -or
                $null -eq $version -or [string]::IsNullOrWhiteSpace($version.InnerText) -or
                $null -eq $count -or -not [long]::TryParse($count.InnerText, [ref]$downloads) -or $downloads -lt 0) {
                throw 'Invalid Gallery version statistics.'
            }
            if (-not $versions.Add($version.InnerText)) { throw 'Duplicate Gallery version.' }
            $total += $downloads
        }
        $next = @($feed.SelectNodes('/a:feed/a:link[@rel="next"]', $ns))
        if ($next.Count -gt 1) { throw 'Ambiguous Gallery pagination.' }
        $uri = if ($next.Count -eq 1) {
            $href = $next[0].GetAttribute('href')
            if ([string]::IsNullOrWhiteSpace($href)) { throw 'Empty Gallery next link.' }
            [uri]::new($uri, $href)
        } else { $null }
    }
    [pscustomobject]@{ Downloads = $total; Versions = $versions.Count }
}

# Dot-source without OutputPath to exercise pagination and failure handling in tests.
if ($OutputPath) {
    $statistics = Get-GalleryDownloadTotal
    $count = $statistics.Downloads.ToString([Globalization.CultureInfo]::InvariantCulture)
    $valueWidth = 20 + 8 * $count.Length
    $width = 82 + $valueWidth
    $valueCenter = 82 + $valueWidth / 2
    $svg = @"
<svg xmlns="http://www.w3.org/2000/svg" width="$width" height="20" role="img" aria-label="Downloads: $count">
  <title>Downloads: $count</title>
  <desc>Sum of VersionDownloadCount across $($statistics.Versions) PowerShell Gallery versions of OSDApps. Updated daily by GitHub Actions; retained on retrieval failure.</desc>
  <clipPath id="rounded"><rect width="$width" height="20" rx="3"/></clipPath>
  <g clip-path="url(#rounded)"><rect width="82" height="20" fill="#555"/><rect x="82" width="$valueWidth" height="20" fill="#007ec6"/></g>
  <g fill="#fff" text-anchor="middle" font-family="Verdana,Arial,sans-serif" font-size="11"><text x="41" y="14">Downloads</text><text x="$valueCenter" y="14">$count</text></g>
</svg>
"@
    # Retrieve and validate every page before touching the previous badge.
    $fullPath = [IO.Path]::GetFullPath($OutputPath)
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($fullPath)) | Out-Null
    [IO.File]::WriteAllText($fullPath, $svg + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    $statistics | Format-List
}
