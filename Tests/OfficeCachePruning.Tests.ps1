Describe 'Microsoft 365 Apps stale cache version pruning' {
    BeforeAll {
        $script:moduleRoot = Split-Path -Parent $PSScriptRoot
        . (Join-Path $script:moduleRoot 'Private\Remove-OSDAppStaleOfficeCacheVersion.ps1')
    }

    It 'keeps the active version and removes only stale version directories' {
        $root = Join-Path $TestDrive 'OfficeCache'
        $data = Join-Path $root 'Office\Data'
        $active = Join-Path $data '16.0.20430.20146'
        $old = Join-Path $data '16.0.20326.20142'
        $other = Join-Path $data 'Telemetry'
        New-Item -ItemType Directory -Path $active,$old,$other -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $active 'stream.dat') -Value 'active'
        Set-Content -LiteralPath (Join-Path $old 'stream.dat') -Value 'old'
        Set-Content -LiteralPath (Join-Path $other 'keep.dat') -Value 'keep'

        $removed = @(Remove-OSDAppStaleOfficeCacheVersion -OfficeRoot $root -ActiveVersion '16.0.20430.20146')

        $removed.Count | Should -Be 1
        $removed[0] | Should -Be '16.0.20326.20142'
        Test-Path -LiteralPath $active | Should -BeTrue
        Test-Path -LiteralPath $old | Should -BeFalse
        Test-Path -LiteralPath $other | Should -BeTrue
    }

    It 'refuses to prune when the active version is missing or empty' {
        $root = Join-Path $TestDrive 'InvalidOfficeCache'
        $old = Join-Path $root 'Office\Data\16.0.20326.20142'
        New-Item -ItemType Directory -Path $old -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $old 'stream.dat') -Value 'old'

        { Remove-OSDAppStaleOfficeCacheVersion -OfficeRoot $root -ActiveVersion '16.0.20430.20146' } |
            Should -Throw '*Active Office cache version folder is missing*'
        Test-Path -LiteralPath $old | Should -BeTrue

        $active = Join-Path $root 'Office\Data\16.0.20430.20146'
        New-Item -ItemType Directory -Path $active -Force | Out-Null
        { Remove-OSDAppStaleOfficeCacheVersion -OfficeRoot $root -ActiveVersion '16.0.20430.20146' } |
            Should -Throw '*contains no files*'
        Test-Path -LiteralPath $old | Should -BeTrue
    }

    It 'wires pruning after successful metadata commit in both sync paths' {
        $sync = Get-Content -LiteralPath (Join-Path $script:moduleRoot 'Public\Sync-OSDAppMicrosoft365Apps.ps1') -Raw
        $runtime = Get-Content -LiteralPath (Join-Path $script:moduleRoot 'Runtime\Invoke-OSDAppPreInstall.ps1') -Raw

        $sync.IndexOf('Set-Content -LiteralPath $cacheInfoPath') | Should -BeLessThan $sync.IndexOf('Remove-OSDAppStaleOfficeCacheVersion')
        $runtime.IndexOf('$cacheInfo | ConvertTo-Json') | Should -BeLessThan $runtime.LastIndexOf('Remove-StaleOfficeCacheVersion -OfficeRoot $acquireRoot')
        $runtime | Should -Match "Event 'OfficeCacheVersionPruned'"
    }
}
