Describe 'CMTrace Open built-in staging' {
    BeforeAll {
        $root = Split-Path $PSScriptRoot -Parent
        Import-Module (Join-Path $root 'OSDApps.psd1') -Force
    }

    It 'advertises the built-in without requiring the online catalog' {
        $app = Get-OSDApp -Name CMTraceOpen -Offline
        $app.Id | Should -Be 'CMTraceOpen'
        $app.Source | Should -Be 'BuiltIn'
        $app.PackageType | Should -Be 'Application'
    }

    It 'fails closed when cached MSI bytes do not match release SHA-256' {
        InModuleScope OSDApps {
            $cache = Join-Path $TestDrive 'InvalidCache'
            $source = Join-Path $cache 'BuiltIn\CMTraceOpen\x64'
            New-Item -ItemType Directory -Path $source -Force | Out-Null
            'modified MSI' | Set-Content -LiteralPath (Join-Path $source 'Package.msi')
            @{
                Id='CMTraceOpen'; Version='1.6.3'; Architecture='x64'
                AssetName='CMTrace-Open_1.6.3_x64.msi'; Sha256=('A' * 64)
            } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $source 'CacheInfo.json') -Encoding UTF8
            Mock Get-OSDAppCachePath { $cache }
            Mock Resolve-OSDAppWindowsPath { $TestDrive }

            { Add-OSDAppCMTraceOpen -WindowsPath $TestDrive -Confirm:$false } |
                Should -Throw '*SHA-256*'
        }
    }

    It 'stages a verified legacy Package.msi under its original release name' {
        InModuleScope OSDApps {
            $cache = Join-Path $TestDrive 'LegacyCache'
            $source = Join-Path $cache 'BuiltIn\CMTraceOpen\x64'
            New-Item -ItemType Directory -Path $source -Force | Out-Null
            $legacy = Join-Path $source 'Package.msi'
            'test MSI payload' | Set-Content -LiteralPath $legacy
            $hash = (Get-FileHash -LiteralPath $legacy -Algorithm SHA256).Hash
            @{
                Id='CMTraceOpen'; Version='1.6.3'; Architecture='x64'
                AssetName='CMTrace-Open_1.6.3_x64.msi'; Sha256=$hash
            } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $source 'CacheInfo.json') -Encoding UTF8
            Mock Get-OSDAppCachePath { $cache }
            Mock Resolve-OSDAppWindowsPath { $TestDrive }
            Mock Add-OSDAppSetupComplete { }
            Mock Get-AuthenticodeSignature { throw 'Authenticode must not run in staging.' }

            $staged = Add-OSDAppCMTraceOpen -WindowsPath $TestDrive -Confirm:$false
            $staged.Name | Should -Be 'CMTraceOpen'
            $stagedFile = Join-Path $TestDrive 'Windows\Temp\OSDApps\BuiltIn\CMTraceOpen\x64\CMTrace-Open_1.6.3_x64.msi'
            Test-Path -LiteralPath $stagedFile -PathType Leaf | Should -BeTrue
            (Get-FileHash -LiteralPath $stagedFile -Algorithm SHA256).Hash | Should -Be $hash
            Test-Path -LiteralPath (Join-Path $TestDrive 'Windows\Temp\OSDApps\BuiltIn\CMTraceOpen\x64\Package.msi') |
                Should -BeFalse
            $manifest = Get-Content -LiteralPath (Join-Path $TestDrive 'Windows\Temp\OSDApps\DeviceManifest.json') -Raw |
                ConvertFrom-Json
            @($manifest.Apps | Where-Object Id -eq 'CMTraceOpen')[0].Package |
                Should -Be 'BuiltIn\CMTraceOpen\x64\CMTrace-Open_1.6.3_x64.msi'
            Should -Invoke Get-AuthenticodeSignature -Times 0 -Exactly
        }
    }

    It 'rejects a different cached asset name before staging' {
        InModuleScope OSDApps {
            $cache = Join-Path $TestDrive 'WrongAssetCache'
            $source = Join-Path $cache 'BuiltIn\CMTraceOpen\x64'
            New-Item -ItemType Directory -Path $source -Force | Out-Null
            $file = Join-Path $source 'CMTrace-Open_1.6.3_x64.msi'
            'known MSI bytes' | Set-Content -LiteralPath $file
            $hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
            @{
                Id='CMTraceOpen'; Version='1.6.3'; Architecture='x64'
                AssetName='Package.msi'; Sha256=$hash
            } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $source 'CacheInfo.json') -Encoding UTF8
            Mock Get-OSDAppCachePath { $cache }
            Mock Resolve-OSDAppWindowsPath { $TestDrive }

            { Add-OSDAppCMTraceOpen -WindowsPath $TestDrive -Confirm:$false } |
                Should -Throw '*official release*'
        }
    }
}
