Describe 'Mega result report acceptance' {
    BeforeAll {
        $source = Get-Content (Join-Path (Split-Path $PSScriptRoot -Parent) 'tools/Test-OSDStageMega.ps1') -Raw
        $start = $source.IndexOf("    `$required = @(")
        $end = $source.IndexOf("    `$checks.Add([pscustomobject]@{Name='Physical deployment result'",$start)
        if ($start -lt 0 -or $end -le $start) { throw 'Mega report validation block not found.' }
        $script:validateRecord = [scriptblock]::Create('param($deployment)' + "`n" + $source.Substring($start,$end-$start) + "`n" + '$passed')
    }
    BeforeEach {
        $script:record = [pscustomobject]@{
            DeploymentId=[guid]::NewGuid().ToString();Status='Succeeded'
            ExpectedPackageCount=1;SuccessfulPackageCount=1;FailedPackageCount=0;SkippedPackageCount=0
            Packages=@([pscustomobject]@{Id='Chrome';Status='Succeeded';PackageType='App'})
        }
    }
    It 'accepts matching complete success evidence' { & $script:validateRecord $record | Should -BeTrue }
    It 'rejects an empty entry array despite successful counters' {
        $record.Packages=@()
        & $script:validateRecord $record | Should -BeFalse
    }
    It 'rejects duplicate IDs despite successful counters' {
        $record.ExpectedPackageCount=2;$record.SuccessfulPackageCount=2
        $record.Packages=@($record.Packages[0],$record.Packages[0])
        & $script:validateRecord $record | Should -BeFalse
    }
    It 'rejects missing fields instead of treating missing failure counts as zero' {
        $record.PSObject.Properties.Remove('FailedPackageCount')
        & $script:validateRecord $record | Should -BeFalse
    }
    It 'rejects invalid deployment identity or a failed entry' {
        $record.DeploymentId='invalid'
        & $script:validateRecord $record | Should -BeFalse
        $record.DeploymentId=[guid]::NewGuid().ToString();$record.Packages[0].Status='Failed'
        & $script:validateRecord $record | Should -BeFalse
    }
}
