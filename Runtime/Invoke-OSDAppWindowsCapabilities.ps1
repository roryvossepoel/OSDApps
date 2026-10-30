[CmdletBinding()]
param([string]$ConfigPath)

function Assert-OSDAppWindowsCapabilityName {
    param([AllowNull()][AllowEmptyString()][string]$Name)
    # Literal DISM identity, including the version/locale separators. No wildcards
    # or native command-line delimiters; do not maintain a capability allowlist.
    if ($Name -notmatch '\A[A-Za-z0-9][A-Za-z0-9._~-]{0,255}\z' -or $Name -notlike '*~*') {
        throw 'Specify an exact capability identity from Get-WindowsCapability, without whitespace, quotes or wildcards.'
    }
}

function Assert-OSDAppWindowsCapabilityConfiguration {
    param([Parameter(Mandatory)]$Configuration)
    $id=[guid]::Empty
    if ([int]$Configuration.SchemaVersion -ne 1 -or
        -not [guid]::TryParse([string]$Configuration.DeploymentId,[ref]$id) -or
        [string]::IsNullOrWhiteSpace([string]$Configuration.ResultPath) -or
        $Configuration.Operations -isnot [System.Collections.IList] -or
        @($Configuration.Operations).Count -lt 1 -or @($Configuration.Operations).Count -gt 2048) {
        throw 'Invalid Windows Capabilities configuration.'
    }
    $seen=@{}
    foreach ($operation in $Configuration.Operations) {
        Assert-OSDAppWindowsCapabilityName -Name ([string]$operation.Name)
        if ([string]$operation.Action -notin @('Add','Remove')) { throw 'Capability action must be Add or Remove.' }
        if ($seen.ContainsKey([string]$operation.Name)) { throw 'Duplicate Windows capability operation.' }
        $seen[[string]$operation.Name]=$true
    }
}

function Assert-OSDAppWindowsCapabilityVersion {
    param([Parameter(Mandatory)]$CurrentVersion)
    if ([string]$CurrentVersion.InstallationType -ne 'Client' -or [int]$CurrentVersion.CurrentBuildNumber -lt 26200) {
        throw 'Windows capabilities require Windows 11 25H2 or later (client build 26200+).'
    }
}

