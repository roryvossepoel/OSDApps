Describe 'Desired-state cache health' {
    BeforeAll {
        $script:moduleRoot = Split-Path -Parent $PSScriptRoot
        Remove-Module OSDApps -Force -ErrorAction SilentlyContinue
        Import-Module (Join-Path $script:moduleRoot 'OSDApps.psd1') -Force

        function global:New-CacheHealthRepository {
            param(
                [Parameter(Mandatory)][string]$Root,
                [Parameter(Mandatory)][object[]]$Application
            )

            $catalogApplications = @()
            foreach ($definition in $Application) {
                $id = [string]$definition.Id
                $version = [string]$definition.Version
                $packageRoot = Join-Path $Root "Apps\$id\$version\x64"
                New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null
                $archivePath = Join-Path $packageRoot 'Package.zip'
                Set-Content -LiteralPath $archivePath -Value "repository-$id-$version" -Encoding ASCII
                $hash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
                @{
                    SchemaVersion=1; Id=$id; DisplayName=$id; Version=$version
                    Architecture='x64'; SuccessCodes=@(0,3010)
                    Archive=@{FileName='Package.zip';Sha256=$hash}
                } | ConvertTo-Json -Depth 10 |
                    Set-Content -LiteralPath (Join-Path $packageRoot 'manifest.json') -Encoding UTF8

                $catalogApplication = [ordered]@{
                    Id=$id
                    Packages=@(@{Architecture='x64';Manifest="Apps/$id/$version/x64/manifest.json"})
                }
                if ($definition.PSObject.Properties.Name -contains 'Aliases') {
                    $catalogApplication['Aliases'] = @($definition.Aliases)
                }
                $catalogApplications += [pscustomobject]$catalogApplication
            }

            $catalogPath = Join-Path $Root 'catalog.json'
            @{
                SchemaVersion=1
                GeneratedAt='2026-10-13T00:00:00Z'
                Applications=$catalogApplications
            } | ConvertTo-Json -Depth 20 |
                Set-Content -LiteralPath $catalogPath -Encoding UTF8
            $catalogPath
        }

        function global:Add-CacheHealthPackage {
            param(
                [Parameter(Mandatory)][string]$CachePath,
                [Parameter(Mandatory)][string]$Id,
                [Parameter(Mandatory)][string]$Version,
                [string[]]$Aliases
            )

            $root = Join-Path $CachePath "Packages\$Id"
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            $archivePath = Join-Path $root 'Package.zip'
            Set-Content -LiteralPath $archivePath -Value "cache-$Id-$Version" -Encoding ASCII
            $entry = [ordered]@{
                Id=$Id; DisplayName=$Id; Version=$Version; Architecture='x64'
                SuccessCodes=@(0,3010)
                Archive=@{FileName='Package.zip';Sha256=(Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash}
            }
            if ($Aliases) { $entry['Aliases'] = @($Aliases) }
            [pscustomobject]$entry
        }
    }

    AfterAll {
        Remove-Item Function:\New-CacheHealthRepository -ErrorAction SilentlyContinue
        Remove-Item Function:\Add-CacheHealthPackage -ErrorAction SilentlyContinue
    }

    It 'treats a valid locally cataloged package as active during an offline inspection' {
        $cache = Join-Path $TestDrive 'OfflineCache'
        $package = Add-CacheHealthPackage -CachePath $cache -Id AppA -Version 1.0.0
        @{
            SchemaVersion=1; GeneratedAt='2026-10-13T00:00:00Z'; Packages=@($package)
        } | ConvertTo-Json -Depth 20 |
            Set-Content -LiteralPath (Join-Path $cache 'CacheCatalog.json') -Encoding UTF8

        $health = Get-OSDAppCacheHealth -CachePath $cache -Offline

        $health.CacheAvailable | Should -BeTrue
        $health.DesiredStateAvailable | Should -BeFalse
        $health.Healthy | Should -BeTrue
        $health.ActiveCount | Should -Be 1
        $health.Entries[0].State | Should -Be 'Active'
        $health.Entries[0].Integrity | Should -Be 'Valid'
    }

    It 'classifies desired, renamed, obsolete, orphaned and incomplete repository content' {
        $repository = Join-Path $TestDrive 'DesiredRepository'
        $catalogPath = New-CacheHealthRepository -Root $repository -Application @(
            [pscustomobject]@{Id='CurrentApp';Version='2.0.0'},
            [pscustomobject]@{Id='NewApp';Version='2.0.0';Aliases=@('OldApp')}
        )
        $cache = Join-Path $TestDrive 'MixedCache'
        $current = Add-CacheHealthPackage -CachePath $cache -Id CurrentApp -Version 2.0.0
        $old = Add-CacheHealthPackage -CachePath $cache -Id OldApp -Version 1.0.0
        $gone = Add-CacheHealthPackage -CachePath $cache -Id GoneApp -Version 1.0.0

        # Make CurrentApp byte-identical to its desired archive and metadata.
        Copy-Item -LiteralPath (Join-Path $repository 'Apps\CurrentApp\2.0.0\x64\Package.zip') `
            -Destination (Join-Path $cache 'Packages\CurrentApp\Package.zip') -Force
        $current.Archive.Sha256 = (Get-FileHash -LiteralPath (Join-Path $cache 'Packages\CurrentApp\Package.zip') -Algorithm SHA256).Hash
        New-Item -ItemType Directory -Path (Join-Path $cache 'Packages\LooseFolder') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $cache 'Packages\LooseFolder\Package.zip') -Value 'unregistered' -Encoding ASCII
        @{
            SchemaVersion=1; GeneratedAt='2026-10-13T00:00:00Z'; Packages=@($current,$old,$gone)
        } | ConvertTo-Json -Depth 20 |
            Set-Content -LiteralPath (Join-Path $cache 'CacheCatalog.json') -Encoding UTF8

        $health = Get-OSDAppCacheHealth -CachePath $cache -CatalogPath $catalogPath
        $byId = @{}
        foreach ($entry in @($health.Entries | Where-Object Source -eq 'Repository')) { $byId[$entry.Id] = $entry }

        $byId.CurrentApp.State | Should -Be 'Active'
        $byId.OldApp.State | Should -Be 'Renamed'
        $byId.OldApp.CanonicalId | Should -Be 'NewApp'
        $byId.GoneApp.State | Should -Be 'Obsolete'
        $byId.LooseFolder.State | Should -Be 'Orphaned'
        $byId.NewApp.State | Should -Be 'Incomplete'
        $health.Healthy | Should -BeFalse
        $health.RenamedCount | Should -Be 1
        $health.ObsoleteCount | Should -Be 1
        $health.OrphanedCount | Should -Be 1
        $health.IncompleteCount | Should -Be 1
    }

    It 'reports a hash mismatch as corrupt even when the package is pinned' {
        $cache = Join-Path $TestDrive 'CorruptPinnedCache'
        $package = Add-CacheHealthPackage -CachePath $cache -Id PinnedApp -Version 1.0.0
        @{
            SchemaVersion=1; GeneratedAt='2026-10-13T00:00:00Z'; Packages=@($package)
        } | ConvertTo-Json -Depth 20 |
            Set-Content -LiteralPath (Join-Path $cache 'CacheCatalog.json') -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $cache 'Packages\PinnedApp\Package.zip') -Value 'tampered' -Encoding ASCII

        $health = Get-OSDAppCacheHealth -CachePath $cache -Offline -PinnedId PinnedApp

        $health.Healthy | Should -BeFalse
        $health.CorruptCount | Should -Be 1
        $entry = @($health.Entries | Where-Object Id -eq 'PinnedApp')[0]
        $entry.State | Should -Be 'Corrupt'
        $entry.Pinned | Should -BeTrue
    }

    It 'marks an unknown requested pin as unhealthy instead of silently ignoring it' {
        $cache = Join-Path $TestDrive 'UnknownPinCache'
        New-Item -ItemType Directory -Path $cache -Force | Out-Null

        $health = Get-OSDAppCacheHealth -CachePath $cache -Offline -PinnedId MissingApp
        $entry = @($health.Entries | Where-Object Id -eq 'MissingApp')[0]

        $health.Healthy | Should -BeFalse
        $health.PinnedCount | Should -Be 1
        $entry.State | Should -Be 'Incomplete'
        $entry.Integrity | Should -Be 'Missing'
        $entry.Action | Should -Be 'Review'
    }

    It 'reports an unreadable cache catalog and preserves unfinished transaction recovery data' {
        $cache = Join-Path $TestDrive 'InterruptedCache'
        $transaction = Join-Path $cache '.staging\Sync-interrupted'
        New-Item -ItemType Directory -Path $transaction -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $transaction 'recovery.bin') -Value 'recovery' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $cache 'CacheCatalog.json') -Value '{not-json' -Encoding UTF8

        $health = Get-OSDAppCacheHealth -CachePath $cache -Offline
        $entry = @($health.Entries | Where-Object Source -eq 'Transaction')[0]

        $health.Healthy | Should -BeFalse
        $health.CacheCatalogError | Should -Not -BeNullOrEmpty
        $health.CorruptCount | Should -Be 1
        $entry.State | Should -Be 'Orphaned'
        $entry.Integrity | Should -Be 'Unknown'
        $entry.Action | Should -Be 'Review'
        (Test-Path -LiteralPath (Join-Path $transaction 'recovery.bin') -PathType Leaf) | Should -BeTrue
    }

    It 'recognizes the retired Teams built-in folder as renamed cache content' {
        $cache = Join-Path $TestDrive 'LegacyTeamsCache'
        $legacy = Join-Path $cache 'BuiltIn\Teams'
        New-Item -ItemType Directory -Path $legacy -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $legacy 'teamsbootstrapper.exe') -Value 'bootstrapper' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $legacy 'teams.msix') -Value 'msix' -Encoding ASCII
        @{Id='Teams';Version='1.0.0';Architecture='x64';SyncedAt='2026-10-13T00:00:00Z'} |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path $legacy 'CacheInfo.json') -Encoding UTF8

        $health = Get-OSDAppCacheHealth -CachePath $cache -Offline
        $entry = @($health.Entries | Where-Object { $_.Source -eq 'BuiltIn' -and $_.Id -eq 'Teams' })[0]

        $entry.State | Should -Be 'Renamed'
        $entry.CanonicalId | Should -Be 'MicrosoftTeams'
        $entry.Action | Should -Be 'MigrateOrRemove'
        $health.Healthy | Should -BeFalse
    }

    It 'does not accept canonical built-in metadata under the wrong folder identity' {
        $cache = Join-Path $TestDrive 'WrongBuiltInFolderCache'
        $wrongRoot = Join-Path $cache 'BuiltIn\WrongFolder'
        New-Item -ItemType Directory -Path $wrongRoot -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $wrongRoot 'teamsbootstrapper.exe') -Value 'bootstrapper' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $wrongRoot 'teams.msix') -Value 'msix' -Encoding ASCII
        @{Id='MicrosoftTeams';Version='1.0.0';Architecture='x64';SyncedAt='2026-10-13T00:00:00Z'} |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path $wrongRoot 'CacheInfo.json') -Encoding UTF8

        $health = Get-OSDAppCacheHealth -CachePath $cache -Offline
        $entry = @($health.Entries | Where-Object { $_.Source -eq 'BuiltIn' -and $_.Id -eq 'WrongFolder' })[0]

        $entry.State | Should -Be 'Orphaned'
        $entry.Action | Should -Be 'Remove'
        $health.ActiveCount | Should -Be 0
        $health.Healthy | Should -BeFalse
    }
}
