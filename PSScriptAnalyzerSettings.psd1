@{
    Severity = @('Error','Warning')

    ExcludeRules = @(
        # OSDStage intentionally uses Write-Host only through its console helper
        # for deployment-oriented interactive output.
        'PSAvoidUsingWriteHost'
    )
}
