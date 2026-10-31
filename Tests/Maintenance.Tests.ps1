Describe 'Read-only maintenance tool' {
    BeforeAll {
        $script:root = Split-Path $PSScriptRoot -Parent
        $script:tool = Join-Path $root 'tools/Test-OSDStageMaintenance.ps1'
        function Find-Module { [CmdletBinding()] param($Name,$RequiredVersion,$Repository) }
        function Get-Volume { [CmdletBinding()] param() }
        function Save-ResultFixture {
            $script:result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $script:resultPath -Encoding UTF8
        }
    }
    AfterAll {
        Remove-Variable -Name 'OSDStageMaintenanceTest*' -Scope Global -ErrorAction SilentlyContinue
    }
    BeforeEach {
        $script:resultPath = Join-Path $TestDrive 'Latest.json'
        $script:result = [ordered]@{
            SchemaVersion='2.0'; Status='Succeeded'; DeploymentId='fixture-deployment'
            ExpectedPackageCount=1; SuccessfulPackageCount=1; FailedPackageCount=0; SkippedPackageCount=0
            Packages=@([pscustomobject]@{ Id='AppA'; Status='Succeeded' })
        }
        $global:OSDStageMaintenanceTestciConclusion = 'success'
        $global:OSDStageMaintenanceTestpublishConclusion = 'success'
        $global:OSDStageMaintenanceTestrunStatus = 'completed'
        $global:OSDStageMaintenanceTestreleaseUnavailable = $false
        Mock Find-Module { [pscustomobject]@{ Version='0.42.0' } }
        Mock Get-Volume { @() }
        Mock Invoke-RestMethod {
            if ($global:OSDStageMaintenanceTestreleaseUnavailable) { throw 'Network unavailable' }
            if ($Uri -match '/releases/') { return [pscustomobject]@{ tag_name='v0.42.0'; draft=$false; prerelease=$false; html_url='https://example.test/release' } }
            if ($Uri -match '/commits/') { return [pscustomobject]@{ sha=('a' * 40) } }
            if ($Uri -match '/actions/workflows/') {
                if ($Uri -notmatch ('head_sha=' + ('a' * 40))) { throw 'Workflow query must target the release commit.' }
                $conclusion = if ($Uri -match 'ci.yml') { $global:OSDStageMaintenanceTestciConclusion } else { $global:OSDStageMaintenanceTestpublishConclusion }
                return [pscustomobject]@{ workflow_runs=@([pscustomobject]@{ status=$global:OSDStageMaintenanceTestrunStatus; conclusion=$conclusion; html_url='https://example.test/run' }) }
            }
            throw "Unexpected request: $Uri"
        }
    }
    It 'parses without PowerShell syntax errors' {
        $tokens=$null; $errors=$null
        [void][Management.Automation.Language.Parser]::ParseFile($tool,[ref]$tokens,[ref]$errors)
        @($errors).Count | Should -Be 0
    }
    It 'accepts complete older results without requiring new acquisition fields' {
        Save-ResultFixture
        $report = & $tool -Mode Result -ResultPath $resultPath -DeploymentId fixture-deployment
        $report.Status | Should -Be Passed
        $report.Details.Result.Packages.Count | Should -Be 1
    }
    It 'reports successful installation with acquisition fallback as review required' {
        $result.Packages[0] | Add-Member NoteProperty AcquisitionOutcome FallbackCacheUsed
        Save-ResultFixture
        $report = & $tool -Mode Result -ResultPath $resultPath
        $report.Status | Should -Be ReviewRequired
        $report.Passed | Should -BeFalse
    }
    It 'does not report unfinished or empty deployments as passed' {
        $result.Status='Running'; Save-ResultFixture
        (& $tool -Mode Result -ResultPath $resultPath).Status | Should -Be ReviewRequired
        $result.Status='Succeeded'; $result.Packages=@(); $result.ExpectedPackageCount=0; $result.SuccessfulPackageCount=0
        Save-ResultFixture
        (& $tool -Mode Result -ResultPath $resultPath).Status | Should -Be ReviewRequired
    }
    It 'rejects failed, contradictory and incorrectly identified results' {
        $result.Status='Failed'; Save-ResultFixture
        (& $tool -Mode Result -ResultPath $resultPath).Status | Should -Be Failed
        $result.Status='Succeeded'; $result.SuccessfulPackageCount=2; Save-ResultFixture
        (& $tool -Mode Result -ResultPath $resultPath).Status | Should -Be Failed
        $result.SuccessfulPackageCount=1; Save-ResultFixture
        (& $tool -Mode Result -ResultPath $resultPath -DeploymentId another-deployment).Status | Should -Be Failed
    }
    It 'rejects missing fields and duplicate app identities' {
        $result.Remove('SchemaVersion'); Save-ResultFixture
        (& $tool -Mode Result -ResultPath $resultPath).Status | Should -Be Failed
        $result.SchemaVersion='2.0'; $result.Packages += $result.Packages[0]
        $result.SuccessfulPackageCount=2; $result.ExpectedPackageCount=2; Save-ResultFixture
        (& $tool -Mode Result -ResultPath $resultPath).Status | Should -Be Failed
    }
    It 'passes release checks only with exact Gallery version and successful release-commit workflows' {
        $report = & $tool -Mode Release -ExpectedVersion 0.42.0
        $report.Status | Should -Be Passed
        $report.Details.ReleaseCommit | Should -Be ('a' * 40)
        Should -Invoke Find-Module -Times 1 -Exactly -ParameterFilter { $RequiredVersion -eq '0.42.0' -and $Repository -eq 'PSGallery' }
        Should -Invoke Invoke-RestMethod -Times 4 -Exactly -ParameterFilter { $TimeoutSec -eq 30 }
    }
    It 'does not hide a failed publishing workflow behind Gallery visibility' {
        $global:OSDStageMaintenanceTestpublishConclusion='failure'
        (& $tool -Mode Release -ExpectedVersion 0.42.0).Status | Should -Be ReviewRequired
        { & $tool -Mode Release -ExpectedVersion 0.42.0 -ThrowOnFailure } | Should -Throw '*ReviewRequired*'
    }
    It 'reports CI failure, pending workflows and unavailable GitHub accurately' {
        $global:OSDStageMaintenanceTestciConclusion='failure'
        (& $tool -Mode Release -ExpectedVersion 0.42.0).Status | Should -Be Failed
        $global:OSDStageMaintenanceTestrunStatus='in_progress'
        (& $tool -Mode Release -ExpectedVersion 0.42.0).Status | Should -Be ReviewRequired
        $global:OSDStageMaintenanceTestreleaseUnavailable=$true
        (& $tool -Mode Release).Status | Should -Be ReviewRequired
    }
    It 'does not pass when Gallery cannot confirm the requested release' {
        Mock Find-Module { throw 'Package not yet available' }
        (& $tool -Mode Release -ExpectedVersion 0.42.0).Status | Should -Be ReviewRequired
    }
    It 'requires an explicit choice when USB autodetection is ambiguous' {
        Mock Get-Volume { @([pscustomobject]@{FileSystemLabel='OSDCloud';DriveLetter='D'},[pscustomobject]@{FileSystemLabel='OSDCloud';DriveLetter='E'}) }
        $report = & $tool -Mode Usb
        $report.Status | Should -Be Failed
        $report.Checks[0].Message | Should -BeLike '*found 2*'
    }
}

