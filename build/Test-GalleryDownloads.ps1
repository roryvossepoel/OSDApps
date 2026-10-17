$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/Update-GalleryDownloads.ps1"

function Get-TestFeed {
    param([string]$Version, [string]$Count, [string]$Next = '')
    $link = if ($Next) { '<link rel="next" href="' + $Next + '"/>' } else { '' }
    @"
<feed xmlns="http://www.w3.org/2005/Atom" xmlns:m="http://schemas.microsoft.com/ado/2007/08/dataservices/metadata" xmlns:d="http://schemas.microsoft.com/ado/2007/08/dataservices">
$link<entry><m:properties><d:Id>OSDApps</d:Id><d:Version>$Version</d:Version><d:DownloadCount>0</d:DownloadCount><d:VersionDownloadCount>$Count</d:VersionDownloadCount></m:properties></entry></feed>
"@
}

$result = Get-GalleryDownloadTotal -FetchPage {
    param($Uri)
    if ($Uri.Query -eq '?page=2') { Get-TestFeed '2.0.0' '7' }
    else { Get-TestFeed '1.0.0' '11' '?page=2' }
}
if ($result.Downloads -ne 18 -or $result.Versions -ne 2) { throw 'Pagination total failed.' }

foreach ($case in @('FailedSecondPage', 'InvalidCount', 'DuplicateVersion', 'RepeatedPage', 'EmptyFeed')) {
    $rejected = $false
    try {
        $null = Get-GalleryDownloadTotal -FetchPage {
            param($Uri)
            switch ($case) {
                'FailedSecondPage' {
                    if ($Uri.Query -eq '?page=2') { throw 'Simulated network failure.' }
                    Get-TestFeed '1.0.0' '11' '?page=2'
                }
                'InvalidCount' { Get-TestFeed '1.0.0' 'invalid' }
                'DuplicateVersion' {
                    if ($Uri.Query -eq '?page=2') { Get-TestFeed '1.0.0' '11' }
                    else { Get-TestFeed '1.0.0' '11' '?page=2' }
                }
                'RepeatedPage' {
                    if ($Uri.Query -eq '?page=2') { Get-TestFeed '2.0.0' '7' '?page=2' }
                    else { Get-TestFeed '1.0.0' '11' '?page=2' }
                }
                'EmptyFeed' { '<feed xmlns="http://www.w3.org/2005/Atom"/>' }
            }
        }
    } catch { $rejected = $true }
    if (-not $rejected) { throw "Invalid statistics accepted: $case" }
}
Write-Host 'Gallery statistics tests passed: paginated total and five failure cases.'
