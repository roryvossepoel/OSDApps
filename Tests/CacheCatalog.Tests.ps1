Describe 'Repository cache catalog merge' {
    BeforeAll {
        $script:moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $script:manifestPath = Join-Path $script:moduleRoot 'OSDStage.psd1'
        Remove-Module OSDStage -Force -ErrorAction SilentlyContinue
        Import-Module $script:manifestPath -Force
    }

    It 'preserves existing cached apps during selective synchronization' {
        InModuleScope OSDStage {
            $sourceRoot = Join-Path $TestDrive 'SourceRepository'
            $cacheRoot = Join-Path $TestDrive 'Cache'
            New-Item -ItemType Directory -Path $sourceRoot,$cacheRoot -Force | Out-Null

            function New-TestPackage {
                param([string]$Id,[string]$Version)
                $packageDir = Join-Path $sourceRoot "Packages\$Id\$Version\x64"
                $payloadRoot = Join-Path $TestDrive "Payload-$Id\Package"
                New-Item -ItemType Directory -Path $packageDir,$payloadRoot -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $payloadRoot 'Install.ps1') -Value 'exit 0' -Encoding UTF8
                $zip = Join-Path $packageDir 'Package.zip'
                Compress-Archive -Path $payloadRoot -DestinationPath $zip -Force
                $hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
                @{
                    SchemaVersion=2; Id=$Id; DisplayName=$Id; Version=$Version; Architecture='x64'; SuccessCodes=@(0,3010);
                    Payload=@{FileName='Package.zip';Sha256=$hash}
                } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $packageDir 'manifest.json') -Encoding UTF8
                return "Packages/$Id/$Version/x64/manifest.json"
            }

            $a = New-TestPackage -Id AppA -Version 1.0.0
            $b = New-TestPackage -Id AppB -Version 1.0.0

            @{
                SchemaVersion=2
                GeneratedAt=(Get-Date).ToUniversalTime().ToString('o')
                Packages=@(
                    @{Id='AppA';Architectures=@(@{Architecture='x64';Manifest=$a})},
                    @{Id='AppB';Architectures=@(@{Architecture='x64';Manifest=$b})}
                )
            } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $sourceRoot 'catalog.json') -Encoding UTF8

            Sync-OSDStageCache -CatalogPath (Join-Path $sourceRoot 'catalog.json') -CachePath $cacheRoot -Name AppA -Confirm:$false | Out-Null
            Sync-OSDStageCache -CatalogPath (Join-Path $sourceRoot 'catalog.json') -CachePath $cacheRoot -Name AppB -Confirm:$false | Out-Null

            $cacheCatalog = Get-Content -LiteralPath (Join-Path $cacheRoot 'CacheCatalog.json') -Raw | ConvertFrom-Json
            @($cacheCatalog.Packages.Id | Sort-Object) | Should -Be @('AppA','AppB')
        }
    }
}
