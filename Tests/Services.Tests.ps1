Describe 'One-shot Windows services' {
    BeforeAll {
        $script:root = Split-Path $PSScriptRoot -Parent
        Import-Module (Join-Path $script:root 'OSDApps.psd1') -Force
        . (Join-Path $script:root 'Runtime\Invoke-OSDAppServices.ps1')
    }
    BeforeEach { Set-OSDAppConfiguration -EnableBuiltIns $true -EnableRepository $true -CleanupMode Never }

    It 'requires explicit noncontradictory intent and exact service names' {
        foreach ($op in @(
            @{Name='Spool*';StartupType='Manual';State='';TimeoutSeconds=30},
            @{Name='Spooler';StartupType='';State='';TimeoutSeconds=30},
            @{Name='Spooler';StartupType='Disabled';State='Running';TimeoutSeconds=30},
            @{Name='Spooler';StartupType='Boot';State='';TimeoutSeconds=30},
            @{Name='Spooler';StartupType='';State='Paused';TimeoutSeconds=30},
            @{Name='Spooler';StartupType='Manual';State='';TimeoutSeconds=0},
            @{Name='bad"name';StartupType='Manual';State='';TimeoutSeconds=30}
        )) { { Assert-OSDAppServiceOperation -Operation ([pscustomobject]$op) } | Should -Throw }
    }
    It 'validates all operations and duplicate names before calling the service manager' {
        Mock Invoke-OSDAppServiceOperation { throw 'must not execute' }
        $config = [pscustomobject]@{SchemaVersion=1;DeploymentId=[guid]::NewGuid().Guid;ResultPath='C:\result.json';Operations=@(
            [pscustomobject]@{Name='Example';StartupType='Manual';State='';TimeoutSeconds=30},
            [pscustomobject]@{Name='example';StartupType='Automatic';State='';TimeoutSeconds=30}
        )}
        { Invoke-OSDAppServiceConfiguration -Configuration $config } | Should -Throw '*Duplicate*'
        Should -Invoke Invoke-OSDAppServiceOperation -Exactly 0
    }
    It 'skips native commands when the service is already in the requested state' {
        Mock Get-OSDAppServiceState { [pscustomobject]@{StartupType='Automatic';State='Running'} }
        Mock Invoke-OSDAppServiceControl { throw 'must not execute' }
        Mock Wait-OSDAppServiceState { throw 'must not wait' }
        $result = Invoke-OSDAppServiceOperation -Operation ([pscustomobject]@{Name='Example';StartupType='Automatic';State='Running';TimeoutSeconds=30})
        $result.Status | Should -Be Succeeded
        $result.Outcome | Should -Be Unchanged
        Should -Invoke Invoke-OSDAppServiceControl -Exactly 0
        Should -Invoke Wait-OSDAppServiceState -Exactly 0
    }
    It 'configures Disabled without implicitly stopping a running service' {
        $script:fakeStartup = 'Manual'
        Mock Get-OSDAppServiceState { [pscustomobject]@{StartupType=$script:fakeStartup;State='Running'} }
        Mock Invoke-OSDAppServiceControl { $script:fakeStartup='Disabled';[pscustomobject]@{ExitCode=0;StandardOutput='configured';StandardError=''} }
        $result = Invoke-OSDAppServiceOperation -Operation ([pscustomobject]@{Name='Example';StartupType='Disabled';State='';TimeoutSeconds=30})
        $result.Status | Should -Be Succeeded
        $result.After.State | Should -Be Running
        Should -Invoke Invoke-OSDAppServiceControl -Exactly 1 -ParameterFilter {$Action -eq 'config'}
        Should -Invoke Invoke-OSDAppServiceControl -Exactly 0 -ParameterFilter {$Action -eq 'stop'}
    }
    It 'waits for an existing pending operation without issuing another request' {
        $script:fakeState = 'StartPending'
        Mock Get-OSDAppServiceState { [pscustomobject]@{StartupType='Manual';State=$script:fakeState} }
        Mock Wait-OSDAppServiceState { $script:fakeState='Running' }
        Mock Invoke-OSDAppServiceControl { throw 'must not execute' }
        $result = Invoke-OSDAppServiceOperation -Operation ([pscustomobject]@{Name='Example';StartupType='';State='Running';TimeoutSeconds=7})
        $result.Status | Should -Be Succeeded
        $result.Outcome | Should -Be PendingCompleted
        Should -Invoke Wait-OSDAppServiceState -Exactly 1 -ParameterFilter {$TimeoutSeconds -eq 7}
        Should -Invoke Invoke-OSDAppServiceControl -Exactly 0
    }
    It 'records a timeout without retry and continues with later services' {
        Mock Get-OSDAppServiceState { param($Name) if ($Name -eq 'Missing') { throw 'Service not found' }; [pscustomobject]@{StartupType='Manual';State='Stopped'} }
        Mock Invoke-OSDAppServiceControl { [pscustomobject]@{ExitCode=0;StandardOutput='request accepted';StandardError=''} }
        Mock Wait-OSDAppServiceState { throw 'fixture timeout' }
        $config = [pscustomobject]@{SchemaVersion=1;DeploymentId=[guid]::NewGuid().Guid;ResultPath='C:\result.json';Operations=@(
            [pscustomobject]@{Name='Missing';StartupType='Manual';State='';TimeoutSeconds=1},
            [pscustomobject]@{Name='Slow';StartupType='';State='Running';TimeoutSeconds=1},
            [pscustomobject]@{Name='AlreadyStopped';StartupType='Manual';State='Stopped';TimeoutSeconds=1}
        )}
        $result = Invoke-OSDAppServiceConfiguration -Configuration $config
        $result.Status | Should -Be Failed
        $result.FailedOperationCount | Should -Be 2
        $result.SuccessfulOperationCount | Should -Be 1
        $result.Items[1].Error | Should -Match 'timeout'
        $result.Items[1].StateCommand.StandardOutput | Should -Be 'request accepted'
        $result.RebootRequested | Should -BeFalse
        Should -Invoke Invoke-OSDAppServiceControl -Exactly 1
        Should -Invoke Wait-OSDAppServiceState -Exactly 1
    }
    It 'preserves successful configuration evidence when the state request fails' {
        $script:fakeStartup = 'Manual'
        Mock Get-OSDAppServiceState { [pscustomobject]@{StartupType=$script:fakeStartup;State='Running'} }
        Mock Invoke-OSDAppServiceControl {
            param($Action)
            if ($Action -eq 'config') { $script:fakeStartup='Disabled';$code=0 } else { $code=1051 }
            [pscustomobject]@{ExitCode=$code;StandardOutput='native detail';StandardError=''}
        }
        $result = Invoke-OSDAppServiceOperation -Operation ([pscustomobject]@{Name='Example';StartupType='Disabled';State='Stopped';TimeoutSeconds=30})
        $result.Status | Should -Be Failed
        $result.ConfigurationCommand.ExitCode | Should -Be 0
        $result.StateCommand.ExitCode | Should -Be 1051
        $result.After.StartupType | Should -Be Disabled
        $result.After.State | Should -Be Running
    }
    It 'stages combined variables and services, merges explicit fields, and rejects tampering' {
        InModuleScope OSDApps {
            Mock Test-OSDAppWinPE { $true }
            $target = Join-Path $TestDrive 'Offline Service Windows'
            New-Item -ItemType Directory -Path $target | Out-Null
            Add-OSDAppService -Name Example -StartupType Manual -WindowsPath $target -WhatIf
            Test-Path (Join-Path $target 'Windows\Temp\OSDApps\DeviceManifest.json') | Should -BeFalse
            Add-OSDAppEnvironmentVariable -Name TestSetting -Value 'Lab' -WindowsPath $target | Out-Null
            Add-OSDAppService -Name Example -StartupType Manual -WindowsPath $target | Out-Null
            Add-OSDAppService -Name example -State Running -TimeoutSeconds 7 -WindowsPath $target | Out-Null
            $ready = Test-OSDAppDeployment -WindowsPath $target -RequireOfflineReady -ThrowOnFailure
            $ready.AppCount | Should -Be 2
            $ready.OfflineReady | Should -BeTrue
            $ready.NetworkRequired | Should -BeFalse
            $configFile = Join-Path $target 'Windows\Temp\OSDApps\BuiltIn\Services\config.json'
            $config = Get-Content $configFile -Raw | ConvertFrom-Json
            @($config.Operations).Count | Should -Be 1
            $config.Operations[0].StartupType | Should -Be Manual
            $config.Operations[0].State | Should -Be Running
            $config.Operations[0].TimeoutSeconds | Should -Be 7
            $hash = (Get-FileHash $configFile).Hash
            { Add-OSDAppService -Name Example -StartupType Disabled -WindowsPath $target } | Should -Throw '*disabled*Running*'
            (Get-FileHash $configFile).Hash | Should -Be $hash
            Mock Add-OSDAppSetupComplete { throw 'fixture rollback' }
            { Add-OSDAppService -Name Example -StartupType Automatic -WindowsPath $target } | Should -Throw '*rollback*'
            (Get-FileHash $configFile).Hash | Should -Be $hash
            Add-Content $configFile 'tamper'
            { Test-OSDAppDeployment -WindowsPath $target -RequireOfflineReady -ThrowOnFailure } | Should -Throw
            { Add-OSDAppService -Name Example -StartupType Automatic -WindowsPath $target } | Should -Throw '*not an intact*'
        }
    }
    It 'rejects preparation-PC staging and honors BuiltIn source selection' {
        InModuleScope OSDApps {
            Mock Test-OSDAppWinPE { $false }
            { Add-OSDAppService -Name Example -State Stopped } | Should -Throw '*WinPE*'
            Set-OSDAppConfiguration -EnableBuiltIns $false
            { Add-OSDAppService -Name Example -State Stopped } | Should -Throw '*disabled*'
        }
    }
    It 'uses native service control and the combined runner on disposable services only' {
        $exe = Join-Path $TestDrive 'OSDApps Test Service.exe'
        $compiler = Join-Path $TestDrive 'CompileService.ps1'
        @'
param([string]$OutputPath)
$ErrorActionPreference='Stop'
Add-Type -ReferencedAssemblies 'System.ServiceProcess.dll','System.dll' -OutputAssembly $OutputPath -OutputType ConsoleApplication -TypeDefinition @"
using System.ServiceProcess;
public sealed class OSDAppsTestService : ServiceBase {
    public OSDAppsTestService(string name) { ServiceName=name; CanStop=true; }
    protected override void OnStart(string[] args) { }
    protected override void OnStop() { }
    public static void Main(string[] args) { ServiceBase.Run(new OSDAppsTestService(args[0])); }
}
"@
'@ | Set-Content $compiler -Encoding UTF8
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $compiler -OutputPath $exe
        $LASTEXITCODE | Should -Be 0
        $nameA = 'OSDAppsTestA_' + [guid]::NewGuid().ToString('N')
        $nameB = 'OSDAppsTestB_' + [guid]::NewGuid().ToString('N')
        $envName = 'OSDAppsTest_' + [guid]::NewGuid().ToString('N')
        try {
            New-Service -Name $nameA -BinaryPathName ('"{0}" {1}' -f $exe,$nameA) -StartupType Manual | Out-Null
            New-Service -Name $nameB -BinaryPathName ('"{0}" {1}' -f $exe,$nameB) -StartupType Manual -DependsOn $nameA | Out-Null
            InModuleScope OSDApps -Parameters @{TestRoot=$TestDrive;NameA=$nameA;NameB=$nameB;EnvName=$envName} {
                param($TestRoot,$NameA,$NameB,$EnvName)
                Mock Test-OSDAppWinPE { $true }
                $target = Join-Path $TestRoot 'Combined Windows'
                New-Item -ItemType Directory -Path $target | Out-Null
                $results = Join-Path $TestRoot 'Combined Results'
                Set-OSDAppConfiguration -LogPath (Join-Path $TestRoot 'Combined.log') -ResultPath (Join-Path $results 'Latest.json') -PreventSleep $false
                Add-OSDAppEnvironmentVariable -Name $EnvName -Value 'Lab' -WindowsPath $target | Out-Null
                Add-OSDAppService -Name $NameA -StartupType Manual -State Running -WindowsPath $target | Out-Null
                Add-OSDAppService -Name $NameB -StartupType AutomaticDelayedStart -State Running -WindowsPath $target | Out-Null
                $stage = Join-Path $target 'Windows\Temp\OSDApps'
                & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $stage 'Invoke-OSDAppPreInstall.ps1') -StagedPath $stage
                $LASTEXITCODE | Should -Be 0
                & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $stage 'Invoke-OSDAppRunner.ps1') -StagedPath $stage
                $LASTEXITCODE | Should -Be 0
                $latest = Get-Content (Join-Path $results 'Latest.json') -Raw | ConvertFrom-Json
                $latest.SuccessfulAppCount | Should -Be 2
                $report = Get-Content (Join-Path $results 'Services-Result.json') -Raw | ConvertFrom-Json
                $report.SuccessfulOperationCount | Should -Be 2
                $report.DeploymentId | Should -Be $latest.DeploymentId
                $report.Items[1].After.StartupType | Should -Be AutomaticDelayedStart
                $report.Items[1].After.State | Should -Be Running
            }
            $blocked = Invoke-OSDAppServiceOperation -Operation ([pscustomobject]@{Name=$nameA;StartupType='';State='Stopped';TimeoutSeconds=10})
            $blocked.Status | Should -Be Failed
            $blocked.StateCommand.ExitCode | Should -Be 1051
            (Get-OSDAppServiceState -Name $nameB).State | Should -Be Running
            $stoppedB = Invoke-OSDAppServiceOperation -Operation ([pscustomobject]@{Name=$nameB;StartupType='Automatic';State='Stopped';TimeoutSeconds=10})
            $stoppedB.Status | Should -Be Succeeded
            $stoppedB.After.StartupType | Should -Be Automatic
            $stoppedB.After.State | Should -Be Stopped
            $op = [pscustomobject]@{Name=$nameA;StartupType='Disabled';State='Stopped';TimeoutSeconds=10}
            (Invoke-OSDAppServiceOperation -Operation $op).Status | Should -Be Succeeded
            (Invoke-OSDAppServiceOperation -Operation $op).Outcome | Should -Be Unchanged
            $disabled = Invoke-OSDAppServiceOperation -Operation ([pscustomobject]@{Name=$nameA;StartupType='';State='Running';TimeoutSeconds=10})
            $disabled.Status | Should -Be Failed
            $disabled.StateCommand | Should -BeNullOrEmpty
        }
        finally {
            foreach ($name in @($nameB,$nameA)) {
                $service = Get-Service -Name $name -ErrorAction SilentlyContinue
                if ($service) {
                    try { & sc.exe stop $name | Out-Null; $service.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Stopped,[TimeSpan]::FromSeconds(15)) }
                    finally { $service.Dispose(); & sc.exe delete $name | Out-Null }
                }
            }
            [Environment]::SetEnvironmentVariable($envName,$null,'Machine')
            Set-OSDAppConfiguration -LogPath '%ProgramData%\OSDApps\Logs\Runtime.log' -ResultPath '%ProgramData%\OSDApps\Results\Latest.json' -PreventSleep $true
        }
    }
}
