[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'dist')
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Path $PSScriptRoot -Parent
$manifestPath = Join-Path $root 'OSDStage.psd1'
$manifest = Test-ModuleManifest -Path $manifestPath
$moduleOutput = Join-Path $OutputPath 'OSDStage'

if (Test-Path -LiteralPath $moduleOutput) {
    Remove-Item -LiteralPath $moduleOutput -Recurse -Force
}
New-Item -ItemType Directory -Path $moduleOutput -Force | Out-Null

$items = @(
    'OSDStage.psd1'
    'OSDStage.psm1'
    'Public'
    'Private'
    'Runtime'
    'metadata'
    'README.md'
    'CHANGELOG.md'
    'LICENSE'
)

foreach ($item in $items) {
    $source = Join-Path $root $item
    if (Test-Path -LiteralPath $source) {
        Copy-Item -LiteralPath $source -Destination $moduleOutput -Recurse -Force
    }
}

$builtManifest = Join-Path $moduleOutput 'OSDStage.psd1'
Test-ModuleManifest -Path $builtManifest -ErrorAction Stop | Out-Null

# External help is generated in the package; source functions are unchanged.
& (Join-Path $PSScriptRoot 'New-CommandHelp.ps1') -ModulePath $moduleOutput | Out-Null
# Existing comment-based help otherwise takes precedence. Annotate only built
# copies, proving their non-comment token streams remain byte-for-byte equal.
& (Join-Path $PSScriptRoot 'Connect-PackagedHelp.ps1') -ModulePath $moduleOutput

Remove-Module OSDStage -Force -ErrorAction SilentlyContinue
Import-Module $builtManifest -Force -ErrorAction Stop

[pscustomobject]@{
    Name = $manifest.Name
    Version = $manifest.Version.ToString()
    Path = $moduleOutput
    Manifest = $builtManifest
}
