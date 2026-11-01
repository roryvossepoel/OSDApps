Describe 'Gallery publication verification' {
    BeforeAll {
        $root = Split-Path $PSScriptRoot -Parent
        $workflow = Get-Content -LiteralPath (Join-Path $root '.github\workflows\publish.yml') -Raw
        $marker = '      - name: Publish and verify PowerShell Gallery package'
        $step = $workflow.Substring($workflow.IndexOf($marker))
        $run = $step.Substring($step.IndexOf('        run: |') + '        run: |'.Length)
        $source = ($run -split '\r?\n' | ForEach-Object { $_ -replace '^          ', '' }) -join "`n"
        $tokens = $null; $errors = $null
        [void][Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$errors)
        if (@($errors).Count) { throw 'Gallery publication workflow contains PowerShell parser errors.' }
        $script:publishStep = [scriptblock]::Create($source)

        # Execute the actual workflow step; all Gallery calls are isolated mocks.
        function Find-Module { [CmdletBinding()] param($Name,$RequiredVersion,$Repository) }
        function Save-Module { [CmdletBinding()] param($Name,$RequiredVersion,$Repository,$Path,[switch]$Force) }
        function Publish-Module { [CmdletBinding()] param($Path,$Repository,$NuGetApiKey,[switch]$Force) }
    }

    BeforeEach {
        $script:previousRunnerTemp = $env:RUNNER_TEMP
        $script:previousVersion = $env:GALLERY_VERSION
        $script:previousKey = $env:PSGALLERY_API_KEY
        $env:RUNNER_TEMP = Join-Path $TestDrive 'Temp'
        $env:GALLERY_VERSION = '0.42.0'
        $env:PSGALLERY_API_KEY = 'fixture-only'
        $workspace = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:fixtureModule = Join-Path $workspace 'dist\OSDStage'
        New-Item -ItemType Directory -Path $fixtureModule -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $fixtureModule 'OSDStage.psd1') -Value "@{ModuleVersion='0.42.0'}"
        Set-Content -LiteralPath (Join-Path $fixtureModule 'OSDStage.psm1') -Value '# fixture payload'
        Push-Location -LiteralPath $workspace
        $script:downloadAttempts = 0
        $script:failuresBeforeSuccess = 0
        $script:contentFault = ''
        Mock Find-Module { $null }
        Mock Publish-Module { }
        Mock Start-Sleep { }
        Mock Save-Module {
            $script:downloadAttempts++
            # A previous failed attempt must not leave usable-looking content behind.
            if (Test-Path -LiteralPath (Join-Path $Path 'partial.txt')) { throw 'Previous partial download was not removed.' }
            if ($script:downloadAttempts -le $script:failuresBeforeSuccess) {
                Set-Content -LiteralPath (Join-Path $Path 'partial.txt') -Value partial
                throw "No match was found for OSDStage on attempt $script:downloadAttempts."
            }
            if ($script:contentFault -eq 'NoDirectory') { return }
            $destination = Join-Path $Path "OSDStage\$RequiredVersion"
            New-Item -ItemType Directory -Path $destination -Force | Out-Null
            Get-ChildItem -LiteralPath $script:fixtureModule -File | Copy-Item -Destination $destination
            if ($script:contentFault -eq 'Mismatch') { Set-Content -LiteralPath (Join-Path $destination 'OSDStage.psm1') -Value '# different bytes' }
            if ($script:contentFault -eq 'Missing') { Remove-Item -LiteralPath (Join-Path $destination 'OSDStage.psm1') }
        }
    }

    AfterEach {
        Pop-Location
        $env:RUNNER_TEMP = $script:previousRunnerTemp
        $env:GALLERY_VERSION = $script:previousVersion
        $env:PSGALLERY_API_KEY = $script:previousKey
    }

    It 'retries delayed downloads with clean attempts and publishes only once' {
        $script:failuresBeforeSuccess = 2
        { & $script:publishStep } | Should -Not -Throw
        Should -Invoke Publish-Module -Exactly 1
        Should -Invoke Find-Module -Exactly 1
        Should -Invoke Save-Module -Exactly 3 -ParameterFilter { $Name -eq 'OSDStage' -and $RequiredVersion -eq '0.42.0' -and $Repository -eq 'PSGallery' }
        Should -Invoke Start-Sleep -Exactly 2 -ParameterFilter { $Seconds -eq 10 }
    }

    It 'fails clearly after the bounded download attempts without repeating the push' {
        $script:failuresBeforeSuccess = 20
        { & $script:publishStep } | Should -Throw '*after 12 attempts*Publication is not verified*attempt 12*'
        Should -Invoke Publish-Module -Exactly 1
        Should -Invoke Save-Module -Exactly 12
        Should -Invoke Start-Sleep -Exactly 11
    }

    It 'rejects a hash mismatch immediately rather than retrying content verification' {
        $script:contentFault = 'Mismatch'
        { & $script:publishStep } | Should -Throw '*does not match the release*OSDStage.psm1*'
        Should -Invoke Save-Module -Exactly 1
        Should -Invoke Start-Sleep -Exactly 0
    }

    It 'rejects a downloaded package with a missing release file immediately' {
        $script:contentFault = 'Missing'
        { & $script:publishStep } | Should -Throw '*missing file*OSDStage.psm1*'
        Should -Invoke Save-Module -Exactly 1
        Should -Invoke Start-Sleep -Exactly 0
    }

    It 'rejects successful retrieval without the expected exact-version directory' {
        $script:contentFault = 'NoDirectory'
        { & $script:publishStep } | Should -Throw '*was not downloaded for verification*'
        Should -Invoke Save-Module -Exactly 1
        Should -Invoke Start-Sleep -Exactly 0
    }

    It 'still rejects pre-existing versions without pushing or downloading' {
        Mock Find-Module { [pscustomobject]@{ Version='0.42.0' } }
        { & $script:publishStep } | Should -Throw '*already exists before publication*'
        Should -Invoke Publish-Module -Exactly 0
        Should -Invoke Save-Module -Exactly 0
    }

    It 'reconciles a post-push 409 only after delayed retrieval and exact content verification' {
        Mock Publish-Module { throw '409 already exists and cannot be modified' }
        $script:failuresBeforeSuccess = 1
        { & $script:publishStep } | Should -Not -Throw
        Should -Invoke Publish-Module -Exactly 1
        Should -Invoke Save-Module -Exactly 2
    }

    It 'does not hide a content mismatch after a post-push 409' {
        Mock Publish-Module { throw '409 already exists and cannot be modified' }
        $script:contentFault = 'Mismatch'
        { & $script:publishStep } | Should -Throw '*does not match the release*'
        Should -Invoke Publish-Module -Exactly 1
        Should -Invoke Save-Module -Exactly 1
    }

    It 'preserves non-conflict publication failures without retrying or verifying' {
        Mock Publish-Module { throw '403 forbidden in fixture' }
        { & $script:publishStep } | Should -Throw '*403 forbidden*'
        Should -Invoke Publish-Module -Exactly 1
        Should -Invoke Save-Module -Exactly 0
        Should -Invoke Start-Sleep -Exactly 0
    }
}
