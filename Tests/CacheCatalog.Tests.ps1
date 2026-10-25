Describe 'Repository cache catalog merge' {
    BeforeAll {
        $script:moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $script:manifestPath = Join-Path $script:moduleRoot 'OSDApps.psd1'
        Remove-Module OSDApps -Force -ErrorAction SilentlyContinue
        Import-Module $script:manifestPath -Force
    }

    It 'preserves existing cached apps during selective synchronization' {
        InModuleScope OSDApps {
            $sourceRoot = Join-Path $TestDrive 'SourceRepository'
            $cacheRoot = Join-Path $TestDrive 'Cache'
            New-Item -ItemType Directory -Path $sourceRoot,$cacheRoot -Force | Out-Null

            function New-TestPackage {
                param([string]$Id,[string]$Version)
                $packageDir = Join-Path $sourceRoot "Apps\$Id\$Version\x64"
                $payloadRoot = Join-Path $TestDrive "Payload-$Id\Package"
                New-Item -ItemType Directory -Path $packageDir,$payloadRoot -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $payloadRoot 'Install.ps1') -Value 'exit 0' -Encoding UTF8
                $zip = Join-Path $packageDir 'Package.zip'
                Compress-Archive -Path $payloadRoot -DestinationPath $zip -Force
                $hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
                @{
                    SchemaVersion=1; Id=$Id; DisplayName=$Id; Version=$Version; Architecture='x64'; SuccessCodes=@(0,3010);
                    Archive=@{FileName='Package.zip';Sha256=$hash}
                } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $packageDir 'manifest.json') -Encoding UTF8
                return "Apps/$Id/$Version/x64/manifest.json"
            }

            $a = New-TestPackage -Id AppA -Version 1.0.0
            $b = New-TestPackage -Id AppB -Version 1.0.0

            @{
                SchemaVersion=1
                GeneratedAt=(Get-Date).ToUniversalTime().ToString('o')
                Apps=@(
                    @{Id='AppA';Packages=@(@{Architecture='x64';Manifest=$a})},
                    @{Id='AppB';Packages=@(@{Architecture='x64';Manifest=$b})}
                )
            } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $sourceRoot 'catalog.json') -Encoding UTF8

            Sync-OSDAppCache -CatalogPath (Join-Path $sourceRoot 'catalog.json') -CachePath $cacheRoot -Name AppA -Confirm:$false | Out-Null
            Sync-OSDAppCache -CatalogPath (Join-Path $sourceRoot 'catalog.json') -CachePath $cacheRoot -Name AppB -Confirm:$false | Out-Null

            $cacheCatalog = Get-Content -LiteralPath (Join-Path $cacheRoot 'CacheCatalog.json') -Raw | ConvertFrom-Json
            @($cacheCatalog.Packages.Id | Sort-Object) | Should -Be @('AppA','AppB')
        }
    }
}
