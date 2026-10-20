Describe 'Runtime sleep prevention helper' {
    BeforeAll {
        $script:root = Split-Path $PSScriptRoot -Parent
        . (Join-Path $script:root 'Runtime/OSDAppSleepPrevention.ps1')
    }

    BeforeEach {
        $script:events = [System.Collections.Generic.List[object]]::new()
        $script:log = { param($Event, $Level, $Message) $script:events.Add(@{ Event=$Event; Level=$Level; Message=$Message }) }
        $script:request = [pscustomobject]@{ Released = $false }
        $script:request | Add-Member ScriptMethod Release { $this.Released = $true }
        Mock New-OSDAppPowerRequest { $script:request }
    }

    It 'defaults a legacy manifest to enabled under StrictMode' {
        Set-StrictMode -Version Latest
        Get-OSDAppPreventSleep -Runtime ([pscustomobject]@{}) | Should -BeTrue
    }

    It 'preserves an explicit false and rejects a string false' {
        Get-OSDAppPreventSleep -Runtime ([pscustomobject]@{ PreventSleep=$false }) | Should -BeFalse
        { Get-OSDAppPreventSleep -Runtime ([pscustomobject]@{ PreventSleep='false' }) } | Should -Throw '*JSON boolean*'
        { Get-OSDAppPreventSleep -Runtime ([pscustomobject]@{ PreventSleep=$null }) } | Should -Throw '*JSON boolean*'
    }

    It 'does not create a native request when disabled' {
        Start-OSDAppSleepPrevention -Enabled $false -Reason 'Disabled test' -Log $script:log | Should -BeNullOrEmpty
        Should -Invoke New-OSDAppPowerRequest -Times 0 -Exactly
        $script:events[0].Event | Should -Be 'SleepPreventionDisabled'
    }

    It 'releases the same request on normal completion or a controlled exception' -TestCases @(
        @{ Fail=$false }, @{ Fail=$true }
    ) {
        param($Fail)
        $request = Start-OSDAppSleepPrevention -Reason 'Test' -Log $script:log
        try { if ($Fail) { throw 'Controlled failure' } }
        catch { $_.Exception.Message | Should -Be 'Controlled failure' }
        finally { Stop-OSDAppSleepPrevention -Request $request -Log $script:log }
        $request.Released | Should -BeTrue
        @($script:events.Event) | Should -Be @('SleepPreventionStarted','SleepPreventionStopped')
    }

    It 'warns and continues if native acquisition fails' {
        Mock New-OSDAppPowerRequest { throw 'Native request denied' }
        Start-OSDAppSleepPrevention -Reason 'Test' -Log $script:log | Should -BeNullOrEmpty
        $script:events[0].Event | Should -Be 'SleepPreventionFailed'
        $script:events[0].Level | Should -Be 'Warning'
    }

    It 'returns the owned request even if logging fails, so finally can release it' {
        $request = Start-OSDAppSleepPrevention -Reason 'Test' -Log { throw 'Log unavailable' } -WarningAction SilentlyContinue
        $request | Should -Not -BeNullOrEmpty
        Stop-OSDAppSleepPrevention -Request $request -Log { throw 'Log unavailable' } -WarningAction SilentlyContinue
        $request.Released | Should -BeTrue
    }

    It 'does not mask a deployment error when release fails' {
        $script:request | Add-Member ScriptMethod Release { throw 'Native clear failed' } -Force
        { Stop-OSDAppSleepPrevention -Request $script:request -Log $script:log } | Should -Not -Throw
        $script:events[0].Event | Should -Be 'SleepPreventionReleaseFailed'
    }

    It 'treats a null request as a no-op' {
        { Stop-OSDAppSleepPrevention -Request $null -Log $script:log } | Should -Not -Throw
        $script:events.Count | Should -Be 0
    }
}

Describe 'Sleep prevention configuration and staging' {
    BeforeEach {
        $script:root = Split-Path $PSScriptRoot -Parent
        Import-Module (Join-Path $script:root 'OSDApps.psd1') -Force
    }

    It 'defaults to true and preserves explicit false across unrelated configuration changes' {
        (Get-OSDAppConfiguration).PreventSleep | Should -BeTrue
        Set-OSDAppConfiguration -PreventSleep $false
        Set-OSDAppConfiguration -CleanupMode Never
        (Get-OSDAppConfiguration).PreventSleep | Should -BeFalse
        InModuleScope OSDApps {
            $manifest = Set-OSDAppManifestRuntimeConfiguration -Manifest ([pscustomobject]@{})
            $manifest.Runtime.PreventSleep | Should -BeFalse
            $json = $manifest | ConvertTo-Json -Depth 10 | ConvertFrom-Json
            $json.Runtime.PreventSleep | Should -BeOfType ([bool])
        }
        (Set-OSDAppConfiguration -PreventSleep $true -PassThru).PreventSleep | Should -BeTrue
    }

    It 'stages the exact shared helper with both standalone phases' {
        InModuleScope OSDApps -Parameters @{ Target=$TestDrive } {
            param($Target)
            Add-OSDAppSetupComplete -WindowsPath $Target | Out-Null
            $source = Join-Path (Split-Path (Get-Module OSDApps).Path -Parent) 'Runtime/OSDAppSleepPrevention.ps1'
            $staged = Join-Path $Target 'Windows/Temp/OSDApps/OSDAppSleepPrevention.ps1'
            (Get-FileHash $staged).Hash | Should -Be (Get-FileHash $source).Hash
        }
    }
}

