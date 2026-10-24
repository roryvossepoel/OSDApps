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
