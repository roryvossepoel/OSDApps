Describe 'Standalone PreInstall retired Teams cache cleanup' {
    BeforeAll {
        . (Join-Path (Split-Path $PSScriptRoot -Parent) 'Runtime/OSDAppPayloadFile.ps1')
        $root = Split-Path -Parent $PSScriptRoot
        $runtimePath = Join-Path $root 'Runtime\Invoke-OSDAppPreInstall.ps1'
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $runtimePath,[ref]$tokens,[ref]$parseErrors
        )
        if (@($parseErrors).Count -ne 0) { throw 'PreInstall script contains PowerShell parse errors.' }

        foreach ($functionName in @('Test-LocalMicrosoftTeamsSource','Remove-LegacyMicrosoftTeamsCache')) {
            $helper = $ast.Find({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq $functionName
            },$true)
            if (-not $helper) { throw "PreInstall helper '$functionName' was not found." }
            . ([scriptblock]::Create($helper.Extent.Text))
        }

        function Assert-PreInstallSignedPayload { param([string]$Id,[string]$Path) }
        function Write-PreInstallLog { param([string]$Event,[string]$Level,[string]$Message,$Data) }
    }

    It 'removes the retired folder after validating a complete canonical cache' {
        $usbRoot = Join-Path $TestDrive 'CompleteUsb'
        $canonical = Join-Path $usbRoot 'BuiltIn\MicrosoftTeams'
        $legacy = Join-Path $usbRoot 'BuiltIn\Teams'
        New-Item -ItemType Directory -Path $canonical,$legacy -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $canonical 'teamsbootstrapper.exe') -Value 'bootstrapper' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $canonical 'teams.msix') -Value 'msix' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $legacy 'legacy.bin') -Value 'legacy' -Encoding ASCII
        Mock Assert-PreInstallSignedPayload { }
        Mock Write-PreInstallLog { }

        { Remove-LegacyMicrosoftTeamsCache -UsbRoot $usbRoot -CanonicalRoot $canonical } | Should -Not -Throw

        (Test-Path -LiteralPath $legacy) | Should -BeFalse
        Should -Invoke Assert-PreInstallSignedPayload -Exactly 1 -ParameterFilter { $Id -eq 'MicrosoftTeams' }
        Should -Invoke Write-PreInstallLog -Exactly 1 -ParameterFilter { $Event -eq 'CacheAliasPruned' }
    }

    It 'preserves the retired folder when canonical content is incomplete' {
        $usbRoot = Join-Path $TestDrive 'IncompleteUsb'
        $canonical = Join-Path $usbRoot 'BuiltIn\MicrosoftTeams'
        $legacy = Join-Path $usbRoot 'BuiltIn\Teams'
        New-Item -ItemType Directory -Path $canonical,$legacy -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $canonical 'teamsbootstrapper.exe') -Value 'bootstrapper' -Encoding ASCII
        Mock Assert-PreInstallSignedPayload { throw 'must not run' }
        Mock Write-PreInstallLog { }

        Remove-LegacyMicrosoftTeamsCache -UsbRoot $usbRoot -CanonicalRoot $canonical

        (Test-Path -LiteralPath $legacy -PathType Container) | Should -BeTrue
        Should -Invoke Assert-PreInstallSignedPayload -Exactly 0
        Should -Invoke Write-PreInstallLog -Exactly 0
    }

    It 'logs and preserves the retired folder when canonical validation fails' {
        $usbRoot = Join-Path $TestDrive 'RejectedUsb'
        $canonical = Join-Path $usbRoot 'BuiltIn\MicrosoftTeams'
        $legacy = Join-Path $usbRoot 'BuiltIn\Teams'
        New-Item -ItemType Directory -Path $canonical,$legacy -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $canonical 'teamsbootstrapper.exe') -Value 'bootstrapper' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $canonical 'teams.msix') -Value 'msix' -Encoding ASCII
        Mock Assert-PreInstallSignedPayload { throw 'rejected canonical bootstrapper' }
        Mock Write-PreInstallLog { }

        { Remove-LegacyMicrosoftTeamsCache -UsbRoot $usbRoot -CanonicalRoot $canonical } | Should -Not -Throw

        (Test-Path -LiteralPath $legacy -PathType Container) | Should -BeTrue
        Should -Invoke Write-PreInstallLog -Exactly 1 -ParameterFilter {
            $Event -eq 'CacheAliasPruneFailed' -and $Level -eq 'Warning'
        }
    }
}
