function Test-OSDStageBuiltInCacheGeneration {
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

    if ($Id -ne 'Microsoft365Apps') {
        $payload = Resolve-OSDStageBuiltInPayloadPath -Root $Root
        if ([string]$cacheInfo.Sha256 -notmatch '^[a-fA-F0-9]{64}$' -or
            [long]$cacheInfo.Size -le 0 -or (Get-Item -LiteralPath $payload -ErrorAction Stop).Length -ne [long]$cacheInfo.Size -or
            (Get-FileHash -LiteralPath $payload -Algorithm SHA256).Hash -ne [string]$cacheInfo.Sha256) {
            throw [IO.InvalidDataException]::new("Built-in cache generation '$Id' failed payload SHA-256 or size validation.")
        }
    }

    foreach ($relativePath in $RequiredFile) {
        $path = (Resolve-OSDStageBuiltInPayloadPath -Path (Join-Path $Root $relativePath))
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Built-in cache generation '$Id' is missing required file '$relativePath'."
        }
        if ((Get-Item -LiteralPath $path).Length -le 0) {
            throw "Built-in cache generation '$Id' contains empty required file '$relativePath'."
        }
    }

    if ($ValidateZip) {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        $zipPath = (Resolve-OSDStageBuiltInPayloadPath -Path (Join-Path $Root $RequiredFile[0]))
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
