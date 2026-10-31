[CmdletBinding()]
param([Parameter(Mandatory)][string]$ModulePath)

$ErrorActionPreference = 'Stop'
$moduleRoot = (Resolve-Path -LiteralPath $ModulePath).Path
$manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $moduleRoot 'OSDStage.psd1')
if (-not (Test-Path -LiteralPath (Join-Path $moduleRoot 'OSDStage-help.xml') -PathType Leaf)) {
    throw 'Generate packaged MAML before connecting existing comment-based help.'
}
$changed = 0
foreach ($name in $manifest.FunctionsToExport) {
    $path = Join-Path $moduleRoot (Join-Path 'Public' "$name.ps1")
    $bytes = [IO.File]::ReadAllBytes($path)
    $text = [IO.File]::ReadAllText($path)
    # Functions without comment-based help use PowerShell's module-level MAML
    # discovery. Existing local help needs an explicit external-help reference.
    $pattern = '(?s)(function\s+' + [regex]::Escape($name) + '\s*\{\s*<#)(?<help>.*?)(#>)'
    $match = [regex]::Match($text,$pattern)
    if (-not $match.Success -or $match.Groups['help'].Value -match '(?im)^\s*\.EXTERNALHELP\b') { continue }
    $newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $position = $match.Groups[1].Index + $match.Groups[1].Length
    $updated = $text.Insert($position, ($newline + '    .EXTERNALHELP OSDStage-help.xml'))

    $beforeTokens = $null; $beforeErrors = $null
    $afterTokens = $null; $afterErrors = $null
    [void][Management.Automation.Language.Parser]::ParseInput($text,[ref]$beforeTokens,[ref]$beforeErrors)
    [void][Management.Automation.Language.Parser]::ParseInput($updated,[ref]$afterTokens,[ref]$afterErrors)
    if (@($beforeErrors).Count -or @($afterErrors).Count) { throw "Help annotation parse failure: $name" }
    $before = @($beforeTokens | Where-Object Kind -ne 'Comment' | ForEach-Object { '{0}:{1}' -f $_.Kind,$_.Text })
    $after = @($afterTokens | Where-Object Kind -ne 'Comment' | ForEach-Object { '{0}:{1}' -f $_.Kind,$_.Text })
    if ($before.Count -ne $after.Count) { throw "Help annotation changed executable token count: $name" }
    for ($i = 0; $i -lt $before.Count; $i++) {
        if ($before[$i] -cne $after[$i]) { throw "Help annotation changed executable tokens: $name" }
    }
    $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191
    [IO.File]::WriteAllText($path,$updated,[Text.UTF8Encoding]::new($bom))
    $changed++
}
Write-Host "Connected $changed existing comment-help topic(s) to packaged MAML; executable tokens unchanged."
