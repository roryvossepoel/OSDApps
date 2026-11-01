Describe 'Packaged help under inherited StrictMode' {
    It 'builds help and preserves parameter defaults with StrictMode enabled' {
        $root = Split-Path $PSScriptRoot -Parent
        $destination = Join-Path $TestDrive 'StrictHelp'
        # Build/import in a child process so the packaged module cannot leak
        # into later Pester InModuleScope tests in this process.
        $childScript = Join-Path $TestDrive 'Build-StrictHelp.ps1'
        @'
param([string]$Root, [string]$OutputPath)
$ErrorActionPreference = 'Stop'
& {
    Set-StrictMode -Version Latest
    & (Join-Path $Root 'build\Build-Module.ps1') -OutputPath $OutputPath | Out-Null
}
& (Join-Path $Root 'build\Test-PackagedHelp.ps1') -ModulePath (Join-Path $OutputPath 'OSDStage')
'@ | Set-Content -LiteralPath $childScript -Encoding UTF8
        $engine = (Get-Process -Id $PID).Path
        & $engine -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $childScript -Root $root -OutputPath $destination
        $LASTEXITCODE | Should -Be 0
        $built = [pscustomobject]@{ Path = (Join-Path $destination 'OSDStage') }
        Test-Path -LiteralPath (Join-Path $built.Path 'OSDStage-help.xml') | Should -BeTrue
        [xml]$help = Get-Content -LiteralPath (Join-Path $built.Path 'OSDStage-help.xml') -Raw
        $ns = [Xml.XmlNamespaceManager]::new($help.NameTable)
        $ns.AddNamespace('command','http://schemas.microsoft.com/maml/dev/command/2004/10')
        $ns.AddNamespace('maml','http://schemas.microsoft.com/maml/2004/10')
        $ns.AddNamespace('dev','http://schemas.microsoft.com/maml/dev/2004/10')
        $default = $help.SelectSingleNode("//command:command[command:details/command:name='Add-OSDStageMicrosoft365Apps']/command:parameters/command:parameter[maml:name='Channel']/dev:defaultValue", $ns)
        $default.InnerText | Should -Be "'Current'"
    }
}
