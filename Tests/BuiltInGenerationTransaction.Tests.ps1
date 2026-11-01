BeforeAll { . (Join-Path $PSScriptRoot 'Helpers/NativePayloadFixtures.ps1') }
Describe 'Built-in cache generation transactions' {
    BeforeAll {
        $moduleRoot = Split-Path -Parent $PSScriptRoot
        Import-Module (Join-Path $moduleRoot 'OSDStage.psd1') -Force
    }

    It 'keeps the active generation unchanged when candidate validation fails' {
        InModuleScope OSDStage {
            $root = Join-Path $TestDrive 'BuiltIn\Example\x64'
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $root 'vendor-installer.msi') -Value 'old-generation' -Encoding ASCII
            $before = (Get-FileHash -LiteralPath (Join-Path $root 'vendor-installer.msi') -Algorithm SHA256).Hash

            {
                Invoke-OSDStageBuiltInCacheTransaction -Root $root -Build {
                    param($candidate)
                    Set-Content -LiteralPath (Join-Path $candidate 'vendor-installer.msi') -Value 'new-generation' -Encoding ASCII
                } -Validate { throw 'simulated candidate validation failure' }
            } | Should -Throw '*simulated candidate validation failure*'

            (Get-FileHash -LiteralPath (Join-Path $root 'vendor-installer.msi') -Algorithm SHA256).Hash | Should -Be $before
            @((Get-ChildItem -LiteralPath (Split-Path $root -Parent) -Directory | Where-Object Name -Like 'x64.osdstage-*')).Count | Should -Be 0
        }
    }

    It 'promotes one validated generation and removes transaction residue' {
        InModuleScope OSDStage {
            $root = Join-Path $TestDrive 'BuiltIn\Example\x64'
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $root 'vendor-installer.msi') -Value 'old-generation' -Encoding ASCII
            New-Item -ItemType Directory -Path "$root.osdstage-new-stale" -Force | Out-Null
            New-Item -ItemType Directory -Path "$root.osdstage-old-stale" -Force | Out-Null

            Invoke-OSDStageBuiltInCacheTransaction -Root $root -Build {
                param($candidate)
                Set-Content -LiteralPath (Join-Path $candidate 'vendor-installer.msi') -Value 'new-generation' -Encoding ASCII
            } -Validate {
                param($candidate)
                if ((Get-Content -LiteralPath (Join-Path $candidate 'vendor-installer.msi') -Raw).Trim() -ne 'new-generation') { throw 'invalid candidate' }
            } | Out-Null

            (Get-Content -LiteralPath (Join-Path $root 'vendor-installer.msi') -Raw).Trim() | Should -Be 'new-generation'
            @((Get-ChildItem -LiteralPath (Split-Path $root -Parent) -Directory | Where-Object Name -Like 'x64.osdstage-*')).Count | Should -Be 0
        }
    }

    It 'wires all non-Office public synchronizers through complete generation validation' {
        $ids = @('MicrosoftTeams','GoogleChromeEnterprise','MozillaFirefoxEnterprise','CiscoWebex','ZoomWorkplace','AdobeAcrobatUnified')
        foreach ($id in $ids) {
            $source = Get-Content -LiteralPath (Join-Path $moduleRoot "Public\Sync-OSDStage$id.ps1") -Raw
            $source | Should -Match 'Invoke-OSDStageBuiltInCacheTransaction|Sync-OSDStageVendorBuiltInCache'
        }
    }

    It 'routes each SetupComplete MSI and ZIP branch through the validated transaction helper' {
        $path = Join-Path $moduleRoot 'Runtime\Invoke-OSDStagePreInstall.ps1'
        $tokens = $null
        $parseErrors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$parseErrors)
        @($parseErrors).Count | Should -Be 0
        $helper = $ast.Find({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Sync-PreInstallVendorMsi'
        },$true)
        $helper | Should -Not -BeNullOrEmpty
        $helper.Extent.Text | Should -Match 'Invoke-OSDStageBuiltInCacheTransaction'
        $helper.Extent.Text | Should -Match 'Assert-SelectedPayload'
        $helper.Extent.Text | Should -Match '-Validate'
        $dispatch = $ast.Find({
            param($node)
            $node -is [Management.Automation.Language.SwitchStatementAst] -and $node.Condition.Extent.Text -eq '$app.Id'
        },$true)
        $dispatch | Should -Not -BeNullOrEmpty
        foreach ($id in @('GoogleChromeEnterprise','MozillaFirefoxEnterprise','CiscoWebex','ZoomWorkplace','AdobeAcrobatUnified')) {
            $clauses = @($dispatch.Clauses | Where-Object { $_.Item1.Value -eq $id })
            $clauses.Count | Should -Be 1 -Because "$id must have one explicit acquisition branch"
            $clauses[0].Item2.Extent.Text | Should -Match 'Sync-PreInstallVendorMsi' -Because "$id must use the shared validated transaction"
        }
        $adobe = @($dispatch.Clauses | Where-Object { $_.Item1.Value -eq 'AdobeAcrobatUnified' })[0]
        $adobe.Item2.Extent.Text | Should -Match '-ExpectedExtension ''.zip'''
        $teams = @($dispatch.Clauses | Where-Object { $_.Item1.Value -eq 'MicrosoftTeams' })
        $teams.Count | Should -Be 1
        $teams[0].Item2.Extent.Text | Should -Match 'Invoke-OSDStageBuiltInCacheTransaction'
        $teams[0].Item2.Extent.Text | Should -Match 'Assert-OSDStageCachedPayload'
        $teams[0].Item2.Extent.Text | Should -Match '-Validate'
    }
}
