# Run on the full Windows preparation PC with the OSDCloud USB connected.
[CmdletBinding()]
param([Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{40}$')][string]$Revision)
$ErrorActionPreference='Stop'
if (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT') { throw 'Prepare this test module on full Windows, not WinPE.' }
$volumes=@(Get-Volume | Where-Object { $_.FileSystemLabel -eq 'OSDCloud' -and $_.DriveLetter })
if ($volumes.Count -ne 1) { throw 'Expected exactly one mounted volume labeled OSDCloud.' }
$usbRoot=('{0}:\' -f $volumes[0].DriveLetter)
$destination=Join-Path $usbRoot ('TestModules\OSDStage-DefaultAssociations-' + $Revision.Substring(0,7).ToLowerInvariant())
if (Test-Path -LiteralPath $destination) { throw ('Test module directory already exists: ' + $destination) }
$temp=Join-Path ([IO.Path]::GetTempPath()) ('OSDStageDefaultAssociations-' + [guid]::NewGuid().ToString('N'))
$promoted=$false
try {
    New-Item -ItemType Directory -Path $temp -Force | Out-Null
    $archive=Join-Path $temp 'source.zip'
    [Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri ('https://github.com/roryvossepoel/OSDApps/archive/' + $Revision + '.zip') -OutFile $archive -UseBasicParsing
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::ExtractToDirectory($archive,(Join-Path $temp 'source'))
    $roots=@(Get-ChildItem -LiteralPath (Join-Path $temp 'source') -Directory | Where-Object {
        Test-Path -LiteralPath (Join-Path $_.FullName 'OSDStage.psd1') -PathType Leaf
    })
    if ($roots.Count -ne 1) { throw 'Expected one OSDStage module in the pinned source archive.' }
    $source=$roots[0].FullName
    $manifest=Join-Path $source 'OSDStage.psd1'
    if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { throw 'The pinned source archive does not contain the expected module.' }
    $info=Test-ModuleManifest -Path $manifest -ErrorAction Stop
    foreach ($command in @('Add-OSDStageDefaultAssociation')) {
        if (-not $info.ExportedFunctions.ContainsKey($command)) { throw ('Missing command: ' + $command) }
    }
    New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Recurse -ErrorAction Stop
    $promoted=$true
    $Revision | Set-Content -LiteralPath (Join-Path $destination 'TestRevision.txt') -Encoding ASCII
    [pscustomobject]@{Revision=$Revision;ModulePath=(Join-Path $destination 'OSDStage.psd1');ExamplePath=(Join-Path $destination 'Examples\Stage-OSDStageDefaultAssociationsTest.ps1')}
}
catch {
    if (-not $promoted -and (Test-Path -LiteralPath $destination)) { Remove-Item -LiteralPath $destination -Recurse -Force }
    throw
}
finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force } }
