Describe 'Conservative Windows Update selection and execution' {
    BeforeAll {
        $script:root=Split-Path $PSScriptRoot -Parent
        Import-Module (Join-Path $script:root 'OSDStage.psd1') -Force
        . (Join-Path $script:root 'Runtime/Invoke-OSDStageWindowsUpdate.ps1')
        function New-TestUpdate {
            param([string]$Title='Beveiligingsupdate',[string]$Category='0fa1201d-4330-4fa8-8ae9-b877473b6441',[int]$Type=1)
            $u=[pscustomobject]@{
                Title=$Title;Type=$Type;Identity=[pscustomobject]@{UpdateID=[guid]::NewGuid().Guid;RevisionNumber=1}
                Categories=@([pscustomobject]@{Type='UpdateClassification';CategoryID=$Category;Name='Localized classification'})
                IsInstalled=$false;IsHidden=$false;BrowseOnly=$false;AutoSelectOnWebSites=$true
                InstallationBehavior=[pscustomobject]@{CanRequestUserInput=$false;RebootBehavior=2}
                BundledUpdates=@();EulaAccepted=$false;IsDownloaded=$true;DriverClass='Net';DriverHardwareID='PCI\VEN_1234'
            }
            $u | Add-Member ScriptMethod AcceptEula { $this.EulaAccepted=$true }
            $u
        }
        function New-TestWuaResult {
            param([int]$Code=2,[bool]$Reboot=$false)
            $r=[pscustomobject]@{ResultCode=$Code;HResult=0;RebootRequired=$Reboot}
            $r | Add-Member ScriptMethod GetUpdateResult { param($index) [pscustomobject]@{ResultCode=$this.ResultCode;HResult=$this.HResult;RebootRequired=$this.RebootRequired} }
            $r
        }
    }
    BeforeEach {
        $script:config=[pscustomobject]@{SchemaVersion=2;DeploymentId=[guid]::NewGuid().Guid;ResultPath=(Join-Path $TestDrive 'Results/WindowsUpdate-Result.json');IncludeDrivers=$false;ScanOnly=$false;TimeoutMinutes=5}
        $script:update=New-TestUpdate
        $script:updates=@($script:update)
        $script:searchCode=2;$script:timedOut=$false;$script:downloadCode=2;$script:installCode=2;$script:reboot=$false;$script:systemReboot=$false
        $script:installOrder=[Collections.Generic.List[string]]::new()
        $script:installer=[pscustomobject]@{IsBusy=$false;RebootRequiredBeforeInstallation=$false;ForceQuiet=$false;AllowSourcePrompts=$true;Updates=$null}
        $script:downloader=[pscustomobject]@{Updates=$null}
        $script:session=[pscustomobject]@{ClientApplicationID=''}
        $script:session | Add-Member ScriptMethod CreateUpdateSearcher { [pscustomobject]@{ServerSelection=0} }
        $script:session | Add-Member ScriptMethod CreateUpdateInstaller { $script:installer }
        $script:session | Add-Member ScriptMethod CreateUpdateDownloader { $script:downloader }
        Mock Assert-OSDStageWindowsUpdateContext {}
        Mock Get-OSDStageWindowsUpdateRelease { [pscustomobject]@{DisplayVersion='25H2';Build='26200';Revision=100;InstallationType='Client'} }
        Mock Write-OSDStageWindowsUpdateMessage {}
        Mock New-OSDStageWindowsUpdateComObject {
            if ($ProgId -eq 'Microsoft.Update.Session') { return $script:session }
            if ($ProgId -eq 'Microsoft.Update.SystemInfo') { return [pscustomobject]@{RebootRequired=$script:systemReboot} }
            if ($ProgId -eq 'Microsoft.Update.UpdateColl') { return ,([Collections.ArrayList]::new()) }
            throw 'Unexpected COM object'
        }
        Mock Invoke-OSDStageWindowsUpdateAsync {
            $result=switch ($Phase) {
                Search { [pscustomobject]@{ResultCode=$script:searchCode;Updates=$script:updates} }
                Download { New-TestWuaResult -Code $script:downloadCode }
                Install {
                    $script:installOrder.Add([string]$Agent.Updates[0].Title)
                    New-TestWuaResult -Code $script:installCode -Reboot $script:reboot
                }
            }
            [pscustomobject]@{Result=$result;TimedOut=$script:timedOut;DurationSeconds=1}
        }
    }
    It 'permits security, critical and definition classifications independently of display language' {
        foreach ($category in @('0fa1201d-4330-4fa8-8ae9-b877473b6441','e6cf1350-c01b-414d-a61f-263d14d133b4','e0789628-ce08-4437-be74-2495b842f43b')) {
            (Get-OSDStageWindowsUpdateSelection (New-TestUpdate -Title ([string][char]0x66f4 + [char]0x65b0) -Category $category)).Selected | Should -BeTrue
        }
    }
    It 'allows cumulative updates that always require a later restart' {
        $script:update.InstallationBehavior.RebootBehavior=1
        (Get-OSDStageWindowsUpdateSelection $script:update).Selected | Should -BeTrue
    }
    It 'rejects feature upgrades, enablement classifications, unknown and conflicting classifications' {
        foreach ($category in @('3689bdc8-b205-4af4-8d4a-a63924c5e9d5','28bc880e-0592-4cbf-8f95-c79b17911d5f','b54e7d24-7add-428f-8b75-90a396fa584f','cd5ffd1e-e932-4e3a-bf74-18bf0b1bbd83','unknown')) {
            (Get-OSDStageWindowsUpdateSelection (New-TestUpdate -Title 'KB1234567' -Category $category)).Selected | Should -BeFalse
        }
        $script:update.Categories+=@([pscustomobject]@{Type='UpdateClassification';CategoryID='3689bdc8-b205-4af4-8d4a-a63924c5e9d5'})
        (Get-OSDStageWindowsUpdateSelection $script:update).Selected | Should -BeFalse
    }
    It 'fails closed on optional, preview, interactive or missing metadata' {
        foreach ($change in @(
            @{BrowseOnly=$true},@{AutoSelectOnWebSites=$false},@{Title='Cumulative Update Preview'},
            @{Title=('Update aper'+[char]0x00e7+'u')},
            @{Title='Enablement package'},@{Categories=@()},@{BundledUpdates=$null},
            @{InstallationBehavior=[pscustomobject]@{CanRequestUserInput=$true;RebootBehavior=2}},
            @{InstallationBehavior=[pscustomobject]@{CanRequestUserInput=$false;RebootBehavior=99}}
        )) {
            $u=New-TestUpdate
            foreach ($key in $change.Keys) { $u.$key=$change[$key] }
            (Get-OSDStageWindowsUpdateSelection $u).Selected | Should -BeFalse
        }
        $u=New-TestUpdate;$u.PSObject.Properties.Remove('BrowseOnly')
        (Get-OSDStageWindowsUpdateSelection $u).Selected | Should -BeFalse
    }
    It 'inspects every bundled update and rejects unknown child metadata' {
        $script:update.BundledUpdates=@((New-TestUpdate))
        (Get-OSDStageWindowsUpdateSelection $script:update).Selected | Should -BeTrue
        $script:update.BundledUpdates[0].Categories=@()
        (Get-OSDStageWindowsUpdateSelection $script:update).Reason | Should -BeLike 'BundleRejected*'
        $script:update.BundledUpdates=@((New-TestUpdate -Category '3689bdc8-b205-4af4-8d4a-a63924c5e9d5'))
        (Get-OSDStageWindowsUpdateSelection $script:update).Selected | Should -BeFalse
    }
    It 'requires driver opt-in and rejects firmware, extension and unknown hardware' {
        $u=New-TestUpdate -Type 2 -Category 'ebfc1fc5-71a4-4f7b-9aca-3b9a503104a0'
        (Get-OSDStageWindowsUpdateSelection $u).Reason | Should -Be DriversDisabled
        (Get-OSDStageWindowsUpdateSelection $u $true).Selected | Should -BeTrue
        foreach ($class in @('Firmware','System','Extension','SoftwareComponent','Unknown')) {
            $u.DriverClass=$class
            (Get-OSDStageWindowsUpdateSelection $u $true).Selected | Should -BeFalse
        }
        $u.DriverClass='Net';$u.DriverHardwareID='UEFI\RES_1234'
        (Get-OSDStageWindowsUpdateSelection $u $true).Selected | Should -BeFalse
    }
    It 'scan-only records decisions without accepting EULAs or installing' {
        $script:config.ScanOnly=$true
        $r=Invoke-OSDStageWindowsUpdateConfiguration $script:config
        $r.Outcome | Should -Be ScanOnly
        $r.Items[0].Selected | Should -BeTrue
        $script:update.EulaAccepted | Should -BeFalse
        Should -Invoke Invoke-OSDStageWindowsUpdateAsync -Times 1 -Exactly
    }
    It 'handles an empty scan without invoking download or install' {
        $script:updates=@()
        $r=Invoke-OSDStageWindowsUpdateConfiguration $script:config
        $r.Outcome | Should -Be NoEligibleUpdates
        $r.RebootRequested | Should -BeFalse
        Should -Invoke Invoke-OSDStageWindowsUpdateAsync -Times 1 -Exactly
    }
    It 'does not download after failed, partial or timed-out searches' {
        foreach ($code in @(3,4,5)) {
            $script:searchCode=$code
            (Invoke-OSDStageWindowsUpdateConfiguration $script:config).Status | Should -Be Failed
        }
        $script:searchCode=2;$script:timedOut=$true
        (Invoke-OSDStageWindowsUpdateConfiguration $script:config).TimedOut | Should -BeTrue
        Should -Invoke Invoke-OSDStageWindowsUpdateAsync -Times 0 -ParameterFilter {$Phase -ne 'Search'}
    }
    It 'defers updates when WUA requires a reboot before installation' {
        $script:installer.RebootRequiredBeforeInstallation=$true
        $r=Invoke-OSDStageWindowsUpdateConfiguration $script:config
        $r.Status | Should -Be Deferred
        $r.RebootRequired | Should -BeTrue
        $r.Items[0].Status | Should -Be Deferred
        Should -Invoke Invoke-OSDStageWindowsUpdateAsync -Times 0 -ParameterFilter {$Phase -ne 'Search'}
    }
    It 'checks per-update downloads and does not install partially downloaded sets' {
        $script:downloadCode=3
        $r=Invoke-OSDStageWindowsUpdateConfiguration $script:config
        $r.Status | Should -Be Failed
        $r.Items[0].DownloadResultCode | Should -Be 3
        Should -Invoke Invoke-OSDStageWindowsUpdateAsync -Times 0 -ParameterFilter {$Phase -eq 'Install'}
    }
    It 'installs software before optional drivers, preserves objects and writes a durable result' {
        $script:config.IncludeDrivers=$true
        $script:updates=@((New-TestUpdate -Title 'Network driver' -Type 2 -Category 'ebfc1fc5-71a4-4f7b-9aca-3b9a503104a0'),$script:update)
        $r=Invoke-OSDStageWindowsUpdateConfiguration $script:config
        $r.Status | Should -Be Succeeded
        $r.InstalledCount | Should -Be 2
        @($script:installOrder) | Should -Be @('Beveiligingsupdate','Network driver')
        $script:installer.ForceQuiet | Should -BeTrue
        $script:installer.AllowSourcePrompts | Should -BeFalse
        $r.FurtherScanRequired | Should -BeTrue
        $r.RebootRequested | Should -BeFalse
        $r.ReleaseUnchanged | Should -BeTrue
        $saved=Get-Content $script:config.ResultPath -Raw | ConvertFrom-Json
        $saved.DeploymentId | Should -Be $script:config.DeploymentId
        $saved.Items[0].InstallResultCode | Should -Be 2
    }
    It 'stops at a reboot boundary and records the remaining updates as deferred' {
        $script:updates=@($script:update,(New-TestUpdate -Title 'Next'))
        $script:reboot=$true
        $r=Invoke-OSDStageWindowsUpdateConfiguration $script:config
        $r.Status | Should -Be Deferred
        $r.InstalledCount | Should -Be 1
        $r.RebootRequired | Should -BeTrue
        $r.Items[1].Status | Should -Be Deferred
        Should -Invoke Invoke-OSDStageWindowsUpdateAsync -Times 1 -Exactly -ParameterFilter {$Phase -eq 'Install'}
    }
    It 'retains HRESULTs and reboot requirements when an installation fails' {
        $script:installCode=4;$script:reboot=$true
        $r=Invoke-OSDStageWindowsUpdateConfiguration $script:config
        $r.Status | Should -Be Failed
        $r.Items[0].InstallResultCode | Should -Be 4
        $r.RebootRequired | Should -BeTrue
    }
    It 'queries reboot state even when the installation API throws' {
        $script:systemReboot=$true
        Mock Invoke-OSDStageWindowsUpdateAsync { throw 'COM installation failure' } -ParameterFilter {$Phase -eq 'Install'}
        $r=Invoke-OSDStageWindowsUpdateConfiguration $script:config
        $r.Status | Should -Be Failed
        $r.RebootRequired | Should -BeTrue
        $r.RebootStateKnown | Should -BeTrue
        $r.Items[0].Status | Should -Be InstallOutcomeUnknown
    }
    It 'records an unavailable update source and a busy installer as failures' {
        $script:installer.IsBusy=$true
        (Invoke-OSDStageWindowsUpdateConfiguration $script:config).Error | Should -BeLike '*busy*'
        Mock Invoke-OSDStageWindowsUpdateAsync { throw 'Source unreachable' }
        (Invoke-OSDStageWindowsUpdateConfiguration $script:config).Error | Should -Be 'Source unreachable'
    }
    It 'accepts a quality revision change but rejects a Windows release change' {
        $script:read=0
        Mock Get-OSDStageWindowsUpdateRelease {
            $script:read++
            [pscustomobject]@{DisplayVersion='25H2';Build='26200';Revision=$script:read}
        }
        (Invoke-OSDStageWindowsUpdateConfiguration $script:config).ReleaseUnchanged | Should -BeTrue
        $script:read=0
        Mock Get-OSDStageWindowsUpdateRelease {
            $script:read++
            [pscustomobject]@{DisplayVersion=if ($script:read -eq 1) {'25H2'} else {'26H2'};Build='26200';Revision=1}
        }
        (Invoke-OSDStageWindowsUpdateConfiguration $script:config).Outcome | Should -Be ReleaseChanged
    }
    It 'stages idempotently, honors WhatIf and rejects offline-only preflight and tampering' {
        InModuleScope OSDStage {
            Set-OSDStageConfiguration -EnableBuiltIns $true | Out-Null
            Mock Test-OSDStageWinPE { $true }
            $target=Join-Path $TestDrive 'Offline Windows'
            New-Item -ItemType Directory -Path $target | Out-Null
            Add-OSDStageWindowsUpdate -WindowsPath $target -WhatIf
            $stage=Join-Path $target 'Windows/Temp/OSDStage'
            Test-Path (Join-Path $stage 'DeviceManifest.json') | Should -BeFalse
            Add-OSDStageWindowsUpdate -WindowsPath $target | Out-Null
            Add-OSDStageWindowsUpdate -WindowsPath $target -ScanOnly -IncludeDrivers | Out-Null
            $m=Get-Content (Join-Path $stage 'DeviceManifest.json') -Raw | ConvertFrom-Json
            $m.Packages.Count | Should -Be 1
            $c=Join-Path $stage 'BuiltIn/WindowsUpdate/config.json'
            (Get-Content $c -Raw | ConvertFrom-Json).ScanOnly | Should -BeTrue
            $check=Test-OSDStageDeployment -WindowsPath $target -ThrowOnFailure
            $check.Valid | Should -BeTrue
            $check.NetworkRequired | Should -BeTrue
            $check.OfflineReady | Should -BeFalse
            { Test-OSDStageDeployment -WindowsPath $target -RequireOfflineReady -ThrowOnFailure } | Should -Throw
            Add-Content $c 'tampered'
            (Test-OSDStageDeployment -WindowsPath $target).Valid | Should -BeFalse
            { Add-OSDStageWindowsUpdate -WindowsPath $target } | Should -Throw '*intact*'
        }
    }
}

