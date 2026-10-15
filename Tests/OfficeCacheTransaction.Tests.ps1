Describe 'Microsoft 365 Apps cache transaction wiring' {
    BeforeAll { $script:moduleRoot = Split-Path -Parent $PSScriptRoot }

    It 'builds and validates a complete sibling generation before replacing the public cache' {
        $sync = Get-Content -LiteralPath (Join-Path $script:moduleRoot 'Public\Sync-OSDAppMicrosoft365Apps.ps1') -Raw

        $sync | Should -Match 'osdapps-new-'
        $sync | Should -Match 'New-OSDAppOfficeDownloadConfiguration'
        $sync | Should -Match 'Test-OSDAppOfficeCacheGeneration -OfficeRoot \$transactionRoot'
        $sync.IndexOf('Test-OSDAppOfficeCacheGeneration') | Should -BeLessThan $sync.IndexOf('Move-Item -LiteralPath $root -Destination $backupRoot')
        $sync | Should -Not -Match 'Remove-OSDAppStaleOfficeCacheVersion'
    }

    It 'builds and validates a complete sibling generation before replacing the SetupComplete cache' {
        $runtime = Get-Content -LiteralPath (Join-Path $script:moduleRoot 'Runtime\Invoke-OSDAppPreInstall.ps1') -Raw

        $runtime | Should -Match 'osdapps-new-'
        $runtime | Should -Match 'Set-OfficeDownloadSourcePath'
        $runtime | Should -Match 'Test-OfficeCacheGeneration -OfficeRoot \$transactionRoot'
        $officeStart = $runtime.IndexOf("'Microsoft365Apps' {")
        $officeEnd = $runtime.IndexOf("'MicrosoftTeams' {", $officeStart)
        $officeBlock = $runtime.Substring($officeStart, $officeEnd - $officeStart)
        $officeBlock.IndexOf('Test-OfficeCacheGeneration -OfficeRoot $transactionRoot') |
            Should -BeLessThan $officeBlock.IndexOf('Move-Item -LiteralPath $acquireRoot -Destination $backupRoot')
        $runtime | Should -Not -Match 'Remove-StaleOfficeCacheVersion'
    }

    It 'rejects an inconsistent USB Office cache before staging it to Windows' {
        $staging = Get-Content -LiteralPath (Join-Path $script:moduleRoot 'Private\Add-OSDAppMicrosoft365Apps.ps1') -Raw
        $runtime = Get-Content -LiteralPath (Join-Path $script:moduleRoot 'Runtime\Invoke-OSDAppPreInstall.ps1') -Raw

        $staging | Should -Match 'Test-OSDAppOfficeCacheGeneration'
        $runtime | Should -Match 'function Test-LocalOfficeSource'
        $runtime | Should -Match 'Test-OfficeCacheGeneration -OfficeRoot \$Root'
    }
}
