Describe 'Release identity' {
    BeforeAll {
        $script:root = Split-Path $PSScriptRoot -Parent
        $script:resolver = Join-Path $script:root 'build/Get-ReleaseVersion.ps1'
    }
    It 'resolves the real candidate consistently' {
        $result = & $script:resolver -ExpectedVersion '1.0.0-rc1'
        $result.ModuleVersion | Should -Be '1.0.0'
        $result.Version | Should -Be '1.0.0-rc1'
        $result.Tag | Should -Be 'v1.0.0-rc1'
        $result.IsPrerelease | Should -BeTrue
    }
    It 'resolves stable releases without a suffix' {
        $path = Join-Path $TestDrive 'stable.psd1'
        Set-Content $path "@{ModuleVersion='1.0.0'}"
        $result = & $script:resolver -ManifestPath $path -ExpectedVersion '1.0.0'
        $result.Tag | Should -Be 'v1.0.0'
        $result.IsPrerelease | Should -BeFalse
    }
    It 'rejects the wrong channel or candidate' {
        { & $script:resolver -ExpectedVersion '1.0.0' } | Should -Throw '*does not match*'
        { & $script:resolver -ExpectedVersion '1.0.0-rc2' } | Should -Throw '*does not match*'
    }
    It 'rejects invalid prerelease manifests' -ForEach @(
        @{ Version='1.0.0.0'; Label='rc1' },
        @{ Version='1.0.0'; Label='rc.1' },
        @{ Version='1.0.0'; Label='rc+1' }
    ) {
        $path = Join-Path $TestDrive 'invalid.psd1'
        Set-Content $path "@{ModuleVersion='$Version';PrivateData=@{PSData=@{Prerelease='$Label'}}}"
        { & $script:resolver -ManifestPath $path } | Should -Throw '*Prerelease requires*'
    }
    It 'creates the GitHub candidate with prerelease and not-latest flags' {
        $workflow = Get-Content (Join-Path $script:root '.github/workflows/release.yml') -Raw
        $step = $workflow.Substring($workflow.IndexOf('      - name: Create GitHub release'))
        $step = ($step -split '\r?\n      - name:')[0]
        $source = $step.Substring($step.IndexOf('        run: |') + '        run: |'.Length)
        $source = ($source -split '\r?\n' | ForEach-Object { $_ -replace '^          ', '' }) -join "`n"
        function gh { $script:ghArgs = @($args); $global:LASTEXITCODE = 0 }
        $previous = @{}
        foreach ($key in @('TAG','RELEASE_VERSION','TAG_EXISTS','IS_PRERELEASE','RUNNER_TEMP','GITHUB_REPOSITORY','GITHUB_SHA')) {
            $previous[$key] = [Environment]::GetEnvironmentVariable($key)
        }
        try {
            $env:TAG='v1.0.0-rc1'; $env:RELEASE_VERSION='1.0.0-rc1'
            $env:TAG_EXISTS='false'; $env:IS_PRERELEASE='true'
            $env:RUNNER_TEMP=$TestDrive; $env:GITHUB_REPOSITORY='fixture/repository'; $env:GITHUB_SHA='fixture'
            Push-Location $script:root
            try { & ([scriptblock]::Create($source)) } finally { Pop-Location }
            $script:ghArgs | Should -Contain '--prerelease'
            $script:ghArgs | Should -Contain '--latest=false'
            $script:ghArgs | Should -Contain 'v1.0.0-rc1'
            Get-Content (Join-Path $TestDrive 'release-notes.md') -Raw | Should -Match 'Not a GA release'
        }
        finally { foreach ($key in $previous.Keys) { [Environment]::SetEnvironmentVariable($key,$previous[$key]) } }
    }
}
