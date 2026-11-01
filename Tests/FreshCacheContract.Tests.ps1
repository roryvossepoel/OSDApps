Describe 'Fresh-cache-only vendor installer contract' {
    BeforeAll {
        $script:root = Split-Path $PSScriptRoot -Parent
        $script:paths = @(
            foreach ($folder in @('Public','Private','Runtime')) {
                Get-ChildItem -LiteralPath (Join-Path $script:root $folder) -File -Filter '*.ps1'
            }
        )
    }

    It 'contains no legacy cache migration entrypoints' {
        $obsolete = @(
            'Remove-' + 'LegacyMicrosoftTeamsCache'
            'Remove-OSDStageRetiredCacheVariant'
            'Remove-OSDStageBuiltInCacheAlias'
            'Allow' + 'LegacyConfiguration'
        )
        $violations = @(
            foreach ($file in $script:paths) {
                $source = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
                foreach ($name in $obsolete) {
                    if ($source.Contains($name)) { "$($file.Name): $name" }
                }
            }
        )
        @($violations).Count | Should -Be 0 -Because ($violations -join '; ')
    }

    It 'does not use generic MSI and EXE filenames for vendor-built-in payloads' {
        $generic = 'Package\.(?:msi|exe)\b'
        $violations = @(
            foreach ($file in $script:paths) {
                $source = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
                if ($source -match $generic) { $file.FullName }
            }
        )
        @($violations).Count | Should -Be 0 -Because ($violations -join '; ')
    }

    It 'never uses a generic ZIP filename for vendor-built-in payloads' {
        $vendorFiles = @(
            'Private/Add-OSDStageAdobeAcrobatUnified.ps1'
            'Public/Add-OSDStageAdobeAcrobatUnified.ps1'
            'Public/Sync-OSDStageAdobeAcrobatUnified.ps1'
            'Runtime/Invoke-OSDStagePreInstall.ps1'
            'Runtime/OSDStagePayloadFile.ps1'
            'Private/Get-OSDStageCachedPackageVersion.ps1'
        )
        $violations = @(
            foreach ($relative in $vendorFiles) {
                $source = Get-Content -LiteralPath (Join-Path $script:root $relative) -Raw -Encoding UTF8
                $codeLines = @($source -split '\r?\n' | Where-Object { $_.TrimStart() -notmatch '^#' })
                if (($codeLines -join "`n") -match 'Package\.zip') { $relative }
            }
        )
        @($violations).Count | Should -Be 0 -Because ($violations -join '; ')
    }

    It 'records the actual filename instead of an inferred file extension in new cache metadata' {
        foreach ($relative in @(
            'Private/Sync-OSDStageVendorBuiltInCache.ps1'
            'Runtime/Invoke-OSDStagePreInstall.ps1'
        )) {
            $source = Get-Content -LiteralPath (Join-Path $script:root $relative) -Raw -Encoding UTF8
            $source | Should -Match 'PayloadFileName' -Because "$relative must pin the acquired vendor filename"
        }
    }

    It 'retains the fixed OSDStage repository Package.zip contract' {
        $source = Get-Content -LiteralPath (Join-Path $script:root 'Public/New-OSDStagePackage.ps1') -Raw -Encoding UTF8
        $source | Should -Match 'Package\.zip'
    }

    It 'declares App, Script, Font, Certificate and Driver as the package type values' {
        $module = Import-Module (Join-Path $script:root 'OSDStage.psd1') -Force -PassThru
        $cmd = Get-Command Add-OSDStagePackage -Module OSDStage -ErrorAction Stop
        $choices = @($cmd.Parameters['PackageType'].Attributes |
            Where-Object { $_ -is [Management.Automation.ValidateSetAttribute] } |
            ForEach-Object { $_.ValidValues })
        @($choices | Sort-Object) | Should -Be @('App','Certificate','Driver','Font','Script')
        $meta = Get-Content -LiteralPath (Join-Path $script:root 'metadata/builtins.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $meta.PSObject.Properties.Name | Should -Contain 'Packages'
        $meta.PSObject.Properties.Name | Should -Not -Contain ('Applic' + 'ations')
        @($meta.Packages | Where-Object { $_.PSObject.Properties.Name -contains 'Aliases' }).Count |
            Should -Be 0
    }
}
