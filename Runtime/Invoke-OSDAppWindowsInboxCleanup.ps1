# Built-in Windows Inbox Cleanup - run once during SetupComplete as SYSTEM.
# Deliberately self-contained; the normal OSDApps runtime only supplies this file and config.json.
[CmdletBinding()]
param(
    [string]$ConfigurationPath = (Join-Path $PSScriptRoot 'config.json'),
    [switch]$DiagnoseOnly
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$script:RunId = [guid]::NewGuid().ToString('D')
$script:StartedUtc = (Get-Date).ToUniversalTime().ToString('o')
$script:LogPaths = @(
    (Join-Path $env:SystemRoot 'Temp\OSDApps-InboxCleanup-Diagnostics.log'),
    (Join-Path $env:ProgramData 'OSDApps\Logs\InboxCleanup.log')
)
$script:ResultPath = Join-Path $env:ProgramData 'OSDApps\Results\InboxCleanup-Result.json'
$script:Outcomes = [System.Collections.Generic.List[object]]::new()
$script:Counts = @{ Removed=0; Absent=0; Skipped=0; Failed=0; WouldRemove=0 }

function Write-InboxLog {
    param([string]$Message, [ValidateSet('INFO','WARN','ERROR')][string]$Level='INFO')
    $line = '{0} [{1}] [RunId={2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Level, $script:RunId, ($Message -replace '[\r\n]+',' | ')
    foreach ($path in $script:LogPaths) {
        try {
            [void][IO.Directory]::CreateDirectory((Split-Path -Path $path -Parent))
            [IO.File]::AppendAllText($path, ($line + [Environment]::NewLine), [Text.Encoding]::UTF8)
        }
        catch { Write-Host ('[LOGGING ERROR] {0}: {1}' -f $path, $_.Exception.Message) }
    }
    Write-Host $line
}
function Write-InboxError {
    param([string]$Operation,[System.Management.Automation.ErrorRecord]$Record)
    Write-InboxLog -Level ERROR -Message ('{0}: {1}; ErrorId={2}; At={3}; Stack={4}' -f $Operation,$Record.Exception.Message,$Record.FullyQualifiedErrorId,$Record.InvocationInfo.PositionMessage,$Record.ScriptStackTrace)
}
function Add-InboxOutcome {
    param([string]$Id,[string]$Status,[int]$ProvisionedBefore=0,[int]$RegisteredBefore=0,[int]$ProvisionedAfter=0,[int]$RegisteredAfter=0,[string[]]$Errors=@())
    [void]$script:Outcomes.Add([pscustomobject]@{
        Id=$Id; Status=$Status; ProvisionedBefore=$ProvisionedBefore; RegisteredBefore=$RegisteredBefore
        ProvisionedAfter=$ProvisionedAfter; RegisteredAfter=$RegisteredAfter; Errors=@($Errors)
    })
}
function Save-InboxResult {
    param([int]$ExitCode,[string]$Fatal)
    $report = [ordered]@{
        SchemaVersion=1; ScriptVersion='BuiltIn-1.0'; RunId=$script:RunId
        StartUtc=$script:StartedUtc; CompletedUtc=(Get-Date).ToUniversalTime().ToString('o')
        Mode=$(if($DiagnoseOnly){'DiagnoseOnly'}else{'Apply'})
        ExitCode=$ExitCode
        Identity=[Security.Principal.WindowsIdentity]::GetCurrent().Name
        Configuration=$ConfigurationPath
        Removed=$script:Counts.Removed; Absent=$script:Counts.Absent
        Skipped=$script:Counts.Skipped; Failed=$script:Counts.Failed
        WouldRemove=$script:Counts.WouldRemove; Fatal=$Fatal
        Items=@($script:Outcomes.ToArray())
    }
    try {
        [void][IO.Directory]::CreateDirectory((Split-Path -Path $script:ResultPath -Parent))
        $temporary = $script:ResultPath + '.' + $script:RunId + '.tmp'
        $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temporary -Encoding UTF8 -ErrorAction Stop
        Move-Item -LiteralPath $temporary -Destination $script:ResultPath -Force -ErrorAction Stop
        Write-InboxLog ('Result saved: {0}' -f $script:ResultPath)
    }
    catch { Write-InboxLog -Level WARN -Message ('Could not save result: {0}' -f $_.Exception.Message) }
}

# This log is written BEFORE reading configuration or enumerating Appx.
Write-InboxLog ('ENTRY BuiltIn-1.0; PID={0}; Mode={1}; Script={2}' -f $PID,$(if($DiagnoseOnly){'DiagnoseOnly'}else{'Apply'}),$PSCommandPath)
$exitCode = 0
$fatal = $null
try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $sid = if ($identity.User) { $identity.User.Value } else { '' }
    Write-InboxLog ('CONTEXT Identity={0}; SID={1}; IsSystem={2}; PSVersion={3}; Is64Bit={4}' -f $identity.Name,$sid,($sid -eq 'S-1-5-18'),$PSVersionTable.PSVersion,[Environment]::Is64BitProcess)
    foreach ($command in @('Get-AppxProvisionedPackage','Remove-AppxProvisionedPackage','Get-AppxPackage','Remove-AppxPackage')) {
        if (-not (Get-Command -Name $command -ErrorAction SilentlyContinue)) {
            throw ('Required Appx command unavailable: {0}' -f $command)
        }
    }
    if (-not (Test-Path -LiteralPath $ConfigurationPath -PathType Leaf)) { throw ('Configuration not found: {0}' -f $ConfigurationPath) }
    $config = Get-Content -LiteralPath $ConfigurationPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ($null -eq $config -or $null -eq $config.PSObject.Properties['Remove'] -or $config.Remove -isnot [array]) {
        throw 'Configuration must contain a Remove array.'
    }
    $names = @($config.Remove | ForEach-Object {
        if ($_ -isnot [string] -or [string]::IsNullOrWhiteSpace($_) -or $_ -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or $_.Contains('..')) {
            throw ('Invalid Windows package name: {0}' -f $_)
        }
        [string]$_
    } | Select-Object -Unique)
    if ($names.Count -eq 0) { throw 'Remove array cannot be empty.' }
    Write-InboxLog ('CONFIG selected={0}; Names={1}' -f $names.Count,($names -join ', '))
    $protectedPackages = @(
        'Microsoft.Windows.ShellExperienceHost','Microsoft.Windows.StartMenuExperienceHost',
        'MicrosoftWindows.Client.CBS','MicrosoftWindows.Client.Core',
        'Microsoft.AAD.BrokerPlugin','Microsoft.AccountsControl',
        'Microsoft.Windows.CloudExperienceHost','Microsoft.Windows.OOBENetworkConnectionFlow',
        'Microsoft.Windows.OOBENetworkCaptivePortal','Microsoft.Windows.SecHealthUI',
        'Microsoft.DesktopAppInstaller','Microsoft.WindowsStore','Microsoft.StorePurchaseApp',
        'Microsoft.VCLibs.140.00','Microsoft.NET.Native.Framework.2.2',
        'Microsoft.NET.Native.Runtime.2.2','Microsoft.UI.Xaml.2.8'
    )
    foreach ($name in $names) {
        Write-InboxLog ('INSPECT {0}' -f $name)
        $operationErrors = @()
        $beforeProvisioned = 0
        $beforeRegistered = 0
        try {
            $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object { $_.DisplayName -eq $name })
            $registered = @(Get-AppxPackage -AllUsers -Name $name -ErrorAction Stop)
            $beforeProvisioned = $provisioned.Count
            $beforeRegistered = $registered.Count
            Write-InboxLog ('FOUND {0}: provisioned={1}; registered={2}' -f $name,$beforeProvisioned,$beforeRegistered)
            if ($name -in $protectedPackages) {
                $script:Counts.Skipped++
                Add-InboxOutcome -Id $name -Status SkippedProtected -ProvisionedBefore $beforeProvisioned -RegisteredBefore $beforeRegistered -ProvisionedAfter $beforeProvisioned -RegisteredAfter $beforeRegistered
                Write-InboxLog -Level WARN -Message ('SKIPPED {0}: protected' -f $name)
                continue
            }
            if (@($registered | Where-Object { $_.NonRemovable -eq $true }).Count -gt 0) {
                $script:Counts.Skipped++
                Add-InboxOutcome -Id $name -Status SkippedNonRemovable -ProvisionedBefore $beforeProvisioned -RegisteredBefore $beforeRegistered -ProvisionedAfter $beforeProvisioned -RegisteredAfter $beforeRegistered
                Write-InboxLog -Level WARN -Message ('SKIPPED {0}: NonRemovable' -f $name)
                continue
            }
            if ($beforeProvisioned -eq 0 -and $beforeRegistered -eq 0) {
                $script:Counts.Absent++
                Add-InboxOutcome -Id $name -Status Absent
                Write-InboxLog ('ABSENT {0}' -f $name)
                continue
            }
            if ($DiagnoseOnly) {
                $script:Counts.WouldRemove++
                Add-InboxOutcome -Id $name -Status WouldRemove -ProvisionedBefore $beforeProvisioned -RegisteredBefore $beforeRegistered -ProvisionedAfter $beforeProvisioned -RegisteredAfter $beforeRegistered
                Write-InboxLog ('WOULD_REMOVE {0}' -f $name)
                continue
            }
            foreach ($package in $provisioned) {
                try {
                    Remove-AppxProvisionedPackage -Online -PackageName $package.PackageName -ErrorAction Stop | Out-Null
                    Write-InboxLog ('DEPROVISIONED {0} ({1})' -f $name,$package.PackageName)
                }
                catch {
                    $operationErrors += ('Provisioning: {0}' -f $_.Exception.Message)
                    Write-InboxError -Operation ('Deprovision {0}' -f $name) -Record $_
                }
            }
            foreach ($package in $registered) {
                try {
                    Remove-AppxPackage -Package $package.PackageFullName -AllUsers -ErrorAction Stop
                    Write-InboxLog ('UNREGISTERED {0} ({1})' -f $name,$package.PackageFullName)
                }
                catch {
                    $operationErrors += ('Registration: {0}' -f $_.Exception.Message)
                    Write-InboxError -Operation ('Unregister {0}' -f $name) -Record $_
                }
            }
            $remainingProvisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object { $_.DisplayName -eq $name })
            $remainingRegistered = @(Get-AppxPackage -AllUsers -Name $name -ErrorAction Stop)
            if ($remainingProvisioned.Count -eq 0 -and $remainingRegistered.Count -eq 0) {
                $script:Counts.Removed++
                Add-InboxOutcome -Id $name -Status Removed -ProvisionedBefore $beforeProvisioned -RegisteredBefore $beforeRegistered -Errors $operationErrors
                Write-InboxLog ('REMOVED {0}' -f $name)
            }
            else {
                $script:Counts.Failed++
                Add-InboxOutcome -Id $name -Status Failed -ProvisionedBefore $beforeProvisioned -RegisteredBefore $beforeRegistered -ProvisionedAfter $remainingProvisioned.Count -RegisteredAfter $remainingRegistered.Count -Errors $operationErrors
                Write-InboxLog -Level ERROR -Message ('FAILED {0}: remaining provisioned={1}, registered={2}; errors={3}' -f $name,$remainingProvisioned.Count,$remainingRegistered.Count,($operationErrors -join ' | '))
            }
        }
        catch {
            $script:Counts.Failed++
            $operationErrors += $_.Exception.Message
            Write-InboxError -Operation ('Inspect/process {0}' -f $name) -Record $_
            Add-InboxOutcome -Id $name -Status Failed -ProvisionedBefore $beforeProvisioned -RegisteredBefore $beforeRegistered -Errors $operationErrors
        }
    }
    Write-InboxLog ('COMPLETE Removed={0}; Absent={1}; Skipped={2}; Failed={3}; WouldRemove={4}; Selected={5}' -f $script:Counts.Removed,$script:Counts.Absent,$script:Counts.Skipped,$script:Counts.Failed,$script:Counts.WouldRemove,$names.Count)
    if ($script:Counts.Failed -gt 0) { $exitCode = 1 }
}
catch {
    $exitCode = 2
    $fatal = $_.Exception.Message
    Write-InboxError -Operation FATAL -Record $_
}
finally {
    Save-InboxResult -ExitCode $exitCode -Fatal $fatal
    Write-InboxLog ('EXIT code={0}' -f $exitCode)
}
exit $exitCode
