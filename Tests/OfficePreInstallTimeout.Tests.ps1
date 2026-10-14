Describe 'Microsoft 365 Apps PreInstall timeout enforcement' {
    BeforeAll {
        $script:runtimePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Runtime\Invoke-OSDAppPreInstall.ps1'
        $script:runtime = Get-Content -LiteralPath $script:runtimePath -Raw
        $tokens = $null
        $errors = $null
        $script:ast = [System.Management.Automation.Language.Parser]::ParseFile($script:runtimePath, [ref]$tokens, [ref]$errors)
        if (@($errors).Count -ne 0) { throw 'PreInstall runtime has PowerShell parse errors.' }
    }

    It 'terminates the Office process tree through a bounded helper' {
        $script:runtime | Should -Match 'function Stop-PreInstallProcessTree'
        $treeArguments = "'/PID', " + '$Process.Id' + ", '/T', '/F'"
        $script:runtime | Should -Match ([regex]::Escape($treeArguments))
        $script:runtime | Should -Match '\.WaitForExit\(\$TimeoutSeconds \* 1000\)'
        $script:runtime | Should -Match 'Stop-PreInstallProcessTree -Process \$process -TimeoutSeconds 5'
    }

    It 'does not use an unbounded WaitForExit call' {
        $waitCalls = @($script:ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
            $node.Member.Value -eq 'WaitForExit'
        }, $true))

        $waitCalls.Count | Should -BeGreaterThan 0
        @($waitCalls | Where-Object { $_.Arguments.Count -eq 0 }).Count | Should -Be 0
    }
}