Describe 'Standalone phase power request lifetime' {
    BeforeAll {
        $script:root = Split-Path $PSScriptRoot -Parent
        $script:engine = (Get-Process -Id $PID).Path
    }

    It 'releases on <Phase> <Scenario> without changing its exit code' -TestCases @(
        @{ Phase='PreInstall'; Scenario='Success'; Enabled=$true; Fails=$false; NativeFails=$false; ExitCode=0 }
        @{ Phase='PreInstall'; Scenario='Failure'; Enabled=$true; Fails=$true; NativeFails=$false; ExitCode=1 }
        @{ Phase='Runner'; Scenario='Success'; Enabled=$true; Fails=$false; NativeFails=$false; ExitCode=0 }
        @{ Phase='Runner'; Scenario='Failure'; Enabled=$true; Fails=$true; NativeFails=$false; ExitCode=1 }
        @{ Phase='PreInstall'; Scenario='Disabled'; Enabled=$false; Fails=$false; NativeFails=$false; ExitCode=0 }
        @{ Phase='Runner'; Scenario='Disabled'; Enabled=$false; Fails=$false; NativeFails=$false; ExitCode=0 }
        @{ Phase='PreInstall'; Scenario='NativeUnavailable'; Enabled=$true; Fails=$false; NativeFails=$true; ExitCode=0 }
        @{ Phase='Runner'; Scenario='NativeUnavailable'; Enabled=$true; Fails=$false; NativeFails=$true; ExitCode=0 }
    ) {
        param($Phase, $Scenario, $Enabled, $Fails, $NativeFails, $ExitCode)
        $folder = Join-Path $TestDrive "$Phase-$Scenario"
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        Copy-Item (Join-Path $script:root 'Runtime/*') -Destination $folder
        # Replace only the native boundary. Execute the real shared helper,
        # runtime control flow, exit statements, finally blocks and log writers.
        $helper = (Join-Path $script:root 'Runtime/OSDAppSleepPrevention.ps1').Replace("'", "''")
        $fake = @'
. '__HELPER__'
function New-OSDAppPowerRequest {
    param([string]$Reason)
    if (__FAIL__) { throw 'Native request unavailable' }
    $request = [pscustomobject]@{ Marker=(Join-Path $PSScriptRoot 'released.txt') }
    $request | Add-Member ScriptMethod Release { Set-Content -LiteralPath $this.Marker -Value 'released' }
    return $request
}
function Get-Volume { throw 'Controlled acquisition failure' }
'@
        $fake = $fake.Replace('__HELPER__', $helper).Replace('__FAIL__', ('$' + $NativeFails.ToString().ToLowerInvariant()))
        Set-Content (Join-Path $folder 'OSDAppSleepPrevention.ps1') $fake -Encoding UTF8
        $apps = @()
        if ($Fails) { $apps = @(@{ Id='..invalid'; Source='BuiltIn'; Type='VendorMsi' }) }
        @{
            DeploymentId=[guid]::NewGuid().Guid
            Runtime=@{ PreventSleep=$Enabled; CleanupMode='Never'; CacheVolumeLabel='OSDAppsTest'; LogPath=(Join-Path $folder 'Runtime.log'); ResultPath=(Join-Path $folder 'Results/Latest.json') }
            Apps=$apps
        } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $folder 'DeviceManifest.json') -Encoding UTF8
        & $script:engine -NoProfile -File (Join-Path $folder "Invoke-OSDApp$Phase.ps1") -StagedPath $folder
        $LASTEXITCODE | Should -Be $ExitCode
        (Test-Path (Join-Path $folder 'released.txt')) | Should -Be ($Enabled -and -not $NativeFails)
        $log = Get-Content (Join-Path $folder 'Runtime.log') -Raw
        if (-not $Enabled) { $log | Should -Match 'SleepPreventionDisabled' }
        elseif ($NativeFails) { $log | Should -Match 'SleepPreventionFailed' }
        else {
            $log | Should -Match 'SleepPreventionStarted'
            $log | Should -Match 'SleepPreventionStopped'
        }
    }
}
