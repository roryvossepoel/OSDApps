[CmdletBinding()]
param([string]$ConfigPath = (Join-Path $PSScriptRoot 'config.json'))

function Assert-OSDAppEnvironmentOperation {
    param([Parameter(Mandatory)]$Operation)

    if ([string]$Operation.Action -notin @('Set','Remove','AppendPath')) { throw 'Unsupported environment operation.' }
    $name = [string]$Operation.Name
    if ([string]::IsNullOrWhiteSpace($name) -or $name.Length -gt 255 -or
        $name -ne $name.Trim() -or $name -match '[=\x00-\x1F]') {
        throw 'Environment variable names must contain 1 to 255 characters, without equals signs, control characters or surrounding whitespace.'
    }
    if ($Operation.Action -eq 'Set') {
        if ($Operation.Value -isnot [string] -or $Operation.Value.Length -gt 32766 -or $Operation.Value.Contains([string][char]0)) {
            throw 'Environment values must be strings of at most 32766 characters without NUL characters.'
        }
        if ([string]$Operation.Kind -notin @('String','ExpandString')) { throw 'Unsupported environment value kind.' }
    }
    if ($Operation.Action -eq 'AppendPath') {
        if ($name -ine 'Path' -or @($Operation.Entries).Count -eq 0) { throw 'AppendPath requires at least one machine PATH entry.' }
        foreach ($entry in @($Operation.Entries)) {
            if ($entry -isnot [string] -or [string]::IsNullOrWhiteSpace($entry) -or $entry.Length -gt 32766 -or
                $entry -match '[;"\x00-\x1F]' -or $entry -ne $entry.Trim() -or
                $entry -notmatch '^(?:[A-Za-z]:[\\/]|\\\\[^\\/]+[\\/][^\\/]+|%[^%=\\/]+%(?:[\\/]|$))') {
                throw 'Each PATH entry must be an absolute drive/UNC path or a percent-variable reference, without quotes, semicolons, control characters or surrounding whitespace.'
            }
        }
    }
}

function Assert-OSDAppEnvironmentConfiguration {
    param([Parameter(Mandatory)]$Configuration)
    $id = [guid]::Empty
    if ([int]$Configuration.SchemaVersion -ne 1 -or
        -not [guid]::TryParse([string]$Configuration.DeploymentId, [ref]$id) -or
        [string]::IsNullOrWhiteSpace([string]$Configuration.ResultPath) -or
        @($Configuration.Operations).Count -eq 0) { throw 'Invalid environment configuration.' }
    foreach ($operation in @($Configuration.Operations)) { Assert-OSDAppEnvironmentOperation -Operation $operation }
}

