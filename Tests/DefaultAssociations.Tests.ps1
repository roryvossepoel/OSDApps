Describe 'Initial file and protocol associations' {
    BeforeAll {
        $script:root=Split-Path $PSScriptRoot -Parent
        Import-Module (Join-Path $script:root 'OSDApps.psd1') -Force
        . (Join-Path $script:root 'Runtime\Invoke-OSDAppDefaultAssociations.ps1')
        function New-AssociationFixture {
            param([string]$Id='.pdf',[string]$ProgId='Example.Pdf',[string]$Name='Example Reader')
            [pscustomobject]@{Identifier=$Id;ProgId=$ProgId;AppName=$Name}
        }
    }
    BeforeEach {
        Set-OSDAppConfiguration -EnableBuiltIns $true -EnableRepository $true -CleanupMode Never
        $script:config=[pscustomobject]@{SchemaVersion=1;DeploymentId=[guid]::NewGuid().Guid;ResultPath=(Join-Path $TestDrive 'Results\DefaultAssociations-Result.json');Associations=@(New-AssociationFixture)}
    }

    It 'round-trips escaped names and normalizes extension and protocol identities' {
        $name='Reader & Tools <test> "edition" ' + [char]0x00e9
        $items=@((New-AssociationFixture -Id '.PDF' -Name $name),(New-AssociationFixture -Id 'HTTPS' -ProgId 'Browser.HTML'))
        $xml=ConvertTo-OSDAppDefaultAssociationsXml -Associations $items
        $path=Join-Path $TestDrive 'input.xml'
        [IO.File]::WriteAllText($path,$xml,[Text.UTF8Encoding]::new($false))
        $read=@(Read-OSDAppDefaultAssociationsXml -Path $path)
        $read.Count | Should -Be 2
        $read[0].Identifier | Should -BeExactly '.pdf'
        $read[0].AppName | Should -BeExactly $name
        $read[1].Identifier | Should -BeExactly 'https'
        $xml | Should -Not -Match 'utf-16'
        $xml | Should -Match '&amp;'
    }
    It 'rejects malformed XML, entities, policy flags, unexpected attributes and duplicate identifiers' {
        $invalid=@(
            '<DefaultAssociations>',
            '<!DOCTYPE DefaultAssociations [<!ENTITY x SYSTEM "file:///missing">]><DefaultAssociations>&x;</DefaultAssociations>',
            '<DefaultAssociations Version="1"><Association Identifier=".pdf" ProgId="Example.Pdf" ApplicationName="Example" /></DefaultAssociations>',
            '<DefaultAssociations><Association Identifier=".pdf" ProgId="Example.Pdf" ApplicationName="Example" Suggested="true" /></DefaultAssociations>',
            '<DefaultAssociations xmlns="urn:other"><Association /></DefaultAssociations>',
            '<DefaultAssociations><Association Identifier=".pdf" ProgId="Example.Pdf" ApplicationName="Example"><Nested /></Association></DefaultAssociations>',
            '<DefaultAssociations><Association Identifier=".pdf" ProgId="Example.Pdf" Extra="Example" /></DefaultAssociations>',
            '<DefaultAssociations><Association Identifier=".PDF" ProgId="Example.Pdf" ApplicationName="Example" /><Association Identifier=".pdf" ProgId="Other.Pdf" ApplicationName="Other" /></DefaultAssociations>',
            '<DefaultAssociations />'
        )
        $path=Join-Path $TestDrive 'invalid.xml'
        foreach ($xml in $invalid) {
            [IO.File]::WriteAllText($path,$xml)
            { Read-OSDAppDefaultAssociationsXml -Path $path } | Should -Throw
        }
        [IO.File]::WriteAllText($path,(' ' * (1MB+1)))
        { Read-OSDAppDefaultAssociationsXml -Path $path } | Should -Throw '*1 MiB*'
    }
    It 'rejects ambiguous identifiers commands and empty selections' {
        foreach ($id in @('https:','*.pdf','.',' .pdf','.p df','C:\x','')) {
            { ConvertTo-OSDAppDefaultAssociations -Associations @(New-AssociationFixture -Id $id) } | Should -Throw
        }
        foreach ($progId in @('C:\reader.exe','cmd /c test','Example"Injected','')) {
            { ConvertTo-OSDAppDefaultAssociations -Associations @(New-AssociationFixture -ProgId $progId) } | Should -Throw
        }
        { ConvertTo-OSDAppDefaultAssociations -Associations @() } | Should -Throw
        { ConvertTo-OSDAppDefaultAssociations -Associations @((New-AssociationFixture),(New-AssociationFixture -Id '.PDF')) } | Should -Throw '*Duplicate*'
    }
    It 'preserves unselected exported associations and applies the last supplied selection' {
        $baseline=@((New-AssociationFixture -Id '.txt' -ProgId 'Text.Handler'),(New-AssociationFixture))
        $merged=@(Merge-OSDAppDefaultAssociations -Baseline $baseline -Overrides @((New-AssociationFixture -Id '.PDF' -ProgId 'Other.Pdf'),(New-AssociationFixture -Id 'https' -ProgId 'Browser.HTML')))
        $merged.Count | Should -Be 3
        ($merged | Where-Object Identifier -eq '.txt').ProgId | Should -Be 'Text.Handler'
        ($merged | Where-Object Identifier -eq '.pdf').ProgId | Should -Be 'Other.Pdf'
        $again=@(Merge-OSDAppDefaultAssociations -Baseline $merged -Overrides @(New-AssociationFixture -Id 'https' -ProgId 'NewBrowser.HTML'))
        $again.Count | Should -Be 3
        ($again | Where-Object Identifier -eq 'https').ProgId | Should -Be 'NewBrowser.HTML'
    }
    It 'exposes mutually exclusive parameter and XML input sets' {
        $command=Get-Command Add-OSDAppDefaultAssociation
        @($command.ParameterSets.Name) | Should -Contain Parameters
        @($command.ParameterSets.Name) | Should -Contain Xml
        { Add-OSDAppDefaultAssociation -Identifier '.pdf' -ProgId Example.Pdf -AppName Example -XmlPath 'x.xml' } | Should -Throw
    }
    It 'refuses a preparation-host target or disabled source before staging' {
        InModuleScope OSDApps {
            Mock Test-OSDAppWinPE { $false }
            { Add-OSDAppDefaultAssociation -Identifier '.pdf' -ProgId Example.Pdf -AppName Example } | Should -Throw '*WinPE*'
            Set-OSDAppConfiguration -EnableBuiltIns $false -EnableRepository $true
            { Add-OSDAppDefaultAssociation -Identifier '.pdf' -ProgId Example.Pdf -AppName Example } | Should -Throw '*disabled*'
        }
    }
    It 'stages both inputs in one ordered entry, survives source deletion, and rejects tampering' {
        InModuleScope OSDApps {
            Mock Test-OSDAppWinPE { $true }
            $target=Join-Path $TestDrive 'Offline Windows'
            New-Item -ItemType Directory -Path $target | Out-Null
            $xml=Join-Path $TestDrive 'selection.xml'
            '<DefaultAssociations><Association Identifier=".pdf" ProgId="Example.Pdf" ApplicationName="Example" /></DefaultAssociations>' | Set-Content $xml -Encoding UTF8
            Add-OSDAppDefaultAssociation -XmlPath $xml -WindowsPath $target -WhatIf
            Test-Path (Join-Path $target 'Windows\Temp\OSDApps\DeviceManifest.json') | Should -BeFalse
            Add-OSDAppDefaultAssociation -XmlPath $xml -WindowsPath $target | Out-Null
            Remove-Item $xml
            Add-OSDAppEnvironmentVariable -Name AssociationTest -Value 'no execution' -WindowsPath $target | Out-Null
            Add-OSDAppDefaultAssociation -Identifier @('http','https') -ProgId Browser.HTML -AppName Browser -WindowsPath $target | Out-Null
            Add-OSDAppDefaultAssociation -Identifier '.PDF' -ProgId Other.Pdf -AppName Other -WindowsPath $target | Out-Null
            $ready=Test-OSDAppDeployment -WindowsPath $target -RequireOfflineReady -ThrowOnFailure
            $ready.OfflineReady | Should -BeTrue
            $ready.NetworkRequired | Should -BeFalse
            $ready.AppCount | Should -Be 2
            $stage=Join-Path $target 'Windows\Temp\OSDApps'
            $manifest=Get-Content (Join-Path $stage 'DeviceManifest.json') -Raw | ConvertFrom-Json
            $manifest.Apps[-1].Id | Should -Be DefaultAssociations
            @($manifest.Apps | Where-Object Id -eq DefaultAssociations).Count | Should -Be 1
            $file=Join-Path $stage 'BuiltIn\DefaultAssociations\config.json'
            $config=Get-Content $file -Raw | ConvertFrom-Json
            $config.Associations.Count | Should -Be 3
            ($config.Associations | Where-Object Identifier -eq '.pdf').ProgId | Should -Be Other.Pdf
            $hash=(Get-FileHash $file).Hash
            Mock Add-OSDAppSetupComplete { throw 'fixture transaction failure' }
            { Add-OSDAppDefaultAssociation -Identifier '.pdf' -ProgId Rejected.Pdf -AppName Rejected -WindowsPath $target } | Should -Throw '*transaction failure*'
            (Get-FileHash $file).Hash | Should -Be $hash
            Add-Content $file 'tampered'
            { Test-OSDAppDeployment -WindowsPath $target -RequireOfflineReady -ThrowOnFailure } | Should -Throw
            { Add-OSDAppDefaultAssociation -Identifier '.pdf' -ProgId Rejected.Pdf -AppName Rejected -WindowsPath $target } | Should -Throw '*not an intact*'
        }
    }
    It 'exports and merges before one import without claiming user-visible success' {
        Mock Assert-OSDAppDefaultAssociationContext { }
        Mock Invoke-OSDAppAssociationDism {
            param($Action,$XmlPath,$LogPath)
            if ($Action -eq 'Export') {
                '<DefaultAssociations><Association Identifier=".txt" ProgId="Text.Handler" ApplicationName="Text" /><Association Identifier=".pdf" ProgId="Old.Pdf" ApplicationName="Old" /></DefaultAssociations>' | Set-Content $XmlPath -Encoding UTF8
            } else {
                $items=@(Read-OSDAppDefaultAssociationsXml -Path $XmlPath)
                $items.Count | Should -Be 2
                ($items | Where-Object Identifier -eq '.txt').ProgId | Should -Be Text.Handler
                ($items | Where-Object Identifier -eq '.pdf').ProgId | Should -Be Example.Pdf
            }
            [pscustomobject]@{Action=$Action;ExitCode=0;LogPath=$LogPath;StandardOutput='fixture';StandardError=''}
        }
        $result=Invoke-OSDAppDefaultAssociationConfiguration -Configuration $script:config -WorkDirectory $TestDrive
        $result.Status | Should -Be Succeeded
        $result.Outcome | Should -Be ImportedForFirstSignIn
        $result.BaselineCount | Should -Be 2
        $result.ImportedCount | Should -Be 2
        $result.UserDefaultsVerified | Should -BeFalse
        $result.RebootRequested | Should -BeFalse
        Should -Invoke Invoke-OSDAppAssociationDism -Exactly 1 -ParameterFilter { $Action -eq 'Export' }
        Should -Invoke Invoke-OSDAppAssociationDism -Exactly 1 -ParameterFilter { $Action -eq 'Import' }
    }
    It 'does not import when export fails or returns empty malformed or missing baseline' {
        Mock Assert-OSDAppDefaultAssociationContext { }
        foreach ($mode in @('Failed','Empty','Malformed','Missing')) {
            $script:mode=$mode
            Mock Invoke-OSDAppAssociationDism {
                param($Action,$XmlPath)
                if ($script:mode -eq 'Empty') { '<DefaultAssociations />' | Set-Content $XmlPath }
                if ($script:mode -eq 'Malformed') { '<NotAssociations />' | Set-Content $XmlPath }
                [pscustomobject]@{ExitCode=if ($script:mode -eq 'Failed') {87} else {0}}
            }
            $result=Invoke-OSDAppDefaultAssociationConfiguration -Configuration $script:config -WorkDirectory $TestDrive
            $result.Status | Should -Be Failed
            $result.Import | Should -BeNullOrEmpty
        }
        Should -Invoke Invoke-OSDAppAssociationDism -Exactly 0 -ParameterFilter { $Action -eq 'Import' }
    }
    It 'reports import failure or restart requirement without retry or forced reboot' {
        Mock Assert-OSDAppDefaultAssociationContext { }
        foreach ($exit in @(87,3010)) {
            $script:importExit=$exit
            Mock Invoke-OSDAppAssociationDism {
                param($Action,$XmlPath)
                if ($Action -eq 'Export') {
                    '<DefaultAssociations><Association Identifier=".txt" ProgId="Text.Handler" ApplicationName="Text" /></DefaultAssociations>' | Set-Content $XmlPath
                }
                [pscustomobject]@{ExitCode=if ($Action -eq 'Export') {0} else {$script:importExit}}
            }
            $result=Invoke-OSDAppDefaultAssociationConfiguration -Configuration $script:config -WorkDirectory $TestDrive
            $result.Status | Should -Be $(if ($exit -eq 3010) {'Succeeded'} else {'Failed'})
            $result.RestartNeeded | Should -Be ($exit -eq 3010)
            $result.RebootRequested | Should -BeFalse
        }
        Should -Invoke Invoke-OSDAppAssociationDism -Exactly 2 -ParameterFilter { $Action -eq 'Import' }
    }
    It 'rejects invalid configuration and unsuitable runtime context before servicing' {
        Mock Invoke-OSDAppAssociationDism { throw 'must not run' }
        Mock Assert-OSDAppDefaultAssociationContext { throw 'existing policy fixture' }
        $result=Invoke-OSDAppDefaultAssociationConfiguration -Configuration $script:config -WorkDirectory $TestDrive
        $result.Status | Should -Be Failed
        $result.Error | Should -Match 'existing policy'
        $script:config.Associations=@(New-AssociationFixture -Id 'invalid:')
        { Invoke-OSDAppDefaultAssociationConfiguration -Configuration $script:config -WorkDirectory $TestDrive } | Should -Throw
        Should -Invoke Invoke-OSDAppAssociationDism -Exactly 0
    }
    It 'uses the real read-only DISM export with a spaced Unicode output path' {
        $folder=Join-Path $TestDrive ('Native export ' + [char]0x00e9)
        New-Item -ItemType Directory -Path $folder | Out-Null
        $path=Join-Path $folder 'Baseline.xml'
        $result=Invoke-OSDAppAssociationDism -Action Export -XmlPath $path -LogPath (Join-Path $folder 'Export.log')
        $result.ExitCode | Should -Be 0 -Because $result.StandardOutput
        @(Read-OSDAppDefaultAssociationsXml -Path $path).Count | Should -BeGreaterThan 0
    }
    It 'dispatches a standalone runtime through PreInstall and Runner without mutating CI defaults' {
        InModuleScope OSDApps {
            Mock Test-OSDAppWinPE { $true }
            $target=Join-Path $TestDrive 'Runner Windows'
            New-Item -ItemType Directory -Path $target | Out-Null
            $results=Join-Path $TestDrive 'Runner Results'
            Set-OSDAppConfiguration -ResultPath (Join-Path $results 'Latest.json') -LogPath (Join-Path $TestDrive 'Runner.log') -PreventSleep $false -CleanupMode Never
            try {
                Add-OSDAppDefaultAssociation -Identifier '.pdf' -ProgId Example.Pdf -AppName Example -WindowsPath $target | Out-Null
                $stage=Join-Path $target 'Windows\Temp\OSDApps'
                & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $stage 'Invoke-OSDAppPreInstall.ps1') -StagedPath $stage
                $LASTEXITCODE | Should -Be 0
                # CI runs as an admin user, not SYSTEM. Production context guard must reject import.
                & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $stage 'Invoke-OSDAppRunner.ps1') -StagedPath $stage
                $LASTEXITCODE | Should -Be 1
                $latest=Get-Content (Join-Path $results 'Latest.json') -Raw | ConvertFrom-Json
                $latest.Apps[0].Id | Should -Be DefaultAssociations
                $report=Get-Content (Join-Path $results 'DefaultAssociations-Result.json') -Raw | ConvertFrom-Json
                $report.DeploymentId | Should -Be $latest.DeploymentId
                $report.Error | Should -Match 'SYSTEM'
                $report.Import | Should -BeNullOrEmpty
                Add-Content (Join-Path $stage 'BuiltIn\DefaultAssociations\config.json') 'tampered'
                & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $stage 'Invoke-OSDAppRunner.ps1') -StagedPath $stage
                $LASTEXITCODE | Should -Be 1
                (Get-Content (Join-Path $TestDrive 'Runner.log') -Raw) | Should -Match 'HashMismatch|integrity failed'
            }
            finally {
                Set-OSDAppConfiguration -ResultPath '%ProgramData%\OSDApps\Results\Latest.json' -LogPath '%ProgramData%\OSDApps\Logs\Runtime.log' -PreventSleep $true
            }
        }
    }
}
