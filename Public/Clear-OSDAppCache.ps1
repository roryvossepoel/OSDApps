function Clear-OSDAppCache {
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'All')]
    param(
        [Parameter(ParameterSetName = 'All')]
        [switch]$All,

        [Parameter(Mandatory, ParameterSetName = 'Repository')]
        [switch]$Repository,

        [Parameter(Mandatory, ParameterSetName = 'BuiltIn')]
        [switch]$BuiltIn,

        [Parameter(Mandatory, ParameterSetName = 'Name')]
        [string[]]$Name,

        [switch]$IncludeLogs
    )

    $cachePath = Get-OSDAppCachePath
    $logPath = Join-Path $cachePath 'Logs\Client.log'
    $scope = $PSCmdlet.ParameterSetName

    if ($scope -eq 'All' -and -not $All) {
        $All = $true
    }

    if ($scope -eq 'Name') {
        foreach ($appName in @($Name)) {
            if ([string]::IsNullOrWhiteSpace([string]$appName) -or
                [string]$appName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or
                [string]$appName -match '\.\.') {
                throw "Invalid cache Id '$appName'."
            }
        }
    }

    $cacheLock = $null
    if (-not $WhatIfPreference) {
        $cacheLock = Enter-OSDAppCacheLock -CachePath $cachePath -Operation 'cache cleanup'
    }
    try {
    if (-not $WhatIfPreference) {
        Write-OSDAppLog -LogPath $logPath -Component 'Cache' -Event 'CacheClearStart' -Message 'Starting OSD App cache clear operation.' -Data @{
            Scope       = $scope
            Names       = @($Name)
            IncludeLogs = [bool]$IncludeLogs
            CachePath   = $cachePath
        }
    }

    $removed = [System.Collections.Generic.List[string]]::new()

    function Remove-CacheItem {
        param(
            [Parameter(Mandatory)]
            [string]$Path,

            [Parameter(Mandatory)]
            [string]$Label
        )

        if (-not (Test-Path -LiteralPath $Path)) {
            return
        }

        if ($PSCmdlet.ShouldProcess($Path, "Remove $Label")) {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            $stopwatch.Stop()

            if (-not $WhatIfPreference) {
                Write-OSDAppLog -LogPath $logPath -Component 'Cache' -Event 'CacheItemRemoved' -Message 'Cache item removed.' -Data @{
                    Label      = $Label
                    Path       = $Path
                    DurationMs = $stopwatch.ElapsedMilliseconds
                }
            }

            $removed.Add($Label)
        }
    }

    $manifestPath = Join-Path $cachePath 'CacheCatalog.json'
    $packagesPath = Join-Path $cachePath 'Packages'
    $builtInPath = Join-Path $cachePath 'BuiltIn'

    if ($All -or $Repository) {
        Remove-CacheItem -Path $packagesPath -Label 'Repository packages'
        Remove-CacheItem -Path $manifestPath -Label 'CacheCatalog.json'
    }

    if ($All -or $BuiltIn) {
        Remove-CacheItem -Path $builtInPath -Label 'Built-in cache'
    }

    if ($PSCmdlet.ParameterSetName -eq 'Name') {
        $manifest = $null

        if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
            try {
                $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
            }
            catch {
                throw "Failed to read cache catalog '$manifestPath': $($_.Exception.Message)"
            }
        }

        foreach ($appName in @($Name | Select-Object -Unique)) {
            # A name can be a current Id, a retired built-in Id, or an
            # organization repository Id. Remove exact matches from both
            # namespaces so renamed entries such as BuiltIn\Teams remain
            # explicitly cleanable without a hard-coded command list.
            Remove-CacheItem -Path (Join-Path $builtInPath $appName) -Label "Built-in app '$appName'"
            Remove-CacheItem -Path (Join-Path $packagesPath $appName) -Label "Repository app '$appName'"

            if ($manifest -and $manifest.PSObject.Properties.Name -contains 'Packages') {
                $remainingPackages = @($manifest.Packages | Where-Object { $_.Id -ne $appName })

                if (@($remainingPackages).Count -ne @($manifest.Packages).Count) {
                    $manifest.Packages = $remainingPackages

                    if ($PSCmdlet.ShouldProcess($manifestPath, "Remove '$appName' from CacheCatalog.json")) {
                        $manifest | ConvertTo-Json -Depth 20 |
                            Set-Content -LiteralPath $manifestPath -Encoding UTF8
                        $removed.Add("Cache catalog entry '$appName'")
                    }
                }
            }
        }
    }

    if ($IncludeLogs) {
        $logsPath = Join-Path $cachePath 'Logs'

        if ($PSCmdlet.ShouldProcess($logsPath, 'Clear OSD App client logs')) {
            if (Test-Path -LiteralPath $logsPath) {
                Get-ChildItem -LiteralPath $logsPath -File -ErrorAction SilentlyContinue |
                    Remove-Item -Force -ErrorAction Stop
            }

            Write-OSDAppLog -LogPath $logPath -Component 'Cache' -Event 'CacheLogsCleared' -Message 'OSD App client logs were cleared by request.' -Data @{
                Scope     = $scope
                Names     = @($Name)
                CachePath = $cachePath
            }
        }
    }

    if (-not $WhatIfPreference) {
        Write-OSDAppLog -LogPath $logPath -Component 'Cache' -Event 'CacheClearComplete' -Message 'OSD App cache clear operation completed.' -Data @{
            Scope       = $scope
            Names       = @($Name)
            IncludeLogs = [bool]$IncludeLogs
            Removed     = @($removed)
            CachePath   = $cachePath
        }
    }

    [pscustomobject]@{
        PSTypeName  = 'OSDApps.CacheClearResult'
        CachePath   = $cachePath
        Scope       = $scope
        Names       = @($Name)
        IncludeLogs = [bool]$IncludeLogs
        Removed     = @($removed)
    }
    }
    finally { if ($cacheLock) { $cacheLock.Dispose() } }
}
