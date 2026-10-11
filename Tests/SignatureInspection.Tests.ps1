Describe 'Built-in Authenticode cache inspection (read-only)' {
    BeforeAll {
        $script:root = Split-Path -Path $PSScriptRoot -Parent
        Import-Module (Join-Path $script:root 'OSDApps.psd1') -Force
    }

    It 'checks MSI files without changing them or initiating an installation' {
        InModuleScope OSDApps {
            $dir = Join-Path $TestDrive 'Msi'
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
            $msi = Join-Path $dir 'Package.msi'
            Set-Content -LiteralPath $msi -Value 'original mock package' -Encoding ASCII
            $before = (Get-FileHash -LiteralPath $msi -Algorithm SHA256).Hash
            Mock Test-OSDAppWinPE { $false }
            Mock Get-AuthenticodeSignature {
                [pscustomobject]@{
                    Status='Valid'; StatusMessage='Signature check succeeded'
                    SignerCertificate=[pscustomobject]@{Subject='CN=Example Publisher'}
                }
            }
            foreach ($id in @('GoogleChromeEnterprise','CiscoWebex','MozillaFirefoxEnterprise')) {
                $result = Get-OSDAppBuiltInSignature -Id $id -CacheEntryPath $dir
                $result.Status | Should -Be 'Valid'
                $result.Scope | Should -Be 'MSI package'
                $result.File | Should -Be $msi
                $result.Signer | Should -Be 'CN=Example Publisher'
            }
            Should -Invoke Get-AuthenticodeSignature -Exactly 3 -ParameterFilter { $LiteralPath -eq $msi }
            (Get-FileHash -LiteralPath $msi -Algorithm SHA256).Hash | Should -Be $before
        }
    }

    It 'does not report an unsigned or untrusted MSI as valid' {
        InModuleScope OSDApps {
            $dir = Join-Path $TestDrive 'Untrusted'
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $dir 'Package.msi') -Value 'unsigned' -Encoding ASCII
            Mock Test-OSDAppWinPE { $false }
            Mock Get-AuthenticodeSignature { [pscustomobject]@{Status='NotSigned';SignerCertificate=$null;StatusMessage='No digital signature'} }
            $found = Get-OSDAppBuiltInSignature -Id CiscoWebex -CacheEntryPath $dir
            $found.Status | Should -Be 'NotSigned'
            $found.Scope | Should -Be 'MSI package'
            $found.Signer | Should -BeNullOrEmpty
        }
    }

    It 'identifies the limited scope of Office and Teams EXE signature checks' {
        InModuleScope OSDApps {
            $dir = Join-Path $TestDrive 'Exe'
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $dir 'setup.exe') -Value 'setup' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $dir 'teamsbootstrapper.exe') -Value 'bootstrapper' -Encoding ASCII
            Mock Test-OSDAppWinPE { $false }
            Mock Get-AuthenticodeSignature { [pscustomobject]@{Status='Valid';StatusMessage='Valid';SignerCertificate=$null} }
            $office = Get-OSDAppBuiltInSignature -Id Microsoft365Apps -CacheEntryPath $dir
            $teams = Get-OSDAppBuiltInSignature -Id MicrosoftTeams -CacheEntryPath $dir
            $office.Scope | Should -Match 'setup.exe only'
            $teams.Scope | Should -Match 'MSIX not checked'
            $teams.File | Should -Be (Join-Path $dir 'teamsbootstrapper.exe')
        }
    }

    It 'does not incorrectly declare an outer Acrobat ZIP signed' {
        InModuleScope OSDApps {
            Mock Get-AuthenticodeSignature { throw 'Should not inspect ZIP' }
            $r = Get-OSDAppBuiltInSignature -Id AdobeAcrobatUnified -CacheEntryPath $TestDrive
            $r.Status | Should -Be 'Not assessed'
            $r.Scope | Should -Match 'ZIP'
            Should -Invoke Get-AuthenticodeSignature -Exactly 0
        }
    }

    It 'does not attempt Windows trust verification in WinPE' {
        InModuleScope OSDApps {
            $dir = Join-Path $TestDrive 'WinPE'
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $dir 'Package.msi') -Value 'package' -Encoding ASCII
            Mock Test-OSDAppWinPE { $true }
            Mock Get-AuthenticodeSignature { throw 'Do not invoke in WinPE' }
            $r = Get-OSDAppBuiltInSignature -Id MozillaFirefoxEnterprise -CacheEntryPath $dir
            $r.Status | Should -Be 'Unavailable in WinPE'
            Should -Invoke Get-AuthenticodeSignature -Exactly 0
        }
    }

    It 'returns a separate signature result from Get-OSDAppCache without altering Valid or cache files' {
        InModuleScope OSDApps {
            $cache = Join-Path $TestDrive 'USB\OSDApps'
            $root = Join-Path $cache 'BuiltIn\CiscoWebex\x64'
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            $msi = Join-Path $root 'Package.msi'
            $metadata = Join-Path $root 'CacheInfo.json'
            Set-Content -LiteralPath $msi -Value 'existing installer' -Encoding ASCII
            '{"Id":"CiscoWebex","Version":"46.9.0.35800","Architecture":"x64"}' |
                Set-Content -LiteralPath $metadata -Encoding UTF8
            $before = (Get-FileHash -LiteralPath $metadata -Algorithm SHA256).Hash
            $script:SignatureTestCacheRoot = $cache
            Mock Get-OSDAppCachePath { $script:SignatureTestCacheRoot }
            Mock Get-OSDAppBuiltInSignature {
                [pscustomobject]@{
                    Status='Valid';Scope='MSI package';File=$msi
                    Signer='CN=Vendor';Detail='Trusted'
                }
            }
            $default = @(Get-OSDAppCache)
            $default[0].Valid | Should -BeTrue
            $default[0].SignatureStatus | Should -Be 'Not checked'
            Should -Invoke Get-OSDAppBuiltInSignature -Exactly 0

            $checked = @(Get-OSDAppCache -VerifySignatures)
            $checked[0].Valid | Should -BeTrue
            $checked[0].SignatureStatus | Should -Be 'Valid'
            $checked[0].SignatureScope | Should -Be 'MSI package'
            $checked[0].SignatureSigner | Should -Be 'CN=Vendor'
            Should -Invoke Get-OSDAppBuiltInSignature -Exactly 1
            (Get-FileHash -LiteralPath $metadata -Algorithm SHA256).Hash | Should -Be $before
        }
    }

    It 'formats supported trust results without treating Not assessed as Valid' {
        InModuleScope OSDApps {
            (Get-OSDAppUISignatureLabel -Status Valid) | Should -Be 'Signature valid'
            (Get-OSDAppUISignatureLabel -Status NotSigned) | Should -Be 'Not signed'
            (Get-OSDAppUISignatureLabel -Status 'Not assessed') | Should -Be 'Not assessed'
            (Get-OSDAppUISignatureLabel -Status UnknownError) | Should -Be 'Trust unknown'
            (Get-OSDAppUISignatureLabel -Status 'Not assessed' -Source Repository) | Should -Be 'N/A'
            (Get-OSDAppUISignatureLabel -Status 'Not assessed' -Source BuiltIn) | Should -Be 'Not assessed'
            (Get-OSDAppUISignatureLabel -Status Valid -Source BuiltIn) | Should -Be 'Signature valid'
        }
    }

    It 'checks signatures by default in the compact GUI with explicit skip option' {
        $source = Get-Content -LiteralPath (Join-Path $script:root 'Public\Show-OSDAppUI.ps1') -Raw
        $source | Should -Match "RowStyle\]::new\('Absolute',80\)"
        $source | Should -Match 'Deployment overview'
        $source | Should -Match 'SkipSignatureVerification'
        $source | Should -Match 'SkipSignatureVerification:\$State.SkipSignatureVerification'
        $source | Should -Match "Columns.Add\('Signature'"
        $source | Should -Match "'Cache'\s+\{ @\(0,75,88,175,95,115,74,122\) \}"
        $source | Should -Match 'Get-OSDAppUISignatureLabel -Status'
        $source | Should -Match '-Source \(\[string\]\$entry.Source\)'
        $source | Should -Not -Match '(?i)\bSet-OSDAppConfiguration\b'
        $source | Should -Not -Match '(?i)\bRemove-OSDAppStaging\b'
    }
    It 'automatically requests Authenticode verification for full Windows Viewer snapshots' {
        InModuleScope OSDApps {
            Mock Get-OSDApp { }
            Mock Get-OSDAppCachePath { throw 'USB not attached' }
            Mock Test-OSDAppWinPE { $false }
            Mock Get-OSDAppCache { }
            Get-OSDAppUIReadOnlySnapshot -Offline | Out-Null
            Should -Invoke Get-OSDAppCache -Exactly 1 -ParameterFilter {
                $VerifySignatures -eq $true -and $ResolveVersions -eq $true
            }
        }
    }

    It 'skips Authenticode only when explicitly requested, but still resolves cached versions' {
        InModuleScope OSDApps {
            Mock Get-OSDApp { }
            Mock Get-OSDAppCachePath { throw 'USB not attached' }
            Mock Test-OSDAppWinPE { $false }
            Mock Get-OSDAppCache { }
            Get-OSDAppUIReadOnlySnapshot -Offline -SkipSignatureVerification | Out-Null
            Should -Invoke Get-OSDAppCache -Exactly 1 -ParameterFilter {
                $VerifySignatures -eq $false -and $ResolveVersions -eq $true
            }
        }
    }

    It 'reports signatures as unavailable in WinPE without trying to resolve MSI versions' {
        InModuleScope OSDApps {
            Mock Get-OSDApp { }
            Mock Get-OSDAppCachePath { throw 'USB not attached' }
            Mock Test-OSDAppWinPE { $true }
            Mock Get-OSDAppCache { }
            Get-OSDAppUIReadOnlySnapshot -Offline | Out-Null
            Should -Invoke Get-OSDAppCache -Exactly 1 -ParameterFilter {
                $VerifySignatures -eq $true -and $ResolveVersions -eq $false
            }
        }
    }

    It 'shows an explicit warning for publisher mismatch in the read-only cache' {
        InModuleScope OSDApps {
            (Get-OSDAppUISignatureLabel -Status PublisherMismatch -Source BuiltIn) |
                Should -Be 'Wrong publisher'
        }
        $source = Get-Content -LiteralPath (Join-Path $script:root 'Public\Show-OSDAppUI.ps1') -Raw
        $source | Should -Match "SignatureStatus -in @\('NotSigned'"
        $source | Should -Match 'Firebrick'
    }

}