Describe 'Maintenance USB inspection with the real module' {
    BeforeAll {
        $script:root = Split-Path $PSScriptRoot -Parent
        $script:tool = Join-Path $root 'tools/Test-OSDStageMaintenance.ps1'
        $script:version = (Import-PowerShellDataFile (Join-Path $root 'OSDStage.psd1')).ModuleVersion
        $script:usb = Join-Path $TestDrive 'Usb'
        $script:moduleRoot = Join-Path $usb "Modules/OSDStage/$version"
        New-Item -ItemType Directory -Path $moduleRoot -Force | Out-Null
        foreach ($item in @('OSDStage.psd1','OSDStage.psm1','Public','Private','Runtime','metadata')) {
            Copy-Item -LiteralPath (Join-Path $root $item) -Destination $moduleRoot -Recurse
        }
        $script:cache = Join-Path $usb 'OSDStage'
        $package = Join-Path $cache 'Packages/AppA'
        New-Item -ItemType Directory -Path $package -Force | Out-Null
        $script:archive = Join-Path $package 'Package.zip'
        Set-Content -LiteralPath $archive -Value fixture-payload -Encoding ASCII
        $entry = @{ Id='AppA'; DisplayName='AppA'; Version='1.0.0'; Architecture='x64'; SuccessCodes=@(0,3010); Payload=@{FileName='Package.zip';Sha256=(Get-FileHash $archive -Algorithm SHA256).Hash} }
        @{SchemaVersion=2;GeneratedAt='2026-10-16T00:00:00Z';Packages=@($entry)} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $cache 'CacheCatalog.json') -Encoding UTF8
    }
    AfterAll {
        Remove-Module OSDStage -Force -ErrorAction SilentlyContinue
        Import-Module (Join-Path $root 'OSDStage.psd1') -Force
    }
    It 'uses existing offline health checks without modifying any USB files or creating a lock' {
        $before = @(Get-ChildItem $usb -File -Recurse | Get-FileHash -Algorithm SHA256 | ForEach-Object { "$($_.Path):$($_.Hash)" } | Sort-Object)
        $report = & $tool -Mode Usb -UsbRoot $usb -ExpectedVersion $version
        $report.Checks | Format-Table | Out-Host
        $report.Status | Should -Be Passed
        $report.Details.CacheHealth.EntryCount | Should -Be 1
        $after = @(Get-ChildItem $usb -File -Recurse | Get-FileHash -Algorithm SHA256 | ForEach-Object { "$($_.Path):$($_.Hash)" } | Sort-Object)
        @(Compare-Object $before $after).Count | Should -Be 0
    }
    It 'does not silently select an older module when a newer directory is present' {
        $newer = Join-Path $usb 'Modules/OSDStage/999.0.0'
        New-Item -ItemType Directory -Path $newer | Out-Null
        try { (& $tool -Mode Usb -UsbRoot $usb -ExpectedVersion $version).Status | Should -Be Failed }
        finally { Remove-Item $newer -Recurse -Force }
    }
    It 'reports corrupt payloads instead of repairing them' {
        Set-Content -LiteralPath $archive -Value corrupted -Encoding ASCII
        (& $tool -Mode Usb -UsbRoot $usb).Status | Should -Be Failed
        (Get-Content $archive -Raw).Trim() | Should -Be corrupted
    }
}
