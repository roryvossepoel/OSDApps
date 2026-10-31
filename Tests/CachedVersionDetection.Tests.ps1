BeforeAll { . (Join-Path $PSScriptRoot 'Helpers/NativePayloadFixtures.ps1') }
Describe 'Built-in cache version detection (read-only)' {
    BeforeAll {
        $script:root = Split-Path -Path $PSScriptRoot -Parent
        Import-Module (Join-Path $script:root 'OSDStage.psd1') -Force
    }

    It 'reads the Acrobat patch build from setup.ini inside ZIP without extracting it' {
        InModuleScope OSDStage {
            Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
            $cache = Join-Path $TestDrive 'Adobe'
            New-Item -ItemType Directory -Path $cache -Force | Out-Null
            $path = Join-Path $cache 'Acrobat_DC_Web_x64_WWMUI.zip'
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
            $result = Get-OSDStageCachedPackageVersion -Id AdobeAcrobatUnified -CacheEntryPath $cache -PayloadPath $path
            $result.Version | Should -Be '26.002.21931'
            $result.VersionSource | Should -Be 'AdobePatchFileName'
            (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash | Should -Be $hashBefore
            (Get-ChildItem -LiteralPath $cache -File).Count | Should -Be 1
        }
    }

    It 'does not invent an Acrobat version when setup.ini has no matching patch' {
        InModuleScope OSDStage {
            Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
            $cache = Join-Path $TestDrive 'AdobeWithoutPatch'
            New-Item -ItemType Directory -Path $cache -Force | Out-Null
            $path = Join-Path $cache 'Acrobat_DC_Web_x64_WWMUI.zip'
            $archive = [System.IO.Compression.ZipFile]::Open($path,[System.IO.Compression.ZipArchiveMode]::Create)
            try {
                $entry = $archive.CreateEntry('Adobe Acrobat/setup.ini')
                $writer = [System.IO.StreamWriter]::new($entry.Open())
                try { $writer.WriteLine('[Product]'); $writer.WriteLine('msi=AcroPro.msi') }
                finally { $writer.Dispose() }
            }
            finally { $archive.Dispose() }
            $result = Get-OSDStageCachedPackageVersion -Id AdobeAcrobatUnified -CacheEntryPath $cache -PayloadPath $path
            $result.Version | Should -BeNullOrEmpty
            $result.VersionSource | Should -BeNullOrEmpty
        }
    }

    It 'routes Chrome, Webex, Zoom and Firefox to MSI ProductVersion without installing software' {
        InModuleScope OSDStage {
            $cache = Join-Path $TestDrive 'Msi'
            New-Item -ItemType Directory -Path $cache -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $cache 'vendor-installer.msi') -Value 'test sentinel' -Encoding ASCII
            Mock Get-OSDStageMsiProductVersion { '155.0.999.0' }
            foreach ($id in @('GoogleChromeEnterprise','CiscoWebex','ZoomWorkplace','MozillaFirefoxEnterprise')) {
                $version = Get-OSDStageCachedPackageVersion -Id $id -CacheEntryPath $cache -PayloadPath (Join-Path $cache 'vendor-installer.msi')
                $version.Version | Should -Be '155.0.999.0'
                $version.VersionSource | Should -Be 'MsiProductVersion'
            }
            Should -Invoke Get-OSDStageMsiProductVersion -Exactly 4
        }
    }

    It 'reads preexisting CacheInfo version without MSI COM on WinPE' {
        InModuleScope OSDStage {
            $cache = Join-Path $TestDrive 'Usb\OSDStage'
            $builtin = Join-Path $cache 'BuiltIn\GoogleChromeEnterprise\x64'
            New-Item -ItemType Directory -Path $builtin -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $builtin 'vendor-installer.msi') -Value 'original' -Encoding ASCII
            $infoPath = Join-Path $builtin 'CacheInfo.json'
            '{"Id":"GoogleChromeEnterprise","Version":"123.4.5","Architecture":"x64","VersionSource":"MsiProductVersion"}' |
                Set-Content -LiteralPath $infoPath -Encoding UTF8
            $record = Get-Content -LiteralPath $infoPath -Raw | ConvertFrom-Json
            Set-OSDStageTestPayloadInfo -Path (Join-Path $builtin 'vendor-installer.msi') -Id $record.Id -Metadata @{Version=$record.Version;VersionSource=$record.VersionSource}
            $before = (Get-FileHash -LiteralPath $infoPath -Algorithm SHA256).Hash
            $script:FixtureCachePath = $cache
            Mock Get-OSDStageCachePath { $script:FixtureCachePath }
            Mock Test-OSDStageWinPE { $true }
            Mock Get-OSDStageCachedPackageVersion { throw 'Version resolver must not run in WinPE' }

            $entries = @(Get-OSDStageCache -ResolveVersions)
            $entries.Count | Should -Be 1
            $entries[0].Version | Should -Be '123.4.5'
            $entries[0].VersionSource | Should -Be 'MsiProductVersion'
            Should -Invoke Get-OSDStageCachedPackageVersion -Exactly 0
            (Get-FileHash -LiteralPath $infoPath -Algorithm SHA256).Hash | Should -Be $before
        }
    }

    It 'can inspect a recorded Current-only payload from Windows without writing metadata' {
        InModuleScope OSDStage {
            $cache = Join-Path $TestDrive 'UsbCurrent\OSDStage'
            $builtin = Join-Path $cache 'BuiltIn\CiscoWebex\x64'
            New-Item -ItemType Directory -Path $builtin -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $builtin 'vendor-installer.msi') -Value 'original' -Encoding ASCII
            $infoPath = Join-Path $builtin 'CacheInfo.json'
            '{"Id":"CiscoWebex","Version":"Current","Architecture":"x64"}' |
                Set-Content -LiteralPath $infoPath -Encoding UTF8
            $record = Get-Content -LiteralPath $infoPath -Raw | ConvertFrom-Json
            Set-OSDStageTestPayloadInfo -Path (Join-Path $builtin 'vendor-installer.msi') -Id $record.Id -Metadata @{Version=$record.Version;VersionSource=$record.VersionSource}
            $before = (Get-FileHash -LiteralPath $infoPath -Algorithm SHA256).Hash

            $script:FixtureCachePath = $cache
            Mock Get-OSDStageCachePath { $script:FixtureCachePath }
            Mock Test-OSDStageWinPE { $false }
            Mock Get-OSDStageCachedPackageVersion {
                [pscustomobject]@{Version='45.6.123';VersionSource='MsiProductVersion'}
            }

            $default = @(Get-OSDStageCache)
            $default[0].Version | Should -Be 'Current'
            Should -Invoke Get-OSDStageCachedPackageVersion -Exactly 0

            $resolved = @(Get-OSDStageCache -ResolveVersions)
            $resolved[0].Version | Should -Be '45.6.123'
            $resolved[0].VersionSource | Should -Be 'MsiProductVersion'
            Should -Invoke Get-OSDStageCachedPackageVersion -Exactly 1
            (Get-FileHash -LiteralPath $infoPath -Algorithm SHA256).Hash | Should -Be $before
        }
    }

    It 'does not inspect an invalid cached payload' {
        InModuleScope OSDStage {
            $cache = Join-Path $TestDrive 'UsbInvalid\OSDStage'
            $builtin = Join-Path $cache 'BuiltIn\GoogleChromeEnterprise\x64'
            New-Item -ItemType Directory -Path $builtin -Force | Out-Null
            $infoPath = Join-Path $builtin 'CacheInfo.json'
            '{"Id":"GoogleChromeEnterprise","Version":"Current","Architecture":"x64"}' |
                Set-Content -LiteralPath $infoPath -Encoding UTF8

            $script:FixtureCachePath = $cache
            Mock Get-OSDStageCachePath { $script:FixtureCachePath }
            Mock Test-OSDStageWinPE { $false }
            Mock Get-OSDStageCachedPackageVersion { throw 'Do not inspect invalid files' }

            $result = @(Get-OSDStageCache -ResolveVersions)
            $result.Count | Should -Be 1
            $result[0].Valid | Should -BeFalse
            $result[0].Version | Should -Be 'Current'
            Should -Invoke Get-OSDStageCachedPackageVersion -Exactly 0
        }
    }
    It 'returns exactly one trimmed MSI version when COM Execute and Close emit whitespace' {
        InModuleScope OSDStage {
            $file = Join-Path $TestDrive 'Mock.msi'
            Set-Content -LiteralPath $file -Value 'test' -Encoding ASCII
            Mock Test-OSDStageWinPE { $false }
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

            $result = @(Get-OSDStageMsiProductVersion -Path $file)
            $result.Count | Should -Be 1
            $result[0] | Should -Be '157.0.1.0'
            $result[0][0] | Should -Be '1'
            $result[0].EndsWith(' ') | Should -BeFalse
        }
    }

    It 'trims whitespace from built-in cache metadata without modifying USB files' {
        InModuleScope OSDStage {
            $cache = Join-Path $TestDrive 'WhitespaceUsb\OSDStage'
            $entry = Join-Path $cache 'BuiltIn\CiscoWebex\x64'
            New-Item -ItemType Directory -Path $entry -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $entry 'vendor-installer.msi') -Value 'mock' -Encoding ASCII
            $infoPath = Join-Path $entry 'CacheInfo.json'
            '{"Id":"CiscoWebex","Version":" 46.9.0.35800 ","Architecture":"x64","VersionSource":"MsiProductVersion"}' |
                Set-Content -LiteralPath $infoPath -Encoding UTF8
            Set-OSDStageTestPayloadInfo -Path (Join-Path $entry 'vendor-installer.msi') -Id CiscoWebex -Metadata @{Version=' 46.9.0.35800 ';VersionSource='MsiProductVersion'}
            $hash = (Get-FileHash -LiteralPath $infoPath -Algorithm SHA256).Hash
            $script:FixtureCachePath = $cache
            Mock Get-OSDStageCachePath { $script:FixtureCachePath }
            Mock Get-OSDStageCachedPackageVersion { throw 'Should use existing cache metadata' }

            $found = @(Get-OSDStageCache -ResolveVersions)
            $found.Count | Should -Be 1
            $found[0].Version | Should -Be '46.9.0.35800'
            $found[0].VersionSource | Should -Be 'MsiProductVersion'
            (Get-FileHash -LiteralPath $infoPath -Algorithm SHA256).Hash | Should -Be $hash
            Should -Invoke Get-OSDStageCachedPackageVersion -Exactly 0
        }
    }

    It 'trims a vendor version returned by the MSI reader before exposing it' {
        InModuleScope OSDStage {
            $entry = Join-Path $TestDrive 'MsiSpaces'
            New-Item -ItemType Directory -Path $entry -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $entry 'vendor-installer.msi') 'fixture'
            Mock Get-OSDStageMsiProductVersion { ' 155.0.8059.40 ' }
            $result = Get-OSDStageCachedPackageVersion -Id GoogleChromeEnterprise -CacheEntryPath $entry -PayloadPath (Join-Path $entry 'vendor-installer.msi')
            $result.Version | Should -Be '155.0.8059.40'
        }
    }

}
