Describe 'All-app cold validation result boundaries' {
    BeforeAll {
        $script:testScript = Join-Path (Split-Path $PSScriptRoot -Parent) 'tools/Test-OSDAppsAllApps.ps1'
        $script:originalProgramData = $env:ProgramData
        $script:originalSystemRoot = $env:SystemRoot
        $env:ProgramData = Join-Path $TestDrive 'ProgramData'
        $env:SystemRoot = Join-Path $TestDrive 'Windows'
        $script:results = Join-Path $env:ProgramData 'OSDApps/Results'
        $script:records = Join-Path $env:ProgramData 'OSDApps/Tests'
        New-Item -ItemType Directory -Path $script:results,$script:records,(Join-Path $env:SystemRoot 'Temp') -Force | Out-Null
        $script:builtIns = @('Microsoft365Apps','MicrosoftTeams','GoogleChromeEnterprise','MozillaFirefoxEnterprise','CiscoWebex','AdobeAcrobatUnified','ZoomWorkplace')
        $script:allIds = @($script:builtIns) + @('NotepadPlusPlus','OmnissaHorizonClient')
        function Write-FixtureRecord { param($Object,$Path) $Object | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8 }
    }
    AfterAll {
        $env:ProgramData = $script:originalProgramData
        $env:SystemRoot = $script:originalSystemRoot
    }
    BeforeEach {
        Mock Test-Path { [IO.Directory]::Exists([string]$Path) -or [IO.File]::Exists([string]$Path) }
        Mock Test-Path { $false } -ParameterFilter { $Path -eq 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT' }
        Mock Write-Host { }
        $script:pre = [pscustomobject]@{
            DeploymentId='fixture-deployment'; Status='Succeeded'; DurationSeconds=100
            Applications=@($script:builtIns | ForEach-Object { [pscustomobject]@{Id=$_;Status='Succeeded';AcquisitionOutcome='Downloaded';RefreshError=$null} })
        }
        $script:runner = [pscustomobject]@{
            DeploymentId='fixture-deployment'; Status='Succeeded'; DurationSeconds=200
            FailedApplicationCount=0; SkippedApplicationCount=0
            Applications=@($script:allIds | ForEach-Object { [pscustomobject]@{Id=$_;Status='Succeeded';ExitCode=0} })
        }
        Write-FixtureRecord ([pscustomobject]@{DeploymentId='fixture-deployment';ModuleVersion='0.45.0';TestMode='Cold';PreviousCacheBackup='E:\OSDApps-Backup-fixture'}) (Join-Path $script:records 'AllApps-Staging.json')
        Write-FixtureRecord $script:pre (Join-Path $script:results 'PreInstall.json')
        Write-FixtureRecord $script:runner (Join-Path $script:results 'Latest.json')
    }
    It 'accepts one correlated cold run with all nine successful applications and cleanup' {
        { & $script:testScript -Phase Validate | Out-Null } | Should -Not -Throw
        Should -Invoke Write-Host -Exactly -Times 1 -ParameterFilter { $Object -eq 'ALL APPS COLD OOBE VALIDATION PASSED!' }
    }
    It 'rejects a successful fallback instead of reporting a cold download pass' {
        $script:pre.Applications[0].AcquisitionOutcome = 'FallbackCacheUsed'
        Write-FixtureRecord $script:pre (Join-Path $script:results 'PreInstall.json')
        { & $script:testScript -Phase Validate | Out-Null } | Should -Throw '*Cold acquisition was not confirmed*'
        Should -Invoke Write-Host -Exactly -Times 0 -ParameterFilter { $Object -eq 'ALL APPS COLD OOBE VALIDATION PASSED!' }
    }
    It 'rejects results belonging to a previous deployment' {
        $script:runner.DeploymentId = 'previous-deployment'
        Write-FixtureRecord $script:runner (Join-Path $script:results 'Latest.json')
        { & $script:testScript -Phase Validate | Out-Null } | Should -Throw '*belongs to another deployment*'
    }
    It 'rejects duplicated entries even when every entry reports success' {
        $script:runner.Applications[8].Id = $script:runner.Applications[7].Id
        Write-FixtureRecord $script:runner (Join-Path $script:results 'Latest.json')
        { & $script:testScript -Phase Validate | Out-Null } | Should -Throw '*expected application IDs*'
    }
    It 'rejects a missing failed-application counter under StrictMode' {
        $script:runner.PSObject.Properties.Remove('FailedApplicationCount')
        Write-FixtureRecord $script:runner (Join-Path $script:results 'Latest.json')
        { & $script:testScript -Phase Validate | Out-Null } | Should -Throw '*Unexpected result counter*'
    }
    It 'refuses staging on the preparation PC before any cache rename' {
        Mock Rename-Item { throw 'A cache rename must not be attempted.' }
        { & $script:testScript -Phase Stage -CatalogUri 'https://example.invalid/catalog.json' | Out-Null } | Should -Throw '*Run Stage in WinPE*'
        Should -Invoke Rename-Item -Exactly -Times 0
    }
}
