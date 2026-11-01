Describe 'Documentation validation' {
    BeforeAll {
        $script:root = Split-Path $PSScriptRoot -Parent
        $script:validator = Join-Path $script:root 'build\Test-Documentation.ps1'
    }

    It 'validates current repository Markdown paths, anchors and command examples' {
        $result = & $script:validator -Root $script:root
        $result.FilesChecked | Should -BeGreaterThan 0
        $result.LocalLinksChecked | Should -BeGreaterThan 0
        $result.PowerShellBlocksParsed | Should -BeGreaterThan 0
        $result.OSDStageCallsChecked | Should -BeGreaterThan 0
        $result.ExamplesExecuted | Should -BeFalse
        $result.ExternalLinksRequested | Should -BeFalse
    }

    It 'accepts real section links and duplicate-heading suffixes' {
        $folder = Join-Path $TestDrive 'ValidDocs'
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $folder 'README.md') -Encoding UTF8 -Value @'
# Start
[details](page.md#details)
[second section](page.md#details-1)
'@
        Set-Content -LiteralPath (Join-Path $folder 'page.md') -Encoding UTF8 -Value "# Details`n# Details`n"
        $result = & $script:validator -Root $folder
        $result.LocalLinksChecked | Should -Be 2
    }

    It 'rejects missing files and does not accept substring matches for anchors' {
        $folder = Join-Path $TestDrive 'BrokenDocs'
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $folder 'README.md') -Encoding UTF8 -Value '[missing](absent.md)'
        { & $script:validator -Root $folder } | Should -Throw '*missing local target*'
        Set-Content -LiteralPath (Join-Path $folder 'page.md') -Encoding UTF8 -Value '# Details'
        Set-Content -LiteralPath (Join-Path $folder 'README.md') -Encoding UTF8 -Value "[valid](page.md#details)`n[invalid](page.md#detail)"
        { & $script:validator -Root $folder } | Should -Throw '*missing section anchor*'
    }

    It 'parses examples without executing them and catches malformed PowerShell' {
        $folder = Join-Path $TestDrive 'ExampleDocs'
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        $path = Join-Path $folder 'README.md'
        Set-Content -LiteralPath $path -Encoding UTF8 -Value @'
# Examples
```powershell
throw 'This must never be executed by documentation validation.'
```
'@
        $result = & $script:validator -Root $folder
        $result.PowerShellBlocksParsed | Should -Be 1
        $result.ExamplesExecuted | Should -BeFalse
        Set-Content -LiteralPath $path -Encoding UTF8 -Value @'
# Examples
```powershell
$x = (
```
'@
        { & $script:validator -Root $folder } | Should -Throw '*PowerShell syntax*'
    }

    It 'validates tilde-fenced PowerShell blocks and does not execute examples' {
        $folder = Join-Path $TestDrive 'TildeDocs'
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        $path = Join-Path $folder 'README.md'
        Set-Content -LiteralPath $path -Encoding UTF8 -Value @'
# Examples
~~~powershell
throw 'This example must not execute.'
~~~
'@
        $result = & $script:validator -Root $folder
        $result.PowerShellBlocksParsed | Should -Be 1
        $result.ExamplesExecuted | Should -BeFalse

        Set-Content -LiteralPath $path -Encoding UTF8 -Value @'
# Examples
~~~powershell
$x = (
~~~
'@
        { & $script:validator -Root $folder } | Should -Throw '*PowerShell syntax*'
    }

    It 'keeps tilde-fenced headings out of Markdown anchor detection' {
        $folder = Join-Path $TestDrive 'TildeHeading'
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $folder 'README.md') -Encoding UTF8 -Value @'
# Document
[not a section](#fake-heading)
~~~powershell
# Fake heading
Get-Date
~~~
'@
        { & $script:validator -Root $folder } | Should -Throw '*missing section anchor*'
    }

    It 'does not close a longer tilde fence with a shorter or different fence' {
        $folder = Join-Path $TestDrive 'MatchingFences'
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $folder 'README.md') -Encoding UTF8 -Value @'
# Document
~~~~text
~~~
```
# Not a section
[not a prose link](missing.md)
~~~~
'@
        $result = & $script:validator -Root $folder
        $result.LocalLinksChecked | Should -Be 0
        $result.PowerShellBlocksParsed | Should -Be 0
        $result.ExamplesExecuted | Should -BeFalse
    }

    It 'keeps Company Portal help and Apps metadata aligned with automatic acquisition' {
        $helpData = Import-PowerShellDataFile -Path (Join-Path $script:root 'help/CommandHelp.psd1')
        $help = $helpData.Commands['Sync-OSDStageMicrosoftCompanyPortal']
        $help.Description | Should -Match 'Downloads.*Microsoft Preinstall Kit by default'
        $help.Description | Should -Match 'Optionally.*-KitPath'
        $help.Parameters.KitPath | Should -Match '^Optional'
        $help.Examples[0].Code | Should -Be 'Sync-OSDStageMicrosoftCompanyPortal -Architecture x64'
        $catalog = Get-Content -LiteralPath (Join-Path $script:root 'metadata/builtins.json') -Raw | ConvertFrom-Json
        $catalog.PSObject.Properties.Name | Should -Contain 'Packages'
        $companyPortal = @($catalog.Packages | Where-Object Id -eq 'MicrosoftCompanyPortal')
        $companyPortal.Count | Should -Be 1
        $companyPortal[0].Acquisition | Should -Be 'MicrosoftPreinstallKit'
        $companyPortal[0].SyncPhase | Should -Be 'FullWindowsPreparation'
        $cmTrace = @($catalog.Packages | Where-Object Id -eq 'CMTraceOpen')
        $cmTrace.Count | Should -Be 1
        $cmTrace[0].SyncPhase | Should -Be 'FullWindowsPreparation'
    }

    It 'does not treat PowerShell comments in code fences as document headings' {
        $folder = Join-Path $TestDrive 'NotAHeading'
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $folder 'README.md') -Encoding UTF8 -Value @'
# Document
[not a section](#fake-heading)
```powershell
# Fake heading
Get-Date
```
'@
        { & $script:validator -Root $folder } | Should -Throw '*missing section anchor*'
    }
}
