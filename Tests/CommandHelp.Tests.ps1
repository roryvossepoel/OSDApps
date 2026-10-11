Describe 'Packaged command-help source contract' {
    BeforeAll {
        $script:root = Split-Path $PSScriptRoot -Parent
        $script:helpData = Import-PowerShellDataFile -LiteralPath (Join-Path $script:root 'help\CommandHelp.psd1')
        $script:manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $script:root 'OSDApps.psd1')
        Import-Module (Join-Path $script:root 'OSDApps.psd1') -Force
        $script:module = Get-Module OSDApps
        $script:common = @('Verbose','Debug','ErrorAction','WarningAction','InformationAction','ProgressAction',
            'ErrorVariable','WarningVariable','InformationVariable','OutVariable','OutBuffer','PipelineVariable','WhatIf','Confirm')
    }

    It 'contains exactly the exported function set, not private or invented commands' {
        $script:helpData.SchemaVersion | Should -Be 1
        @(Compare-Object @($script:manifest.FunctionsToExport | Sort-Object) @($script:helpData.Commands.Keys | Sort-Object)).Count | Should -Be 0
    }

    It 'gives every command meaningful usage, environment, result and examples' {
        foreach ($name in $script:manifest.FunctionsToExport) {
            $spec = $script:helpData.Commands[$name]
            foreach ($field in @('Synopsis','Description','Environment','Output')) {
                ([string]$spec[$field]).Length | Should -BeGreaterThan 15 -Because "$name requires $field"
            }
            @($spec.Examples).Count | Should -BeGreaterThan 0 -Because "$name needs an example"
            Test-Path -LiteralPath (Join-Path $script:root $spec.Link) -PathType Leaf | Should -BeTrue
        }
    }

    It 'documents all declared parameters without accepting stale parameter names' {
        foreach ($name in $script:manifest.FunctionsToExport) {
            $cmd = $script:module.ExportedFunctions[$name]
            $spec = $script:helpData.Commands[$name]
            $parameters = @($cmd.Parameters.Keys | Where-Object { $_ -notin $script:common })
            foreach ($parameter in $parameters) {
                $description = if ($spec.Parameters -and $spec.Parameters.ContainsKey($parameter)) {
                    $spec.Parameters[$parameter]
                } else { $script:helpData.CommonParameters[$parameter] }
                ([string]$description).Length | Should -BeGreaterThan 15 -Because "$name/$parameter needs accurate help"
            }
            if ($spec.Parameters) {
                foreach ($parameter in $spec.Parameters.Keys) {
                    $parameter | Should -BeIn $parameters -Because "$name must not document invented parameters"
                }
            }
        }
    }

    It 'parses every help example and checks OSDApps command parameter names without running it' {
        foreach ($name in $script:manifest.FunctionsToExport) {
            foreach ($example in $script:helpData.Commands[$name].Examples) {
                $tokens = $null
                $parseErrors = $null
                $ast = [System.Management.Automation.Language.Parser]::ParseInput([string]$example.Code,[ref]$tokens,[ref]$parseErrors)
                @($parseErrors).Count | Should -Be 0 -Because "example for $name must parse: $($parseErrors -join '; ')"
                ([string]$example.Remarks).Length | Should -BeGreaterThan 10
                $calls = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] },$true)
                foreach ($call in $calls) {
                    $callName = $call.GetCommandName()
                    if ($callName -notmatch '^[A-Za-z]+-OSDApp') { continue }
                    $callName | Should -BeIn @($script:manifest.FunctionsToExport)
                    $command = $script:module.ExportedFunctions[$callName]
                    foreach ($element in $call.CommandElements) {
                        if ($element -is [System.Management.Automation.Language.CommandParameterAst]) {
                            $element.ParameterName | Should -BeIn @($command.Parameters.Keys)
                        }
                    }
                }
            }
        }
    }

    It 'keeps literal Boolean and pipeline-variable syntax in examples' {
        $script:helpData.Commands['Add-OSDAppCiscoWebex'].Examples[0].Code | Should -Match '\$false'
        $script:helpData.Commands['Test-OSDAppRepository'].Examples[0].Code | Should -Match '\$_\.Valid'
    }

    It 'does not claim that Offline disables trust verification or that cached means installed' {
        $script:helpData.Commands['Show-OSDAppUI'].Parameters.Offline | Should -Match 'signature checks stay enabled'
        $script:helpData.Commands['Get-OSDAppCache'].Description | Should -Match 'SignatureStatus is separate'
        $script:helpData.Commands['Add-OSDApp'].Output | Should -Match 'not installation proof'
    }
}
