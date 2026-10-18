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
            foreach ($id in @('GoogleChromeEnterprise','CiscoWebex','ZoomWorkplace','MozillaFirefoxEnterprise')) {
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
    It 'returns exactly one trimmed MSI version when COM Execute and Close emit whitespace' {
        InModuleScope OSDApps {
            $file = Join-Path $TestDrive 'Mock.msi'
            Set-Content -LiteralPath $file -Value 'test' -Encoding ASCII
            Mock Test-OSDAppWinPE { $false }
            Mock New-Object {
                $record = [pscustomobject]@{}
                $record | Add-Member -MemberType ScriptMethod -Name StringData -Value {
                    param([int]$column)
                    ' 157.0.1.0 '
                }
                $view = [pscustomobject]@{ Record = $record }
                $view | Add-Member -MemberType ScriptMethod -Name Execute -Value { '' }
                $view | Add-Member -MemberType ScriptMethod -Name Fetch -Value { $this.Record }
                $view | Add-Member -MemberType ScriptMethod -Name Close -Value { '' }
                $db = [pscustomobject]@{ View = $view }
                $db | Add-Member -MemberType ScriptMethod -Name OpenView -Value {
                    param([string]$sql)
                    $this.View
                }
                $installer = [pscustomobject]@{ Database = $db }
                $installer | Add-Member -MemberType ScriptMethod -Name OpenDatabase -Value {
                    param([string]$path,[int]$mode)
                    $this.Database
                }
                $installer
            } -ParameterFilter { $ComObject -eq 'WindowsInstaller.Installer' }

            $result = @(Get-OSDAppMsiProductVersion -Path $file)
            $result.Count | Should -Be 1
            $result[0] | Should -Be '157.0.1.0'
            $result[0][0] | Should -Be '1'
            $result[0].EndsWith(' ') | Should -BeFalse
        }
    }

    It 'trims whitespace from old built-in cache metadata without modifying USB files' {
        InModuleScope OSDApps {
            $cache = Join-Path $TestDrive 'WhitespaceUsb\OSDApps'
            $entry = Join-Path $cache 'BuiltIn\CiscoWebex\x64'
            New-Item -ItemType Directory -Path $entry -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $entry 'Package.msi') -Value 'mock' -Encoding ASCII
            $infoPath = Join-Path $entry 'CacheInfo.json'
            '{"Id":"CiscoWebex","Version":" 46.9.0.35800 ","Architecture":"x64","VersionSource":"MsiProductVersion"}' |
                Set-Content -LiteralPath $infoPath -Encoding UTF8
            $hash = (Get-FileHash -LiteralPath $infoPath -Algorithm SHA256).Hash
            $script:FixtureCachePath = $cache
            Mock Get-OSDAppCachePath { $script:FixtureCachePath }
            Mock Get-OSDAppCachedPackageVersion { throw 'Should use existing cache metadata' }

            $found = @(Get-OSDAppCache -ResolveVersions)
            $found.Count | Should -Be 1
            $found[0].Version | Should -Be '46.9.0.35800'
            $found[0].VersionSource | Should -Be 'MsiProductVersion'
            (Get-FileHash -LiteralPath $infoPath -Algorithm SHA256).Hash | Should -Be $hash
            Should -Invoke Get-OSDAppCachedPackageVersion -Exactly 0
        }
    }

    It 'trims a vendor version returned by the MSI reader before exposing it' {
        InModuleScope OSDApps {
            $entry = Join-Path $TestDrive 'MsiSpaces'
            New-Item -ItemType Directory -Path $entry -Force | Out-Null
            Mock Get-OSDAppMsiProductVersion { ' 155.0.8059.40 ' }
            $result = Get-OSDAppCachedPackageVersion -Id GoogleChromeEnterprise -CacheEntryPath $entry
            $result.Version | Should -Be '155.0.8059.40'
        }
    }

}
