Describe 'Built-in metadata' {
    BeforeAll {
        $script:moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $script:manifestPath = Join-Path $script:moduleRoot 'OSDApps.psd1'
        $script:metadataPath = Join-Path $script:moduleRoot 'metadata\builtins.json'

        Remove-Module OSDApps -Force -ErrorAction SilentlyContinue
        Import-Module $script:manifestPath -Force

        $script:metadata = Get-Content -LiteralPath $script:metadataPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }

    It 'uses the supported metadata schema' {
        $script:metadata.SchemaVersion | Should -Be 1
        $script:metadata.Project | Should -Be 'OSDApps'
    }

    It 'contains unique built-in application ids' {
        $ids = @($script:metadata.Applications.Id)
        @($ids | Select-Object -Unique).Count | Should -Be $ids.Count
    }

    It 'uses unique cache aliases that never collide with canonical ids' {
        $ids = @($script:metadata.Applications.Id)
        $aliases = @($script:metadata.Applications | ForEach-Object { @($_.Aliases) } | Where-Object { $_ })
        @($aliases | Select-Object -Unique).Count | Should -Be $aliases.Count
        foreach ($alias in $aliases) {
            $alias | Should -Not -BeIn $ids
            $alias | Should -Match '^[A-Za-z0-9][A-Za-z0-9._-]*$'
        }
    }

    It 'contains required fields for every built-in' {
        foreach ($app in @($script:metadata.Applications)) {
            $app.Id | Should -Not -BeNullOrEmpty
            $app.DisplayName | Should -Not -BeNullOrEmpty
            $app.Source | Should -Be 'BuiltIn'
            $app.Vendor | Should -Not -BeNullOrEmpty
            $app.Acquisition | Should -Not -BeNullOrEmpty
            $app.SyncPhase | Should -Be 'FullWindowsPreInstall'
            $app.AddCommand | Should -Not -BeNullOrEmpty
            $app.SyncCommand | Should -Not -BeNullOrEmpty
            @($app.Architectures).Count | Should -BeGreaterThan 0
            $app.CachePath | Should -Not -BeNullOrEmpty
            $app.IconUrl | Should -Match '^https://'
        }
    }

    It 'keeps public raw icon URLs aligned with tracked SVG files' {
        foreach ($app in @($script:metadata.Applications)) {
            $expectedUrl = 'https://raw.githubusercontent.com/roryvossepoel/OSDApps/main/metadata/icons/'
            $app.IconUrl.StartsWith($expectedUrl) | Should -BeTrue
            $fileName = $app.IconUrl.Substring($expectedUrl.Length)
            $fileName.EndsWith('.svg') | Should -BeTrue
            (Test-Path -LiteralPath (Join-Path $script:moduleRoot ('metadata/icons/' + $fileName)) -PathType Leaf) | Should -BeTrue
        }
    }

    It 'advertises Cisco Webex with the stable viewer contract' {
        $webex = @($script:metadata.Applications | Where-Object Id -eq 'CiscoWebex')
        $webex.Count | Should -Be 1
        $webex[0].AddCommand | Should -Be 'Add-OSDAppCiscoWebex'
        $webex[0].SyncCommand | Should -Be 'Sync-OSDAppCiscoWebex'
        $webex[0].CachePath | Should -Be 'BuiltIn/CiscoWebex/<architecture>'
        @($webex[0].Architectures | Sort-Object) | Should -Be @('arm64','x64')
    }

    It 'maps every metadata command to an exported function' {
        $exported = @(Get-Command -Module OSDApps -CommandType Function | Select-Object -ExpandProperty Name)
        foreach ($app in @($script:metadata.Applications)) {
            $app.AddCommand | Should -BeIn $exported
            $app.SyncCommand | Should -BeIn $exported
        }
    }
    It 'contains every exported built-in Add command' {
        $exportedBuiltIns = @(
            Get-Command -Module OSDApps -CommandType Function |
                Select-Object -ExpandProperty Name |
                Where-Object {
                    $_ -like 'Add-OSDApp*' -and
                    $_ -notin @('Add-OSDApp','Add-OSDAppPackage')
                } |
                Sort-Object
        )

        $metadataCommands = @($script:metadata.Applications.AddCommand | Sort-Object)

        Compare-Object -ReferenceObject $exportedBuiltIns -DifferenceObject $metadataCommands |
            Should -BeNullOrEmpty
    }
}
