BeforeAll { . (Join-Path $PSScriptRoot 'Helpers/NativePayloadFixtures.ps1') }
Describe 'Trusted built-in publisher enforcement' {
    BeforeAll {
        $script:root = Split-Path $PSScriptRoot -Parent
        Import-Module (Join-Path $script:root 'OSDStage.psd1') -Force
    }

    It 'recognizes exact expected signer organizations, including quoted Cisco organization' {
        InModuleScope OSDStage {
            (Test-OSDStageExpectedPublisher -Id Microsoft365Apps -SignerSubject 'CN=Microsoft Corporation, O=Microsoft Corporation, C=US') | Should -BeTrue
            (Test-OSDStageExpectedPublisher -Id MicrosoftTeams -SignerSubject 'CN=Microsoft Corporation, O=Microsoft Corporation, C=US') | Should -BeTrue
            (Test-OSDStageExpectedPublisher -Id CiscoWebex -SignerSubject 'CN="Cisco Systems, Inc.", O="Cisco Systems, Inc.", L=San Jose, C=US') | Should -BeTrue
            (Test-OSDStageExpectedPublisher -Id GoogleChromeEnterprise -SignerSubject 'CN=Google LLC, O=Google LLC, C=US') | Should -BeTrue
            (Test-OSDStageExpectedPublisher -Id MozillaFirefoxEnterprise -SignerSubject 'CN=Mozilla Corporation, OU=Firefox Engineering Operations, O=Mozilla Corporation, C=US') | Should -BeTrue
        }
    }

    It 'rejects lookalike publishers and an unrelated organization despite trusted Authenticode status' {
        InModuleScope OSDStage {
            (Test-OSDStageExpectedPublisher -Id MicrosoftTeams -SignerSubject 'CN=Microsoft Corporation, O=Unrelated Vendor, C=US') | Should -BeFalse
            (Test-OSDStageExpectedPublisher -Id CiscoWebex -SignerSubject 'CN=Cisco Systems, Inc., O=Another Publisher LLC, C=US') | Should -BeFalse
            (Test-OSDStageExpectedPublisher -Id GoogleChromeEnterprise -SignerSubject 'CN=Google LLC, OU=Google LLC, O=Unrelated Vendor') | Should -BeFalse
            (Test-OSDStageExpectedPublisher -Id MozillaFirefoxEnterprise -SignerSubject 'CN=Mozilla Corporation, O=Mozilla Corporation Fake, C=US') | Should -BeFalse
            (Test-OSDStageExpectedPublisher -Id UnknownApp -SignerSubject 'CN=Unknown, O=Unknown') | Should -BeFalse
        }
    }

    It 'exposes PublisherMismatch as distinct from signature Invalid' {
        InModuleScope OSDStage {
            $dir = Join-Path $TestDrive 'Installer'
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
            $file = Join-Path $dir 'vendor-installer.msi'
            Set-Content -LiteralPath $file -Value 'fake bytes' -Encoding ASCII
            Mock Test-OSDStageWinPE { $false }
            Mock Get-AuthenticodeSignature {
                [pscustomobject]@{
                    Status='Valid'; StatusMessage='Signature valid'
                    SignerCertificate=[pscustomobject]@{Subject='CN=Someone, O=Unrelated Vendor LLC, C=US'}
                }
            }
            $result = Get-OSDStageBuiltInSignature -Id GoogleChromeEnterprise -FilePath $file -CheckPublisher
            $result.Status | Should -Be 'PublisherMismatch'
            $result.ExpectedPublisher | Should -Be 'Google LLC'
            $result.PublisherMatches | Should -BeFalse
            { Assert-OSDStageBuiltInSignature -Id GoogleChromeEnterprise -FilePath $file } |
                Should -Throw '*PublisherMismatch*'
        }
    }

    It 'accepts a valid expected publisher and fails closed on unsigned payloads' {
        InModuleScope OSDStage {
            $dir = Join-Path $TestDrive 'Trusted'
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
            $file = Join-Path $dir 'vendor-installer.msi'
            Set-Content -LiteralPath $file -Value 'test bytes' -Encoding ASCII
            Mock Test-OSDStageWinPE { $false }
            Mock Get-AuthenticodeSignature {
                [pscustomobject]@{
                    Status='Valid';StatusMessage='Trusted'
                    SignerCertificate=[pscustomobject]@{Subject='CN=Google LLC, O=Google LLC, C=US'}
                }
            }
            $valid = Assert-OSDStageBuiltInSignature -Id GoogleChromeEnterprise -FilePath $file
            $valid.Status | Should -Be 'Valid'
            $valid.PublisherMatches | Should -BeTrue

            Mock Get-AuthenticodeSignature {
                [pscustomobject]@{Status='NotSigned';StatusMessage='Unsigned';SignerCertificate=$null}
            }
            { Assert-OSDStageBuiltInSignature -Id GoogleChromeEnterprise -FilePath $file } |
                Should -Throw '*NotSigned*'
        }
    }

    It 'preserves previously cached MSI when a new download fails trust validation' {
        InModuleScope OSDStage {
            $dir = Join-Path $TestDrive 'Protected'
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
            $path = Join-Path $dir 'vendor-installer.msi'
            'original trusted installer' | Set-Content -LiteralPath $path -Encoding ASCII
            $originalHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
            Mock Test-OSDStageWinPE { $false }
            Mock Save-OSDStageDownload {
                Set-Content -LiteralPath $DestinationPath -Value 'suspicious download' -Encoding ASCII
                Get-Item -LiteralPath $DestinationPath
            }
            Mock Assert-OSDStageBuiltInSignature { throw 'PublisherMismatch' }

            { Save-OSDStageVerifiedBuiltInDownload -Id GoogleChromeEnterprise -Uri ([uri]'https://example.org/vendor-installer.msi') -DestinationPath $path -Activity 'Test' } |
                Should -Throw '*PublisherMismatch*'
            (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash | Should -Be $originalHash
            @((Get-ChildItem -LiteralPath $dir -File)).Count | Should -Be 1
        }
    }

    It 'promotes only a validated new candidate and removes temporary files' {
        InModuleScope OSDStage {
            $dir = Join-Path $TestDrive 'Promotion'
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
            $path = Join-Path $dir 'vendor-installer.msi'
            'old installer' | Set-Content -LiteralPath $path -Encoding ASCII
            Mock Test-OSDStageWinPE { $false }
            Mock Save-OSDStageDownload {
                Set-Content -LiteralPath $DestinationPath -Value 'trusted update' -Encoding ASCII
                Get-Item -LiteralPath $DestinationPath
            }
            Mock Assert-OSDStageBuiltInSignature {
                [pscustomobject]@{Status='Valid';PublisherMatches=$true}
            }
            $result = Save-OSDStageVerifiedBuiltInDownload -Id GoogleChromeEnterprise -Uri ([uri]'https://example.org/vendor-installer.msi') -DestinationPath $path -Activity 'Test'
            $result.SignatureVerified | Should -BeTrue
            (Get-Content -LiteralPath $path -Raw) | Should -Match 'trusted update'
            @((Get-ChildItem -LiteralPath $dir -File)).Count | Should -Be 1
            Should -Invoke Assert-OSDStageBuiltInSignature -Exactly 1
        }
    }

    It 'uses security checks in all signable full-Windows sync paths' {
        $root = Split-Path -Parent $PSScriptRoot
        $sharedVendorSync = Get-Content -LiteralPath (Join-Path $root 'Private\Sync-OSDStageVendorBuiltInCache.ps1') -Raw
        foreach ($id in @('GoogleChromeEnterprise','CiscoWebex','ZoomWorkplace','MozillaFirefoxEnterprise','MicrosoftTeams','Microsoft365Apps')) {
            $path = Join-Path $root "Public\Sync-OSDStage$id.ps1"
            $source = Get-Content -LiteralPath $path -Raw
            if ($id -in @('GoogleChromeEnterprise','CiscoWebex','ZoomWorkplace','MozillaFirefoxEnterprise')) {
                $source | Should -Match 'Sync-OSDStageVendorBuiltInCache'
                $source | Should -Match '-SignedPackage'
                $sharedVendorSync | Should -Match 'Save-OSDStageVerifiedBuiltInDownload'
                $sharedVendorSync | Should -Match 'Assert-OSDStageBuiltInSignature'
            }
            else {
                $source | Should -Match 'Save-OSDStageVerifiedBuiltInDownload'
                $source | Should -Match 'Assert-OSDStageBuiltInSignature'
            }
        }
    }

    It 'guards SetupComplete downloads, offline fallback and vendor MSI staging' {
        $root = Split-Path -Parent $PSScriptRoot
        $runtime = Get-Content -LiteralPath (Join-Path $root 'Runtime\Invoke-OSDStagePreInstall.ps1') -Raw
        $runtime | Should -Match 'function Assert-PreInstallSignedPayload'
        $runtime | Should -Match 'BuiltInSignatureVerified'
        $runtime | Should -Match 'Assert-PreInstallSignedPayload -Id \$id -Path \$path'
        $runtime | Should -Match 'Assert-PreInstallSignedPayload -Id ''Microsoft365Apps'' -Path \$setupPath'
        $runtime | Should -Match 'Assert-PreInstallSignedPayload -Id (?:''MicrosoftTeams''|MicrosoftTeams) -Path'
        $runtime | Should -Match 'Expected \x27\$expected\x27'
    }
}
