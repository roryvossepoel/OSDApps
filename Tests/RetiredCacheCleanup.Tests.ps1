Describe 'Automatic retired cache cleanup' {
    BeforeAll { . (Join-Path (Split-Path $PSScriptRoot -Parent) 'Runtime/OSDAppPayloadFile.ps1') }
    BeforeEach {
        $cache = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $root = Join-Path $cache 'BuiltIn/VisualCRedist/x64'
        $old = Join-Path $cache 'BuiltIn/VisualCppRedist'
        foreach ($path in @($root, (Join-Path $old 'x64'), (Join-Path $old 'x86'))) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
            Set-Content (Join-Path $path 'Package.exe') 'payload'
        }
        @{ Id='VisualCppRedist'; Architecture='x64' } | ConvertTo-Json | Set-Content (Join-Path $old 'x64/CacheInfo.json')
        $hash = (Get-FileHash (Join-Path $root 'Package.exe')).Hash
    }
    It 'removes only the replaced architecture and preserves active bytes' {
        Remove-OSDAppRetiredCacheVariant -Root $root -Id VisualCRedist -Architecture x64 -Validate { }
        Test-Path (Join-Path $old 'x64') | Should -BeFalse
        Test-Path (Join-Path $old 'x86/Package.exe') | Should -BeTrue
        (Get-FileHash (Join-Path $root 'Package.exe')).Hash | Should -Be $hash
    }
    It 'preserves old cache when validation fails' {
        Remove-OSDAppRetiredCacheVariant -Root $root -Id VisualCRedist -Architecture x64 -Validate { throw 'Invalid' } -WarningAction SilentlyContinue
        Test-Path (Join-Path $old 'x64/Package.exe') | Should -BeTrue
    }
    It 'preserves recovery content' {
        New-Item -ItemType Directory -Path (Join-Path $old 'x64/data.osdapps-old-test') | Out-Null
        Remove-OSDAppRetiredCacheVariant -Root $root -Id VisualCRedist -Architecture x64 -Validate { throw 'Must not run' }
        Test-Path (Join-Path $old 'x64/Package.exe') | Should -BeTrue
    }
    It 'requires old metadata identity' {
        @{Id='Custom';Architecture='x64'} | ConvertTo-Json | Set-Content (Join-Path $old 'x64/CacheInfo.json')
        Remove-OSDAppRetiredCacheVariant -Root $root -Id VisualCRedist -Architecture x64 -Validate { throw 'Must not run' }
        Test-Path (Join-Path $old 'x64/Package.exe') | Should -BeTrue
    }
    It 'removes empty retired parent after last variant' {
        Remove-Item (Join-Path $old 'x86') -Recurse -Force
        Remove-OSDAppRetiredCacheVariant -Root $root -Id VisualCRedist -Architecture x64 -Validate { }
        Test-Path $old | Should -BeFalse
    }
    It 'preserves linked content' {
        $outside = Join-Path $cache 'Outside'
        New-Item -ItemType Directory -Path $outside | Out-Null
        Set-Content (Join-Path $outside 'keep.txt') 'keep'
        $type = if ($env:OS -eq 'Windows_NT') { 'Junction' } else { 'SymbolicLink' }
        New-Item -ItemType $type -Path (Join-Path $old 'x64/link') -Target $outside | Out-Null
        Remove-OSDAppRetiredCacheVariant -Root $root -Id VisualCRedist -Architecture x64 -Validate { }
        Test-Path (Join-Path $old 'x64/Package.exe') | Should -BeTrue
        Get-Content (Join-Path $outside 'keep.txt') | Should -Be 'keep'
    }
    It 'also cleans the SevenZip predecessor' {
        $new7 = Join-Path $cache 'BuiltIn/7Zip/x64'
        $old7 = Join-Path $cache 'BuiltIn/SevenZip/x64'
        New-Item -ItemType Directory -Path $new7,$old7 -Force | Out-Null
        @{Id='SevenZip';Architecture='x64'} | ConvertTo-Json | Set-Content (Join-Path $old7 'CacheInfo.json')
        Remove-OSDAppRetiredCacheVariant -Root $new7 -Id 7Zip -Architecture x64 -Validate { }
        Test-Path $old7 | Should -BeFalse
        Test-Path $new7 | Should -BeTrue
    }
}

