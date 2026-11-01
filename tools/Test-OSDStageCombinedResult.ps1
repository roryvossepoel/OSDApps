# Manual read-only check after normal SetupComplete/OOBE. No tasks or repairs.
[CmdletBinding()]
param(
    [string]$RecordPath = "$env:ProgramData\OSDStage\Tests\Combined-Staging.json",
    [string]$ResultPath = "$env:ProgramData\OSDStage\Results\Latest.json",
    [string]$StagePath = "$env:SystemRoot\Temp\OSDStage"
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$record = Get-Content -LiteralPath $RecordPath -Raw | ConvertFrom-Json
$result = Get-Content -LiteralPath $ResultPath -Raw | ConvertFrom-Json
$guid = [guid]::Empty
if (-not [guid]::TryParse([string]$record.DeploymentId,[ref]$guid) -or $guid -eq [guid]::Empty) { throw 'Invalid staging deployment ID.' }
if ($record.Revision -notmatch '^[a-fA-F0-9]{40}$') { throw 'Missing pinned module revision.' }
if ($record.DeploymentId -ne $result.DeploymentId) { throw 'Result belongs to another deployment.' }
$expected = @($record.ExpectedIds)
$actual = @($result.Packages)
if ($expected.Count -ne 16 -or @($expected | Sort-Object -Unique).Count -ne $expected.Count -or
    @($expected | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count) { throw 'Invalid combined test selection record.' }
$required = @('GoogleChromeEnterprise','AdobeAcrobatUnified','RegistrySettings','EnvironmentVariables','Services','WindowsFeatures','WindowsCapabilities','WiFiProfiles','DesktopSettings','WindowsInboxCleanup','DefaultAssociations')
foreach ($id in $required) { if ($expected -notcontains $id) { throw ('Missing combined test feature: ' + $id) } }
if ($actual.Count -ne $expected.Count -or @(Compare-Object ($expected | Sort-Object) (@($actual.Id) | Sort-Object)).Count) {
    throw 'Result does not contain exactly the expected package IDs.'
}
if ($result.Status -ne 'Succeeded' -or @($actual | Where-Object Status -ne 'Succeeded').Count -ne 0) {
    throw 'The runner has not completed every selected entry successfully.'
}
foreach ($field in @('ExpectedPackageCount','SuccessfulPackageCount','FailedPackageCount','SkippedPackageCount')) {
    $wanted = if ($field -in @('ExpectedPackageCount','SuccessfulPackageCount')) { $expected.Count } else { 0 }
    if ($result.$field -isnot [int] -and $result.$field -isnot [long]) { throw ('Invalid result counter: ' + $field) }
    if ($result.$field -ne $wanted) { throw ('Unexpected result counter: ' + $field) }
}
if ($record.CleanupMode -ne 'OnSuccess' -or $result.CleanupMode -ne 'OnSuccess') { throw 'This profile requires OnSuccess cleanup.' }
if (Test-Path -LiteralPath $StagePath) { throw 'Staging still exists. Cleanup is pending or failed; do not report cleanup as passed.' }
[pscustomobject]@{
    DeploymentId=$record.DeploymentId; Revision=$record.Revision; RunnerStatus='Succeeded'
    EntryCount=$actual.Count; StagingRemoved=$true; UserExperience='Manual acceptance still required'
}
