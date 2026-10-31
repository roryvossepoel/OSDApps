Describe 'Windows capability staging and runtime' {
    BeforeAll {
        $script:root=Split-Path $PSScriptRoot -Parent
        Import-Module (Join-Path $script:root 'OSDStage.psd1') -Force
        . (Join-Path $script:root 'Runtime\Invoke-OSDStageWindowsCapabilities.ps1')
        if (-not (Get-Command Get-WindowsCapability -ErrorAction SilentlyContinue)) {
            function Get-WindowsCapability { [CmdletBinding()]param([switch]$Online,[string]$Name) throw 'Native Windows command must be mocked.' }
        }
    }
    BeforeEach {
        Set-OSDStageConfiguration -EnableBuiltIns $true
        $script:name='XPS.Viewer~~~~0.0.1.0'
        $script:config=[pscustomobject]@{
            SchemaVersion=2;DeploymentId=[guid]::NewGuid().Guid
            ResultPath=(Join-Path $TestDrive 'Results\WindowsCapabilities-Result.json')
            Operations=@([pscustomobject]@{Name=$script:name;Action='Add'})
        }
    }

    It 'accepts literal identities including unversioned capabilities but rejects injection and wildcards' {
        foreach ($name in @('XPS.Viewer~~~~0.0.1.0','Language.Basic~~~nl-NL~0.0.1.0','VBSCRIPT~~~~')) {
            { Assert-OSDStageWindowsCapabilityName -Name $name } | Should -Not -Throw
        }
        foreach ($name in @('', 'Rsat.*', 'XPS.Viewer~~~~ /Remove-Capability', 'XPS"~~~~', "XPS~~~~`n", 'C:\XPS~~~~', ' XPS~~~~')) {
            { Assert-OSDStageWindowsCapabilityName -Name $name } | Should -Throw
        }
    }
    It 'rejects duplicate operations, invalid actions and deployment identifiers' {
        $script:config.Operations+=@([pscustomobject]@{Name=$script:name.ToUpperInvariant();Action='Remove'})
        { Assert-OSDStageWindowsCapabilityConfiguration $script:config } | Should -Throw '*Duplicate*'
        $script:config.Operations=@([pscustomobject]@{Name=$script:name;Action='Enable'})
        { Assert-OSDStageWindowsCapabilityConfiguration $script:config } | Should -Throw '*Add or Remove*'
        $script:config.DeploymentId='invalid'
        { Assert-OSDStageWindowsCapabilityConfiguration $script:config } | Should -Throw '*Invalid*'
    }
    It 'accepts 25H2 and newer client builds but rejects older Windows and Server' {
        foreach ($build in @(26200,26300)) {
            { Assert-OSDStageWindowsCapabilityVersion ([pscustomobject]@{InstallationType='Client';CurrentBuildNumber=$build}) } | Should -Not -Throw
        }
        foreach ($version in @(
            [pscustomobject]@{InstallationType='Client';CurrentBuildNumber=26100},
            [pscustomobject]@{InstallationType='Server';CurrentBuildNumber=26300}
        )) { { Assert-OSDStageWindowsCapabilityVersion $version } | Should -Throw '*25H2*' }
    }
    It 'honors source selection and refuses staging from full Windows' {
        Set-OSDStageConfiguration -EnableBuiltIns $false
        { Add-OSDStageWindowsCapability -Name $script:name -Action Add -WhatIf } | Should -Throw '*disabled*'
        Set-OSDStageConfiguration -EnableBuiltIns $true
        InModuleScope OSDStage {
            Mock Test-OSDStageWinPE { $false }
            { Add-OSDStageWindowsCapability -Name 'XPS.Viewer~~~~0.0.1.0' -Action Add } | Should -Throw '*WinPE*'
        }
    }
    It 'merges intent, honors WhatIf and separates online readiness from script integrity' {
        InModuleScope OSDStage {
            Mock Test-OSDStageWinPE { $true }
            $target=Join-Path $TestDrive 'Offline Windows'
            New-Item -ItemType Directory -Path $target | Out-Null
            $stage=Join-Path $target 'Windows\Temp\OSDStage'
            Add-OSDStageWindowsCapability -Name 'XPS.Viewer~~~~0.0.1.0' -Action Add -WindowsPath $target -WhatIf
            Test-Path (Join-Path $stage 'DeviceManifest.json') | Should -BeFalse
            Add-OSDStageWindowsCapability -Name 'XPS.Viewer~~~~0.0.1.0' -Action Add -WindowsPath $target | Out-Null
            Add-OSDStageWindowsCapability -Name 'OpenSSH.Client~~~~0.0.1.0' -Action Remove -WindowsPath $target | Out-Null
            $preflight=Test-OSDStageDeployment -WindowsPath $target -ThrowOnFailure
            $preflight.Valid | Should -BeTrue
            $preflight.NetworkRequired | Should -BeTrue
            $preflight.OfflineReady | Should -BeFalse
            $preflight.Packages[0].IntegrityValid | Should -BeTrue
            { Test-OSDStageDeployment -WindowsPath $target -RequireOfflineReady -ThrowOnFailure } | Should -Throw
            $last=Add-OSDStageWindowsCapability -Name 'XPS.Viewer~~~~0.0.1.0' -Action Remove -WindowsPath $target
            $last.OperationCount | Should -Be 2
            $last.NetworkRequired | Should -BeFalse
            $manifest=Get-Content (Join-Path $stage 'DeviceManifest.json') -Raw | ConvertFrom-Json
            @($manifest.Packages | Where-Object Id -eq WindowsCapabilities).Count | Should -Be 1
            $preflight=Test-OSDStageDeployment -WindowsPath $target -RequireOfflineReady -ThrowOnFailure
            $preflight.OfflineReady | Should -BeTrue
            $preflight.NetworkRequired | Should -BeFalse
            $configPath=Join-Path $stage 'BuiltIn\WindowsCapabilities\config.json'
            Add-Content -LiteralPath $configPath -Value 'tampered'
            (Test-OSDStageDeployment -WindowsPath $target).Valid | Should -BeFalse
            { Add-OSDStageWindowsCapability -Name 'XPS.Viewer~~~~0.0.1.0' -Action Add -WindowsPath $target } | Should -Throw '*intact*'
        }
    }
    It 'requires exactly the requested identity from Windows' {
        Mock Get-WindowsCapability { @() }
        { Get-OSDStageWindowsCapabilityState $script:name } | Should -Throw '*not available*'
        Mock Get-WindowsCapability { [pscustomobject]@{Name='Other~~~~';State='Installed'} }
        { Get-OSDStageWindowsCapabilityState $script:name } | Should -Throw '*not available*'
        Mock Get-WindowsCapability { [pscustomobject]@{Name=$Name;State='NotPresent'} }
        Get-OSDStageWindowsCapabilityState $script:name | Should -Be NotPresent
    }
    It 'skips already satisfied Add and Remove requests without servicing' {
        Mock Invoke-OSDStageCapabilityDism { throw 'must not run' }
        Mock Get-OSDStageWindowsCapabilityState { 'Installed' }
        $r=Invoke-OSDStageWindowsCapabilityOperation $script:config.Operations[0] (Join-Path $TestDrive 'dism.log')
        $r.Outcome | Should -Be AlreadyInstalled
        $script:config.Operations[0].Action='Remove'
        Mock Get-OSDStageWindowsCapabilityState { 'NotPresent' }
        $r=Invoke-OSDStageWindowsCapabilityOperation $script:config.Operations[0] (Join-Path $TestDrive 'dism.log')
        $r.Outcome | Should -Be AlreadyAbsent
        Should -Invoke Invoke-OSDStageCapabilityDism -Exactly 0
    }
    It 'verifies actual Add and Remove transitions immediately' {
        foreach ($action in @('Add','Remove')) {
            $script:state=if ($action -eq 'Add') {'NotPresent'} else {'Installed'}
            Mock Get-OSDStageWindowsCapabilityState { $script:state }
            Mock Invoke-OSDStageCapabilityDism {
                $script:state=if ($Action -eq 'Add') {'Installed'} else {'NotPresent'}
                [pscustomobject]@{ExitCode=0}
            }
            $script:config.Operations[0].Action=$action
            $r=Invoke-OSDStageWindowsCapabilityOperation $script:config.Operations[0] (Join-Path $TestDrive 'dism.log')
            $r.Status | Should -Be Succeeded
            $r.StateBefore | Should -Not -Be $r.StateAfter
            $r.RestartNeeded | Should -BeFalse
        }
        Should -Invoke Invoke-OSDStageCapabilityDism -Exactly 1 -ParameterFilter { $Action -eq 'Add' }
        Should -Invoke Invoke-OSDStageCapabilityDism -Exactly 1 -ParameterFilter { $Action -eq 'Remove' }
    }
    It 'fails a success exit without the requested state and preserves native failures' {
        Mock Get-OSDStageWindowsCapabilityState { 'NotPresent' }
        Mock Invoke-OSDStageCapabilityDism { [pscustomobject]@{ExitCode=0} }
        $r=Invoke-OSDStageWindowsCapabilityOperation $script:config.Operations[0] (Join-Path $TestDrive 'dism.log')
        $r.Status | Should -Be Failed
        $r.Error | Should -Match 'expected Installed'
        Mock Invoke-OSDStageCapabilityDism { [pscustomobject]@{ExitCode=-2146498529} }
        $r=Invoke-OSDStageWindowsCapabilityOperation $script:config.Operations[0] (Join-Path $TestDrive 'dism.log')
        $r.Status | Should -Be Failed
        $r.ExitCode | Should -Be -2146498529
    }
    It 'reports pending completion separately without requesting a reboot' {
        Mock Assert-OSDStageWindowsCapabilityContext {}
        Mock Get-OSDStageWindowsCapabilityState { 'NotPresent' }
        Mock Invoke-OSDStageCapabilityDism { [pscustomobject]@{ExitCode=3010} }
        $r=Invoke-OSDStageWindowsCapabilityConfiguration $script:config
        $r.Status | Should -Be Succeeded
        $r.Items[0].Outcome | Should -Be PendingRestart
        $r.RestartNeeded | Should -BeTrue
        $r.RebootRequested | Should -BeFalse
    }
    It 'does not service an unknown or initially pending capability' {
        Mock Invoke-OSDStageCapabilityDism { throw 'must not run' }
        Mock Get-OSDStageWindowsCapabilityState { throw 'Capability not available' }
        $r=Invoke-OSDStageWindowsCapabilityOperation $script:config.Operations[0] (Join-Path $TestDrive 'dism.log')
        $r.Status | Should -Be Failed
        Mock Get-OSDStageWindowsCapabilityState { 'InstallPending' }
        $r=Invoke-OSDStageWindowsCapabilityOperation $script:config.Operations[0] (Join-Path $TestDrive 'dism.log')
        $r.Status | Should -Be Failed
        $r.RestartNeeded | Should -BeTrue
        Should -Invoke Invoke-OSDStageCapabilityDism -Exactly 0
    }
    It 'continues independent operations after an ordinary failure and aggregates results' {
        Mock Assert-OSDStageWindowsCapabilityContext {}
        $script:config.Operations+=@([pscustomobject]@{Name='OpenSSH.Client~~~~0.0.1.0';Action='Remove'})
        Mock Get-OSDStageWindowsCapabilityState { if ($Name -like 'XPS*') {throw 'Not available'} else {'NotPresent'} }
        Mock Invoke-OSDStageCapabilityDism { throw 'must not run' }
        $r=Invoke-OSDStageWindowsCapabilityConfiguration $script:config
        $r.Status | Should -Be Failed
        $r.FailedOperationCount | Should -Be 1
        $r.SuccessfulOperationCount | Should -Be 1
        $r.Items[1].Outcome | Should -Be AlreadyAbsent
    }
    It 'stops further servicing after a timeout and does not retry' {
        Mock Assert-OSDStageWindowsCapabilityContext {}
        $script:config.Operations+=@([pscustomobject]@{Name='OpenSSH.Client~~~~0.0.1.0';Action='Remove'})
        Mock Get-OSDStageWindowsCapabilityState { 'NotPresent' }
        Mock Invoke-OSDStageCapabilityDism { throw [TimeoutException]::new('Servicing timed out') }
        $r=Invoke-OSDStageWindowsCapabilityConfiguration $script:config
        $r.Status | Should -Be Failed
        $r.Items[0].TimedOut | Should -BeTrue
        $r.Items[1].Outcome | Should -Be NotAttempted
        Should -Invoke Invoke-OSDStageCapabilityDism -Exactly 1
    }
    It 'rejects unsupported runtime context before querying or changing capabilities' {
        Mock Assert-OSDStageWindowsCapabilityContext { throw 'Requires Windows 11 25H2 SYSTEM' }
        Mock Get-OSDStageWindowsCapabilityState { throw 'must not run' }
        $r=Invoke-OSDStageWindowsCapabilityConfiguration $script:config
        $r.Status | Should -Be Failed
        $r.Error | Should -Match '25H2 SYSTEM'
        Should -Invoke Get-OSDStageWindowsCapabilityState -Exactly 0
    }
    It 'keeps native NoRestart and does not add retry or login mechanisms' {
        $source=Get-Content (Join-Path $script:root 'Runtime\Invoke-OSDStageWindowsCapabilities.ps1') -Raw
        $source | Should -Match '/NoRestart'
        $source | Should -Not -Match '\bRestart-Computer\b|shutdown\.exe|Register-ScheduledTask|RunOnce|Set-ItemProperty'
    }
    It 'dispatches through standalone PreInstall/Runner and rejects non-SYSTEM before mutation' -Skip:($env:OS -ne 'Windows_NT') {
        InModuleScope OSDStage {
            Mock Test-OSDStageWinPE { $true }
            $target=Join-Path $TestDrive 'Runner Windows'
            New-Item -ItemType Directory -Path $target | Out-Null
            $results=Join-Path $TestDrive 'Runner Results'
            Set-OSDStageConfiguration -ResultPath (Join-Path $results 'Latest.json') -LogPath (Join-Path $TestDrive 'Runner.log') -PreventSleep $false -CleanupMode Never
            try {
                Add-OSDStageWindowsCapability -Name 'XPS.Viewer~~~~0.0.1.0' -Action Add -WindowsPath $target | Out-Null
                $stage=Join-Path $target 'Windows\Temp\OSDStage'
                & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $stage 'Invoke-OSDStagePreInstall.ps1') -StagedPath $stage
                $LASTEXITCODE | Should -Be 0
                & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $stage 'Invoke-OSDStageRunner.ps1') -StagedPath $stage
                $LASTEXITCODE | Should -Be 1
                $latest=Get-Content (Join-Path $results 'Latest.json') -Raw | ConvertFrom-Json
                $latest.Packages[0].Id | Should -Be WindowsCapabilities
                $report=Get-Content (Join-Path $results 'WindowsCapabilities-Result.json') -Raw | ConvertFrom-Json
                $report.DeploymentId | Should -Be $latest.DeploymentId
                $report.Error | Should -Match 'SYSTEM'
                $report.Items.Count | Should -Be 0
                Add-Content (Join-Path $stage 'BuiltIn\WindowsCapabilities\config.json') 'tampered'
                & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $stage 'Invoke-OSDStageRunner.ps1') -StagedPath $stage
                $LASTEXITCODE | Should -Be 1
                (Get-Content (Join-Path $TestDrive 'Runner.log') -Raw) | Should -Match 'HashMismatch|integrity failed'
            }
            finally { Set-OSDStageConfiguration -ResultPath '%ProgramData%\OSDStage\Results\Latest.json' -LogPath '%ProgramData%\OSDStage\Logs\Runtime.log' -PreventSleep $true }
        }
    }
}
