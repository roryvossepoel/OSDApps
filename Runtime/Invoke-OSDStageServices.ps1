[CmdletBinding()]
param([string]$ConfigPath = (Join-Path $PSScriptRoot 'config.json'))

function Assert-OSDStageServiceOperation {
    param([Parameter(Mandatory)]$Operation)
    $name = [string]$Operation.Name
    if ([string]::IsNullOrWhiteSpace($name) -or $name.Length -gt 256 -or
        $name -ne $name.Trim() -or $name -match '["/\\*?\[\]\x00-\x1F]') {
        throw 'Use an exact service name of at most 256 characters, without wildcards, quotes, slashes or control characters.'
    }
    $startup = [string]$Operation.StartupType
    $state = [string]$Operation.State
    if (-not $startup -and -not $state) { throw 'Specify StartupType, State, or both.' }
    if ($startup -and $startup -notin @('Automatic','AutomaticDelayedStart','Manual','Disabled')) { throw 'Unsupported service startup type.' }
    if ($state -and $state -notin @('Running','Stopped')) { throw 'Unsupported service state.' }
    if ($startup -eq 'Disabled' -and $state -eq 'Running') { throw 'A disabled service cannot be requested Running.' }
    if ([int]$Operation.TimeoutSeconds -lt 1 -or [int]$Operation.TimeoutSeconds -gt 300) { throw 'TimeoutSeconds must be between 1 and 300.' }
}

function Assert-OSDStageServiceConfiguration {
    param([Parameter(Mandatory)]$Configuration)
    $id = [guid]::Empty
    if ([int]$Configuration.SchemaVersion -ne 2 -or
        -not [guid]::TryParse([string]$Configuration.DeploymentId, [ref]$id) -or
        [string]::IsNullOrWhiteSpace([string]$Configuration.ResultPath) -or
        @($Configuration.Operations).Count -eq 0) { throw 'Invalid Services configuration.' }
    $seen = @{}
    foreach ($operation in @($Configuration.Operations)) {
        Assert-OSDStageServiceOperation -Operation $operation
        if ($seen.ContainsKey([string]$operation.Name)) { throw 'Duplicate service operation.' }
        $seen[[string]$operation.Name] = $true
    }
}

function Get-OSDStageServiceState {
    param([Parameter(Mandatory)][string]$Name)
    $service = Get-Service -Name $Name -ErrorAction Stop
    try {
        if ($service.Name -ine $Name -or (([int]$service.ServiceType -band 48) -eq 0)) { throw 'Only exact Win32 service names are supported; driver services are excluded.' }
        $service.Refresh()
        $startup = [string]$service.StartType
        if ($startup -eq 'Automatic') {
            $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Services\' + $Name)
            try { if ($key -and [int]$key.GetValue('DelayedAutoStart', 0) -eq 1) { $startup = 'AutomaticDelayedStart' } }
            finally { if ($key) { $key.Dispose() } }
        }
        [pscustomobject]@{State=[string]$service.Status;StartupType=$startup}
    }
    finally { $service.Dispose() }
}

function Invoke-OSDStageServiceControl {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('config','start','stop')][string]$Action,
        [string]$StartupType,
        [int]$TimeoutSeconds = 30
    )
    # No shell interpretation, remote target, credentials or arbitrary sc.exe arguments.
    $arguments = '{0} "{1}"' -f $Action, $Name
    if ($Action -eq 'config') {
        $mode = @{Automatic='auto';AutomaticDelayedStart='delayed-auto';Manual='demand';Disabled='disabled'}[$StartupType]
        if (-not $mode) { throw 'Unsupported service startup type.' }
        $arguments += ' start= ' + $mode
    }
    $native = Join-Path $env:SystemRoot 'System32\sc.exe'
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { $native = Join-Path $env:SystemRoot 'Sysnative\sc.exe' }
    $process = New-Object System.Diagnostics.Process
    try {
        $process.StartInfo.FileName = $native
        $process.StartInfo.Arguments = $arguments
        $process.StartInfo.UseShellExecute = $false
        $process.StartInfo.CreateNoWindow = $true
        $process.StartInfo.RedirectStandardOutput = $true
        $process.StartInfo.RedirectStandardError = $true
        $encoding = [Text.Encoding]::GetEncoding([Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)
        $process.StartInfo.StandardOutputEncoding = $encoding
        $process.StartInfo.StandardErrorEncoding = $encoding
        if (-not $process.Start()) { throw 'Unable to start service control utility.' }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $process.Kill()
            $process.WaitForExit()
            throw 'Service control utility timed out; the requested change may already have taken effect.'
        }
        [pscustomobject]@{Command=('sc.exe ' + $arguments);ExitCode=$process.ExitCode;StandardOutput=$stdout.GetAwaiter().GetResult();StandardError=$stderr.GetAwaiter().GetResult()}
    }
    finally { $process.Dispose() }
}