Describe 'Retired cache cleanup logging' {
    BeforeAll {
        $moduleRoot = Split-Path $PSScriptRoot -Parent
        . (Join-Path $moduleRoot 'Runtime/OSDAppPayloadFile.ps1')
        . (Join-Path $moduleRoot 'Private/Write-OSDAppLog.ps1')
    }
    BeforeEach {
        $cache = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $root = Join-Path $cache 'BuiltIn/VisualCRedist/x64'
        $old = Join-Path $cache 'BuiltIn/VisualCppRedist/x64'
        New-Item -ItemType Directory -Path $root,$old -Force | Out-Null
        Set-Content (Join-Path $root 'Package.exe') 'active'
        Set-Content (Join-Path $old 'Package.exe') 'retired'
        @{Id='VisualCppRedist';Architecture='x64'} | ConvertTo-Json | Set-Content (Join-Path $old 'CacheInfo.json')
        $script:records = [System.Collections.Generic.List[object]]::new()
        $log = { param($record) $script:records.Add($record) }
        $before = (Get-FileHash (Join-Path $root 'Package.exe')).Hash
    }
    It 'records removal only after validation and preserves the active bytes and other architecture' {
        $other = Join-Path (Split-Path $old) 'x86'
        New-Item -ItemType Directory -Path $other | Out-Null
        Set-Content (Join-Path $other 'Package.exe') 'other'
        $output = @(Remove-OSDAppRetiredCacheVariant -Root $root -Id VisualCRedist -Architecture x64 -Validate {
            Test-Path $old | Should -BeTrue
            $script:records.Count | Should -Be 0
        } -Log $log)
        $output.Count | Should -Be 0
        $script:records.Event | Should -Be @('CacheRetiredVariantRemoved','CacheRetiredParentRetained')
        $script:records[0].Data.ActivePath | Should -Be $root
        $script:records[0].Data.Path | Should -Be $old
        $script:records[0].Data.Architecture | Should -Be 'x64'
        $script:records[1].Data.Reason | Should -Be 'OtherContentRemaining'
        Test-Path $old | Should -BeFalse
        Get-Content (Join-Path $other 'Package.exe') | Should -Be 'other'
        (Get-FileHash (Join-Path $root 'Package.exe')).Hash | Should -Be $before
    }
    It 'records empty parent removal separately' {
        Remove-OSDAppRetiredCacheVariant -Root $root -Id VisualCRedist -Architecture x64 -Validate {} -Log $log
        $script:records.Event | Should -Be @('CacheRetiredVariantRemoved','CacheRetiredParentRemoved')
        Test-Path (Split-Path $old) | Should -BeFalse
    }
    It 'records protected recovery content without invoking validation' {
        Set-Content (Join-Path $old 'state.osdapps-old-test') 'recovery'
        Remove-OSDAppRetiredCacheVariant -Root $root -Id VisualCRedist -Architecture x64 -Validate { throw 'Must not run' } -Log $log
        $script:records.Count | Should -Be 1
        $script:records[0].Event | Should -Be 'CacheRetiredVariantRetained'
        $script:records[0].Data.Reason | Should -Be 'LinkedOrRecoveryContent'
        Test-Path (Join-Path $old 'Package.exe') | Should -BeTrue
    }
    It 'records mismatched metadata without removing content' {
        @{Id='Custom';Architecture='x64'} | ConvertTo-Json | Set-Content (Join-Path $old 'CacheInfo.json')
        Remove-OSDAppRetiredCacheVariant -Root $root -Id VisualCRedist -Architecture x64 -Validate { throw 'Must not run' } -Log $log
        $script:records[0].Data.Reason | Should -Be 'MetadataIdentityMismatch'
        Test-Path $old | Should -BeTrue
    }
    It 'records a missing matching architecture without touching the other variant' {
        $other = Join-Path (Split-Path $old) 'x86'
        Move-Item $old $other
        Remove-OSDAppRetiredCacheVariant -Root $root -Id VisualCRedist -Architecture x64 -Validate { throw 'Must not run' } -Log $log
        $script:records[0].Data.Reason | Should -Be 'NoMatchingArchitecture'
        Test-Path (Join-Path $other 'Package.exe') | Should -BeTrue
    }
    It 'records validation failure as a warning and never reports removal' {
        Remove-OSDAppRetiredCacheVariant -Root $root -Id VisualCRedist -Architecture x64 -Validate { throw 'Invalid replacement' } -Log $log -WarningAction SilentlyContinue
        $script:records.Count | Should -Be 1
        $script:records[0].Event | Should -Be 'CacheRetiredCleanupFailed'
        $script:records[0].Level | Should -Be 'Warning'
        $script:records[0].Data.Stage | Should -Be 'ValidateReplacement'
        $script:records[0].Data.Error | Should -Be 'Invalid replacement'
        Test-Path $old | Should -BeTrue
    }
    It 'records deletion failure without falsely claiming removal' {
        Mock Remove-Item { throw 'Access denied' } -ParameterFilter { $LiteralPath -eq $old }
        Remove-OSDAppRetiredCacheVariant -Root $root -Id VisualCRedist -Architecture x64 -Validate {} -Log $log -WarningAction SilentlyContinue
        $script:records.Count | Should -Be 1
        $script:records[0].Event | Should -Be 'CacheRetiredCleanupFailed'
        $script:records[0].Data.Stage | Should -Be 'RemoveVariant'
        $script:records[0].Data.Error | Should -Be 'Access denied'
        Test-Path $old | Should -BeTrue
    }
    It 'does not alter successful cleanup when the logger throws even with WarningAction Stop' {
        { Remove-OSDAppRetiredCacheVariant -Root $root -Id VisualCRedist -Architecture x64 -Validate {} -Log { throw 'Log unavailable' } -WarningAction Stop } | Should -Not -Throw
        Test-Path (Split-Path $old) | Should -BeFalse
        (Get-FileHash (Join-Path $root 'Package.exe')).Hash | Should -Be $before
    }
    It 'does not let a logger failure bypass a preservation guard' {
        Set-Content (Join-Path $old '.staging') 'keep'
        { Remove-OSDAppRetiredCacheVariant -Root $root -Id VisualCRedist -Architecture x64 -Validate { throw 'Must not run' } -Log { throw 'Log unavailable' } -WarningAction Stop } | Should -Not -Throw
        Test-Path $old | Should -BeTrue
    }
    It 'reports parent removal failure after the variant was removed without claiming rollback' {
        $parent = Split-Path $old
        Mock Remove-Item { [IO.Directory]::Delete($LiteralPath, $true) }
        Mock Remove-Item { throw 'Parent locked' } -ParameterFilter { -not $Recurse }
        Remove-OSDAppRetiredCacheVariant -Root $root -Id VisualCRedist -Architecture x64 -Validate {} -Log $log -WarningAction SilentlyContinue
        $script:records.Event | Should -Be @('CacheRetiredVariantRemoved','CacheRetiredCleanupFailed')
        $script:records[1].Data.Stage | Should -Be 'RemoveEmptyParent'
        $script:records[1].Data.Error | Should -Be 'Parent locked'
        $script:records[1].Data.Path | Should -Be $parent
        Test-Path $old | Should -BeFalse
        Test-Path $parent | Should -BeTrue
    }
    It 'suppresses logger success output and stays quiet when no predecessor exists' {
        $result = @(Remove-OSDAppRetiredCacheVariant -Root $root -Id VisualCRedist -Architecture x64 -Validate {} -Log { 'Logger output' })
        $result.Count | Should -Be 0
        Remove-OSDAppRetiredCacheVariant -Root $root -Id VisualCRedist -Architecture x64 -Validate { throw 'Must not run' } -Log $log
        $script:records.Count | Should -Be 0
    }
    It 'writes persistent CMTrace records through the existing client logger' {
        $clientLog = Join-Path $cache 'Logs/Client.log'
        Remove-OSDAppRetiredCacheVariant -Root $root -Id VisualCRedist -Architecture x64 -Validate {} -Log {
            param($record)
            Write-OSDAppLog -LogPath $clientLog -Component CacheCleanup -Event $record.Event -Level $record.Level -Message $record.Message -Data $record.Data -ErrorAction Stop
        }
        $lines = @(Get-Content $clientLog)
        $lines.Count | Should -Be 2
        $lines[0] | Should -Match '\[CacheRetiredVariantRemoved\]'
        $lines[0] | Should -Match 'Architecture=x64'
        $lines[0] | Should -Match 'Reason=ReplacementValidated'
        $lines[1] | Should -Match '\[CacheRetiredParentRemoved\]'
    }
}

