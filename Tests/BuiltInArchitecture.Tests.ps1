Describe 'Built-in application architecture contracts' {
    BeforeAll {
        $moduleRoot = Split-Path -Parent $PSScriptRoot
        Import-Module (Join-Path $moduleRoot 'OSDApps.psd1') -Force
        $metadata = Get-Content -LiteralPath (Join-Path $moduleRoot 'metadata\builtins.json') -Raw | ConvertFrom-Json
    }

    It 'defaults applications to x64 and Visual C++ to both supported architectures' {
        foreach ($app in $metadata.Applications) {
            $app.DefaultArchitecture | Should -Be 'x64'
            foreach ($name in @($app.AddCommand,$app.SyncCommand)) {
                $command = Get-Command $name
                $command.Parameters['Architecture'].Attributes |
                    Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } | Out-Null
                if ($app.Id -eq 'VisualCppRedist') {
                    $command.Definition | Should -Match '\$Architecture\s*=\s*@\(''x86'',''x64''\)'
                    @($app.DefaultArchitectures) | Should -Be @('x86','x64')
                } else {
                    $command.Definition | Should -Match '\$Architecture\s*=\s*''x64'''
                }
            }
        }
    }

    It 'exposes only the advertised architectures' {
        foreach ($app in $metadata.Applications) {
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
        foreach ($app in $metadata.Applications) {
            $app.Architectures | Should -Not -Contain 'Auto'
            $app.Architectures | Should -Not -Contain '32'
            $app.Architectures | Should -Not -Contain '64'
        }
    }
}
