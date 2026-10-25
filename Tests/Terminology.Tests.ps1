Describe 'Canonical OSDApps terminology' {
    BeforeAll {
        $script:repositoryRoot = Split-Path $PSScriptRoot -Parent
        $script:obsoleteTerm = 'Applic' + 'ation'
        $script:obsoletePattern = '(?i)' + $script:obsoleteTerm
    }

    It 'uses App and Apps in owned source, schemas, examples, help, tests and filenames' {
        $paths = @(Get-ChildItem -LiteralPath $script:repositoryRoot -Recurse -File -ErrorAction Stop |
            Where-Object {
                $_.Extension -in @('.ps1','.psm1','.psd1','.json','.md','.yml','.yaml','.svg','.cs') -and
                $_.FullName -notmatch '[\\/](dist|TestResults|\\.git)[\\/]'
            })
        $found = [System.Collections.Generic.List[string]]::new()
        foreach ($file in $paths) {
            $relative = $file.FullName.Substring($script:repositoryRoot.Length).TrimStart('\','/')
            if ($relative -match $script:obsoletePattern) {
                $found.Add("Filename: $relative")
            }
            $source = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
            # The GitHub Accept header is an external MIME standard, not OSDApps terminology.
            $source = $source -replace ('(?i)' + $script:obsoleteTerm + '/vnd\\.github\\+json'), ''
            # These are mandatory PSHost API overrides, not OSDApps-owned terminology.
            $source = $source -replace ('Notify(Begin|End)' + $script:obsoleteTerm), ''
            if ($source -match $script:obsoletePattern) {
                $found.Add("Content: $relative")
            }
        }
        @($found).Count | Should -Be 0 -Because (@($found) -join '; ')
    }
}
