Describe 'Trusted built-in publisher enforcement' {
    BeforeAll {
        $script:root = Split-Path $PSScriptRoot -Parent
        Import-Module (Join-Path $script:root 'OSDApps.psd1') -Force
    }

    It 'recognizes exact expected signer organizations, including quoted Cisco organization' {
        InModuleScope OSDApps {
            (Test-OSDAppExpectedPublisher -Id Microsoft365Apps -SignerSubject 'CN=Microsoft Corporation, O=Microsoft Corporation, C=US') | Should -BeTrue
            (Test-OSDAppExpectedPublisher -Id MicrosoftTeams -SignerSubject 'CN=Microsoft Corporation, O=Microsoft Corporation, C=US') | Should -BeTrue
            (Test-OSDAppExpectedPublisher -Id CiscoWebex -SignerSubject 'CN="Cisco Systems, Inc.", O="Cisco Systems, Inc.", L=San Jose, C=US') | Should -BeTrue
            (Test-OSDAppExpectedPublisher -Id GoogleChromeEnterprise -SignerSubject 'CN=Google LLC, O=Google LLC, C=US') | Should -BeTrue
            (Test-OSDAppExpectedPublisher -Id MozillaFirefoxEnterprise -SignerSubject 'CN=Mozilla Corporation, OU=Firefox Engineering Operations, O=Mozilla Corporation, C=US') | Should -BeTrue
        }
    }

    It 'rejects lookalike publishers and an unrelated organization despite trusted Authenticode status' {
        InModuleScope OSDApps {
            (Test-OSDAppExpectedPublisher -Id MicrosoftTeams -SignerSubject 'CN=Microsoft Corporation, O=Unrelated Vendor, C=US') | Should -BeFalse
            (Test-OSDAppExpectedPublisher -Id CiscoWebex -SignerSubject 'CN=Cisco Systems, Inc., O=Another Publisher LLC, C=US') | Should -BeFalse
            (Test-OSDAppExpectedPublisher -Id GoogleChromeEnterprise -SignerSubject 'CN=Google LLC, OU=Google LLC, O=Unrelated Vendor') | Should -BeFalse
            (Test-OSDAppExpectedPublisher -Id MozillaFirefoxEnterprise -SignerSubject 'CN=Mozilla Corporation, O=Mozilla Corporation Fake, C=US') | Should -BeFalse
            (Test-OSDAppExpectedPublisher -Id UnknownApp -SignerSubject 'CN=Unknown, O=Unknown') | Should -BeFalse
        }
    }

    It 'exposes PublisherMismatch as distinct from signature Invalid' {
        InModuleScope OSDApps {
            $dir = Join-Path $TestDrive 'Installer'
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
            $file = Join-Path $dir 'Package.msi'
            Set-Content -LiteralPath $file -Value 'fake bytes' -Encoding ASCII
            Mock Test-OSDAppWinPE { $false }
            Mock Get-AuthenticodeSignature {
                [pscustomobject]@{
                    Status='Valid'; StatusMessage='Signature valid'
                    SignerCertificate=[pscustomobject]@{Subject='CN=Someone, O=Unrelated Vendor LLC, C=US'}
                }
            }
            $result = Get-OSDAppBuiltInSignature -Id GoogleChromeEnterprise -FilePath $file -CheckPublisher
            $result.Status | Should -Be 'PublisherMismatch'
            $result.ExpectedPublisher | Should -Be 'Google LLC'
            $result.PublisherMatches | Should -BeFalse
            { Assert-OSDAppBuiltInSignature -Id GoogleChromeEnterprise -FilePath $file } |
                Should -Throw '*PublisherMismatch*'
        }
    }

    It 'accepts a valid expected publisher and fails closed on unsigned payloads' {
        InModuleScope OSDApps {
            $dir = Join-Path $TestDrive 'Trusted'
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
            $file = Join-Path $dir 'Package.msi'
            Set-Content -LiteralPath $file -Value 'test bytes' -Encoding ASCII
            Mock Test-OSDAppWinPE { $false }
            Mock Get-AuthenticodeSignature {
                [pscustomobject]@{
                    Status='Valid';StatusMessage='Trusted'
                    SignerCertificate=[pscustomobject]@{Subject='CN=Google LLC, O=Google LLC, C=US'}
                }
            }
            $valid = Assert-OSDAppBuiltInSignature -Id GoogleChromeEnterprise -FilePath $file
            $valid.Status | Should -Be 'Valid'
            $valid.PublisherMatches | Should -BeTrue

            Mock Get-AuthenticodeSignature {
                [pscustomobject]@{Status='NotSigned';StatusMessage='Unsigned';SignerCertificate=$null}
            }
            { Assert-OSDAppBuiltInSignature -Id GoogleChromeEnterprise -FilePath $file } |
                Should -Throw '*NotSigned*'
        }
    }

    It 'preserves previously cached MSI when a new download fails trust validation' {
        InModuleScope OSDApps {
            $dir = Join-Path $TestDrive 'Protected'
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
            $path = Join-Path $dir 'Package.msi'
            'original trusted installer' | Set-Content -LiteralPath $path -Encoding ASCII
            $originalHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
            Mock Test-OSDAppWinPE { $false }
            Mock Save-OSDAppDownload {
                Set-Content -LiteralPath $DestinationPath -Value 'suspicious download' -Encoding ASCII
            }
            Mock Assert-OSDAppBuiltInSignature { throw 'PublisherMismatch' }

            { Save-OSDAppVerifiedBuiltInDownload -Id GoogleChromeEnterprise -Uri ([uri]'https://example.org/package.msi') -DestinationPath $path -Activity 'Test' } |
                Should -Throw '*PublisherMismatch*'
            (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash | Should -Be $originalHash
            @((Get-ChildItem -LiteralPath $dir -File)).Count | Should -Be 1
        }
    }

    It 'promotes only a validated new candidate and removes temporary files' {
        InModuleScope OSDApps {
            $dir = Join-Path $TestDrive 'Promotion'
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
            $path = Join-Path $dir 'Package.msi'
            'old installer' | Set-Content -LiteralPath $path -Encoding ASCII
            Mock Test-OSDAppWinPE { $false }
            Mock Save-OSDAppDownload {
                Set-Content -LiteralPath $DestinationPath -Value 'trusted update' -Encoding ASCII
            }
            Mock Assert-OSDAppBuiltInSignature {
                [pscustomobject]@{Status='Valid';PublisherMatches=$true}
            }
            $result = Save-OSDAppVerifiedBuiltInDownload -Id GoogleChromeEnterprise -Uri ([uri]'https://example.org/package.msi') -DestinationPath $path -Activity 'Test'
            $result.SignatureVerified | Should -BeTrue
            (Get-Content -LiteralPath $path -Raw) | Should -Match 'trusted update'
            @((Get-ChildItem -LiteralPath $dir -File)).Count | Should -Be 1
            Should -Invoke Assert-OSDAppBuiltInSignature -Exactly 1
        }
    }

    It 'uses security checks in all signable full-Windows sync paths' {
        $root = Split-Path -Parent $PSScriptRoot
        foreach ($id in @('GoogleChromeEnterprise','CiscoWebex','MozillaFirefoxEnterprise','MicrosoftTeams','Microsoft365Apps')) {
            $path = Join-Path $root "Public\Sync-OSDApp$id.ps1"
            $source = Get-Content -LiteralPath $path -Raw
            $source | Should -Match 'Save-OSDAppVerifiedBuiltInDownload'
            $source | Should -Match 'Assert-OSDAppBuiltInSignature'
        }
    }

    It 'guards SetupComplete downloads, offline fallback and vendor MSI staging' {
        $root = Split-Path -Parent $PSScriptRoot
        $runtime = Get-Content -LiteralPath (Join-Path $root 'Runtime\Invoke-OSDAppPreInstall.ps1') -Raw
        $runtime | Should -Match 'function Assert-PreInstallSignedPayload'
        $runtime | Should -Match 'BuiltInSignatureVerified'
        $runtime | Should -Match 'Assert-PreInstallSignedPayload -Id \$id -Path \$tempPackage'
        $runtime | Should -Match 'Assert-PreInstallSignedPayload -Id ''Microsoft365Apps'' -Path \$setupPath'
        $runtime | Should -Match 'Assert-PreInstallSignedPayload -Id ''MicrosoftTeams'' -Path \$tempBootstrapper'
        $runtime | Should -Match 'Expected \x27\$expected\x27'
    }
}
