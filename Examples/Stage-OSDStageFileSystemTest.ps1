# Run in WinPE after OSDCloud with a module build containing the file system cmdlets.
# Does not deploy Windows, reboot, or modify paths outside its unique test directory.
[CmdletBinding()]
param([string]$WindowsPath)

$ErrorActionPreference = 'Stop'
$testRoot = '%ProgramData%\OSDStageFileTest-' + [guid]::NewGuid().ToString('N')
$target = @{}
if ($WindowsPath) { $target.WindowsPath = $WindowsPath }

Add-OSDStageDirectory -Path "$testRoot\Remove\Nested" @target
Add-OSDStageFile -Path "$testRoot\Remove\Nested\old.txt" -Content 'temporary' @target
Add-OSDStageDirectory -Path "$testRoot\Remove" -Remove -Recurse -Force @target
Add-OSDStageFile -Path "$testRoot\result.txt" -Content 'before' @target
Add-OSDStageFile -Path "$testRoot\result.txt" -Content 'after' -Force @target
Add-OSDStageFile -Path "$testRoot\empty.txt" @target

$source = Join-Path ([IO.Path]::GetTempPath()) ('OSDStageSource-' + [guid]::NewGuid().ToString('N') + '.bin')
try {
    [IO.File]::WriteAllBytes($source, [byte[]](0, 255, 10, 13, 128))
    Add-OSDStageFile -SourcePath $source -DestinationPath "$testRoot\copy.bin" @target
}
finally { if (Test-Path -LiteralPath $source) { Remove-Item -LiteralPath $source -Force } }

Test-OSDStageDeployment @target -ThrowOnFailure
Write-Host "File system test staged at $testRoot"
Write-Host 'After SetupComplete: result.txt = after; empty.txt = 0 bytes; copy.bin = 00-FF-0A-0D-80; Remove directory absent.'
Write-Host 'Check FileSystem-Result.json in the configured results directory. This script does not reboot.'
