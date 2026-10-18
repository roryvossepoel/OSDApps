Describe 'Packaged help under inherited StrictMode' {
    It 'builds help and preserves parameter defaults with StrictMode enabled' {
        $root = Split-Path $PSScriptRoot -Parent
        $destination = Join-Path $TestDrive 'StrictHelp'
        $result = & {
            Set-StrictMode -Version Latest
            & (Join-Path $root 'build\Build-Module.ps1') -OutputPath $destination
        }
        $built = @($result | Where-Object { $_.PSObject.Properties['Manifest'] })[-1]
        Test-Path -LiteralPath (Join-Path $built.Path 'OSDApps-help.xml') | Should -BeTrue
        & (Join-Path $root 'build\Test-PackagedHelp.ps1') -ModulePath $built.Path
        [xml]$help = Get-Content -LiteralPath (Join-Path $built.Path 'OSDApps-help.xml') -Raw
        $ns = [Xml.XmlNamespaceManager]::new($help.NameTable)
        $ns.AddNamespace('command','http://schemas.microsoft.com/maml/dev/command/2004/10')
        $ns.AddNamespace('maml','http://schemas.microsoft.com/maml/2004/10')
        $ns.AddNamespace('dev','http://schemas.microsoft.com/maml/dev/2004/10')
        $default = $help.SelectSingleNode("//command:command[command:details/command:name='Add-OSDAppMicrosoft365Apps']/command:parameters/command:parameter[maml:name='Channel']/dev:defaultValue", $ns)
        $default.InnerText | Should -Be "'Current'"
    }
}
