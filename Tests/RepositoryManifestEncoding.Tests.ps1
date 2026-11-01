Describe 'Repository manifest HTTP decoding' {
    BeforeAll {
        Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'OSDStage.psd1') -Force
    }

    It 'reads UTF-8 JSON with BOM=<Bom> and content type <ContentType>' -ForEach @(
        @{ Bom = $true; ContentType = 'application/json' }
        @{ Bom = $false; ContentType = 'application/json' }
        @{ Bom = $true; ContentType = 'application/octet-stream' }
        @{ Bom = $false; ContentType = 'text/plain' }
    ) {
        InModuleScope OSDStage -Parameters @{ Bom=$Bom; ContentType=$ContentType } {
            param($Bom, $ContentType)
            $script:encodingBody = '{"Id":"RepoTestFonts","DisplayName":"Caf' + [char]0xE9 + '","Architecture":"any"}'
            $encoding = [Text.UTF8Encoding]::new($Bom)
            $script:responseBytes = [byte[]]($encoding.GetPreamble() + $encoding.GetBytes($script:encodingBody))
            $script:responseType = $ContentType
            Mock Invoke-WebRequest {
                [pscustomobject]@{
                    RawContentStream = [IO.MemoryStream]::new($script:responseBytes)
                    Headers = @{ 'Content-Type' = $script:responseType }
                }
            }
            $result = Get-OSDStageManifest -Uri 'https://example.org/manifest.json'
            $result.Id | Should -Be 'RepoTestFonts'
            $result.DisplayName | Should -Be ('Caf' + [char]0xE9)
            Should -Invoke Invoke-WebRequest -Times 1 -Exactly
        }
    }

    It 'rejects malformed JSON without disclosing the response body' {
        InModuleScope OSDStage {
            Mock Invoke-WebRequest {
                [pscustomobject]@{ RawContentStream = [IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes('private-body-not-json')) }
            }
            { Get-OSDStageManifest -Uri 'https://example.org/manifest.json' } |
                Should -Throw -ExpectedMessage 'Repository manifest response is not valid JSON.'
        }
    }

    It 'rejects a JSON scalar instead of reporting an empty package Id' {
        InModuleScope OSDStage {
            Mock Invoke-WebRequest {
                [pscustomobject]@{ RawContentStream = [IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes('"not-a-manifest"')) }
            }
            { Get-OSDStageManifest -Uri 'https://example.org/manifest.json' } |
                Should -Throw -ExpectedMessage 'Repository manifest response must contain a JSON object.'
        }
    }

    It 'propagates HTTP failures' {
        InModuleScope OSDStage {
            Mock Invoke-WebRequest { throw 'HTTP 404' }
            { Get-OSDStageManifest -Uri 'https://example.org/manifest.json' } | Should -Throw '*HTTP 404*'
        }
    }

    It 'keeps local UTF-8 BOM manifests readable' {
        InModuleScope OSDStage {
            $path = Join-Path $TestDrive 'manifest.json'
            [IO.File]::WriteAllText($path, '{"Id":"RepoTestFonts"}', [Text.UTF8Encoding]::new($true))
            (Get-OSDStageManifest -Path $path).Id | Should -Be 'RepoTestFonts'
        }
    }
}