Describe 'WUA asynchronous cancellation lifetime' {
    BeforeAll { . (Join-Path (Split-Path $PSScriptRoot -Parent) 'Runtime/Invoke-OSDStageWindowsUpdate.ps1') }
    It 'requests cancellation, completes EndSearch and cleans up without terminating servicing' {
        Mock New-OSDStageWindowsUpdateCallback { [pscustomobject]@{} }
        Mock Write-OSDStageWindowsUpdateMessage {}
        Mock Start-Sleep {}
        $script:job=[pscustomobject]@{IsCompleted=$false;Aborted=$false;Cleaned=$false}
        $script:job | Add-Member ScriptMethod RequestAbort { $this.Aborted=$true;$this.IsCompleted=$true }
        $script:job | Add-Member ScriptMethod CleanUp { $this.Cleaned=$true }
        $agent=[pscustomobject]@{Ended=$false}
        $agent | Add-Member ScriptMethod BeginSearch { param($criteria,$callback,$state) $script:job }
        $agent | Add-Member ScriptMethod EndSearch { param($job) $this.Ended=$true;[pscustomobject]@{ResultCode=5} }
        $r=Invoke-OSDStageWindowsUpdateAsync -Agent $agent -Phase Search -TimeoutMinutes 0
        $r.TimedOut | Should -BeTrue
        $agent.Ended | Should -BeTrue
        $script:job.Aborted | Should -BeTrue
        $script:job.Cleaned | Should -BeTrue
    }
}
