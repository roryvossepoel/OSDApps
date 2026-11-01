[CmdletBinding()]
param(
    [string]$Root = (Split-Path $PSScriptRoot -Parent),
    [string[]]$Files
)

$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\','/')
if (-not $Files) {
    $Files = @(Get-ChildItem -LiteralPath $Root -Filter '*.md' -File -Recurse |
        Where-Object { $_.FullName -notmatch '[\\/](\.git|dist|TestResults)[\\/]' } |
        ForEach-Object { $_.FullName })
}
$problems = [System.Collections.Generic.List[string]]::new()
$anchorCache = @{}
$checkedLinks = 0
$checkedBlocks = 0
$checkedCalls = 0
$commands = @{}
$manifestPath = Join-Path $Root 'OSDStage.psd1'
if (Test-Path -LiteralPath $manifestPath) {
    $module = Import-Module $manifestPath -Force -PassThru -ErrorAction Stop
    foreach ($name in $module.ExportedFunctions.Keys) { $commands[$name] = $module.ExportedFunctions[$name] }
}

function Get-MarkdownAnchorSet {
    param([string]$Path)
    if ($anchorCache.ContainsKey($Path)) { return ,$anchorCache[$Path] }
    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $text = [regex]::Replace($text,'(?ms)^[ \t]*(?<fence>`{3,}|~{3,})(?![`~])[^\r\n]*\r?\n.*?^[ \t]*\k<fence>[ \t]*\r?$','')
    $anchors = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $seen = @{}
    foreach ($heading in [regex]::Matches($text,'(?m)^#{1,6}[ \t]+(.+?)[ \t]*#*[ \t]*\r?$')) {
        $value = [regex]::Replace($heading.Groups[1].Value.ToLowerInvariant(),'[^\p{L}\p{N}_\-\s]','')
        $value = [regex]::Replace($value,'\s','-')
        $base = $value
        if ($seen.ContainsKey($base)) {
            $seen[$base]++
            $value = "$base-$($seen[$base])"
        } else { $seen[$base] = 0 }
        [void]$anchors.Add($value)
    }
    foreach ($anchor in [regex]::Matches($text,'(?i)<a\s+(?:id|name)=["'']([^"'']+)["'']')) {
        [void]$anchors.Add($anchor.Groups[1].Value)
    }
    $anchorCache[$Path] = $anchors
    return ,$anchors
}

foreach ($file in $Files) {
    $fullPath = (Resolve-Path -LiteralPath $file).Path
    $relative = $fullPath.Substring($Root.Length).TrimStart('\','/').Replace('\','/')
    $text = Get-Content -LiteralPath $fullPath -Raw -Encoding UTF8
    $blocks = [regex]::Matches($text,'(?ms)^[ \t]*(?<fence>`{3,}|~{3,})(?![`~])(?<lang>[A-Za-z0-9_-]*)[^\r\n]*\r?\n(?<code>.*?)^[ \t]*\k<fence>[ \t]*\r?$')
    foreach ($block in $blocks) {
        if ($block.Groups['lang'].Value -notin @('powershell','ps1','pwsh')) { continue }
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($block.Groups['code'].Value,[ref]$tokens,[ref]$parseErrors)
        $checkedBlocks++
        foreach ($parseError in @($parseErrors)) { $problems.Add("${relative}: PowerShell syntax: $($parseError.Message)") }
        # Historical release evidence retains its historical command vocabulary.
        if ($relative -in @('CHANGELOG.md','docs/testing.md','docs/performance.md')) { continue }
        foreach ($call in $ast.FindAll({param($node) $node -is [System.Management.Automation.Language.CommandAst]},$true)) {
            $name = $call.GetCommandName()
            if ($name -notmatch '^[A-Za-z]+-OSDStage[0-9A-Za-z]*$' -or $commands.Count -eq 0) { continue }
            $checkedCalls++
            if (-not $commands.ContainsKey($name)) { $problems.Add("${relative}: unknown public command $name"); continue }
            foreach ($element in $call.CommandElements) {
                if ($element -is [System.Management.Automation.Language.CommandParameterAst] -and
                    -not $commands[$name].Parameters.ContainsKey($element.ParameterName)) {
                    $problems.Add("${relative}: unknown parameter $name -$($element.ParameterName)")
                }
            }
        }
    }
    $prose = [regex]::Replace($text,'(?ms)^[ \t]*(?<fence>`{3,}|~{3,})(?![`~])[^\r\n]*\r?\n.*?^[ \t]*\k<fence>[ \t]*\r?$','')
    foreach ($link in [regex]::Matches($prose,'!?\[[^\]\r\n]*\]\(([^\s)]+)(?:\s+"[^"]*")?\)')) {
        $target = $link.Groups[1].Value.Trim('<','>')
        if ($target -match '^[A-Za-z][A-Za-z0-9+.-]*:' -or $target.StartsWith('//')) { continue }
        $parts = $target -split '#',2
        $pathPart = [uri]::UnescapeDataString(($parts[0] -split '\?',2)[0])
        $resolved = if (-not $pathPart) { $fullPath }
            elseif ($pathPart.StartsWith('/')) { Join-Path $Root $pathPart.TrimStart('/') }
            else { Join-Path (Split-Path $fullPath -Parent) $pathPart }
        $resolved = [IO.Path]::GetFullPath($resolved)
        $checkedLinks++
        if (-not (Test-Path -LiteralPath $resolved)) { $problems.Add("${relative}: missing local target $target"); continue }
        if ($parts.Count -gt 1 -and $parts[1] -and [IO.Path]::GetExtension($resolved) -eq '.md') {
            $anchors = Get-MarkdownAnchorSet -Path $resolved
            $fragment = [uri]::UnescapeDataString($parts[1])
            if (-not $anchors.Contains($fragment)) { $problems.Add("${relative}: missing section anchor $target") }
        }
    }
}
if ($problems.Count) { throw ($problems -join [Environment]::NewLine) }
[pscustomobject]@{
    FilesChecked = @($Files).Count
    LocalLinksChecked = $checkedLinks
    PowerShellBlocksParsed = $checkedBlocks
    OSDStageCallsChecked = $checkedCalls
    ExamplesExecuted = $false
    ExternalLinksRequested = $false
}
