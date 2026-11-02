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
                BundledUpdates=@();EulaAccepted=$false;IsDownloaded=$true;DriverClass='Networking';DriverHardwareID='PCI\VEN_1234'
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
        foreach ($category in @('3689bdc8-b205-4af4-8d4a-a63924c5e9d5','b54e7d24-7add-428f-8b75-90a396fa584f','unknown')) {
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
    It 'inherits a checked classification only for unclassified software bundle members' {
        $script:update.BundledUpdates=@((New-TestUpdate))
        (Get-OSDStageWindowsUpdateSelection $script:update).Selected | Should -BeTrue
        $script:update.BundledUpdates[0].Categories=@()
        foreach ($category in @('0fa1201d-4330-4fa8-8ae9-b877473b6441','e6cf1350-c01b-414d-a61f-263d14d133b4','e0789628-ce08-4437-be74-2495b842f43b')) {
            $script:update.Categories[0].CategoryID=$category
            $decision=Get-OSDStageWindowsUpdateSelection $script:update
            $decision.Selected | Should -BeTrue
            $decision.ClassificationSource | Should -Be Own
            $decision.BundleDecisions[0].ClassificationSource | Should -Be ParentBundle
            $decision.BundleDecisions[0].ClassificationIds.Count | Should -Be 0
            @($decision.BundleDecisions[0].EffectiveClassificationIds) | Should -Be @($category)
        }
    }
    It 'rejects missing category metadata and never supplies a classification to a root offer' {
        $u=New-TestUpdate;$u.Categories=@()
        (Get-OSDStageWindowsUpdateSelection $u).Selected | Should -BeFalse
        (Get-OSDStageWindowsUpdateSelection $u -ParentSoftwareClassifications 'e0789628-ce08-4437-be74-2495b842f43b').Selected | Should -BeFalse
        $script:update.BundledUpdates=@($u)
        $u.Categories=$null
        (Get-OSDStageWindowsUpdateSelection $script:update).Reason | Should -Be 'BundleRejected: ClassificationMetadataMissing'
        $u.PSObject.Properties.Remove('Categories')
        (Get-OSDStageWindowsUpdateSelection $script:update).Selected | Should -BeFalse
    }
    It 'preserves explicit child classification exclusions and records all bundle members' {
        foreach ($category in @('3689bdc8-b205-4af4-8d4a-a63924c5e9d5','b54e7d24-7add-428f-8b75-90a396fa584f','unknown')) {
            $bad=New-TestUpdate -Category $category
            $unclassified=New-TestUpdate;$unclassified.Categories=@()
            $script:update.BundledUpdates=@($bad,$unclassified)
            $decision=Get-OSDStageWindowsUpdateSelection $script:update
            $decision.Selected | Should -BeFalse
            $decision.BundleDecisions.Count | Should -Be 2
            $decision.BundleDecisions[0].ClassificationSource | Should -Be Own
            $decision.BundleDecisions[1].Selected | Should -BeTrue
            $bad.Categories+=@([pscustomobject]@{Type='UpdateClassification';CategoryID='e0789628-ce08-4437-be74-2495b842f43b'})
            (Get-OSDStageWindowsUpdateSelection $script:update).Selected | Should -BeFalse
        }
    }
    It 'checks nested bundles and keeps preview, feature, interactive and driver exclusions' {
        $child=New-TestUpdate;$child.Categories=@()
        $leaf=New-TestUpdate;$leaf.Categories=@()
        $child.BundledUpdates=@($leaf);$script:update.BundledUpdates=@($child)
        (Get-OSDStageWindowsUpdateSelection $script:update).Selected | Should -BeTrue
        $leaf.Categories=@([pscustomobject]@{Type='UpdateClassification';CategoryID='3689bdc8-b205-4af4-8d4a-a63924c5e9d5'})
        (Get-OSDStageWindowsUpdateSelection $script:update).Selected | Should -BeFalse
        $leaf.Categories=@()
        foreach ($title in @('Feature Update','Enablement package','Preview','Firmware')) {
            $leaf.Title=$title
            (Get-OSDStageWindowsUpdateSelection $script:update).Selected | Should -BeFalse
        }
        $leaf.Title='Binary 0';$leaf.InstallationBehavior.CanRequestUserInput=$true
        (Get-OSDStageWindowsUpdateSelection $script:update).Selected | Should -BeFalse
        $leaf.InstallationBehavior.CanRequestUserInput=$false;$leaf.Type=2
        (Get-OSDStageWindowsUpdateSelection $script:update).Selected | Should -BeFalse
        (Get-OSDStageWindowsUpdateSelection $script:update -IncludeDrivers $true).Selected | Should -BeFalse
        $driver=New-TestUpdate -Type 2 -Category 'ebfc1fc5-71a4-4f7b-9aca-3b9a503104a0'
        $leaf.Type=1;$driver.BundledUpdates=@($leaf)
        (Get-OSDStageWindowsUpdateSelection $driver -IncludeDrivers $true).Selected | Should -BeFalse
    }
    It 'selects complete definition bundles with categoryless binary members and saves their evidence' {
        # Regression shape from PC1 on 2 November: one Security platform binary
        # and four Defender binaries. Titles are diagnostics, not an allowlist.
        $definition='e0789628-ce08-4437-be74-2495b842f43b'
        $platform=New-TestUpdate -Title 'KB5007651' -Category $definition
        $defender=New-TestUpdate -Title 'KB2267602' -Category $definition
        $platform.BundledUpdates=@((New-TestUpdate -Title 'Binary 0'))
        $defender.BundledUpdates=@('HIDDEN: MpSigStub','HIDDEN: Engine','HIDDEN: Bases','Full Deltas' | ForEach-Object { New-TestUpdate -Title $_ })
        foreach ($u in @($platform.BundledUpdates)+@($defender.BundledUpdates)) { $u.Categories=@() }
        $script:updates=@($platform,$defender,(New-TestUpdate -Title 'KB890830' -Category '28bc880e-0592-4cbf-8f95-c79b17911d5f'))
        $r=Invoke-OSDStageWindowsUpdateConfiguration $script:config
        $r.SelectionPolicy | Should -Be QualityAndDriversV5
        $r.SelectedCount | Should -Be 3
        $r.InstalledCount | Should -Be 3
        $r.Items[2].Selected | Should -BeTrue
        # Install only root offers, never their internal binaries separately.
        @($script:installOrder) | Should -Be @('KB5007651','KB2267602','KB890830')
        $saved=Get-Content $script:config.ResultPath -Raw | ConvertFrom-Json
        $saved.Items[1].BundleDecisions.Count | Should -Be 4
        $saved.Items[1].BundleDecisions[3].ClassificationSource | Should -Be ParentBundle
        $saved.Items[1].BundleDecisions[3].ClassificationIds.Count | Should -Be 0
    }
    It 'requires opt-in but then includes all classes including firmware and optional offers' {
        foreach ($class in @('Firmware','System','Extension','SoftwareComponent','OtherHardware','Networking','Sound','Video','NewVendorClass')) {
            $u=New-TestUpdate -Title 'Vendor Firmware' -Type 2 -Category 'ebfc1fc5-71a4-4f7b-9aca-3b9a503104a0'
            $u.DriverClass=$class;$u.DriverHardwareID='UEFI\RES_1234'
            $u.AutoSelectOnWebSites=$false;$u.BrowseOnly=$true
            (Get-OSDStageWindowsUpdateSelection $u).Reason | Should -Be DriversDisabled
            (Get-OSDStageWindowsUpdateSelection $u $true).Selected | Should -BeTrue
        }
    }
    It 'uses optional exact WUA class names as an allowlist without weakening software policy' {
        $u=New-TestUpdate -Type 2 -Category 'ebfc1fc5-71a4-4f7b-9aca-3b9a503104a0'
        (Get-OSDStageWindowsUpdateSelection $u $true -DriverClass @('networking','Sound')).Selected | Should -BeTrue
        $u.DriverClass='Extension'
        (Get-OSDStageWindowsUpdateSelection $u $true -DriverClass @('Networking','Sound')).Reason | Should -Be DriverClassNotIncluded
        $u.DriverClass=''
        (Get-OSDStageWindowsUpdateSelection $u $true).Reason | Should -Be DriverClassMissing
        $u=New-TestUpdate;$u.AutoSelectOnWebSites=$false
        (Get-OSDStageWindowsUpdateSelection $u $true).Reason | Should -Be NotAutomatic
    }
    It 'allows normal NET Updates and rollups but excludes previews and feature packs' {
        foreach ($category in @('cd5ffd1e-e932-4e3a-bf74-18bf0b1bbd83','28bc880e-0592-4cbf-8f95-c79b17911d5f')) {
            $u=New-TestUpdate -Title '.NET cumulative update' -Category $category
            (Get-OSDStageWindowsUpdateSelection $u).Selected | Should -BeTrue
            foreach ($title in @('.NET cumulative update Preview','Feature update','Enablement package')) {
                $u.Title=$title
                (Get-OSDStageWindowsUpdateSelection $u).Selected | Should -BeFalse
            }
        }
    }
    It 'rejects invalid class configuration and persists valid class filters into the runtime report' {
        foreach ($classes in @(@('Networking'),@(''),@('*'),@('Net?'),@('Net[12]'),@(123))) {
            $c=$script:config.PSObject.Copy()
            $c | Add-Member NoteProperty DriverClass $classes
            { Assert-OSDStageWindowsUpdateConfiguration $c } | Should -Throw
        }
        foreach ($classes in @(@(''),@('*'),@('Net?'),@('Net[12]'),@(123))) {
            $c=$script:config.PSObject.Copy();$c.IncludeDrivers=$true
            $c | Add-Member NoteProperty DriverClass $classes
            { Assert-OSDStageWindowsUpdateConfiguration $c } | Should -Throw
        }
        $script:config.IncludeDrivers=$true
        $script:config | Add-Member NoteProperty DriverClass @('Sound')
        $u=New-TestUpdate -Type 2 -Category 'ebfc1fc5-71a4-4f7b-9aca-3b9a503104a0'
        $script:updates=@($u)
        $r=Invoke-OSDStageWindowsUpdateConfiguration $script:config
        $r.DriverClass | Should -Be @('Sound')
        $r.Items[0].SelectionReason | Should -Be DriverClassNotIncluded
        $r.SelectedCount | Should -Be 0
    }
    It 'allows UI-capable opted-in drivers only through the quiet runtime' {
        $driver=New-TestUpdate -Title 'Intel network' -Type 2 -Category 'ebfc1fc5-71a4-4f7b-9aca-3b9a503104a0'
        $driver.InstallationBehavior.CanRequestUserInput=$true
        $driver.AutoSelectOnWebSites=$false
        (Get-OSDStageWindowsUpdateSelection $driver).Reason | Should -Be DriversDisabled
        (Get-OSDStageWindowsUpdateSelection $driver $true).Selected | Should -BeTrue
        $script:config.IncludeDrivers=$true;$script:updates=@($driver)
        $r=Invoke-OSDStageWindowsUpdateConfiguration $script:config
        $r.InstalledCount | Should -Be 1
        $r.Items[0].CanRequestUserInput | Should -BeTrue
        $r.Items[0].RebootBehavior | Should -Be 2
        $script:installer.ForceQuiet | Should -BeTrue
        $script:installer.AllowSourcePrompts | Should -BeFalse
        $r.RebootRequested | Should -BeFalse
        $driver.InstallationBehavior.CanRequestUserInput=$null
        (Get-OSDStageWindowsUpdateSelection $driver $true).Reason | Should -Be InteractionMetadataUnknown
        $driver.InstallationBehavior.CanRequestUserInput=$true;$driver.InstallationBehavior.RebootBehavior=99
        (Get-OSDStageWindowsUpdateSelection $driver $true).Reason | Should -Be RebootBehaviorUnknown
        $driver.InstallationBehavior=$null
        (Get-OSDStageWindowsUpdateSelection $driver $true).Reason | Should -Be InstallationBehaviorMissing
    }
    It 'preserves distinct WUA offers sharing a hardware ID rather than inventing a version ranking' {
        $older=New-TestUpdate -Title 'Intel 24.20.0.4' -Type 2 -Category 'ebfc1fc5-71a4-4f7b-9aca-3b9a503104a0'
        $newer=New-TestUpdate -Title 'Intel 24.70.0.3' -Type 2 -Category 'ebfc1fc5-71a4-4f7b-9aca-3b9a503104a0'
        $older.DriverHardwareID='pci\ven_8086&dev_7af0&subsys_40908086'
        $newer.DriverHardwareID=$older.DriverHardwareID.ToUpperInvariant()
        $script:config.IncludeDrivers=$true;$script:config.ScanOnly=$true
        $script:updates=@($older,$newer)
        $r=Invoke-OSDStageWindowsUpdateConfiguration $script:config
        $r.SelectedCount | Should -Be 2
        @($r.Items | Where-Object Selected).Count | Should -Be 2
        $r.Items[0].UpdateId | Should -Not -Be $r.Items[1].UpdateId
        $older.EulaAccepted | Should -BeFalse
        Should -Invoke Invoke-OSDStageWindowsUpdateAsync -Times 1 -Exactly
    }
    It 'stops after a driver cannot install quietly without an interactive retry' {
        $driver=New-TestUpdate -Title 'UI capable driver' -Type 2 -Category 'ebfc1fc5-71a4-4f7b-9aca-3b9a503104a0'
        $driver.InstallationBehavior.CanRequestUserInput=$true
        $other=New-TestUpdate -Title 'Next driver' -Type 2 -Category 'ebfc1fc5-71a4-4f7b-9aca-3b9a503104a0'
        $other.DriverHardwareID='USB\VID_1234'
        $script:updates=@($driver,$other);$script:config.IncludeDrivers=$true
        Mock Invoke-OSDStageWindowsUpdateAsync {
            $r=New-TestWuaResult -Code 4
            $r.HResult=-2145116156 # WU_E_UH_DOESNOTSUPPORTACTION (0x80242004)
            $r | Add-Member ScriptMethod GetUpdateResult { param($index) [pscustomobject]@{ResultCode=4;HResult=$this.HResult;RebootRequired=$false} } -Force
            [pscustomobject]@{Result=$r;TimedOut=$false;DurationSeconds=1}
        } -ParameterFilter {$Phase -eq 'Install'}
        $r=Invoke-OSDStageWindowsUpdateConfiguration $script:config
        $r.Status | Should -Be Failed
        $r.InstalledCount | Should -Be 0
        $r.Items[0].InstallHResult | Should -Be -2145116156
        $script:installer.ForceQuiet | Should -BeTrue
        $script:installer.AllowSourcePrompts | Should -BeFalse
        $r.RebootRequested | Should -BeFalse
        Should -Invoke Invoke-OSDStageWindowsUpdateAsync -Times 1 -Exactly -ParameterFilter {$Phase -eq 'Install'}
    }
    It 'records raw automatic-selection flags without turning missing metadata into false' {
        $driver=New-TestUpdate -Title 'Network driver' -Type 2 -Category 'ebfc1fc5-71a4-4f7b-9aca-3b9a503104a0'
        $driver.BrowseOnly=$true;$driver.AutoSelectOnWebSites=$false
        $missing=New-TestUpdate;$missing.BrowseOnly=$null
        $script:updates=@($driver,$missing);$script:config.IncludeDrivers=$true;$script:config.ScanOnly=$true
        $r=Invoke-OSDStageWindowsUpdateConfiguration $script:config
        $r.SelectedCount | Should -Be 1
        $r.Items[0].BrowseOnly | Should -BeTrue
        $r.Items[0].AutoSelectOnWebSites | Should -BeFalse
        $r.Items[0].SelectionReason | Should -Be OptedInHardwareDriver
        ($null -eq $r.Items[1].BrowseOnly) | Should -BeTrue
        Should -Invoke Invoke-OSDStageWindowsUpdateAsync -Times 1 -Exactly
    }
    It 'keeps hardware drivers optional in the runtime and records their metadata' {
        $driver=New-TestUpdate -Title 'Network driver' -Type 2 -Category 'ebfc1fc5-71a4-4f7b-9aca-3b9a503104a0'
        $driver.AutoSelectOnWebSites=$false
        $firmware=New-TestUpdate -Title 'Dell Firmware' -Type 2 -Category 'ebfc1fc5-71a4-4f7b-9aca-3b9a503104a0'
        $firmware.DriverClass='Firmware'
        $script:updates=@($driver,$firmware,$script:update)
        $r=Invoke-OSDStageWindowsUpdateConfiguration $script:config
        $r.SelectedCount | Should -Be 1
        $r.Items[0].SelectionReason | Should -Be DriversDisabled
        $script:config.IncludeDrivers=$true;$script:installOrder.Clear()
        $r=Invoke-OSDStageWindowsUpdateConfiguration $script:config
        $r.SelectedCount | Should -Be 3
        $r.Items[0].Status | Should -Be Installed
        $r.Items[0].DriverClass | Should -Be Networking
        $r.Items[0].DriverHardwareId | Should -Be 'PCI\VEN_1234'
        $r.Items[1].Selected | Should -BeTrue
        @($script:installOrder) | Should -Be @('Beveiligingsupdate','Network driver','Dell Firmware')
        $r.RebootRequested | Should -BeFalse
    }
    It 'scan-only records decisions without accepting EULAs or installing' {
        $script:config.ScanOnly=$true
        $r=Invoke-OSDStageWindowsUpdateConfiguration $script:config
        $r.Outcome | Should -Be ScanOnly
        $r.Items[0].Selected | Should -BeTrue
        $script:update.EulaAccepted | Should -BeFalse
        Should -Invoke Invoke-OSDStageWindowsUpdateAsync -Times 1 -Exactly
    }
    It 'labels a manual OOBE test separately and keeps its scan read-only' {
        $script:config.ScanOnly=$true
        $r=Invoke-OSDStageWindowsUpdateConfiguration $script:config -OobeTest
        $r.Phase | Should -Be ManualOobeTest
        $r.RebootRequested | Should -BeFalse
        Should -Invoke Assert-OSDStageWindowsUpdateContext -Times 1 -Exactly -ParameterFilter { $OobeTest }
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
        @($script:installOrder) | Should -Be @('Beveiligingsupdate')
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
            Add-OSDStageWindowsUpdate -WindowsPath $target -ScanOnly -IncludeDrivers -DriverClass Networking,Sound | Out-Null
            $m=Get-Content (Join-Path $stage 'DeviceManifest.json') -Raw | ConvertFrom-Json
            $m.Packages.Count | Should -Be 1
            $c=Join-Path $stage 'BuiltIn/WindowsUpdate/config.json'
            (Get-Content $c -Raw | ConvertFrom-Json).ScanOnly | Should -BeTrue
            @((Get-Content $c -Raw | ConvertFrom-Json).DriverClass) | Should -Be @('Networking','Sound')
            { Add-OSDStageWindowsUpdate -WindowsPath $target -DriverClass Sound } | Should -Throw '*requires*'
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
