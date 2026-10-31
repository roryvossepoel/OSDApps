Describe 'Machine environment variables' {
    BeforeAll {
        $script:root = Split-Path $PSScriptRoot -Parent
        Import-Module (Join-Path $script:root 'OSDStage.psd1') -Force
        . (Join-Path $script:root 'Runtime\Invoke-OSDStageEnvironmentVariables.ps1')
    }
    BeforeEach {
        Set-OSDStageConfiguration -EnableBuiltIns $true -EnableRepository $true -CleanupMode Never
        $script:keyPath = 'Software\OSDStageTests\Environment-' + [guid]::NewGuid().ToString('N')
        $script:key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($script:keyPath)
        Mock Send-OSDStageEnvironmentChange { $true }
    }
    AfterEach {
        $script:key.Dispose()
        [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($script:keyPath, $false)
    }

    It 'sets literal and expandable strings without expanding references or evaluating code' {
        $value = '%ProgramData%\Tools;$(throw "not executable")'
        Invoke-OSDStageEnvironmentOperation -EnvironmentKey $script:key -Operation ([pscustomobject]@{Action='Set';Name='Tools';Value=$value;Kind='ExpandString'}) | Out-Null
        $script:key.GetValue('Tools', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) | Should -BeExactly $value
        $script:key.GetValueKind('Tools') | Should -Be ExpandString
        Invoke-OSDStageEnvironmentOperation -EnvironmentKey $script:key -Operation ([pscustomobject]@{Action='Set';Name='Tools';Value=$value;Kind='String'}) | Out-Null
        $script:key.GetValueKind('Tools') | Should -Be String
        $result = Invoke-OSDStageEnvironmentOperation -EnvironmentKey $script:key -Operation ([pscustomobject]@{Action='Set';Name='tools';Value=$value;Kind='String'})
        $result.Changed | Should -BeFalse
        ($result | ConvertTo-Json) | Should -Not -Match 'ProgramData|not executable'
    }
    It 'distinguishes an empty string from explicit removal on both PowerShell hosts' {
        Invoke-OSDStageEnvironmentOperation -EnvironmentKey $script:key -Operation ([pscustomobject]@{Action='Set';Name='Empty';Value='';Kind='String'}) | Out-Null
        $script:key.GetValueNames() | Should -Contain Empty
        $script:key.GetValue('Empty') | Should -BeExactly ''
        (Invoke-OSDStageEnvironmentOperation -EnvironmentKey $script:key -Operation ([pscustomobject]@{Action='Remove';Name='Empty'})).Outcome | Should -Be Removed
        (Invoke-OSDStageEnvironmentOperation -EnvironmentKey $script:key -Operation ([pscustomobject]@{Action='Remove';Name='Empty'})).Outcome | Should -Be AlreadyAbsent
    }
    It 'appends PATH without importing process PATH or rewriting existing entries and raw references' {
        $before = '%SystemRoot%\system32;C:\Tools\;"C:\Program Files\Tools";C:\;C:\Existing;C:\Existing'
        $script:key.SetValue('Path', $before, [Microsoft.Win32.RegistryValueKind]::ExpandString)
        $op = [pscustomobject]@{Action='AppendPath';Name='Path';Entries=@('c:/tools','C:\Program Files\Tools\','c:\','%ProgramData%\OSDStage\Tools','%programdata%\osdstage\tools\')}
        $result = Invoke-OSDStageEnvironmentOperation -EnvironmentKey $script:key -Operation $op
        $result.AddedPathEntryCount | Should -Be 1
        $expected = $before + ';%ProgramData%\OSDStage\Tools'
        $script:key.GetValue('Path', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) | Should -BeExactly $expected
        $script:key.GetValueKind('Path') | Should -Be ExpandString
        (Invoke-OSDStageEnvironmentOperation -EnvironmentKey $script:key -Operation $op).Changed | Should -BeFalse
    }
    It 'preserves a string PATH and existing final separator while appending' {
        $script:key.SetValue('Path', 'C:\Existing;', [Microsoft.Win32.RegistryValueKind]::String)
        Invoke-OSDStageEnvironmentOperation -EnvironmentKey $script:key -Operation ([pscustomobject]@{Action='AppendPath';Name='Path';Entries=@('C:\New')}) | Out-Null
        $script:key.GetValue('Path') | Should -BeExactly 'C:\Existing;C:\New'
        $script:key.GetValueKind('Path') | Should -Be String
    }
    It 'creates a missing PATH as expandable and accepts UNC entries' {
        Invoke-OSDStageEnvironmentOperation -EnvironmentKey $script:key -Operation ([pscustomobject]@{Action='AppendPath';Name='Path';Entries=@('\\server\share\tools')}) | Out-Null
        $script:key.GetValueKind('Path') | Should -Be ExpandString
        $script:key.GetValue('Path') | Should -BeExactly '\\server\share\tools'
    }
    It 'rejects invalid names values and PATH lists before modifying anything' {
        foreach ($op in @(
            @{Action='Set';Name='bad=name';Value='x';Kind='String'},
            @{Action='Set';Name='Name';Value="x$([char]0)y";Kind='String'},
            @{Action='Set';Name='Name';Value=$null;Kind='String'},
            @{Action='Set';Name='Name';Value='x';Kind='DWord'},
            @{Action='AppendPath';Name='Path';Entries=@('C:\Good','C:\Other;C:\Injected')},
            @{Action='AppendPath';Name='Path';Entries=@('relative\path')},
            @{Action='AppendPath';Name='Path';Entries=@('C:relative')},
            @{Action='AppendPath';Name='Path';Entries=@()}
        )) { { Invoke-OSDStageEnvironmentOperation -EnvironmentKey $script:key -Operation ([pscustomobject]$op) } | Should -Throw }
        @($script:key.GetValueNames()).Count | Should -Be 0
    }
    It 'rejects a combined PATH overflow without truncating the existing value' {
        $original = 'C:\' + ('a' * 32750)
        $script:key.SetValue('Path', $original)
        { Invoke-OSDStageEnvironmentOperation -EnvironmentKey $script:key -Operation ([pscustomobject]@{Action='AppendPath';Name='Path';Entries=@('C:\AnotherLongDirectory')}) } | Should -Throw '*exceeds*'
        $script:key.GetValue('Path') | Should -BeExactly $original
    }
    It 'validates every operation before any writes and does not broadcast on rejection' {
        $config = [pscustomobject]@{SchemaVersion=2;DeploymentId=[guid]::NewGuid().Guid;ResultPath='C:\Result.json';Operations=@(
            [pscustomobject]@{Action='Set';Name='Good';Value='value';Kind='String'},
            [pscustomobject]@{Action='Set';Name='bad=name';Value='value';Kind='String'}
        )}
        { Invoke-OSDStageEnvironmentConfiguration -Configuration $config -EnvironmentKey $script:key } | Should -Throw
        @($script:key.GetValueNames()).Count | Should -Be 0
        Should -Invoke Send-OSDStageEnvironmentChange -Exactly 0
    }
    It 'continues after an operation failure with redacted results and one notification' {
        $script:key.SetValue('BadType', 12, [Microsoft.Win32.RegistryValueKind]::DWord)
        $config = [pscustomobject]@{SchemaVersion=2;DeploymentId=[guid]::NewGuid().Guid;ResultPath='C:\Result.json';Operations=@(
            [pscustomobject]@{Action='Set';Name='BadType';Value='sensitive-fixture';Kind='String'},
            [pscustomobject]@{Action='Set';Name='Good';Value='sensitive-fixture';Kind='String'}
        )}
        $record = Invoke-OSDStageEnvironmentConfiguration -Configuration $config -EnvironmentKey $script:key
        $record.Status | Should -Be Failed
        $record.FailedOperationCount | Should -Be 1
        $record.SuccessfulOperationCount | Should -Be 1
        $script:key.GetValue('Good') | Should -BeExactly 'sensitive-fixture'
        ($record | ConvertTo-Json -Depth 10) | Should -Not -Match 'sensitive-fixture'
        $record.RebootRequested | Should -BeFalse
        $record.ExistingProcessesRefreshed | Should -BeFalse
        Should -Invoke Send-OSDStageEnvironmentChange -Exactly 1
    }
    It 'records notification failure without undoing successful persistence or requesting restart' {
        Mock Send-OSDStageEnvironmentChange { throw 'notification unavailable' }
        $config = [pscustomobject]@{SchemaVersion=2;DeploymentId=[guid]::NewGuid().Guid;ResultPath='C:\Result.json';Operations=@([pscustomobject]@{Action='Set';Name='Good';Value='value';Kind='String'})}
        $record = Invoke-OSDStageEnvironmentConfiguration -Configuration $config -EnvironmentKey $script:key
        $record.Status | Should -Be Succeeded
        $record.NotificationSucceeded | Should -BeFalse
        $record.RestartNeeded | Should -BeFalse
    }
    It 'rejects full Windows staging and disabled BuiltIn source without changing machine variables' {
        InModuleScope OSDStage {
            Mock Test-OSDStageWinPE { $false }
            { Add-OSDStageEnvironmentVariable -Name Example -Value 'x' } | Should -Throw '*WinPE*'
            Set-OSDStageConfiguration -EnableBuiltIns $false
            { Add-OSDStageEnvironmentVariable -Name Example -Value 'x' } | Should -Throw '*disabled*'
        }
    }
    It 'stages combined intent offline, preserves literal values, honors WhatIf and detects tampering' {
        InModuleScope OSDStage {
            Mock Test-OSDStageWinPE { $true }
            $target = Join-Path $TestDrive 'Offline Windows'
            New-Item -Path $target -ItemType Directory | Out-Null
            Add-OSDStageEnvironmentVariable -Name Example -Value 'first' -WindowsPath $target -WhatIf
            Test-Path (Join-Path $target 'Windows\Temp\OSDStage\DeviceManifest.json') | Should -BeFalse
            Add-OSDStageEnvironmentVariable -Name Example -Value 'first' -WindowsPath $target | Out-Null
            Add-OSDStageEnvironmentVariable -Name example -Remove -WindowsPath $target | Out-Null
            Add-OSDStageEnvironmentVariable -Name Example -Value '%ProgramData%\Tools' -ExpandString -WindowsPath $target | Out-Null
            Add-OSDStageEnvironmentVariable -AppendPath @('C:\Tools') -WindowsPath $target | Out-Null
            Add-OSDStageEnvironmentVariable -AppendPath @('c:\tools\','C:\Other') -WindowsPath $target | Out-Null
            $ready = Test-OSDStageDeployment -WindowsPath $target -RequireOfflineReady -ThrowOnFailure
            $ready.OfflineReady | Should -BeTrue
            $ready.NetworkRequired | Should -BeFalse
            $ready.PackageCount | Should -Be 1
            $configFile = Join-Path $target 'Windows\Temp\OSDStage\BuiltIn\EnvironmentVariables\config.json'
            $config = Get-Content $configFile -Raw | ConvertFrom-Json
            @($config.Operations).Count | Should -Be 3
            $config.Operations[0].Value | Should -BeExactly '%ProgramData%\Tools'
            $config.Operations[0].Kind | Should -Be ExpandString
            $before = (Get-FileHash $configFile).Hash
            Mock Add-OSDStageSetupComplete { throw 'fixture transaction failure' }
            { Add-OSDStageEnvironmentVariable -Name Example -Value 'rejected' -WindowsPath $target } | Should -Throw '*transaction failure*'
            (Get-FileHash $configFile).Hash | Should -Be $before
            Add-Content $configFile 'tampered'
            { Test-OSDStageDeployment -WindowsPath $target -RequireOfflineReady -ThrowOnFailure } | Should -Throw
            { Add-OSDStageEnvironmentVariable -Name Example -Value 'rejected' -WindowsPath $target } | Should -Throw '*not an intact*'
        }
    }
    It 'runs the actual PreInstall and SetupComplete runner using only unique temporary machine variables' {
        InModuleScope OSDStage {
            Mock Test-OSDStageWinPE { $true }
            $target = Join-Path $TestDrive 'Native Environment Windows'
            New-Item -ItemType Directory -Path $target | Out-Null
            $prefix = 'OSDStageTest_' + [guid]::NewGuid().ToString('N')
            $names = @("${prefix}_Set", "${prefix}_Empty", "${prefix}_Remove")
            $machine = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Control\Session Manager\Environment', $true)
            try {
                $machine.SetValue($names[2], 'temporary test fixture')
                $results = Join-Path $TestDrive 'Native Results'
                $log = Join-Path $TestDrive 'Native.log'
                Set-OSDStageConfiguration -LogPath $log -ResultPath (Join-Path $results 'Latest.json') -CleanupMode Never -PreventSleep $false
                Add-OSDStageEnvironmentVariable -Name $names[0] -Value '%ProgramData%\fixture-do-not-log' -ExpandString -WindowsPath $target | Out-Null
                Add-OSDStageEnvironmentVariable -Name $names[1] -Value '' -WindowsPath $target | Out-Null
                Add-OSDStageEnvironmentVariable -Name $names[2] -Remove -WindowsPath $target | Out-Null
                $stage = Join-Path $target 'Windows\Temp\OSDStage'
                & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $stage 'Invoke-OSDStagePreInstall.ps1') -StagedPath $stage
                $LASTEXITCODE | Should -Be 0
                & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $stage 'Invoke-OSDStageRunner.ps1') -StagedPath $stage
                $LASTEXITCODE | Should -Be 0
                $latest = Get-Content (Join-Path $results 'Latest.json') -Raw | ConvertFrom-Json
                $latest.Status | Should -Be Succeeded
                $latest.Packages[0].Integrity | Should -Be Sha256Validated
                $reportFile = Join-Path $results 'EnvironmentVariables-Result.json'
                $record = Get-Content $reportFile -Raw | ConvertFrom-Json
                $record.SuccessfulOperationCount | Should -Be 3
                $record.FailedOperationCount | Should -Be 0
                $record.DeploymentId | Should -Be $latest.DeploymentId
                $machine.GetValue($names[0], $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) | Should -BeExactly '%ProgramData%\fixture-do-not-log'
                $machine.GetValueKind($names[0]) | Should -Be ExpandString
                $machine.GetValueNames() | Should -Contain $names[1]
                $machine.GetValueNames() | Should -Not -Contain $names[2]
                (Get-Content $log -Raw) | Should -Not -Match 'fixture-do-not-log'
                (Get-Content $reportFile -Raw) | Should -Not -Match 'fixture-do-not-log'
            }
            finally {
                foreach ($name in $names) { $machine.DeleteValue($name, $false) }
                $machine.Dispose()
                Set-OSDStageConfiguration -LogPath '%ProgramData%\OSDStage\Logs\Runtime.log' -ResultPath '%ProgramData%\OSDStage\Results\Latest.json' -PreventSleep $true
            }
        }
    }
}
