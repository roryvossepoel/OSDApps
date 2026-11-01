[CmdletBinding()]
param(
    [string]$ManifestPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'OSDStage.psd1'),
    [string]$ExpectedVersion
)

$ErrorActionPreference = 'Stop'
$data = Import-PowerShellDataFile -LiteralPath $ManifestPath
$numeric = [string]$data.ModuleVersion
if ($numeric -notmatch '^\d+\.\d+\.\d+(\.\d+)?$') { throw 'ModuleVersion must be a numeric module version.' }
$label = ''
if ($data.ContainsKey('PrivateData') -and $data.PrivateData.PSData -and $data.PrivateData.PSData.ContainsKey('Prerelease')) {
    $label = [string]$data.PrivateData.PSData.Prerelease
}
if ($label -and ($numeric -notmatch '^\d+\.\d+\.\d+$' -or $label -notmatch '^[A-Za-z][A-Za-z0-9]*$')) {
    throw 'Prerelease requires a three-part ModuleVersion and an alphanumeric label beginning with a letter, such as rc1.'
}
$version = if ($label) { "$numeric-$label" } else { $numeric }
if ($ExpectedVersion -and $ExpectedVersion -cne $version) {
    throw "Expected version '$ExpectedVersion' does not match manifest release '$version'."
}
[pscustomobject]@{
    ModuleVersion = $numeric
    Version = $version
    Tag = "v$version"
    IsPrerelease = [bool]$label
}