function Get-OSDAppEnvironmentPathIdentity {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Entry)
    # Lexical comparison only: never expand against the preparation PC or resolve files.
    $identity = $Entry.Trim().Trim('"').Replace('/', '\')
    if ($identity -notmatch '^[A-Za-z]:\\$') { $identity = $identity.TrimEnd('\') }
    $identity.ToUpperInvariant()
}

function Invoke-OSDAppEnvironmentOperation {
    param(
        [Parameter(Mandatory)]$Operation,
        [Parameter(Mandatory)][Microsoft.Win32.RegistryKey]$EnvironmentKey
    )
    Assert-OSDAppEnvironmentOperation -Operation $Operation
    $name = [string]$Operation.Name
    $action = [string]$Operation.Action
    $exists = $name -in @($EnvironmentKey.GetValueNames())
    $outcome = 'Unchanged'
    $kind = $null
    $added = 0
    if ($action -eq 'Remove') {
        if ($exists) { $EnvironmentKey.DeleteValue($name, $false); $outcome = 'Removed' }
        else { $outcome = 'AlreadyAbsent' }
    }
    else {
        $before = $null
        $oldKind = $null
        if ($exists) {
            $oldKind = $EnvironmentKey.GetValueKind($name)
            if ($oldKind -notin @([Microsoft.Win32.RegistryValueKind]::String, [Microsoft.Win32.RegistryValueKind]::ExpandString)) {
                throw 'Existing environment value has a non-string registry type.'
            }
            $before = [string]$EnvironmentKey.GetValue($name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        }
        if ($action -eq 'Set') {
            $value = [string]$Operation.Value
            $kind = [Microsoft.Win32.RegistryValueKind]([string]$Operation.Kind)
        }
        else {
            $kind = if ($exists) { $oldKind } else { [Microsoft.Win32.RegistryValueKind]::ExpandString }
            $value = if ($exists) { $before } else { '' }
            $seen = @{}
            foreach ($part in @($value -split ';')) { $seen[(Get-OSDAppEnvironmentPathIdentity -Entry $part)] = $true }
            foreach ($entry in @($Operation.Entries)) {
                $identity = Get-OSDAppEnvironmentPathIdentity -Entry $entry
                if (-not $seen.ContainsKey($identity)) {
                    if ($value.Length -gt 0 -and -not $value.EndsWith(';')) { $value += ';' }
                    $value += $entry
                    $seen[$identity] = $true
                    $added++
                }
            }
        }
        if ($value.Length -gt 32766) { throw 'Resulting environment value exceeds 32766 characters.' }
        if (-not $exists -or $before -cne $value -or $oldKind -ne $kind) {
            $EnvironmentKey.SetValue($name, $value, $kind)
            $outcome = if ($action -eq 'AppendPath') { 'Appended' } else { 'Set' }
        }
    }
    [pscustomobject]@{
        Name=$name;Action=$action;Status='Succeeded';Outcome=$outcome
        Changed=($outcome -in @('Set','Removed','Appended'));Kind=[string]$kind
        AddedPathEntryCount=$added;Error=$null
    }
}

function Send-OSDAppEnvironmentChange {
    # Notify listeners once; existing process environments and services are not rewritten.
    if (-not ('OSDApps.EnvironmentNotification' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace OSDApps {
    public static class EnvironmentNotification {
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern IntPtr SendMessageTimeout(IntPtr window, uint message,
            UIntPtr wParam, string lParam, uint flags, uint timeout, out UIntPtr result);
    }
}
'@ -ErrorAction Stop
    }
    $result = [UIntPtr]::Zero
    $sent = [OSDApps.EnvironmentNotification]::SendMessageTimeout([IntPtr]0xffff, 0x1a, [UIntPtr]::Zero, 'Environment', 2, 1000, [ref]$result)
    return ($sent -ne [IntPtr]::Zero)
}

function Invoke-OSDAppEnvironmentConfiguration {
    param(
        [Parameter(Mandatory)]$Configuration,
        [Parameter(Mandatory)][Microsoft.Win32.RegistryKey]$EnvironmentKey
    )
    Assert-OSDAppEnvironmentConfiguration -Configuration $Configuration
    $items = [System.Collections.Generic.List[object]]::new()
    foreach ($operation in @($Configuration.Operations)) {
        try { $items.Add((Invoke-OSDAppEnvironmentOperation -Operation $operation -EnvironmentKey $EnvironmentKey)) }
        catch {
            # Do not echo configuration values or native exception messages into logs/results.
            $items.Add([pscustomobject]@{
                Name=[string]$operation.Name;Action=[string]$operation.Action;Status='Failed'
                Outcome='Failed';Changed=$false;Kind=$null;AddedPathEntryCount=0
                Error=('Environment operation failed ({0}).' -f $_.Exception.GetType().Name)
            })
        }
    }
    $failed = @($items | Where-Object Status -eq 'Failed').Count
    $changed = @($items | Where-Object Changed).Count
    $notification = $null
    if ($changed -gt 0) {
        try { $notification = Send-OSDAppEnvironmentChange }
        catch { $notification = $false }
    }
    [pscustomobject]@{
        SchemaVersion=1;DeploymentId=[string]$Configuration.DeploymentId
        Status=if ($failed) { 'Failed' } else { 'Succeeded' }
        Scope='Machine';OperationCount=$items.Count;SuccessfulOperationCount=($items.Count-$failed)
        FailedOperationCount=$failed;ChangedOperationCount=$changed
        NotificationSucceeded=$notification;RestartNeeded=$false;RebootRequested=$false
        ExistingProcessesRefreshed=$false;Items=@($items)
        Error=if ($failed) { "$failed environment operation(s) failed." } else { $null }
    }
}

# Dot-sourcing exposes shared validation to module staging without performing writes.
if ($MyInvocation.InvocationName -eq '.') { return }
$ErrorActionPreference = 'Stop'
$environmentKey = $null
$configuration = $null
try {
    if (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT') { throw 'Environment runtime requires full Windows.' }
    $configuration = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    Assert-OSDAppEnvironmentConfiguration -Configuration $configuration
    $environmentKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Control\Session Manager\Environment', $true)
    if ($null -eq $environmentKey) { throw 'Machine environment registry key is unavailable.' }
    $record = Invoke-OSDAppEnvironmentConfiguration -Configuration $configuration -EnvironmentKey $environmentKey
    $resultPath = [Environment]::ExpandEnvironmentVariables([string]$configuration.ResultPath)
    New-Item -ItemType Directory -Path (Split-Path $resultPath -Parent) -Force | Out-Null
    $record | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    if ($record.Status -eq 'Failed') { exit 1 }
    exit 0
}
catch {
    # A malformed config cannot authorize any environment write.
    Write-Error 'Environment configuration failed; no values are included in this diagnostic.' -ErrorAction Continue
    exit 1
}
finally { if ($null -ne $environmentKey) { $environmentKey.Dispose() } }
