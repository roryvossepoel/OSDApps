Describe 'Built-in cache version detection (read-only)' {
    BeforeAll {
        $script:root = Split-Path -Path $PSScriptRoot -Parent
        Import-Module (Join-Path $script:root 'OSDApps.psd1') -Force
    }

    It 'reads the Acrobat patch build from setup.ini inside ZIP without extracting it' {
        InModuleScope OSDApps {
            Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
            $cache = Join-Path $TestDrive 'Adobe'
            New-Item -ItemType Directory -Path $cache -Force | Out-Null
            $path = Join-Path $cache 'Package.zip'
            $archive = [System.IO.Compression.ZipFile]::Open($path,[System.IO.Compression.ZipArchiveMode]::Create)
            try {
                $entry = $archive.CreateEntry('Adobe Acrobat/setup.ini')
                $writer = [System.IO.StreamWriter]::new($entry.Open())
                try {
                    $writer.WriteLine('[Startup]')
                    $writer.WriteLine('RequireOS=Windows 10')
                    $writer.WriteLine('[Product]')
                    $writer.WriteLine('PATCH=AcrobatDCx64Upd2600221931.msp')
                    $writer.WriteLine('msi=AcroPro.msi')
                }
                finally { $writer.Dispose() }
            }
            finally { $archive.Dispose() }

            $hashBefore = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
            $result = Get-OSDAppCachedPackageVersion -Id AdobeAcrobatUnified -CacheEntryPath $cache
            $result.Version | Should -Be '26.002.21931'
            $result.VersionSource | Should -Be 'AdobePatchFileName'
            (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash | Should -Be $hashBefore
            (Get-ChildItem -LiteralPath $cache -File).Count | Should -Be 1
        }
    }

    It 'does not invent an Acrobat version when setup.ini has no matching patch' {
        InModuleScope OSDApps {
            Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
            $cache = Join-Path $TestDrive 'AdobeWithoutPatch'
            New-Item -ItemType Directory -Path $cache -Force | Out-Null
            $path = Join-Path $cache 'Package.zip'
            $archive = [System.IO.Compression.ZipFile]::Open($path,[System.IO.Compression.ZipArchiveMode]::Create)
            try {
                $entry = $archive.CreateEntry('Adobe Acrobat/setup.ini')
                $writer = [System.IO.StreamWriter]::new($entry.Open())
                try { $writer.WriteLine('[Product]'); $writer.WriteLine('msi=AcroPro.msi') }
                finally { $writer.Dispose() }
            }
            finally { $archive.Dispose() }
            $result = Get-OSDAppCachedPackageVersion -Id AdobeAcrobatUnified -CacheEntryPath $cache
            $result.Version | Should -BeNullOrEmpty
            $result.VersionSource | Should -BeNullOrEmpty
        }
    }

    It 'routes Chrome, Webex and Firefox to MSI ProductVersion without installing software' {
        InModuleScope OSDApps {
            $cache = Join-Path $TestDrive 'Msi'
            New-Item -ItemType Directory -Path $cache -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $cache 'Package.msi') -Value 'test sentinel' -Encoding ASCII
            Mock Get-OSDAppMsiProductVersion { '155.0.999.0' }
            foreach ($id in @('GoogleChromeEnterprise','CiscoWebex','MozillaFirefoxEnterprise')) {
                $version = Get-OSDAppCachedPackageVersion -Id $id -CacheEntryPath $cache
                $version.Version | Should -Be '155.0.999.0'
                $version.VersionSource | Should -Be 'MsiProductVersion'
            }
            Should -Invoke Get-OSDAppMsiProductVersion -Exactly 3
        }
    }

    It 'reads preexisting CacheInfo version without MSI COM on WinPE' {
        InModuleScope OSDApps {
            $cache = Join-Path $TestDrive 'Usb\OSDApps'
            $builtin = Join-Path $cache 'BuiltIn\GoogleChromeEnterprise\x64'
            New-Item -ItemType Directory -Path $builtin -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $builtin 'Package.msi') -Value 'original' -Encoding ASCII
            $infoPath = Join-Path $builtin 'CacheInfo.json'
            '{"Id":"GoogleChromeEnterprise","Version":"123.4.5","Architecture":"x64","VersionSource":"MsiProductVersion"}' |
                Set-Content -LiteralPath $infoPath -Encoding UTF8
            $before = (Get-FileHash -LiteralPath $infoPath -Algorithm SHA256).Hash
            $script:FixtureCachePath = $cache
            Mock Get-OSDAppCachePath { $script:FixtureCachePath }
            Mock Test-OSDAppWinPE { $true }
            Mock Get-OSDAppCachedPackageVersion { throw 'Version resolver must not run in WinPE' }

            $entries = @(Get-OSDAppCache -ResolveVersions)
            $entries.Count | Should -Be 1
            $entries[0].Version | Should -Be '123.4.5'
            $entries[0].VersionSource | Should -Be 'MsiProductVersion'
            Should -Invoke Get-OSDAppCachedPackageVersion -Exactly 0
            (Get-FileHash -LiteralPath $infoPath -Algorithm SHA256).Hash | Should -Be $before
        }
    }

    It 'can inspect a legacy Current-only cache from Windows without writing metadata' {
        InModuleScope OSDApps {
            $cache = Join-Path $TestDrive 'UsbLegacy\OSDApps'
            $builtin = Join-Path $cache 'BuiltIn\CiscoWebex\x64'
            New-Item -ItemType Directory -Path $builtin -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $builtin 'Package.msi') -Value 'original' -Encoding ASCII
            $infoPath = Join-Path $builtin 'CacheInfo.json'
            '{"Id":"CiscoWebex","Version":"Current","Architecture":"x64"}' |
                Set-Content -LiteralPath $infoPath -Encoding UTF8
            $before = (Get-FileHash -LiteralPath $infoPath -Algorithm SHA256).Hash

            $script:FixtureCachePath = $cache
            Mock Get-OSDAppCachePath { $script:FixtureCachePath }
            Mock Test-OSDAppWinPE { $false }
            Mock Get-OSDAppCachedPackageVersion {
                [pscustomobject]@{Version='45.6.123';VersionSource='MsiProductVersion'}
            }

            $default = @(Get-OSDAppCache)
            $default[0].Version | Should -Be 'Current'
            Should -Invoke Get-OSDAppCachedPackageVersion -Exactly 0

            $resolved = @(Get-OSDAppCache -ResolveVersions)
            $resolved[0].Version | Should -Be '45.6.123'
            $resolved[0].VersionSource | Should -Be 'MsiProductVersion'
            Should -Invoke Get-OSDAppCachedPackageVersion -Exactly 1
            (Get-FileHash -LiteralPath $infoPath -Algorithm SHA256).Hash | Should -Be $before
        }
    }

    It 'does not inspect an invalid cached payload' {
        InModuleScope OSDApps {
            $cache = Join-Path $TestDrive 'UsbInvalid\OSDApps'
            $builtin = Join-Path $cache 'BuiltIn\GoogleChromeEnterprise\x64'
            New-Item -ItemType Directory -Path $builtin -Force | Out-Null
            $infoPath = Join-Path $builtin 'CacheInfo.json'
            '{"Id":"GoogleChromeEnterprise","Version":"Current","Architecture":"x64"}' |
                Set-Content -LiteralPath $infoPath -Encoding UTF8

            $script:FixtureCachePath = $cache
            Mock Get-OSDAppCachePath { $script:FixtureCachePath }
            Mock Test-OSDAppWinPE { $false }
            Mock Get-OSDAppCachedPackageVersion { throw 'Do not inspect invalid files' }

            $result = @(Get-OSDAppCache -ResolveVersions)
            $result.Count | Should -Be 1
            $result[0].Valid | Should -BeFalse
            $result[0].Version | Should -Be 'Current'
            Should -Invoke Get-OSDAppCachedPackageVersion -Exactly 0
        }
    }
}
