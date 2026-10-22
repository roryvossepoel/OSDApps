function Test-OSDAppBuiltInCacheGeneration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string[]]$RequiredFile,
        [switch]$ValidateZip
    )

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        throw "Built-in cache generation '$Id' is missing: $Root"
    }

    $cacheInfoPath = Join-Path $Root 'CacheInfo.json'
    if (-not (Test-Path -LiteralPath $cacheInfoPath -PathType Leaf)) {
        throw "Built-in cache generation '$Id' is missing CacheInfo.json."
    }

    try {
        $cacheInfo = Get-Content -LiteralPath $cacheInfoPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        throw "Built-in cache generation '$Id' contains unreadable CacheInfo.json. $($_.Exception.Message)"
    }

    if ([string]$cacheInfo.Id -ne $Id -or -not $cacheInfo.Cached) {
        throw "Built-in cache generation '$Id' has inconsistent cache metadata."
    }

    foreach ($relativePath in $RequiredFile) {
        $path = (Resolve-OSDAppBuiltInPayloadPath -Path (Join-Path $Root $relativePath))
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Built-in cache generation '$Id' is missing required file '$relativePath'."
        }
        if ((Get-Item -LiteralPath $path).Length -le 0) {
            throw "Built-in cache generation '$Id' contains empty required file '$relativePath'."
        }
    }

    if ($ValidateZip) {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        $zipPath = (Resolve-OSDAppBuiltInPayloadPath -Path (Join-Path $Root $RequiredFile[0]))
        $archive = $null
        try {
            $archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
            if ($archive.Entries.Count -eq 0) {
                throw "Built-in cache generation '$Id' contains an empty ZIP archive."
            }
        }
        catch {
            throw "Built-in cache generation '$Id' contains an unreadable ZIP archive. $($_.Exception.Message)"
        }
        finally {
            if ($archive) { $archive.Dispose() }
        }
    }

    [pscustomobject]@{
        Id           = $Id
        Root         = $Root
        CacheInfo    = $cacheInfo
        RequiredFile = @($RequiredFile)
        Valid        = $true
    }
}
