Describe 'Explicit managed built-in namespace pruning' {
    BeforeAll {
        Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'OSDStage.psd1') -Force
    }
    It 'removes unmanaged roots and loose files while preserving all managed variants and repository data' {
        InModuleScope OSDStage {
            $cache = Join-Path $TestDrive 'Cache'
            $protected = @('BuiltIn\VisualCRedist\x86\Package.exe','BuiltIn\VisualCRedist\x64\VC_redist.x64.exe','BuiltIn\Microsoft365Apps\Office\Data\payload.bin','BuiltIn\7Zip\x64\7z2605-x64.exe','Packages\CustomApp\Package.zip','CacheCatalog.json')
            foreach ($relative in $protected + @('BuiltIn\VisualCppRedist\x86\Package.exe','BuiltIn\VisualCppRedist\x64\Package.exe','BuiltIn\UnknownApp\nested\data.bin','BuiltIn\notes.txt')) {
                $path = Join-Path $cache $relative
                New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force | Out-Null
                Set-Content -LiteralPath $path -Value $relative
            }
            $before = @($protected | ForEach-Object { (Get-FileHash (Join-Path $cache $_)).Hash })
            Mock Get-OSDStageCachePath { $cache }
            $result = Clear-OSDStageCache -BuiltIn -Prune -Confirm:$false
            $result.Prune | Should -BeTrue
            $result.Removed.Count | Should -Be 3
            Test-Path (Join-Path $cache 'BuiltIn\VisualCppRedist') | Should -BeFalse
            Test-Path (Join-Path $cache 'BuiltIn\UnknownApp') | Should -BeFalse
            Test-Path (Join-Path $cache 'BuiltIn\notes.txt') | Should -BeFalse
            $after = @($protected | ForEach-Object { (Get-FileHash (Join-Path $cache $_)).Hash })
            ($after -join ',') | Should -Be ($before -join ',')
        }
    }
    It 'keeps WhatIf completely read-only including logs and lock creation' {
        InModuleScope OSDStage {
            $cache = Join-Path $TestDrive 'Preview'
            New-Item -ItemType Directory -Path (Join-Path $cache 'BuiltIn\Unknown') -Force | Out-Null
            Mock Get-OSDStageCachePath { $cache }
            Mock Enter-OSDStageCacheLock { throw 'Must not acquire a writer lock for preview' }
            Clear-OSDStageCache -BuiltIn -Prune -WhatIf | Out-Null
            Test-Path (Join-Path $cache 'BuiltIn\Unknown') | Should -BeTrue
            Test-Path (Join-Path $cache 'Logs') | Should -BeFalse
            Should -Invoke Enter-OSDStageCacheLock -Times 0 -Exactly
        }
    }
    It 'removes unmanaged roots while preserving transaction recovery content' {
        InModuleScope OSDStage {
            $cache = Join-Path $TestDrive 'Recovery'
            foreach ($name in @('Teams','MicrosoftTeams.osdstage-old-123','Unknown\x64.osdstage-new-123','VisualCRedist\x64.osdstage-old-123')) {
                New-Item -ItemType Directory -Path (Join-Path $cache "BuiltIn\$name") -Force | Out-Null
            }
            Mock Get-OSDStageCachePath { $cache }
            $result = Clear-OSDStageCache -BuiltIn -Prune -Confirm:$false -WarningAction SilentlyContinue
            $result.Removed.Count | Should -Be 1
            $result.Review.Count | Should -Be 2
            Test-Path (Join-Path $cache 'BuiltIn\VisualCRedist\x64.osdstage-old-123') | Should -BeTrue
            Test-Path (Join-Path $cache 'BuiltIn\Teams') | Should -BeFalse
        }
    }
    It 'does not prune when another writer holds the cache lock' {
        InModuleScope OSDStage {
            $cache = Join-Path $TestDrive 'Busy'
            New-Item -ItemType Directory -Path (Join-Path $cache 'BuiltIn\Unknown') -Force | Out-Null
            Mock Get-OSDStageCachePath { $cache }
            $lock = Enter-OSDStageCacheLock -CachePath $cache -Operation 'test writer'
            try {
                { Clear-OSDStageCache -BuiltIn -Prune -Confirm:$false } | Should -Throw '*Cannot acquire*'
                Test-Path (Join-Path $cache 'BuiltIn\Unknown') | Should -BeTrue
            }
            finally { $lock.Dispose() }
        }
    }
    It 'fails closed when built-in metadata cannot be read' {
        InModuleScope OSDStage {
            $cache = Join-Path $TestDrive 'BadMetadata'
            New-Item -ItemType Directory -Path (Join-Path $cache 'BuiltIn\Unknown') -Force | Out-Null
            Mock Get-OSDStageCachePath { $cache }
            Mock Get-Content { throw 'metadata unavailable' } -ParameterFilter { $LiteralPath -like '*builtins.json' }
            { Clear-OSDStageCache -BuiltIn -Prune -Confirm:$false } | Should -Throw '*metadata unavailable*'
            Test-Path (Join-Path $cache 'BuiltIn\Unknown') | Should -BeTrue
        }
    }
    It 'rejects combining prune with the repository scope' {
        { Clear-OSDStageCache -Repository -Prune } | Should -Throw
    }
    It 'reports loose built-in root files in read-only cache health' {
        InModuleScope OSDStage {
            $cache = Join-Path $TestDrive 'LooseFile'
            New-Item -ItemType Directory -Path (Join-Path $cache 'BuiltIn') -Force | Out-Null
            $file = Join-Path $cache 'BuiltIn\notes.txt'
            Set-Content $file 'unmanaged'
            $health = Get-OSDStageCacheHealth -CachePath $cache -Offline
            $health.Healthy | Should -BeFalse
            $health.OrphanedCount | Should -Be 1
            $health.Entries[0].Action | Should -Be 'Remove'
            Test-Path $file | Should -BeTrue
        }
    }
    It 'preserves an unmanaged tree containing a link and never touches the link target' {
        InModuleScope OSDStage {
            $cache = Join-Path $TestDrive 'Linked'
            $outside = Join-Path $TestDrive 'Outside'
            New-Item -ItemType Directory -Path $outside,(Join-Path $cache 'BuiltIn\Unknown') -Force | Out-Null
            $sentinel = Join-Path $outside 'sentinel.txt'
            Set-Content $sentinel 'must survive'
            $hash = (Get-FileHash $sentinel).Hash
            $linkType = if ($env:OS -eq 'Windows_NT') { 'Junction' } else { 'SymbolicLink' }
            New-Item -ItemType $linkType -Path (Join-Path $cache 'BuiltIn\Unknown\LinkedData') -Target $outside | Out-Null
            Mock Get-OSDStageCachePath { $cache }
            $result = Clear-OSDStageCache -BuiltIn -Prune -Confirm:$false -WarningAction SilentlyContinue
            $result.Removed.Count | Should -Be 0
            $result.Review.Count | Should -Be 1
            (Get-FileHash $sentinel).Hash | Should -Be $hash
        }
    }
}
