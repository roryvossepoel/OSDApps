Describe 'Built-in app architecture contracts' {
    BeforeAll {
        $moduleRoot = Split-Path -Parent $PSScriptRoot
        Import-Module (Join-Path $moduleRoot 'OSDApps.psd1') -Force
        $metadata = Get-Content -LiteralPath (Join-Path $moduleRoot 'metadata\builtins.json') -Raw | ConvertFrom-Json
    }

    It 'requires one explicit runtime architecture and keeps other app defaults' {
        foreach ($app in $metadata.Apps) {
            if ($app.PackageType -eq 'Script') {
                $app.Architectures | Should -Be @('any')
                $app.DefaultArchitecture | Should -Be 'any'
                (Get-Command $app.AddCommand).Parameters.ContainsKey('Architecture') | Should -BeFalse
                continue
            }
            foreach ($name in @($app.AddCommand,$app.SyncCommand)) {
                $command = Get-Command $name
                if ($app.Id -in @('VisualCRedist','DotNetRuntime')) {
                    $app.DefaultArchitecture | Should -BeNullOrEmpty
                    $app.ArchitectureRequired | Should -BeTrue
                    $command.Parameters['Architecture'].ParameterType | Should -Be ([string])
                    @($command.Parameters['Architecture'].Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory }).Count | Should -BeGreaterThan 0
                    $command.Definition | Should -Not -Match '\$Architecture\s*='
                    { & $name -Architecture @('x86','x64') -WhatIf } | Should -Throw
                } else {
                    $app.DefaultArchitecture | Should -Be 'x64'
                    $command.Definition | Should -Match '\$Architecture\s*=\s*''x64'''
                }
            }
        }
    }

    It 'exposes only the advertised architectures' {
        foreach ($app in $metadata.Apps) {
            if ($app.PackageType -eq 'Script') {
                (Get-Command $app.AddCommand).Parameters.ContainsKey('Architecture') | Should -BeFalse
                continue
            }
            foreach ($name in @($app.AddCommand,$app.SyncCommand)) {
                $command = Get-Command $name
                $validation = @($command.Parameters['Architecture'].Attributes |
                    Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] })
                $validation.Count | Should -Be 1
                @($validation[0].ValidValues | Sort-Object) | Should -Be @($app.Architectures | Sort-Object)
            }
        }
    }

    It 'does not expose Auto or numeric Office values' {
        foreach ($app in $metadata.Apps) {
            $app.Architectures | Should -Not -Contain 'Auto'
            $app.Architectures | Should -Not -Contain '32'
            $app.Architectures | Should -Not -Contain '64'
        }
    }
}