function Wait-OSDStageServiceState {
    param([string]$Name, [string]$State, [int]$TimeoutSeconds)
    $service = Get-Service -Name $Name -ErrorAction Stop
    try { $service.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]$State, [TimeSpan]::FromSeconds($TimeoutSeconds)) }
    finally { $service.Dispose() }
}

function Invoke-OSDStageServiceOperation {
    param([Parameter(Mandatory)]$Operation)
    Assert-OSDStageServiceOperation -Operation $Operation
    $record = [ordered]@{
        Name=[string]$Operation.Name;StartupTypeRequested=[string]$Operation.StartupType;StateRequested=[string]$Operation.State
        Status='Failed';Outcome='Failed';Before=$null;After=$null
        ConfigurationCommand=$null;StateCommand=$null;Error=$null
    }
    try {
        $record.Before = Get-OSDStageServiceState -Name $Operation.Name
        $current = $record.Before
        if ($Operation.StartupType -and $current.StartupType -ne $Operation.StartupType) {
            $record.ConfigurationCommand = Invoke-OSDStageServiceControl -Name $Operation.Name -Action config -StartupType $Operation.StartupType -TimeoutSeconds $Operation.TimeoutSeconds
            if ($record.ConfigurationCommand.ExitCode -ne 0) { throw ('Service configuration failed with exit code {0}.' -f $record.ConfigurationCommand.ExitCode) }
            $current = Get-OSDStageServiceState -Name $Operation.Name
            if ($current.StartupType -ne $Operation.StartupType) { throw 'Requested startup type was not observed after service configuration.' }
        }
        if ($Operation.State -and $current.State -ne $Operation.State) {
            if ($Operation.State -eq 'Running' -and $current.StartupType -eq 'Disabled') { throw 'Service is disabled; explicitly request an enabled StartupType before starting it.' }
            $pending = if ($Operation.State -eq 'Running') { 'StartPending' } else { 'StopPending' }
            if ($current.State -ne $pending) {
                $action = if ($Operation.State -eq 'Running') { 'start' } else { 'stop' }
                $record.StateCommand = Invoke-OSDStageServiceControl -Name $Operation.Name -Action $action -TimeoutSeconds $Operation.TimeoutSeconds
                if ($record.StateCommand.ExitCode -ne 0) { throw ('Service state request failed with exit code {0}.' -f $record.StateCommand.ExitCode) }
            }
            Wait-OSDStageServiceState -Name $Operation.Name -State $Operation.State -TimeoutSeconds $Operation.TimeoutSeconds
        }
        $record.After = Get-OSDStageServiceState -Name $Operation.Name
        if ($Operation.StartupType -and $record.After.StartupType -ne $Operation.StartupType) { throw 'Requested startup type was not observed at the end of this operation.' }
        if ($Operation.State -and $record.After.State -ne $Operation.State) { throw 'Requested service state was not observed during this run.' }
        $record.Status = 'Succeeded'
        $record.Outcome = if ($record.ConfigurationCommand -or $record.StateCommand) { 'Applied' } elseif ($record.Before.State -ne $record.After.State) { 'PendingCompleted' } else { 'Unchanged' }
    }
    catch {
        $record.Error = $_.Exception.Message
        try { $record.After = Get-OSDStageServiceState -Name $Operation.Name } catch { }
    }
    [pscustomobject]$record
}

function Invoke-OSDStageServiceConfiguration {
    param([Parameter(Mandatory)]$Configuration)
    Assert-OSDStageServiceConfiguration -Configuration $Configuration
    $items = @(foreach ($operation in @($Configuration.Operations)) { Invoke-OSDStageServiceOperation -Operation $operation })
    $failed = @($items | Where-Object Status -eq 'Failed').Count
    [pscustomobject]@{
        SchemaVersion=2;DeploymentId=[string]$Configuration.DeploymentId
        Status=if ($failed) { 'Failed' } else { 'Succeeded' }
        OperationCount=$items.Count;SuccessfulOperationCount=($items.Count-$failed);FailedOperationCount=$failed
        RestartNeeded=$false;RebootRequested=$false;Items=$items
        Error=if ($failed) { "$failed service operation(s) failed." } else { $null }
    }
}

if ($MyInvocation.InvocationName -eq '.') { return }
$ErrorActionPreference = 'Stop'
try {
    if (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT') { throw 'Service runtime requires full Windows.' }
    $configuration = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    $record = Invoke-OSDStageServiceConfiguration -Configuration $configuration
    $resultPath = [Environment]::ExpandEnvironmentVariables([string]$configuration.ResultPath)
    New-Item -ItemType Directory -Path (Split-Path $resultPath -Parent) -Force | Out-Null
    $record | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    if ($record.Status -eq 'Failed') { exit 1 }
    exit 0
}
catch { Write-Error $_.Exception.Message -ErrorAction Continue; exit 1 }
