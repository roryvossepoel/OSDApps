Describe 'Packaged external-help binding' {
    BeforeAll {
        $script:connector = Join-Path (Split-Path $PSScriptRoot -Parent) 'build\Connect-PackagedHelp.ps1'
    }

    It 'adds only an external-help comment and keeps executable tokens unchanged' {
        $root = Join-Path $TestDrive 'WithComments'
        New-Item -ItemType Directory -Path (Join-Path $root 'Public') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'OSDApps.psd1') -Encoding UTF8 -Value "@{FunctionsToExport=@('Get-Example')}"
        Set-Content -LiteralPath (Join-Path $root 'OSDApps-help.xml') -Encoding UTF8 -Value '<helpItems />'
        $file = Join-Path $root 'Public\Get-Example.ps1'
        $source = @'
function Get-Example {
    <#
    .SYNOPSIS
    Existing help.
    #>
    [CmdletBinding()]
    param([switch]$Flag)
    throw 'Do not execute this fixture.'
}
'@
        Set-Content -LiteralPath $file -Encoding UTF8 -Value $source
        $beforeTokens = $null; $errors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($file,[ref]$beforeTokens,[ref]$errors)
        & $script:connector -ModulePath $root
        $after = Get-Content -LiteralPath $file -Raw
        $after | Should -Match '\.EXTERNALHELP OSDApps-help.xml'
        $afterTokens = $null
        [void][Management.Automation.Language.Parser]::ParseFile($file,[ref]$afterTokens,[ref]$errors)
        @($errors).Count | Should -Be 0
        $beforeCode = @($beforeTokens | Where-Object Kind -ne Comment | ForEach-Object Text) -join '|'
        $afterCode = @($afterTokens | Where-Object Kind -ne Comment | ForEach-Object Text) -join '|'
        $afterCode | Should -BeExactly $beforeCode
        $hash = (Get-FileHash -LiteralPath $file).Hash
        & $script:connector -ModulePath $root
        (Get-FileHash -LiteralPath $file).Hash | Should -Be $hash
    }

    It 'leaves functions without local help byte-for-byte unchanged' {
        $root = Join-Path $TestDrive 'AutomaticDiscovery'
        New-Item -ItemType Directory -Path (Join-Path $root 'Public') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'OSDApps.psd1') -Encoding UTF8 -Value "@{FunctionsToExport=@('Get-Example')}"
        Set-Content -LiteralPath (Join-Path $root 'OSDApps-help.xml') -Encoding UTF8 -Value '<helpItems />'
        $file = Join-Path $root 'Public\Get-Example.ps1'
        Set-Content -LiteralPath $file -Encoding UTF8 -Value 'function Get-Example { param() throw "never execute" }'
        $hash = (Get-FileHash -LiteralPath $file).Hash
        & $script:connector -ModulePath $root
        (Get-FileHash -LiteralPath $file).Hash | Should -Be $hash
    }

    It 'refuses to bind help when the packaged help file is missing' {
        $root = Join-Path $TestDrive 'MissingHelp'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'OSDApps.psd1') -Encoding UTF8 -Value "@{FunctionsToExport=@('Get-Example')}"
        { & $script:connector -ModulePath $root } | Should -Throw '*Generate packaged MAML*'
    }
}
