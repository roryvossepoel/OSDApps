# Shared by the standalone runtimes and the isolated development-PC test.
# Loading this file does not compile native code or create a power request.
function Get-OSDAppPreventSleep {
    param([Parameter(Mandatory)]$Runtime)

    $property = $Runtime.PSObject.Properties['PreventSleep']
    if ($null -eq $property) { return $true }
    if ($property.Value -isnot [bool]) {
        throw 'Device manifest Runtime.PreventSleep must be a JSON boolean.'
    }
    return $property.Value
}

function New-OSDAppPowerRequest {
    param([Parameter(Mandatory)][string]$Reason)

    if (-not ('OSDApps.Runtime.SystemPowerRequest' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace OSDApps.Runtime
{
    public sealed class SystemPowerRequest : SafeHandleZeroOrMinusOneIsInvalid
    {
        [StructLayout(LayoutKind.Sequential)]
        private struct DetailedReason
        {
            public IntPtr Module;
            public uint ReasonId;
            public uint StringCount;
            public IntPtr Strings;
        }

        [StructLayout(LayoutKind.Explicit)]
        private struct ReasonUnion
        {
            [FieldOffset(0)] public IntPtr Simple;
            [FieldOffset(0)] public DetailedReason Detailed;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct ReasonContext
        {
            public uint Version;
            public uint Flags;
            public ReasonUnion Reason;
        }

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr PowerCreateRequest(ref ReasonContext context);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool PowerSetRequest(SystemPowerRequest request, int type);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool PowerClearRequest(SystemPowerRequest request, int type);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CloseHandle(IntPtr handle);

        private SystemPowerRequest() : base(true) { }

        public static SystemPowerRequest Create(string reason)
        {
            var request = new SystemPowerRequest();
            IntPtr text = Marshal.StringToHGlobalUni(reason);
            try
            {
                var context = new ReasonContext();
                context.Flags = 1; // POWER_REQUEST_CONTEXT_SIMPLE_STRING
                context.Reason.Simple = text;
                request.SetHandle(PowerCreateRequest(ref context));
                if (request.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error());
                // SystemRequired only: allow the display to turn off normally.
                if (!PowerSetRequest(request, 1)) throw new Win32Exception(Marshal.GetLastWin32Error());
                return request;
            }
            catch
            {
                request.Dispose();
                throw;
            }
            finally { Marshal.FreeHGlobal(text); }
        }

        public void Release()
        {
            if (IsClosed || IsInvalid) return;
            try
            {
                if (!PowerClearRequest(this, 1)) throw new Win32Exception(Marshal.GetLastWin32Error());
            }
            finally { Dispose(); }
        }

        // Also closes the handle if the caller fails to dispose this object.
        // On forced process termination Windows closes its owned handles.
        protected override bool ReleaseHandle() { return CloseHandle(handle); }
    }
}
'@ -ErrorAction Stop
    }
    [OSDApps.Runtime.SystemPowerRequest]::Create($Reason)
}

function Write-OSDAppSleepPreventionLog {
    param([scriptblock]$Log, [string]$EventName, [string]$Level = 'Info', [string]$Message)

    # Logging must never leak an acquired request or change a deployment exit code.
    try {
        if ($Log) { $null = & $Log $EventName $Level $Message }
        elseif ($Level -eq 'Warning') { Write-Warning "$EventName`: $Message" -WarningAction Continue }
    }
    catch { Write-Warning "$EventName`: $Message (Logging failed: $($_.Exception.Message))" -WarningAction Continue }
}

function Start-OSDAppSleepPrevention {
    [CmdletBinding()]
    param(
        [bool]$Enabled = $true,
        [Parameter(Mandatory)][string]$Reason,
        [scriptblock]$Log
    )

    if (-not $Enabled) {
        Write-OSDAppSleepPreventionLog -Log $Log -EventName 'SleepPreventionDisabled' -Message 'Automatic sleep prevention is disabled for this deployment.'
        return $null
    }
    try { $request = New-OSDAppPowerRequest -Reason $Reason }
    catch {
        Write-OSDAppSleepPreventionLog -Log $Log -EventName 'SleepPreventionFailed' -Level Warning -Message "Could not request automatic sleep prevention; continuing deployment. $($_.Exception.Message)"
        return $null
    }
    Write-OSDAppSleepPreventionLog -Log $Log -EventName 'SleepPreventionStarted' -Message $Reason
    return $request
}

function Stop-OSDAppSleepPrevention {
    [CmdletBinding()]
    param([AllowNull()]$Request, [scriptblock]$Log)

    if ($null -eq $Request) { return }
    try {
        $Request.Release()
        Write-OSDAppSleepPreventionLog -Log $Log -EventName 'SleepPreventionStopped' -Message 'The temporary power request was released.'
    }
    catch {
        Write-OSDAppSleepPreventionLog -Log $Log -EventName 'SleepPreventionReleaseFailed' -Level Warning -Message "Could not cleanly release the temporary power request. $($_.Exception.Message)"
    }
}
