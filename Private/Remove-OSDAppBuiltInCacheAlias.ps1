function Remove-OSDAppBuiltInCacheAlias {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$CachePath,

        [Parameter(Mandatory)]
        [string]$CanonicalId,

        [Parameter(Mandatory)]
        [string[]]$Alias,

        [string]$LogPath
    )

    if ($CanonicalId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or
        $CanonicalId -match '\.\.') {
        throw "Invalid canonical built-in cache Id '$CanonicalId'."
    }

    $canonicalRoot = [IO.Path]::GetFullPath((Join-Path (Join-Path $CachePath 'BuiltIn') $CanonicalId))
    $canonicalEntries = @(
        Get-OSDAppCache -CachePath $CachePath |
            Where-Object {
                $_.Source -eq 'BuiltIn' -and
                $_.Id -ieq $CanonicalId -and
                [IO.Path]::GetFullPath([string]$_.CachePath) -ieq $canonicalRoot
            }
    )
    if ($canonicalEntries.Count -ne 1 -or -not $canonicalEntries[0].Valid) {
        throw "Canonical built-in cache '$CanonicalId' is not complete; renamed cache content was preserved."
    }

    $removed = [System.Collections.Generic.List[string]]::new()
    foreach ($aliasId in @($Alias | Select-Object -Unique)) {
        if ([string]::IsNullOrWhiteSpace([string]$aliasId) -or
            [string]$aliasId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or
            [string]$aliasId -match '\.\.' -or
            [string]$aliasId -ieq $CanonicalId) {
            throw "Invalid built-in cache alias '$aliasId' for '$CanonicalId'."
        }

        $aliasRoot = Join-Path (Join-Path $CachePath 'BuiltIn') $aliasId
        if (-not (Test-Path -LiteralPath $aliasRoot)) { continue }

        if ($PSCmdlet.ShouldProcess($aliasRoot, "Remove renamed built-in cache after validating '$CanonicalId'")) {
            Remove-Item -LiteralPath $aliasRoot -Recurse -Force -ErrorAction Stop
            $removed.Add([string]$aliasId)
            if ($LogPath) {
                Write-OSDAppLog -LogPath $LogPath -Component $CanonicalId -Event 'CacheAliasPruned' -Message 'Renamed built-in cache content was removed after canonical replacement validation.' -Data @{
                    Alias       = [string]$aliasId
                    CanonicalId = $CanonicalId
                    Path        = $aliasRoot
                }
            }
        }
    }

    @($removed)
}
