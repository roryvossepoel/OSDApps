Describe 'Microsoft Company Portal automatic Preinstall Kit download' {
    BeforeAll {
        $root = Split-Path $PSScriptRoot -Parent
        Import-Module (Join-Path $root 'OSDApps.psd1') -Force
    }

    It 'allows synchronization without supplying KitPath' {
        $command = Get-Command Sync-OSDAppMicrosoftCompanyPortal -Module OSDApps
        $parameter = $command.Parameters['KitPath']
        $parameter | Should -Not -BeNullOrEmpty
        @($parameter.Attributes | Where-Object {
            $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory
        }).Count | Should -Be 0
    }

    It 'downloads and extracts a synthetic Microsoft-format x64 kit without KitPath' {
        InModuleScope OSDApps {
            Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
            Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop

            $cache = Join-Path $TestDrive 'AutomaticCache'
            New-Item -ItemType Directory -Path $cache -Force | Out-Null
            $bundleRoot = Join-Path $TestDrive 'BundleSource'
            $metadataRoot = Join-Path $bundleRoot 'AppxMetadata'
            New-Item -ItemType Directory -Path $metadataRoot -Force | Out-Null
            '<Bundle><Identity Name="Microsoft.CompanyPortal" Publisher="CN=Microsoft Corporation, O=Microsoft Corporation, C=US" Version="11.2.1495.0" /></Bundle>' |
                Set-Content -LiteralPath (Join-Path $metadataRoot 'AppxBundleManifest.xml') -Encoding UTF8

            $kitRoot = Join-Path $TestDrive 'KitSource'
            New-Item -ItemType Directory -Path $kitRoot -Force | Out-Null
            [IO.Compression.ZipFile]::CreateFromDirectory($bundleRoot, (Join-Path $kitRoot 'CompanyPortal.appxbundle'))
            'test fixture license' | Set-Content -LiteralPath (Join-Path $kitRoot 'CompanyPortal_License1.xml')
            foreach ($family in @(
                'Microsoft.NET.Native.Framework.2.2_',
                'Microsoft.NET.Native.Runtime.2.2_',
                'Microsoft.Services.Store.Engagement_',
                'Microsoft.UI.Xaml.2.7_',
                'Microsoft.VCLibs.140.00_'
            )) {
                $name = $family + '1.0.0.0_x64__example.appx'
                ('fixture:' + $family) | Set-Content -LiteralPath (Join-Path $kitRoot $name)
            }
            $script:fixtureKit = Join-Path $TestDrive 'OfficialFormatKit.zip'
            [IO.Compression.ZipFile]::CreateFromDirectory($kitRoot, $script:fixtureKit)

            Mock Test-OSDAppWinPE { $false }
            Mock Get-OSDAppCachePath { $cache }
            Mock Enter-OSDAppCacheLock { $null }
            Mock Invoke-WebRequest { Copy-Item -LiteralPath $script:fixtureKit -Destination $OutFile -Force }

            $result = Sync-OSDAppMicrosoftCompanyPortal -Architecture x64 -Confirm:$false
            $result.Updated | Should -BeTrue
            $result.CacheReused | Should -BeFalse
            $result.Files | Should -Be 7
            $result.Version | Should -Be '11.2.1495.0'

            $prepared = Join-Path $cache 'BuiltIn\MicrosoftCompanyPortal\x64'
            $info = Get-Content -LiteralPath (Join-Path $prepared 'CacheInfo.json') -Raw | ConvertFrom-Json
            $info.Source | Should -Be 'Microsoft Download Center'
            $info.SourceKitSha256 | Should -Be (Get-FileHash -LiteralPath $script:fixtureKit -Algorithm SHA256).Hash
            @($info.Files).Count | Should -Be 7
            $info.DependencyCount | Should -Be 5
            foreach ($file in @($info.Files)) {
                (Get-FileHash -LiteralPath (Join-Path $prepared $file.Path) -Algorithm SHA256).Hash |
                    Should -Be $file.Sha256
            }
            Should -Invoke Invoke-WebRequest -Exactly 1 -ParameterFilter { $Uri -like 'https://download.microsoft.com/*' }
        }
    }

    It 'reuses only a hash-verified x64 cache when the official download is unavailable' {
        InModuleScope OSDApps {
            $cache = Join-Path $TestDrive 'Cache'
            $target = Join-Path $cache 'BuiltIn\MicrosoftCompanyPortal\x64'
            New-Item -ItemType Directory -Path (Join-Path $target 'Dependencies') -Force | Out-Null
            $paths = @('Bundle.appxbundle', 'License.xml',
                'Dependencies\one.appx','Dependencies\two.appx','Dependencies\three.appx',
                'Dependencies\four.appx','Dependencies\five.appx')
            $files = @()
            foreach ($relative in $paths) {
                $dest = Join-Path $target $relative
                ('verified:' + $relative) | Set-Content -LiteralPath $dest
                $files += @{ Path=$relative; Sha256=(Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash }
            }
            @{
                Id='MicrosoftCompanyPortal';Version='11.2.1495.0';Architecture='x64'
                SourceKitSha256=('A'*64);Files=$files
            } | ConvertTo-Json -Depth 6 |
                Set-Content -LiteralPath (Join-Path $target 'CacheInfo.json') -Encoding UTF8

            Mock Test-OSDAppWinPE { $false }
            Mock Get-OSDAppCachePath { $cache }
            Mock Enter-OSDAppCacheLock { $null }
            Mock Invoke-WebRequest { throw 'Microsoft download unavailable' }

            $result = Sync-OSDAppMicrosoftCompanyPortal -Architecture x64 -Confirm:$false -WarningAction SilentlyContinue
            $result.CacheReused | Should -BeTrue
            $result.Updated | Should -BeFalse
            $result.Files | Should -Be 7
            Should -Invoke Invoke-WebRequest -Times 1 -Exactly
        }
    }
}
