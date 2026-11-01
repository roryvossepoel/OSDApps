Describe 'Current-deployment cache flags (issue 74)' {
    BeforeAll {
        $root = Split-Path $PSScriptRoot -Parent
        $script:runnerPath = Join-Path $root 'Runtime\Invoke-OSDStageRunner.ps1'
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:runnerPath,[ref]$tokens,[ref]$errors)
        if (@($errors).Count) { throw 'Runner parser errors.' }
        foreach ($name in @('Write-RunnerLog','Get-RunnerCacheInfo','New-RunnerAppResult')) {
            $definition = $ast.Find({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)
            if (-not $definition) { throw "Missing production function $name." }
            . ([scriptblock]::Create($definition.Extent.Text))
        }
    }

    BeforeEach {
        $script:StagedPath = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $cache = Join-Path $StagedPath 'BuiltIn\GoogleChromeEnterprise\x64'
        New-Item -ItemType Directory -Path $cache -Force | Out-Null
        # Reproduce the old preparation-PC sync metadata, without altering it in the fix.
        @{Updated=$true;Cached=$true;Version='1.0';Architecture='x64'} | ConvertTo-Json |
            Set-Content (Join-Path $cache 'CacheInfo.json') -Encoding UTF8
        $script:manifest = [pscustomobject]@{DeploymentId=[guid]::NewGuid().Guid}
        $script:app = [pscustomobject]@{Id='GoogleChromeEnterprise';Source='BuiltIn';Type='VendorMsi'}
        $script:entry = [pscustomobject]@{
            Id=$app.Id;Status='Succeeded';AcquisitionOutcome='CacheReused'
            CacheUsed=$false;PackageUpdated=$false;CacheDecisionReason='Current run evidence.'
        }
        $script:preInstallResult = [pscustomobject]@{DeploymentId=$manifest.DeploymentId;Packages=@($entry)}
    }

    It 'copies <Outcome> flags from the current phase, never from the stored sync' -TestCases @(
        @{Outcome='Downloaded';Updated=$true}
        @{Outcome='CacheReused';Updated=$false}
        @{Outcome='OfflineCacheUsed';Updated=$false}
        @{Outcome='FallbackCacheUsed';Updated=$false}
    ) {
        param($Outcome,$Updated)
        $entry.AcquisitionOutcome = $Outcome
        $entry.PackageUpdated = $Updated
        $result = New-RunnerAppResult -App $app -Status Succeeded
        $result.PackageUpdated | Should -BeOfType ([bool])
        $result.PackageUpdated | Should -Be $Updated
        $result.CacheUsed | Should -BeFalse
        $result.AcquisitionOutcome | Should -Be $Outcome
        $result.Version | Should -Be '1.0'
        $result.Architecture | Should -Be x64
        $saved = Get-Content (Join-Path $StagedPath 'BuiltIn\GoogleChromeEnterprise\x64\CacheInfo.json') -Raw | ConvertFrom-Json
        $saved.Updated | Should -BeTrue
        $saved.Cached | Should -BeTrue
    }

    It 'leaves both flags null for <Case> instead of reading historical cache facts' -TestCases @(
        @{Case='absent phase';Expected='Unknown'}
        @{Case='missing phase ID';Expected='Unknown'}
        @{Case='blank phase ID';Expected='Unknown'}
        @{Case='another deployment';Expected='Unknown'}
        @{Case='missing manifest ID';Expected='Unknown'}
        @{Case='missing app';Expected='Unknown'}
        @{Case='another app';Expected='Unknown'}
        @{Case='duplicate app';Expected='Unknown'}
        @{Case='missing fields';Expected='CacheReused'}
        @{Case='null fields';Expected='CacheReused'}
        @{Case='string fields';Expected='CacheReused'}
        @{Case='unknown outcome';Expected='Unknown'}
    ) {
        param($Case,$Expected)
        switch ($Case) {
            'absent phase' { $preInstallResult = $null }
            'missing phase ID' { $preInstallResult.PSObject.Properties.Remove('DeploymentId') }
            'blank phase ID' { $preInstallResult.DeploymentId = ' ' }
            'another deployment' { $preInstallResult.DeploymentId = [guid]::NewGuid().Guid }
            'missing manifest ID' { $manifest.PSObject.Properties.Remove('DeploymentId') }
            'missing app' { $preInstallResult.Packages = @() }
            'another app' { $entry.Id = 'OtherApp' }
            'duplicate app' { $preInstallResult.Packages = @($entry,$entry) }
            'missing fields' { $entry.PSObject.Properties.Remove('CacheUsed'); $entry.PSObject.Properties.Remove('PackageUpdated') }
            'null fields' { $entry.CacheUsed=$null; $entry.PackageUpdated=$null }
            'string fields' { $entry.CacheUsed='false'; $entry.PackageUpdated='false' }
            'unknown outcome' { $entry.AcquisitionOutcome='Unrecognized' }
        }
        $result = New-RunnerAppResult -App $app -Status Succeeded
        ($null -eq $result.PackageUpdated) | Should -BeTrue
        ($null -eq $result.CacheUsed) | Should -BeTrue
        $result.AcquisitionOutcome | Should -Be $Expected
    }

    It 'keeps known USB selection separate from confirmed primary reuse' {
        $entry.AcquisitionOutcome = 'Downloaded'
        $entry.PackageUpdated = $true
        $entry.CacheUsed = $true
        $result = New-RunnerAppResult -App $app -Status Failed -FailureType InstallerFailed
        $result.PackageUpdated | Should -BeTrue
        $result.CacheUsed | Should -BeTrue
        $result.AcquisitionOutcome | Should -Be Downloaded
        $result.Status | Should -Be Failed
    }

    It 'does not turn an incomplete acquisition into a successful primary update' {
        $entry.Status = 'Failed'
        $entry.AcquisitionOutcome = 'Failed'
        $entry.PackageUpdated = $true
        $result = New-RunnerAppResult -App $app -Status Skipped
        ($null -eq $result.PackageUpdated) | Should -BeTrue
        $result.AcquisitionOutcome | Should -Be Failed
    }

    It 'does not substitute a different prerequisite architecture' {
        $app.Id = 'VisualCRedist-x64'; $app.Type = 'PrerequisiteExe'
        # No file needs to be inspected for this matching test.
        Mock Get-RunnerCacheInfo { [pscustomobject]@{Updated=$true;Cached=$true} }
        $entry.Id = 'VisualCRedist-x86'
        $result = New-RunnerAppResult -App $app -Status Succeeded
        ($null -eq $result.PackageUpdated) | Should -BeTrue
        $result.AcquisitionOutcome | Should -Be Unknown
    }

    It 'reports NotApplicable for <Id>, with no invented acquisition flags' -TestCases @(
        @{Id='WindowsInboxCleanup';Type='WindowsInboxCleanupScript';Source='BuiltIn'}
        @{Id='MicrosoftCompanyPortal';Type='CompanyPortalAppxBundle';Source='BuiltIn'}
        @{Id='CMTraceOpen';Type='VendorMsi';Source='BuiltIn'}
        @{Id='RegistrySettings';Type='RepositoryPackage';Source='Repository'}
    ) {
        param($Id,$Type,$Source)
        $app.Id=$Id; $app.Type=$Type; $app.Source=$Source
        $entry.Id=$Id; $entry.CacheUsed=$true; $entry.PackageUpdated=$true
        $result = New-RunnerAppResult -App $app -Status Succeeded
        $result.AcquisitionOutcome | Should -Be NotApplicable
        ($null -eq $result.PackageUpdated) | Should -BeTrue
        ($null -eq $result.CacheUsed) | Should -BeTrue
    }

    It 'writes correctly correlated JSON from a fresh production runner for <Correlation>' -Skip:($env:OS -ne 'Windows_NT') -TestCases @(
        @{Correlation='current';Expected='CacheReused'}
        @{Correlation='missing';Expected='Unknown'}
        @{Correlation='other';Expected='Unknown'}
    ) {
        param($Correlation,$Expected)
        $stage = Join-Path $TestDrive ('Standalone-' + $Correlation)
        $payloadRoot = Join-Path $stage 'BuiltIn\VisualCRedist\x64'
        $resultPath = Join-Path $stage 'Results\Latest.json'
        $log = Join-Path $stage 'Logs\Runtime.log'
        New-Item -ItemType Directory -Path $payloadRoot,(Split-Path $resultPath -Parent) -Force | Out-Null
        $payload = Join-Path $payloadRoot 'VC_redist.x64.exe'
        [IO.File]::WriteAllText($payload,'original fixture',[Text.Encoding]::ASCII)
        $hash = (Get-FileHash $payload -Algorithm SHA256).Hash
        $size = (Get-Item $payload).Length
        @{Id='VisualCRedist';Architecture='x64';PayloadFileName='VC_redist.x64.exe';Sha256=$hash;Size=$size;Cached=$true;Updated=$true} |
            ConvertTo-Json | Set-Content (Join-Path $payloadRoot 'CacheInfo.json') -Encoding UTF8
        $id = [guid]::NewGuid().Guid
        @{
            SchemaVersion=2;DeploymentId=$id
            Runtime=@{CleanupMode='Never';PreventSleep=$false;ResultPath=$resultPath;LogPath=$log}
            Packages=@(@{
                Id='VisualCRedist-x64';Source='BuiltIn';Type='PrerequisiteExe';PackageType='App'
                Family='VisualCRedist';Architecture='x64';RuntimeType='Runtime';Channel='14'
                PayloadRoot='BuiltIn\VisualCRedist\x64';PayloadExtension='.exe';PayloadSha256=$hash
                Package='BuiltIn\VisualCRedist\x64\VC_redist.x64.exe'
            })
        } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $stage 'DeviceManifest.json') -Encoding UTF8
        $phase = @{
            Phase='PreInstall';Status='Succeeded';DeploymentId=$id
            Packages=@(@{Id='VisualCRedist-x64';Status='Succeeded';AcquisitionOutcome='CacheReused';PackageUpdated=$false;CacheUsed=$false})
        }
        if ($Correlation -eq 'missing') { $phase.Remove('DeploymentId') }
        if ($Correlation -eq 'other') { $phase.DeploymentId=[guid]::NewGuid().Guid }
        $phase | ConvertTo-Json -Depth 10 | Set-Content (Join-Path (Split-Path $resultPath -Parent) 'PreInstall.json') -Encoding UTF8
        # Intentionally invalid bytes stop at real integrity validation, before any installer.
        [IO.File]::WriteAllText($payload,'tampered fixture, not an executable',[Text.Encoding]::ASCII)
        $start = [Diagnostics.ProcessStartInfo]::new()
        $start.FileName = (Get-Process -Id $PID).Path
        $start.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -StagedPath "{1}"' -f $script:runnerPath,$stage
        $start.UseShellExecute=$false; $start.CreateNoWindow=$true
        $start.RedirectStandardOutput=$true; $start.RedirectStandardError=$true
        $child=[Diagnostics.Process]::new(); $child.StartInfo=$start
        $started=$false
        try {
            $started=$child.Start()
            if (-not $started) { throw 'Runner did not start.' }
            $stdout=$child.StandardOutput.ReadToEndAsync(); $stderr=$child.StandardError.ReadToEndAsync()
            if (-not $child.WaitForExit(30000)) { $child.Kill(); throw 'Reporting runner timed out.' }
            if (-not [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdout,$stderr),5000)) { throw 'Runner output timeout.' }
            [IO.File]::WriteAllText((Join-Path $stage 'stdout.txt'),$stdout.Result)
            [IO.File]::WriteAllText((Join-Path $stage 'stderr.txt'),$stderr.Result)
            $child.ExitCode | Should -Be 1
        }
        finally { if ($started -and -not $child.HasExited) { $child.Kill() }; $child.Dispose() }
        $result=Get-Content $resultPath -Raw | ConvertFrom-Json
        $result.DeploymentId | Should -Be $id
        $result.Packages[0].FailureType | Should -Be HashMismatch
        $result.Packages[0].AcquisitionOutcome | Should -Be $Expected
        if ($Correlation -eq 'current') {
            $result.Packages[0].PackageUpdated | Should -BeFalse
            $result.Packages[0].CacheUsed | Should -BeFalse
            $result.PreInstall.DeploymentId | Should -Be $id
        } else {
            ($null -eq $result.Packages[0].PackageUpdated) | Should -BeTrue
            ($null -eq $result.Packages[0].CacheUsed) | Should -BeTrue
            $result.PreInstall | Should -BeNullOrEmpty
            (Get-Content $log -Raw) | Should -Match 'PreInstallResultIgnored'
        }
        (Get-Content $log -Raw) | Should -Not -Match '\[BuiltInInstallStart\]'
    }
}
