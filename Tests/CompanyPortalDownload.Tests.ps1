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

    It 'automatically downloads a synthetic kit and retains every original vendor filename' {
        InModuleScope OSDApps {
            Add-Type -AssemblyName System.IO.Compression
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $cache = Join-Path $TestDrive 'ColdCache'
            New-Item -ItemType Directory -Path $cache -Force | Out-Null
            $kitRoot = Join-Path $TestDrive 'KitSource'
            New-Item -ItemType Directory -Path $kitRoot -Force | Out-Null
            $vendorBundle = 'CompanyPortal_11_2_1495_0_neutral.appxbundle'
            $zip = [IO.Compression.ZipFile]::Open((Join-Path $kitRoot $vendorBundle),[IO.Compression.ZipArchiveMode]::Create)
            try {
                $writer = [IO.StreamWriter]::new($zip.CreateEntry('AppxMetadata/AppxBundleManifest.xml').Open())
                try { $writer.Write('<Bundle><Identity Name="Microsoft.CompanyPortal" Publisher="CN=Microsoft Corporation, O=Microsoft Corporation, C=US" Version="11.2.1495.0" /></Bundle>') }
                finally { $writer.Dispose() }
            }
            finally { $zip.Dispose() }
            'synthetic license' | Set-Content -LiteralPath (Join-Path $kitRoot 'CompanyPortal_License1.xml')
            foreach ($family in @('Microsoft.NET.Native.Framework.2.2_','Microsoft.NET.Native.Runtime.2.2_','Microsoft.Services.Store.Engagement_','Microsoft.UI.Xaml.2.7_','Microsoft.VCLibs.140.00_')) {
                'synthetic dependency' | Set-Content -LiteralPath (Join-Path $kitRoot ($family + '1.0.0.0_x64__test.appx'))
            }
            $script:vendorKit = Join-Path $TestDrive 'CompanyPortal-Universal-PreinstallKit.zip'
            [IO.Compression.ZipFile]::CreateFromDirectory($kitRoot,$script:vendorKit)
            Mock Test-OSDAppWinPE { $false }
            Mock Get-OSDAppCachePath { $cache }
            Mock Enter-OSDAppCacheLock { $null }
            Mock Save-OSDAppDownload {
                $file = Join-Path $DestinationDirectory (Split-Path $script:vendorKit -Leaf)
                New-Item -ItemType Directory -Path $DestinationDirectory -Force | Out-Null
                Copy-Item -LiteralPath $script:vendorKit -Destination $file
                Get-Item -LiteralPath $file
            }
            $result = Sync-OSDAppMicrosoftCompanyPortal -Architecture x64 -Confirm:$false
            $result.Updated | Should -BeTrue
            $result.CacheReused | Should -BeFalse
            $result.Files | Should -Be 7
            $info = Get-Content (Join-Path $result.CachePath 'CacheInfo.json') -Raw | ConvertFrom-Json
            $info.PayloadFileName | Should -BeExactly $vendorBundle
            $info.LicenseFileName | Should -BeExactly 'CompanyPortal_License1.xml'
            $info.SourceKitSha256 | Should -Be (Get-FileHash $script:vendorKit).Hash
            foreach ($entry in $info.Files) {
                $path = Join-Path $result.CachePath $entry.Path
                (Get-FileHash $path).Hash | Should -Be $entry.Sha256
            }
            $info.Files.Path | Should -Not -Contain 'Bundle.appxbundle'
            $info.Files.Path | Should -Not -Contain 'License.xml'
            Should -Invoke Save-OSDAppDownload -Times 1 -Exactly -ParameterFilter { $ExpectedExtension -eq '.zip' -and $Uri -like 'https://download.microsoft.com/*' }
        }
    }

    It 'reuses only a hash-verified x64 cache when the official download is unavailable' {
        InModuleScope OSDApps {
            $cache = Join-Path $TestDrive 'Cache'
            $target = Join-Path $cache 'BuiltIn\MicrosoftCompanyPortal\x64'
            New-Item -ItemType Directory -Path (Join-Path $target 'Dependencies') -Force | Out-Null
            $paths = @('CompanyPortal_11_2_1495_0_neutral.appxbundle', 'CompanyPortal_License1.xml',
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
                PayloadFileName='CompanyPortal_11_2_1495_0_neutral.appxbundle'; LicenseFileName='CompanyPortal_License1.xml'
                Sha256=$files[0].Sha256;Size=(Get-Item (Join-Path $target 'CompanyPortal_11_2_1495_0_neutral.appxbundle')).Length
                DependencyCount=5;SourceKitSha256=('A'*64);Files=$files
            } | ConvertTo-Json -Depth 6 |
                Set-Content -LiteralPath (Join-Path $target 'CacheInfo.json') -Encoding UTF8

            Mock Test-OSDAppWinPE { $false }
            Mock Get-OSDAppCachePath { $cache }
            Mock Enter-OSDAppCacheLock { $null }
            Mock Save-OSDAppDownload { throw 'Microsoft download unavailable' }

            $result = Sync-OSDAppMicrosoftCompanyPortal -Architecture x64 -Confirm:$false -WarningAction SilentlyContinue
            $result.CacheReused | Should -BeTrue
            $result.Updated | Should -BeFalse
            $result.Files | Should -Be 7
            Should -Invoke Save-OSDAppDownload -Times 1 -Exactly

            Add-Content -LiteralPath (Join-Path $target 'Dependencies\one.appx') -Value 'tampered bytes'
            { Sync-OSDAppMicrosoftCompanyPortal -Architecture x64 -Confirm:$false -WarningAction SilentlyContinue } |
                Should -Throw '*Microsoft download unavailable*'
            Should -Invoke Save-OSDAppDownload -Times 2 -Exactly
        }
    }
}