function Assert-OSDAppWindowsCapabilityContext {
    if (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT') { throw 'Windows capabilities runtime requires full Windows, not WinPE.' }
    if (-not [Environment]::Is64BitProcess -or [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-18') {
        throw 'Windows capabilities runtime requires native 64-bit PowerShell as SYSTEM during SetupComplete.'
    }
    $cv=Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
    Assert-OSDAppWindowsCapabilityVersion -CurrentVersion $cv
}

function Get-OSDAppWindowsCapabilityState {
    param([Parameter(Mandatory)][string]$Name)
    Assert-OSDAppWindowsCapabilityName -Name $Name
    $capabilityMatches=@(Get-WindowsCapability -Online -Name $Name -ErrorAction Stop | Where-Object { [string]$_.Name -ieq $Name })
    if ($capabilityMatches.Count -ne 1) { throw "Capability '$Name' is not available on this Windows image." }
    [string]$capabilityMatches[0].State
}

function Invoke-OSDAppCapabilityDism {
    param(
        [Parameter(Mandatory)][ValidateSet('Add','Remove')][string]$Action,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$LogPath,
        [ValidateRange(1,3600)][int]$TimeoutSeconds=1800
    )
    Assert-OSDAppWindowsCapabilityName -Name $Name
    if (-not [IO.Path]::IsPathRooted($LogPath) -or $LogPath -match '["\x00-\x1F]' -or $LogPath.EndsWith('\')) {
        throw 'DISM log path must be an absolute file path without quotes or control characters.'
    }
    # Add-WindowsCapability has no NoRestart switch. Use the native DISM switch
    # explicitly, while leaving source/update policy selection to Windows.
    $process=[Diagnostics.Process]::new()
    try {
        $process.StartInfo.FileName=Join-Path $env:SystemRoot 'System32\dism.exe'
        $process.StartInfo.Arguments='/Online /{0}-Capability /CapabilityName:{1} /NoRestart /English /LogPath:"{2}"' -f $Action,$Name,$LogPath
        $process.StartInfo.UseShellExecute=$false;$process.StartInfo.CreateNoWindow=$true
        $process.StartInfo.RedirectStandardOutput=$true;$process.StartInfo.RedirectStandardError=$true
        if (-not $process.Start()) { throw 'Unable to start capability servicing.' }
        $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds*1000)) {
            $process.Kill();$null=$process.WaitForExit(5000)
            throw [TimeoutException]::new('Capability servicing timed out. Windows servicing may still be active; no further operations, retry or reboot are requested.')
        }
        if (-not $stdout.Wait(5000) -or -not $stderr.Wait(5000)) { throw [TimeoutException]::new('DISM output capture timed out; no further operations are requested.') }
        [pscustomobject]@{ExitCode=$process.ExitCode;StandardOutput=$stdout.Result;StandardError=$stderr.Result;LogPath=$LogPath}
    }
    finally { $process.Dispose() }
}

function Invoke-OSDAppWindowsCapabilityOperation {
    param([Parameter(Mandatory)]$Operation,[Parameter(Mandatory)][string]$LogPath)
    $name=[string]$Operation.Name;$action=[string]$Operation.Action
    $record=[ordered]@{
        Name=$name;Action=$action;Status='Failed';Outcome='Failed';StateBefore=$null;StateAfter=$null
        ExitCode=$null;RestartNeeded=$false;TimedOut=$false;DismLogPath=$null;Error=$null
    }
    try {
        if ($action -notin @('Add','Remove')) { throw 'Capability action must be Add or Remove.' }
        $record.StateBefore=Get-OSDAppWindowsCapabilityState -Name $name
        $record.StateAfter=$record.StateBefore
        $desired=if ($action -eq 'Add') { 'Installed' } else { 'NotPresent' }
        if ($record.StateBefore -eq $desired) {
            $record.Status='Succeeded';$record.Outcome=if ($action -eq 'Add') { 'AlreadyInstalled' } else { 'AlreadyAbsent' }
            return [pscustomobject]$record
        }
        if ($record.StateBefore -notin @('Installed','NotPresent','Staged','Resolved')) {
            if ($record.StateBefore -match 'Pending') { $record.RestartNeeded=$true }
            throw ('Capability is in state {0}; no servicing attempt was made.' -f $record.StateBefore)
        }
        $record.DismLogPath=$LogPath
        $record.StateAfter=$null
        $native=Invoke-OSDAppCapabilityDism -Action $action -Name $name -LogPath $LogPath
        $record.ExitCode=$native.ExitCode
        $record.RestartNeeded=($native.ExitCode -eq 3010)
        if ($native.ExitCode -notin @(0,3010)) { throw ('DISM {0}-Capability failed with exit code {1}. See {2}' -f $action,$native.ExitCode,$LogPath) }
        $record.StateAfter=Get-OSDAppWindowsCapabilityState -Name $name
        if ($record.StateAfter -ne $desired) {
            if ($record.RestartNeeded -or $record.StateAfter -match 'Pending') {
                $record.RestartNeeded=$true;$record.Status='Succeeded';$record.Outcome='PendingRestart'
            } else { throw ('DISM returned success but capability state is {0}, expected {1}.' -f $record.StateAfter,$desired) }
        } else {
            $record.Status='Succeeded';$record.Outcome=if ($action -eq 'Add') { 'Installed' } else { 'Removed' }
        }
    }
    catch {
        $record.Error=$_.Exception.Message
        $record.TimedOut=($_.Exception -is [TimeoutException])
    }
    [pscustomobject]$record
}

function Invoke-OSDAppWindowsCapabilityConfiguration {
    param([Parameter(Mandatory)]$Configuration)
    Assert-OSDAppWindowsCapabilityConfiguration -Configuration $Configuration
    $record=[ordered]@{
        SchemaVersion=1;DeploymentId=[string]$Configuration.DeploymentId;Status='Failed'
        OperationCount=@($Configuration.Operations).Count;SuccessfulOperationCount=0;FailedOperationCount=0
        RestartNeeded=$false;RebootRequested=$false;Items=@();Error=$null
    }
    try {
        Assert-OSDAppWindowsCapabilityContext
        $resultPath=[Environment]::ExpandEnvironmentVariables([string]$Configuration.ResultPath)
        $logDirectory=Split-Path $resultPath -Parent
        New-Item -ItemType Directory -Path $logDirectory -Force -ErrorAction Stop | Out-Null
        $items=[System.Collections.Generic.List[object]]::new()
        $timedOut=$false
        foreach ($operation in $Configuration.Operations) {
            if ($timedOut) {
                $items.Add([pscustomobject]@{Name=$operation.Name;Action=$operation.Action;Status='Failed';Outcome='NotAttempted';StateBefore=$null;StateAfter=$null;ExitCode=$null;RestartNeeded=$false;TimedOut=$false;DismLogPath=$null;Error='Not attempted after a servicing timeout.'})
                continue
            }
            $log=Join-Path $logDirectory ('WindowsCapabilities-{0}-{1}.log' -f $Configuration.DeploymentId,$items.Count)
            $item=Invoke-OSDAppWindowsCapabilityOperation -Operation $operation -LogPath $log
            $items.Add($item)
            $timedOut=$item.TimedOut
        }
        $record.Items=@($items.ToArray())
        $record.SuccessfulOperationCount=@($items | Where-Object Status -eq 'Succeeded').Count
        $record.FailedOperationCount=@($items | Where-Object Status -eq 'Failed').Count
        $record.RestartNeeded=@($items | Where-Object RestartNeeded).Count -gt 0
        if ($record.FailedOperationCount -gt 0) { throw ('{0} Windows capability operation(s) failed.' -f $record.FailedOperationCount) }
        $record.Status='Succeeded'
    }
    catch { $record.Error=$_.Exception.Message }
    [pscustomobject]$record
}

if ($MyInvocation.InvocationName -eq '.') { return }
$ErrorActionPreference='Stop'
try {
    if (-not $ConfigPath) { $ConfigPath=Join-Path $PSScriptRoot 'config.json' }
    $configuration=Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    $record=Invoke-OSDAppWindowsCapabilityConfiguration -Configuration $configuration
    $resultPath=[Environment]::ExpandEnvironmentVariables([string]$configuration.ResultPath)
    New-Item -ItemType Directory -Path (Split-Path $resultPath -Parent) -Force -ErrorAction Stop | Out-Null
    $record | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resultPath -Encoding UTF8 -ErrorAction Stop
    if ($record.Status -eq 'Failed') { Write-Error $record.Error -ErrorAction Continue;exit 1 }
    if ($record.RestartNeeded) { exit 3010 }
    exit 0
}
catch { Write-Error $_.Exception.Message -ErrorAction Continue;exit 1 }
