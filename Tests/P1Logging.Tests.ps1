Describe 'P1 client logging' {
    BeforeAll {
        $moduleRoot = Split-Path -Parent $PSScriptRoot
        Import-Module (Join-Path $moduleRoot 'OSDStage.psd1') -Force
    }

    It 'keeps structured log records on one physical line' {
        InModuleScope OSDStage {
            $path = Join-Path $TestDrive 'Client\Logs\Client.log'
            Write-OSDStageLog -LogPath $path -Component 'Sync' -Event 'Test' -Message "line 1$([char]10)line 2" -Data @{ Detail = "A$([char]13)$([char]10)B" }
            $lines = @(Get-Content -LiteralPath $path)
            $lines.Count | Should -Be 1
            $lines[0] | Should -Match 'line 1 line 2'
            $lines[0] | Should -Match 'Detail=A B'
        }
    }

    It 'keeps one active log and at most three rotated files' {
        InModuleScope OSDStage {
            $dir = Join-Path $TestDrive 'Rotation'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            $path = Join-Path $dir 'Client.log'
            [IO.File]::WriteAllBytes($path, (New-Object byte[] (1MB)))
            Set-Content -LiteralPath "$path.1" -Value 'old-1'
            Set-Content -LiteralPath "$path.2" -Value 'old-2'
            Set-Content -LiteralPath "$path.3" -Value 'old-3'

            Write-OSDStageLog -LogPath $path -Component 'Sync' -Event 'Rotate' -Message 'rotated'

            (Test-Path -LiteralPath $path) | Should -BeTrue
            (Test-Path -LiteralPath "$path.1") | Should -BeTrue
            (Test-Path -LiteralPath "$path.2") | Should -BeTrue
            (Test-Path -LiteralPath "$path.3") | Should -BeTrue
            (Test-Path -LiteralPath "$path.4") | Should -BeFalse
            (Get-Content -LiteralPath "$path.2" -Raw) | Should -Match 'old-1'
            (Get-Content -LiteralPath "$path.3" -Raw) | Should -Match 'old-2'
        }
    }
}
