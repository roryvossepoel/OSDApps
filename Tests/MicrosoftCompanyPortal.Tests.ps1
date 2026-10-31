Describe 'Microsoft Company Portal built-in staging' {
    BeforeAll {
        $root = Split-Path $PSScriptRoot -Parent
        Import-Module (Join-Path $root 'OSDStage.psd1') -Force
    }

    It 'exposes Company Portal as a built-in app without an online catalog' {
        $app = Get-OSDStage -Name MicrosoftCompanyPortal -Offline
        $app.Id | Should -Be 'MicrosoftCompanyPortal'
        $app.PackageType | Should -Be 'App'
        $app.Source | Should -Be 'BuiltIn'
    }

    It 'stages a complete pre-prepared kit without changing the other queue entries' {
        InModuleScope OSDStage {
            $cache = Join-Path $TestDrive 'Cache'
            $target = Join-Path $TestDrive 'OfflineWindows'
            $variant = Join-Path $cache 'BuiltIn\MicrosoftCompanyPortal\x64'
            New-Item -ItemType Directory -Path (Join-Path $variant 'Dependencies') -Force | Out-Null
            $relative = @('CompanyPortal_11_2_1495_0_neutral.appxbundle','CompanyPortal_License1.xml',
                'Dependencies\Microsoft.NET.Native.Framework.2.2_1_x64__test.appx',
                'Dependencies\Microsoft.NET.Native.Runtime.2.2_1_x64__test.appx',
                'Dependencies\Microsoft.Services.Store.Engagement_1_x64__test.appx',
                'Dependencies\Microsoft.UI.Xaml.2.7_1_x64__test.appx',
                'Dependencies\Microsoft.VCLibs.140.00_1_x64__test.appx')
            $files = @()
            foreach ($r in $relative) {
                $p = Join-Path $variant $r
                'test payload' | Set-Content -LiteralPath $p -Encoding ASCII
                $files += [pscustomobject]@{
                    Path=$r
                    Sha256=(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash
                }
            }
            [ordered]@{
                Id='MicrosoftCompanyPortal'; Architecture='x64'; Version='11.2.1495.0'
                PayloadFileName='CompanyPortal_11_2_1495_0_neutral.appxbundle'; LicenseFileName='CompanyPortal_License1.xml'
                Sha256=$files[0].Sha256; Size=(Get-Item (Join-Path $variant 'CompanyPortal_11_2_1495_0_neutral.appxbundle')).Length
                DependencyCount=5; Files=@($files)
            } | ConvertTo-Json -Depth 12 |
                Set-Content -LiteralPath (Join-Path $variant 'CacheInfo.json') -Encoding UTF8

            Mock Get-OSDStageCachePath { $cache }
            Mock Resolve-OSDStageWindowsPath { $target }

            $staged = Add-OSDStageMicrosoftCompanyPortal -Architecture x64 -WindowsPath $target -Confirm:$false
            $staged.Name | Should -Be 'MicrosoftCompanyPortal'
            $manifest = Get-Content -LiteralPath (Join-Path $target 'Windows\Temp\OSDStage\DeviceManifest.json') -Raw | ConvertFrom-Json
            @($manifest.Packages).Count | Should -Be 1
            $manifest.Packages[0].Type | Should -Be 'CompanyPortalAppxBundle'
            @($manifest.Packages[0].Dependencies).Count | Should -Be 5

            $check = Test-OSDStageDeployment -WindowsPath $target -RequireOfflineReady
            $check.Valid | Should -BeTrue
            $check.OfflineReady | Should -BeTrue

            $bundle = Join-Path $target 'Windows\Temp\OSDStage\BuiltIn\MicrosoftCompanyPortal\x64\CompanyPortal_11_2_1495_0_neutral.appxbundle'
            Set-Content -LiteralPath $bundle -Value 'changed' -Encoding ASCII
            $broken = Test-OSDStageDeployment -WindowsPath $target -RequireOfflineReady
            $broken.Valid | Should -BeFalse
            $broken.OfflineReady | Should -BeFalse
        }
    }
}