Describe 'Public synchronization cleanup log routing' {
    BeforeAll { Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'OSDApps.psd1') -Force }
    It 'routes <Family> cleanup to Client.log without adding output objects' -ForEach @(
        @{Family='7Zip';Retired='SevenZip';Command='Sync-OSDApp7Zip';Generation='Sync-OSDApp7ZipGeneration'}
        @{Family='VisualCRedist';Retired='VisualCppRedist';Command='Sync-OSDAppVisualCRedist';Generation='Sync-OSDAppPrerequisiteGeneration'}
    ) {
        InModuleScope OSDApps -Parameters @{Family=$Family;Retired=$Retired;Command=$Command;Generation=$Generation} {
            param($Family,$Retired,$Command,$Generation)
            $script:testFamily = $Family
            $script:testCache = Join-Path $TestDrive $Family
            $active = Join-Path $script:testCache "BuiltIn/$Family/x64"
            $old = Join-Path $script:testCache "BuiltIn/$Retired/x64"
            New-Item -ItemType Directory -Path $active,$old -Force | Out-Null
            @{Id=$Retired;Architecture='x64'} | ConvertTo-Json | Set-Content (Join-Path $old 'CacheInfo.json')
            Mock Test-OSDAppWinPE { $false }
            Mock Get-OSDAppCachePath { $script:testCache }
            Mock $Generation {
                param($Root,$Log)
                Remove-OSDAppRetiredCacheVariant -Root $Root -Id $script:testFamily -Architecture x64 -Validate {} -Log $Log
                [pscustomobject]@{Version='1.0';Updated=$false}
            }
            $result = @(& $Command -Architecture x64 -Confirm:$false)
            $result.Count | Should -Be 1
            $result[0].Updated | Should -BeFalse
            Test-Path $old | Should -BeFalse
            Get-Content (Join-Path $script:testCache 'Logs/Client.log') -Raw | Should -Match '\[CacheRetiredVariantRemoved\]'
        }
    }
}
