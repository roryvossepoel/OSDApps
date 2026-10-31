[CmdletBinding()]
param([string]$ConfigPath)
$ErrorActionPreference='Stop'
if([string]::IsNullOrWhiteSpace($ConfigPath)){$ConfigPath=Join-Path $PSScriptRoot 'config.json'}

function Initialize-OSDStageWiFiNative {
    if('OSDStage.WiFiNative' -as [type]){return}
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
namespace OSDStage {
    public sealed class WiFiImportResult {
        public string InterfaceId;
        public uint ErrorCode;
        public uint ReasonCode;
    }
    public static class WiFiNative {
        [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
        private struct InterfaceInfo {
            public Guid Id;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst=256)] public string Description;
            public int State;
        }
        [DllImport("wlanapi.dll")] private static extern uint WlanOpenHandle(uint version, IntPtr reserved, out uint negotiated, out IntPtr handle);
        [DllImport("wlanapi.dll")] private static extern uint WlanCloseHandle(IntPtr handle, IntPtr reserved);
        [DllImport("wlanapi.dll")] private static extern uint WlanEnumInterfaces(IntPtr handle, IntPtr reserved, out IntPtr list);
        [DllImport("wlanapi.dll")] private static extern void WlanFreeMemory(IntPtr memory);
        [DllImport("wlanapi.dll", CharSet=CharSet.Unicode)]
        private static extern uint WlanSetProfile(IntPtr handle, ref Guid id, uint flags, string xml, string security,
            [MarshalAs(UnmanagedType.Bool)] bool overwrite, IntPtr reserved, out uint reason);
        public static WiFiImportResult[] Import(string xml) {
            IntPtr handle=IntPtr.Zero, list=IntPtr.Zero;
            try {
                uint negotiated;
                uint code=WlanOpenHandle(2,IntPtr.Zero,out negotiated,out handle);
                if(code!=0) throw new InvalidOperationException("WlanOpenHandle error " + code);
                code=WlanEnumInterfaces(handle,IntPtr.Zero,out list);
                if(code!=0) throw new InvalidOperationException("WlanEnumInterfaces error " + code);
                int count=Marshal.ReadInt32(list);
                if(count==0) throw new InvalidOperationException("No enabled Wi-Fi interface is available.");
                int size=Marshal.SizeOf(typeof(InterfaceInfo));
                var results=new List<WiFiImportResult>();
                for(int i=0;i<count;i++) {
                    var info=(InterfaceInfo)Marshal.PtrToStructure(IntPtr.Add(list,8+i*size),typeof(InterfaceInfo));
                    uint reason;
                    // flags=0 creates an all-user profile. A same-name profile is updated.
                    code=WlanSetProfile(handle,ref info.Id,0,xml,null,true,IntPtr.Zero,out reason);
                    results.Add(new WiFiImportResult {InterfaceId=info.Id.ToString(),ErrorCode=code,ReasonCode=reason});
                }
                return results.ToArray();
            }
            finally {
                if(list!=IntPtr.Zero)WlanFreeMemory(list);
                if(handle!=IntPtr.Zero)WlanCloseHandle(handle,IntPtr.Zero);
            }
        }
    }
}
'@ -ErrorAction Stop
}

function Import-OSDStageWiFiNativeProfile {
    param([Parameter(Mandatory)][string]$Xml)
    [OSDStage.WiFiNative]::Import($Xml)
}

function Invoke-OSDStageWiFiProfileOperation {
    param([Parameter(Mandatory)]$Operation)
    # Never include XML or native exception messages in reports: they may contain credentials.
    try {
        $interfaces=@(Import-OSDStageWiFiNativeProfile -Xml ([string]$Operation.Xml))
        $failed=@($interfaces | Where-Object ErrorCode -ne 0).Count
        if($interfaces.Count -eq 0){throw 'No interfaces.'}
        [pscustomobject]@{
            Name=[string]$Operation.Name
            Status=if($failed){'Failed'}else{'Succeeded'}
            Outcome=if($failed){'ImportFailed'}else{'Imported'}
            Interfaces=$interfaces
            Error=if($failed){'Wi-Fi profile import failed; see numeric interface error and reason codes.'}else{$null}
        }
    }
    catch {
        [pscustomobject]@{Name=[string]$Operation.Name;Status='Failed';Outcome='ImportFailed';Interfaces=@();Error='Wi-Fi import could not run. Check WLAN service, driver and adapter availability.'}
    }
}

$configuration=$null
$exitCode=1
$items=@()
$errorMessage=$null
try {
    $configuration=Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    $id=[guid]::Empty
    if([int]$configuration.SchemaVersion -ne 2 -or -not [guid]::TryParse([string]$configuration.DeploymentId,[ref]$id) -or
        [string]::IsNullOrWhiteSpace([string]$configuration.ResultPath) -or @($configuration.Operations).Count -eq 0) {throw 'Invalid configuration.'}
    foreach($operation in @($configuration.Operations)) {
        if([string]::IsNullOrWhiteSpace([string]$operation.Name) -or [string]::IsNullOrWhiteSpace([string]$operation.Xml)){throw 'Invalid operation.'}
    }
    $service=Get-Service -Name WlanSvc -ErrorAction Stop
    if($service.Status -ne 'Running'){Start-Service -Name WlanSvc -ErrorAction Stop}
    Initialize-OSDStageWiFiNative
    $items=@(foreach($operation in @($configuration.Operations)){Invoke-OSDStageWiFiProfileOperation -Operation $operation})
    if(@($items | Where-Object Status -ne 'Succeeded').Count -eq 0){$exitCode=0}
    else{$errorMessage='One or more Wi-Fi profile imports failed.'}
}
catch {$errorMessage='Wi-Fi staging could not be processed. Check configuration, WLAN service and driver availability.'}
finally {
    # Credential-bearing staging is consumed once, including on failure and CleanupMode Never.
    try {Remove-Item -LiteralPath $ConfigPath -Force -ErrorAction Stop}
    catch {$exitCode=1;$errorMessage='Wi-Fi configuration cleanup failed; the restricted staging file may still contain a shared key.'}
}
try {
    if($configuration -and $configuration.ResultPath) {
        $resultPath=[Environment]::ExpandEnvironmentVariables([string]$configuration.ResultPath)
        New-Item -ItemType Directory -Path (Split-Path $resultPath -Parent) -Force | Out-Null
        [ordered]@{
            SchemaVersion=2;DeploymentId=[string]$configuration.DeploymentId
            Status=if($exitCode -eq 0){'Succeeded'}else{'Failed'}
            OperationCount=@($configuration.Operations).Count
            SuccessfulOperationCount=@($items | Where-Object Status -eq 'Succeeded').Count
            FailedOperationCount=if($items.Count){@($items | Where-Object Status -ne 'Succeeded').Count}else{@($configuration.Operations).Count}
            RestartNeeded=$false;Items=@($items);Error=$errorMessage
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resultPath -Encoding UTF8 -ErrorAction Stop
    }
}
catch {$exitCode=1}
if($exitCode -ne 0){Write-Output 'Wi-Fi profile staging failed. See WiFiProfiles-Result.json when available.'}
exit $exitCode
