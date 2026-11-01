function Get-OSDStageDriverInfFiles {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$PayloadRoot)

    $root=Get-Item -LiteralPath $PayloadRoot -Force -ErrorAction Stop
    if (-not $root.PSIsContainer -or ($root.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Driver payload must be a directory without reparse points.'
    }
    $pending=[Collections.Generic.Stack[string]]::new()
    $pending.Push($root.FullName)
    $infs=[Collections.Generic.List[IO.FileInfo]]::new()
    while ($pending.Count -gt 0) {
        foreach ($entry in @(Get-ChildItem -LiteralPath $pending.Pop() -Force -ErrorAction Stop)) {
            if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Driver payloads cannot contain reparse points.' }
            if ($entry.PSIsContainer) { $pending.Push($entry.FullName) }
            elseif ($entry.Extension -ieq '.inf') { $infs.Add($entry) }
        }
    }
    if ($infs.Count -eq 0) { throw 'Driver packages require at least one .inf file under Package/.' }
    $infs | Sort-Object FullName
}

function Invoke-OSDStagePnPUtil {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$InfPath,
        [switch]$Install
    )
    if ($InfPath.Contains('"')) { throw 'Invalid quote in INF path.' }
    $systemDirectory=if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { 'Sysnative' } else { 'System32' }
    $executable=Join-Path $env:SystemRoot ($systemDirectory+'\pnputil.exe')
    if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) { throw 'Windows PnPUtil was not found.' }
    $arguments='/add-driver "'+$InfPath+'"'
    if ($Install) { $arguments+=' /install' }

    $start=[Diagnostics.ProcessStartInfo]::new()
    $start.FileName=$executable
    $start.Arguments=$arguments
    $start.WorkingDirectory=Split-Path $InfPath -Parent
    $start.UseShellExecute=$false
    $start.CreateNoWindow=$true
    $start.RedirectStandardOutput=$true
    $start.RedirectStandardError=$true
    $encoding=[Text.Encoding]::GetEncoding([Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)
    $start.StandardOutputEncoding=$encoding
    $start.StandardErrorEncoding=$encoding
    $process=[Diagnostics.Process]::new()
    $process.StartInfo=$start
    try {
        if (-not $process.Start()) { throw 'PnPUtil did not start.' }
        # Drain both streams concurrently so verbose vendor output cannot block
        # the child process. Do not interpret localized output as machine state.
        $stdout=$process.StandardOutput.ReadToEndAsync()
        $stderr=$process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        [pscustomobject]@{
            Command=('pnputil.exe '+$arguments)
            ExitCode=$process.ExitCode
            StandardOutput=$stdout.GetAwaiter().GetResult()
            StandardError=$stderr.GetAwaiter().GetResult()
        }
    }
    finally { $process.Dispose() }
}

function Invoke-OSDStageDriverPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PayloadRoot,
        [Parameter(Mandatory)][string]$PackageId,
        [Parameter(Mandatory)][string]$DeploymentId,
        [Parameter(Mandatory)][string]$ResultPath
    )
    $items=[Collections.Generic.List[object]]::new()
    $failure=$null
    try {
        # This helper is only used by the full-Windows SetupComplete runner.
        if (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT') { throw 'Driver import must run in full Windows during SetupComplete, not in WinPE.' }
        $infs=@(Get-OSDStageDriverInfFiles -PayloadRoot $PayloadRoot)
        $resolvedRoot=(Get-Item -LiteralPath $PayloadRoot).FullName.TrimEnd('\','/')
        foreach ($inf in $infs) {
            $item=[ordered]@{
                Inf=$inf.FullName.Substring($resolvedRoot.Length+1)
                Status='Failed'
                DriverStoreStatus='NotAttempted'
                DeviceInstallStatus='NotAttempted'
                DeviceBindingConfirmed=$null
                RestartNeeded=$false
                StoreCommand=$null
                InstallCommand=$null
                Error=$null
            }
            try {
                # Separate store and device operations: exit 259 from /install
                # says no device was updated, not whether store import succeeded.
                $item.DriverStoreStatus='Attempting'
                $stage=Invoke-OSDStagePnPUtil -InfPath $inf.FullName
                $item.StoreCommand=$stage
                $item.RestartNeeded=($stage.ExitCode -eq 3010)
                if ($stage.ExitCode -notin @(0,3010)) {
                    $item.DriverStoreStatus='Failed'
                    throw "Driver Store import failed with exit code $($stage.ExitCode)."
                }
                $item.DriverStoreStatus='AddedOrAlreadyPresent'
                $item.DeviceInstallStatus='Attempting'
                $install=Invoke-OSDStagePnPUtil -InfPath $inf.FullName -Install
                $item.InstallCommand=$install
                $item.RestartNeeded=($item.RestartNeeded -or $install.ExitCode -eq 3010)
                switch ([int]$install.ExitCode) {
                    0 {
                        # Success alone does not prove a new binding to a device.
                        $item.DeviceInstallStatus='SucceededBindingNotReported'
                    }
                    259 {
                        $item.DeviceInstallStatus='NoMatchingDeviceOrBetterDriver'
                        $item.DeviceBindingConfirmed=$false
                    }
                    3010 {
                        $item.DeviceInstallStatus='InstalledRebootRequired'
                        $item.DeviceBindingConfirmed=$true
                    }
                    default {
                        $item.DeviceInstallStatus='Failed'
                        throw "Device driver installation failed with exit code $($install.ExitCode)."
                    }
                }
                $item.Status='Succeeded'
            }
            catch {
                if ($item.DriverStoreStatus -eq 'Attempting') { $item.DriverStoreStatus='Failed' }
                if ($item.DeviceInstallStatus -eq 'Attempting') { $item.DeviceInstallStatus='Failed' }
                $item.Error=$_.Exception.Message
            }
            $items.Add([pscustomobject]$item)
        }
    }
    catch { $failure=$_.Exception.Message }

    $failed=@($items | Where-Object Status -eq Failed).Count
    $restartNeeded=@($items | Where-Object RestartNeeded).Count -gt 0
    $exitCode=if ($failure -or $failed) { 1 } elseif ($restartNeeded) { 3010 } else { 0 }
    $record=[ordered]@{
        SchemaVersion=2;DeploymentId=$DeploymentId;PackageId=$PackageId
        Status=if ($failure -or $failed) { 'Failed' } else { 'Succeeded' }
        InfCount=$items.Count
        SuccessfulInfCount=($items.Count-$failed)
        FailedInfCount=$failed
        DriverStoreReadyCount=@($items | Where-Object DriverStoreStatus -eq AddedOrAlreadyPresent).Count
        NoDeviceChangeCount=@($items | Where-Object DeviceInstallStatus -eq NoMatchingDeviceOrBetterDriver).Count
        RestartNeeded=$restartNeeded
        RebootRequested=$false
        Items=@($items.ToArray())
        Error=if ($failure) { $failure } elseif ($failed) { "$failed driver INF operation(s) failed." } else { $null }
    }
    New-Item -ItemType Directory -Path (Split-Path $ResultPath -Parent) -Force -ErrorAction Stop | Out-Null
    $record | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $ResultPath -Encoding UTF8 -ErrorAction Stop
    [pscustomobject]@{
        ExitCode=$exitCode;Integrity='Sha256Validated';RestartNeeded=$restartNeeded;ResultPath=$ResultPath
    }
}
