function Get-OSDStageRemoteFileMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [uri]$Uri
    )

    Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue

    $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.AllowAutoRedirect = $true
    $client = New-Object System.Net.Http.HttpClient($handler)

    try {
        $response = $client.GetAsync($Uri, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        $response.EnsureSuccessStatusCode()

        $etag = $null
        if ($response.Headers.ETag) {
            $etag = [string]$response.Headers.ETag.Tag
        }

        $lastModified = $null
        if ($response.Content.Headers.LastModified) {
            $lastModified = $response.Content.Headers.LastModified.UtcDateTime.ToString('o')
        }

        $contentLength = $null
        if ($response.Content.Headers.ContentLength) {
            $contentLength = [int64]$response.Content.Headers.ContentLength
        }

        [pscustomobject]@{
            Uri           = [string]$Uri
            FinalUri      = [string]$response.RequestMessage.RequestUri.AbsoluteUri
            ETag          = $etag
            LastModified  = $lastModified
            ContentLength = $contentLength
        }
    }
    finally {
        if ($response) { $response.Dispose() }
        $client.Dispose()
        $handler.Dispose()
    }
}
