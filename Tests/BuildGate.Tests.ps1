Describe 'Pester build result gate' {
    BeforeAll {
        . (Join-Path (Split-Path $PSScriptRoot -Parent) 'build\Assert-PesterSuccess.ps1')
    }
    It 'accepts a completed non-empty passing run' {
        $result = [pscustomobject]@{ Result='Passed'; TotalCount=12; FailedCount=0; NotRunCount=0; FailedBlocksCount=0; FailedContainersCount=0 }
        { Assert-PesterSuccess -Result $result } | Should -Not -Throw
    }
    It 'rejects a discovery failure even when zero tests are marked failed' {
        $result = [pscustomobject]@{ Result='Failed'; TotalCount=0; FailedCount=0; NotRunCount=0; FailedContainersCount=1 }
        { Assert-PesterSuccess -Result $result } | Should -Throw
    }
    It 'rejects empty, missing and incomplete test results' {
        { Assert-PesterSuccess -Result $null } | Should -Throw
        { Assert-PesterSuccess -Result ([pscustomobject]@{ Result='Passed'; TotalCount=0; FailedCount=0; NotRunCount=0 }) } | Should -Throw
        { Assert-PesterSuccess -Result ([pscustomobject]@{ Result='Passed'; TotalCount=3; FailedCount=0; NotRunCount=2 }) } | Should -Throw
    }
    It 'rejects block/container failures independently of the individual failed count' {
        foreach ($field in @('FailedBlocksCount','FailedContainersCount')) {
            $result = [pscustomobject]@{ Result='Passed'; TotalCount=3; FailedCount=0; NotRunCount=0 }
            $result | Add-Member -NotePropertyName $field -NotePropertyValue 1
            { Assert-PesterSuccess -Result $result } | Should -Throw
        }
    }
}
