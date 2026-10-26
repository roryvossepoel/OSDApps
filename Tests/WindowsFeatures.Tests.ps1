Describe 'Built-in Windows Features staging' {
    BeforeAll {
        $script:root=Split-Path $PSScriptRoot -Parent
        Import-Module (Join-Path $script:root 'OSDApps.psd1') -Force

        $runtimePath=Join-Path $script:root 'Runtime\Invoke-OSDAppWindowsFeatures.ps1'
        $tokens=$null;$errors=$null
        $ast=[Management.Automation.Language.Parser]::ParseFile($runtimePath,[ref]$tokens,[ref]$errors)
        if(@($errors).Count){throw 'Windows Features runtime parser errors.'}
        foreach($name in @('Assert-OSDAppWindowsFeatureConfiguration','Invoke-OSDAppWindowsFeatureOperation')){
            $def=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
            if(-not $def){throw "Missing runtime function $name."}
            . ([scriptblock]::Create($def.Extent.Text))
        }
    }

    It 'exports one declarative cmdlet without feature-name validation catalogs' {
        $cmd=Get-Command Add-OSDAppWindowsFeature -Module OSDApps
        $cmd.Parameters.Keys | Should -Contain 'Enable'
        $cmd.Parameters.Keys | Should -Contain 'Disable'
        $cmd.Parameters.Keys | Should -Contain 'WindowsPath'
        @($cmd.Parameters.Enable.Attributes | Where-Object { $_ -is [Management.Automation.ValidateSetAttribute] }).Count | Should -Be 0
        @($cmd.Parameters.Disable.Attributes | Where-Object { $_ -is [Management.Automation.ValidateSetAttribute] }).Count | Should -Be 0
    }

    It 'rejects empty and contradictory intent before staging' {
        InModuleScope OSDApps {
            Mock Test-OSDAppWinPE { $true }
            { Add-OSDAppWindowsFeature -WindowsPath $TestDrive } | Should -Throw '*at least one feature*'
            { Add-OSDAppWindowsFeature -Enable NetFx3 -Disable NetFx3 -WindowsPath $TestDrive } | Should -Throw '*enabled and disabled*'
        }
    }

    It 'honors BuiltIn source selection' {
        Set-OSDAppConfiguration -EnableBuiltIns $false
        { Add-OSDAppWindowsFeature -Enable NetFx3 -WhatIf } | Should -Throw '*Built-in apps*disabled*'
    }

    It 'stages one offline built-in Script and last desired state wins across calls' {
        InModuleScope OSDApps {
            Mock Test-OSDAppWinPE { $true }
            $target=Join-Path $TestDrive 'OfflineWindows'
            New-Item -ItemType Directory -Path $target | Out-Null

            Add-OSDAppWindowsFeature -Enable @('NetFx3','Microsoft-Windows-Subsystem-Linux') -WindowsPath $target | Out-Null
            $last=Add-OSDAppWindowsFeature -Disable NetFx3 -WindowsPath $target
            $last.OperationCount | Should -Be 2
            $last.Disabled | Should -Contain 'NetFx3'
            $last.Enabled | Should -Contain 'Microsoft-Windows-Subsystem-Linux'

            $stage=Join-Path $target 'Windows\Temp\OSDApps'
            $manifest=Get-Content (Join-Path $stage 'DeviceManifest.json') -Raw | ConvertFrom-Json
            $entry=@($manifest.Apps | Where-Object Id -eq WindowsFeatures)
            $entry.Count | Should -Be 1
            $entry[0].Source | Should -Be 'BuiltIn'
            $entry[0].PackageType | Should -Be 'Script'
            $entry[0].Type | Should -Be 'WindowsFeatureScript'
            $entry[0].WindowsFeatureOperationCount | Should -Be 2

            $config=Get-Content (Join-Path $stage 'BuiltIn\WindowsFeatures\config.json') -Raw | ConvertFrom-Json
            @($config.Operations | Where-Object Name -eq NetFx3)[0].Action | Should -Be Disable
            @($config.Operations | Where-Object Name -eq 'Microsoft-Windows-Subsystem-Linux')[0].Action | Should -Be Enable

            $preflight=Test-OSDAppDeployment -WindowsPath $target -RequireOfflineReady -ThrowOnFailure
            $preflight.OfflineReady | Should -BeTrue
            $preflight.NetworkRequired | Should -BeFalse
        }
    }

    It 'reports already enabled idempotently without invoking servicing' {
        Mock Get-WindowsOptionalFeature { [pscustomobject]@{State='Enabled'} }
        Mock Enable-WindowsOptionalFeature { throw 'must not run' }
        $result=Invoke-OSDAppWindowsFeatureOperation -Operation ([pscustomobject]@{Action='Enable';Name='NetFx3'})
        $result.Status | Should -Be Succeeded
        $result.Outcome | Should -Be AlreadyEnabled
        $result.RestartNeeded | Should -BeFalse
        Should -Invoke Enable-WindowsOptionalFeature -Exactly 0
    }

    It 'reports already disabled idempotently without invoking servicing' {
        Mock Get-WindowsOptionalFeature { [pscustomobject]@{State='Disabled'} }
        Mock Disable-WindowsOptionalFeature { throw 'must not run' }
        $result=Invoke-OSDAppWindowsFeatureOperation -Operation ([pscustomobject]@{Action='Disable';Name='Printing-XPSServices-Features'})
        $result.Outcome | Should -Be AlreadyDisabled
        Should -Invoke Disable-WindowsOptionalFeature -Exactly 0
    }

    It 'records restart-needed from native enable without reboot orchestration' {
        Mock Get-WindowsOptionalFeature { [pscustomobject]@{State='Disabled'} }
        Mock Enable-WindowsOptionalFeature { [pscustomobject]@{RestartNeeded=$true} }
        $result=Invoke-OSDAppWindowsFeatureOperation -Operation ([pscustomobject]@{Action='Enable';Name='NetFx3'})
        $result.Outcome | Should -Be Enabled
        $result.RestartNeeded | Should -BeTrue
        Should -Invoke Enable-WindowsOptionalFeature -Exactly 1 -ParameterFilter { $Online -and $All -and $NoRestart -and $FeatureName -eq 'NetFx3' }
    }

    It 'uses NoRestart for disable and does not infer or validate feature names itself' {
        Mock Get-WindowsOptionalFeature { [pscustomobject]@{State='Enabled'} }
        Mock Disable-WindowsOptionalFeature { [pscustomobject]@{RestartNeeded=$false} }
        $result=Invoke-OSDAppWindowsFeatureOperation -Operation ([pscustomobject]@{Action='Disable';Name='Vendor.Custom-Feature'})
        $result.Outcome | Should -Be Disabled
        Should -Invoke Disable-WindowsOptionalFeature -Exactly 1 -ParameterFilter { $Online -and $NoRestart -and $FeatureName -eq 'Vendor.Custom-Feature' }
    }

    It 'declares per-operation continuation and no reboot command in the runtime source' {
        $source=Get-Content (Join-Path $script:root 'Runtime\Invoke-OSDAppWindowsFeatures.ps1') -Raw
        $source | Should -Match 'foreach\(\$operation in @\(\$configuration\.Operations\)\)'
        $source | Should -Match "Status='Failed';Outcome='Failed'"
        $source | Should -Match '-NoRestart'
        $source | Should -Not -Match '(?i)\bRestart-Computer\b|shutdown\.exe|InitiateSystemShutdown'
    }
}
