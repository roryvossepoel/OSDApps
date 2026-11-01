Describe 'CMTrace Open built-in staging' {
    BeforeAll {
        $root = Split-Path $PSScriptRoot -Parent
        Import-Module (Join-Path $root 'OSDStage.psd1') -Force
    }

    It 'advertises the built-in without requiring the online catalog' {
        $app = Get-OSDStage -Name CMTraceOpen -Offline
        $app.Id | Should -Be 'CMTraceOpen'
        $app.Source | Should -Be 'BuiltIn'
        $app.PackageType | Should -Be 'App'
    }

    It 'fails closed when cached MSI bytes do not match release SHA-256' {
        InModuleScope OSDStage {
            $cache = Join-Path $TestDrive 'InvalidCache'
            $source = Join-Path $cache 'BuiltIn\CMTraceOpen\x64'
            New-Item -ItemType Directory -Path $source -Force | Out-Null
            'modified MSI' | Set-Content -LiteralPath (Join-Path $source 'CMTrace-Open_1.6.3_x64.msi')
            @{
                Id='CMTraceOpen'; Version='1.6.3'; Architecture='x64'
                PayloadFileName='CMTrace-Open_1.6.3_x64.msi'; Sha256=('A' * 64)
            } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $source 'CacheInfo.json') -Encoding UTF8
            Mock Get-OSDStageCachePath { $cache }
            Mock Resolve-OSDStageWindowsPath { $TestDrive }

            { Add-OSDStageCMTraceOpen -WindowsPath $TestDrive -Confirm:$false } |
                Should -Throw '*SHA-256*'
        }
    }

    It 'stages a verified vendor MSI under its unchanged release filename' {
        InModuleScope OSDStage {
            $cache = Join-Path $TestDrive 'NativeCache'
            $source = Join-Path $cache 'BuiltIn\CMTraceOpen\x64'
            New-Item -ItemType Directory -Path $source -Force | Out-Null
            $original = Join-Path $source 'CMTrace-Open_1.6.3_x64.msi'
            'test MSI payload' | Set-Content -LiteralPath $original
            $hash = (Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash
            @{
                Id='CMTraceOpen'; Version='1.6.3'; Architecture='x64'
                PayloadFileName='CMTrace-Open_1.6.3_x64.msi'; Sha256=$hash; Size=(Get-Item -LiteralPath $original).Length
            } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $source 'CacheInfo.json') -Encoding UTF8
            Mock Get-OSDStageCachePath { $cache }
            Mock Resolve-OSDStageWindowsPath { $TestDrive }
            Mock Add-OSDStageSetupComplete { }
            Mock Get-AuthenticodeSignature { throw 'Authenticode must not run in staging.' }

            $staged = Add-OSDStageCMTraceOpen -WindowsPath $TestDrive -Confirm:$false
            $staged.Name | Should -Be 'CMTraceOpen'
            $stagedFile = Join-Path $TestDrive 'Windows\Temp\OSDStage\BuiltIn\CMTraceOpen\x64\CMTrace-Open_1.6.3_x64.msi'
            Test-Path -LiteralPath $stagedFile -PathType Leaf | Should -BeTrue
            (Get-FileHash -LiteralPath $stagedFile -Algorithm SHA256).Hash | Should -Be $hash
            $manifest = Get-Content -LiteralPath (Join-Path $TestDrive 'Windows\Temp\OSDStage\DeviceManifest.json') -Raw |
                ConvertFrom-Json
            @($manifest.Packages | Where-Object Id -eq 'CMTraceOpen')[0].Package |
                Should -Be 'BuiltIn\CMTraceOpen\x64\CMTrace-Open_1.6.3_x64.msi'
            Should -Invoke Get-AuthenticodeSignature -Times 0 -Exactly
        }
    }

    It 'rejects a different cached asset name before staging' {
        InModuleScope OSDStage {
            $cache = Join-Path $TestDrive 'WrongAssetCache'
            $source = Join-Path $cache 'BuiltIn\CMTraceOpen\x64'
            New-Item -ItemType Directory -Path $source -Force | Out-Null
            $file = Join-Path $source 'CMTrace-Open_1.6.3_x64.msi'
            'known MSI bytes' | Set-Content -LiteralPath $file
            $hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
            @{
                Id='CMTraceOpen'; Version='1.6.3'; Architecture='x64'
                PayloadFileName='Unexpected_1.6.3_x64.msi'; Sha256=$hash
            } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $source 'CacheInfo.json') -Encoding UTF8
            Mock Get-OSDStageCachePath { $cache }
            Mock Resolve-OSDStageWindowsPath { $TestDrive }

            { Add-OSDStageCMTraceOpen -WindowsPath $TestDrive -Confirm:$false } |
                Should -Throw '*official release*'
        }
    }
}
