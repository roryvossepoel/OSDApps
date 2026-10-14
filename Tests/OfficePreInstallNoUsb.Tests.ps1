Describe 'Microsoft 365 Apps PreInstall configuration handling' {
    BeforeAll {
        $runtimePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Runtime\Invoke-OSDAppPreInstall.ps1'
        $tokens = $null
        $parseErrors = $null
        $runtimeAst = [System.Management.Automation.Language.Parser]::ParseFile(
            $runtimePath,
            [ref]$tokens,
            [ref]$parseErrors
        )
        if (@($parseErrors).Count -ne 0) { throw 'PreInstall runtime has PowerShell parse errors.' }

        # Load only the real runtime helper; do not start PreInstall during unit tests.
        $helperAst = $runtimeAst.Find({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq 'Copy-OfficeConfigurationToCache'
        }, $true)
        if (-not $helperAst) { throw 'Office configuration copy helper is missing from PreInstall.' }

        . ([scriptblock]::Create($helperAst.Extent.Text))
    }

    It 'keeps the same local configuration file unchanged when USB cache is absent' {
        $officeDir = Join-Path $TestDrive 'BuiltIn\Microsoft365Apps'
        New-Item -ItemType Directory -Path $officeDir -Force | Out-Null
        $config = Join-Path $officeDir 'configuration.xml'
        Set-Content -LiteralPath $config -Value '<Configuration id="offline" />' -Encoding UTF8

        { Copy-OfficeConfigurationToCache -LocalConfig $config -AcquireConfig $config } | Should -Not -Throw
        Get-Content -LiteralPath $config -Raw | Should -Match 'id="offline"'
    }

    It 'copies the configuration from local staging to a distinct cache location' {
        $localDir = Join-Path $TestDrive 'Local'
        $usbDir = Join-Path $TestDrive 'Usb'
        New-Item -ItemType Directory -Path $localDir,$usbDir -Force | Out-Null
        $localConfig = Join-Path $localDir 'configuration.xml'
        $usbConfig = Join-Path $usbDir 'configuration.xml'
        Set-Content -LiteralPath $localConfig -Value '<Configuration id="latest" />' -Encoding UTF8
        Set-Content -LiteralPath $usbConfig -Value '<Configuration id="old" />' -Encoding UTF8

        Copy-OfficeConfigurationToCache -LocalConfig $localConfig -AcquireConfig $usbConfig
        Get-Content -LiteralPath $usbConfig -Raw | Should -Match 'id="latest"'
        Get-Content -LiteralPath $localConfig -Raw | Should -Match 'id="latest"'
    }

    It 'uses an isolated generation configuration in the Office PreInstall acquisition route' {
        $runtime = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'Runtime\Invoke-OSDAppPreInstall.ps1') -Raw
        $runtime | Should -Match 'Set-OfficeDownloadSourcePath -SourcePath \$localConfig -DestinationPath \$downloadConfig'
        $runtime | Should -Match 'Test-OfficeCacheGeneration -OfficeRoot \$transactionRoot'
        [regex]::IsMatch($runtime, 'Copy-OfficeConfigurationToCache -LocalConfig \$localConfig -AcquireConfig \$acquireConfig') | Should -BeFalse
    }
}
