Describe 'CMTrace Open built-in staging' {
    BeforeAll {
        $root = Split-Path $PSScriptRoot -Parent
        Import-Module (Join-Path $root 'OSDApps.psd1') -Force
    }
    It 'advertises CMTrace Open as a built-in application' {
        $app = Get-OSDApp -Name CMTraceOpen -Offline
        $app.Source | Should -Be 'BuiltIn'
        $app.PackageType | Should -Be 'Application'
    }
    It 'refuses to stage when a cached MSI hash differs' {
        InModuleScope OSDApps {
            $target = Join-Path $TestDrive 'Target'
            $cache = Join-Path $TestDrive 'Cache'
            $root = Join-Path $cache 'BuiltIn\CMTraceOpen\x64'
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            'fake msi' | Set-Content -LiteralPath (Join-Path $root 'Package.msi')
            @{Id='CMTraceOpen';Version='1.6.3';Architecture='x64';Sha256=('A'*64)} |
                ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'CacheInfo.json') -Encoding UTF8
            Mock Get-OSDAppCachePath { $cache }
            Mock Resolve-OSDAppWindowsPath { $target }
            { Add-OSDAppCMTraceOpen -WindowsPath $target -Confirm:$false } | Should -Throw '*SHA-256*'
            Test-Path -LiteralPath $target | Should -BeFalse
        }
    }
}
