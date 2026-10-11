function Assert-PesterSuccess {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowNull()]$Result)

    if ($null -eq $Result) { throw 'Pester returned no result object.' }
    $total = [int]$Result.TotalCount
    $failed = [int]$Result.FailedCount
    $notRun = [int]$Result.NotRunCount
    if ([string]$Result.Result -ne 'Passed' -or $total -le 0 -or $failed -gt 0 -or $notRun -gt 0) {
        throw "Pester did not complete successfully: Result=$($Result.Result); Total=$total; Failed=$failed; NotRun=$notRun. Check discovery, BeforeAll and container errors as well as individual tests."
    }
    foreach ($property in @('FailedBlocksCount','FailedContainersCount')) {
        if ($Result.PSObject.Properties[$property] -and [int]$Result.$property -gt 0) {
            throw "Pester reported $property=$($Result.$property)."
        }
    }
}
