Describe 'Website PowerShell examples' {
    It 'parses displayed code and uses exported commands with valid parameters' {
        $root = Split-Path $PSScriptRoot -Parent
        $module = Import-Module (Join-Path $root 'OSDStage.psd1') -Force -PassThru
        $problems = [System.Collections.Generic.List[string]]::new()
        $blocks = 0
        foreach ($file in Get-ChildItem (Join-Path $root 'site') -Filter '*.html' -Recurse) {
            $html = Get-Content $file.FullName -Raw -Encoding UTF8
            foreach ($match in [regex]::Matches($html,'(?s)<pre><code>(.*?)</code></pre>')) {
                $blocks++
                $code = [System.Net.WebUtility]::HtmlDecode($match.Groups[1].Value)
                $tokens = $null; $errors = $null
                $ast = [System.Management.Automation.Language.Parser]::ParseInput($code,[ref]$tokens,[ref]$errors)
                foreach ($error in $errors) { $problems.Add("$($file.Name): $($error.Message)") }
                foreach ($call in $ast.FindAll({param($n) $n -is [System.Management.Automation.Language.CommandAst]},$true)) {
                    $name = $call.GetCommandName()
                    if ($name -notmatch '^[A-Za-z]+-OSDStage') { continue }
                    if (-not $module.ExportedFunctions.ContainsKey($name)) { $problems.Add("Unknown command: $name"); continue }
                    foreach ($element in $call.CommandElements) {
                        if ($element -is [System.Management.Automation.Language.CommandParameterAst] -and
                            -not $module.ExportedFunctions[$name].Parameters.ContainsKey($element.ParameterName)) {
                            $problems.Add("Unknown parameter: $name -$($element.ParameterName)")
                        }
                    }
                }
            }
        }
        $blocks | Should -BeGreaterThan 15
        $problems.Count | Should -Be 0 -Because ($problems -join '; ')
    }
}
