Describe 'Standalone SetupComplete PreInstall built-in signer checks' {
    BeforeAll {
        $root = Split-Path -Parent $PSScriptRoot
        $runtime = Join-Path $root 'Runtime\Invoke-OSDAppPreInstall.ps1'
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $runtime,[ref]$tokens,[ref]$errors
        )
        if (@($errors).Count -ne 0) { throw 'PreInstall script contains PowerShell parse errors.' }
        $helper = $ast.Find({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq 'Assert-PreInstallSignedPayload'
        },$true)
        if (-not $helper) { throw 'PreInstall signer verifier not found.' }
        . ([scriptblock]::Create($helper.Extent.Text))

        function Write-PreInstallLog { param([string]$Event,[string]$Message,$Data) }
    }

    It 'accepts a trusted expected publisher before allowing a cached MSI' {
        $folder = Join-Path $TestDrive 'Valid'
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
        $file = Join-Path $folder 'Package.msi'
        Set-Content -LiteralPath $file -Value 'test' -Encoding ASCII
        Mock Get-AuthenticodeSignature {
            [pscustomobject]@{
                Status='Valid'
                SignerCertificate=[pscustomobject]@{Subject='CN=Mozilla Corporation, O=Mozilla Corporation, C=US'}
            }
        }
        Mock Write-PreInstallLog { }

        { Assert-PreInstallSignedPayload -Id MozillaFirefoxEnterprise -Path $file } | Should -Not -Throw
        Should -Invoke Get-AuthenticodeSignature -Exactly 1
    }

    It 'rejects unexpected signer organizations with a valid signature status' {
        $folder = Join-Path $TestDrive 'PublisherMismatch'
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
        $file = Join-Path $folder 'Package.msi'
        Set-Content -LiteralPath $file -Value 'test' -Encoding ASCII
        Mock Get-AuthenticodeSignature {
            [pscustomobject]@{
                Status='Valid'
                SignerCertificate=[pscustomobject]@{Subject='CN=Google LLC, O=Someone Else LLC, C=US'}
            }
        }
        Mock Write-PreInstallLog { }
        { Assert-PreInstallSignedPayload -Id GoogleChromeEnterprise -Path $file } |
            Should -Throw '*publisher mismatch*'
        Should -Invoke Write-PreInstallLog -Exactly 0
    }

    It 'rejects unsigned files and an unknown built-in id' {
        $folder = Join-Path $TestDrive 'Unsigned'
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
        $file = Join-Path $folder 'Package.msi'
        Set-Content -LiteralPath $file -Value 'test' -Encoding ASCII
        Mock Get-AuthenticodeSignature {
            [pscustomobject]@{Status='NotSigned';SignerCertificate=$null}
        }
        Mock Write-PreInstallLog { }
        { Assert-PreInstallSignedPayload -Id CiscoWebex -Path $file } |
            Should -Throw '*signature validation failed*'
        { Assert-PreInstallSignedPayload -Id UnknownApp -Path $file } |
            Should -Throw '*No trusted signer policy*'
        Should -Invoke Write-PreInstallLog -Exactly 0
    }

    It 'does not perform a signature check when the intended signed file is missing' {
        $file = Join-Path $TestDrive 'does-not-exist.msi'
        Mock Get-AuthenticodeSignature { throw 'must not be called' }
        { Assert-PreInstallSignedPayload -Id GoogleChromeEnterprise -Path $file } |
            Should -Throw '*missing*'
        Should -Invoke Get-AuthenticodeSignature -Exactly 0
    }
}
