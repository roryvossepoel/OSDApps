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
