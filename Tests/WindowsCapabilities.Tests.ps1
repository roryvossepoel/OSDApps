Describe 'Windows capability staging and runtime' {
    BeforeAll {
        $script:root=Split-Path $PSScriptRoot -Parent
        Import-Module (Join-Path $script:root 'OSDApps.psd1') -Force
        . (Join-Path $script:root 'Runtime\Invoke-OSDAppWindowsCapabilities.ps1')
        if (-not (Get-Command Get-WindowsCapability -ErrorAction SilentlyContinue)) {
            function Get-WindowsCapability { [CmdletBinding()]param([switch]$Online,[string]$Name) throw 'Native Windows command must be mocked.' }
        }
    }
    BeforeEach {
        Set-OSDAppConfiguration -EnableBuiltIns $true
        $script:name='XPS.Viewer~~~~0.0.1.0'
        $script:config=[pscustomobject]@{
            SchemaVersion=1;DeploymentId=[guid]::NewGuid().Guid
            ResultPath=(Join-Path $TestDrive 'Results\WindowsCapabilities-Result.json')
            Operations=@([pscustomobject]@{Name=$script:name;Action='Add'})
        }
    }

    It 'accepts literal identities including unversioned capabilities but rejects injection and wildcards' {
        foreach ($name in @('XPS.Viewer~~~~0.0.1.0','Language.Basic~~~nl-NL~0.0.1.0','VBSCRIPT~~~~')) {
            { Assert-OSDAppWindowsCapabilityName -Name $name } | Should -Not -Throw
        }
        foreach ($name in @('', 'Rsat.*', 'XPS.Viewer~~~~ /Remove-Capability', 'XPS"~~~~', "XPS~~~~`n", 'C:\XPS~~~~', ' XPS~~~~')) {
            { Assert-OSDAppWindowsCapabilityName -Name $name } | Should -Throw
        }
    }
    It 'rejects duplicate operations, invalid actions and deployment identifiers' {
        $script:config.Operations+=@([pscustomobject]@{Name=$script:name.ToUpperInvariant();Action='Remove'})
        { Assert-OSDAppWindowsCapabilityConfiguration $script:config } | Should -Throw '*Duplicate*'
        $script:config.Operations=@([pscustomobject]@{Name=$script:name;Action='Enable'})
        { Assert-OSDAppWindowsCapabilityConfiguration $script:config } | Should -Throw '*Add or Remove*'
        $script:config.DeploymentId='invalid'
        { Assert-OSDAppWindowsCapabilityConfiguration $script:config } | Should -Throw '*Invalid*'
    }
    It 'accepts 25H2 and newer client builds but rejects older Windows and Server' {
        foreach ($build in @(26200,26300)) {
            { Assert-OSDAppWindowsCapabilityVersion ([pscustomobject]@{InstallationType='Client';CurrentBuildNumber=$build}) } | Should -Not -Throw
        }
        foreach ($version in @(
            [pscustomobject]@{InstallationType='Client';CurrentBuildNumber=26100},
            [pscustomobject]@{InstallationType='Server';CurrentBuildNumber=26300}
        )) { { Assert-OSDAppWindowsCapabilityVersion $version } | Should -Throw '*25H2*' }
    }
    It 'honors source selection and refuses staging from full Windows' {
        Set-OSDAppConfiguration -EnableBuiltIns $false
        { Add-OSDAppWindowsCapability -Name $script:name -Action Add -WhatIf } | Should -Throw '*disabled*'
        Set-OSDAppConfiguration -EnableBuiltIns $true
        InModuleScope OSDApps {
            Mock Test-OSDAppWinPE { $false }
            { Add-OSDAppWindowsCapability -Name 'XPS.Viewer~~~~0.0.1.0' -Action Add } | Should -Throw '*WinPE*'
        }
    }
    It 'merges intent, honors WhatIf and separates online readiness from script integrity' {
        InModuleScope OSDApps {
            Mock Test-OSDAppWinPE { $true }
            $target=Join-Path $TestDrive 'Offline Windows'
            New-Item -ItemType Directory -Path $target | Out-Null
            $stage=Join-Path $target 'Windows\Temp\OSDApps'
            Add-OSDAppWindowsCapability -Name 'XPS.Viewer~~~~0.0.1.0' -Action Add -WindowsPath $target -WhatIf
            Test-Path (Join-Path $stage 'DeviceManifest.json') | Should -BeFalse
            Add-OSDAppWindowsCapability -Name 'XPS.Viewer~~~~0.0.1.0' -Action Add -WindowsPath $target | Out-Null
            Add-OSDAppWindowsCapability -Name 'OpenSSH.Client~~~~0.0.1.0' -Action Remove -WindowsPath $target | Out-Null
            $preflight=Test-OSDAppDeployment -WindowsPath $target -ThrowOnFailure
            $preflight.Valid | Should -BeTrue
            $preflight.NetworkRequired | Should -BeTrue
            $preflight.OfflineReady | Should -BeFalse
            $preflight.Apps[0].IntegrityValid | Should -BeTrue
            { Test-OSDAppDeployment -WindowsPath $target -RequireOfflineReady -ThrowOnFailure } | Should -Throw
            $last=Add-OSDAppWindowsCapability -Name 'XPS.Viewer~~~~0.0.1.0' -Action Remove -WindowsPath $target
            $last.OperationCount | Should -Be 2
            $last.NetworkRequired | Should -BeFalse
            $manifest=Get-Content (Join-Path $stage 'DeviceManifest.json') -Raw | ConvertFrom-Json
            @($manifest.Apps | Where-Object Id -eq WindowsCapabilities).Count | Should -Be 1
            $preflight=Test-OSDAppDeployment -WindowsPath $target -RequireOfflineReady -ThrowOnFailure
            $preflight.OfflineReady | Should -BeTrue
            $preflight.NetworkRequired | Should -BeFalse
            $configPath=Join-Path $stage 'BuiltIn\WindowsCapabilities\config.json'
            Add-Content -LiteralPath $configPath -Value 'tampered'
            (Test-OSDAppDeployment -WindowsPath $target).Valid | Should -BeFalse
            { Add-OSDAppWindowsCapability -Name 'XPS.Viewer~~~~0.0.1.0' -Action Add -WindowsPath $target } | Should -Throw '*intact*'
        }
    }
    It 'requires exactly the requested identity from Windows' {
        Mock Get-WindowsCapability { @() }
        { Get-OSDAppWindowsCapabilityState $script:name } | Should -Throw '*not available*'
        Mock Get-WindowsCapability { [pscustomobject]@{Name='Other~~~~';State='Installed'} }
        { Get-OSDAppWindowsCapabilityState $script:name } | Should -Throw '*not available*'
        Mock Get-WindowsCapability { [pscustomobject]@{Name=$Name;State='NotPresent'} }
        Get-OSDAppWindowsCapabilityState $script:name | Should -Be NotPresent
    }
    It 'skips already satisfied Add and Remove requests without servicing' {
        Mock Invoke-OSDAppCapabilityDism { throw 'must not run' }
        Mock Get-OSDAppWindowsCapabilityState { 'Installed' }
        $r=Invoke-OSDAppWindowsCapabilityOperation $script:config.Operations[0] (Join-Path $TestDrive 'dism.log')
        $r.Outcome | Should -Be AlreadyInstalled
        $script:config.Operations[0].Action='Remove'
        Mock Get-OSDAppWindowsCapabilityState { 'NotPresent' }
        $r=Invoke-OSDAppWindowsCapabilityOperation $script:config.Operations[0] (Join-Path $TestDrive 'dism.log')
        $r.Outcome | Should -Be AlreadyAbsent
        Should -Invoke Invoke-OSDAppCapabilityDism -Exactly 0
    }
    It 'verifies actual Add and Remove transitions immediately' {
        foreach ($action in @('Add','Remove')) {
            $script:state=if ($action -eq 'Add') {'NotPresent'} else {'Installed'}
            Mock Get-OSDAppWindowsCapabilityState { $script:state }
            Mock Invoke-OSDAppCapabilityDism {
                $script:state=if ($Action -eq 'Add') {'Installed'} else {'NotPresent'}
                [pscustomobject]@{ExitCode=0}
            }
            $script:config.Operations[0].Action=$action
            $r=Invoke-OSDAppWindowsCapabilityOperation $script:config.Operations[0] (Join-Path $TestDrive 'dism.log')
            $r.Status | Should -Be Succeeded
            $r.StateBefore | Should -Not -Be $r.StateAfter
            $r.RestartNeeded | Should -BeFalse
        }
        Should -Invoke Invoke-OSDAppCapabilityDism -Exactly 1 -ParameterFilter { $Action -eq 'Add' }
        Should -Invoke Invoke-OSDAppCapabilityDism -Exactly 1 -ParameterFilter { $Action -eq 'Remove' }
    }
    It 'fails a success exit without the requested state and preserves native failures' {
        Mock Get-OSDAppWindowsCapabilityState { 'NotPresent' }
        Mock Invoke-OSDAppCapabilityDism { [pscustomobject]@{ExitCode=0} }
        $r=Invoke-OSDAppWindowsCapabilityOperation $script:config.Operations[0] (Join-Path $TestDrive 'dism.log')
        $r.Status | Should -Be Failed
        $r.Error | Should -Match 'expected Installed'
        Mock Invoke-OSDAppCapabilityDism { [pscustomobject]@{ExitCode=-2146498529} }
        $r=Invoke-OSDAppWindowsCapabilityOperation $script:config.Operations[0] (Join-Path $TestDrive 'dism.log')
        $r.Status | Should -Be Failed
        $r.ExitCode | Should -Be -2146498529
    }
    It 'reports pending completion separately without requesting a reboot' {
        Mock Assert-OSDAppWindowsCapabilityContext {}
        Mock Get-OSDAppWindowsCapabilityState { 'NotPresent' }
        Mock Invoke-OSDAppCapabilityDism { [pscustomobject]@{ExitCode=3010} }
        $r=Invoke-OSDAppWindowsCapabilityConfiguration $script:config
        $r.Status | Should -Be Succeeded
        $r.Items[0].Outcome | Should -Be PendingRestart
        $r.RestartNeeded | Should -BeTrue
        $r.RebootRequested | Should -BeFalse
    }
    It 'does not service an unknown or initially pending capability' {
        Mock Invoke-OSDAppCapabilityDism { throw 'must not run' }
        Mock Get-OSDAppWindowsCapabilityState { throw 'Capability not available' }
        $r=Invoke-OSDAppWindowsCapabilityOperation $script:config.Operations[0] (Join-Path $TestDrive 'dism.log')
        $r.Status | Should -Be Failed
        Mock Get-OSDAppWindowsCapabilityState { 'InstallPending' }
        $r=Invoke-OSDAppWindowsCapabilityOperation $script:config.Operations[0] (Join-Path $TestDrive 'dism.log')
        $r.Status | Should -Be Failed
        $r.RestartNeeded | Should -BeTrue
        Should -Invoke Invoke-OSDAppCapabilityDism -Exactly 0
    }
    It 'continues independent operations after an ordinary failure and aggregates results' {
        Mock Assert-OSDAppWindowsCapabilityContext {}
        $script:config.Operations+=@([pscustomobject]@{Name='OpenSSH.Client~~~~0.0.1.0';Action='Remove'})
        Mock Get-OSDAppWindowsCapabilityState { if ($Name -like 'XPS*') {throw 'Not available'} else {'NotPresent'} }
        Mock Invoke-OSDAppCapabilityDism { throw 'must not run' }
        $r=Invoke-OSDAppWindowsCapabilityConfiguration $script:config
        $r.Status | Should -Be Failed
        $r.FailedOperationCount | Should -Be 1
        $r.SuccessfulOperationCount | Should -Be 1
        $r.Items[1].Outcome | Should -Be AlreadyAbsent
    }
    It 'stops further servicing after a timeout and does not retry' {
        Mock Assert-OSDAppWindowsCapabilityContext {}
        $script:config.Operations+=@([pscustomobject]@{Name='OpenSSH.Client~~~~0.0.1.0';Action='Remove'})
        Mock Get-OSDAppWindowsCapabilityState { 'NotPresent' }
        Mock Invoke-OSDAppCapabilityDism { throw [TimeoutException]::new('Servicing timed out') }
        $r=Invoke-OSDAppWindowsCapabilityConfiguration $script:config
        $r.Status | Should -Be Failed
        $r.Items[0].TimedOut | Should -BeTrue
        $r.Items[1].Outcome | Should -Be NotAttempted
        Should -Invoke Invoke-OSDAppCapabilityDism -Exactly 1
    }
    It 'rejects unsupported runtime context before querying or changing capabilities' {
        Mock Assert-OSDAppWindowsCapabilityContext { throw 'Requires Windows 11 25H2 SYSTEM' }
        Mock Get-OSDAppWindowsCapabilityState { throw 'must not run' }
        $r=Invoke-OSDAppWindowsCapabilityConfiguration $script:config
        $r.Status | Should -Be Failed
        $r.Error | Should -Match '25H2 SYSTEM'
        Should -Invoke Get-OSDAppWindowsCapabilityState -Exactly 0
    }
    It 'keeps native NoRestart and does not add retry or login mechanisms' {
        $source=Get-Content (Join-Path $script:root 'Runtime\Invoke-OSDAppWindowsCapabilities.ps1') -Raw
        $source | Should -Match '/NoRestart'
        $source | Should -Not -Match '\bRestart-Computer\b|shutdown\.exe|Register-ScheduledTask|RunOnce|Set-ItemProperty'
    }
    It 'dispatches through standalone PreInstall/Runner and rejects non-SYSTEM before mutation' -Skip:($env:OS -ne 'Windows_NT') {
        InModuleScope OSDApps {
            Mock Test-OSDAppWinPE { $true }
            $target=Join-Path $TestDrive 'Runner Windows'
            New-Item -ItemType Directory -Path $target | Out-Null
            $results=Join-Path $TestDrive 'Runner Results'
            Set-OSDAppConfiguration -ResultPath (Join-Path $results 'Latest.json') -LogPath (Join-Path $TestDrive 'Runner.log') -PreventSleep $false -CleanupMode Never
            try {
                Add-OSDAppWindowsCapability -Name 'XPS.Viewer~~~~0.0.1.0' -Action Add -WindowsPath $target | Out-Null
                $stage=Join-Path $target 'Windows\Temp\OSDApps'
                & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $stage 'Invoke-OSDAppPreInstall.ps1') -StagedPath $stage
                $LASTEXITCODE | Should -Be 0
                & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $stage 'Invoke-OSDAppRunner.ps1') -StagedPath $stage
                $LASTEXITCODE | Should -Be 1
                $latest=Get-Content (Join-Path $results 'Latest.json') -Raw | ConvertFrom-Json
                $latest.Apps[0].Id | Should -Be WindowsCapabilities
                $report=Get-Content (Join-Path $results 'WindowsCapabilities-Result.json') -Raw | ConvertFrom-Json
                $report.DeploymentId | Should -Be $latest.DeploymentId
                $report.Error | Should -Match 'SYSTEM'
                $report.Items.Count | Should -Be 0
                Add-Content (Join-Path $stage 'BuiltIn\WindowsCapabilities\config.json') 'tampered'
                & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $stage 'Invoke-OSDAppRunner.ps1') -StagedPath $stage
                $LASTEXITCODE | Should -Be 1
                (Get-Content (Join-Path $TestDrive 'Runner.log') -Raw) | Should -Match 'HashMismatch|integrity failed'
            }
            finally { Set-OSDAppConfiguration -ResultPath '%ProgramData%\OSDApps\Results\Latest.json' -LogPath '%ProgramData%\OSDApps\Logs\Runtime.log' -PreventSleep $true }
        }
    }
}
