function Add-OSDStageDriver {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position=0)]
        [Alias('Name')]
        [string]$Id,

        [string]$WindowsPath,

        [switch]$SkipCacheRefresh
    )

    Assert-OSDStageSourceEnabled -Source Repository

    $matches = @(
        Get-OSDStage -Name $Id -Offline:$SkipCacheRefresh |
            Where-Object { [string]$_.Source -eq 'Repository' -and [string]$_.Id -ieq $Id }
    )
    if ($matches.Count -ne 1) {
        throw "Repository driver package '$Id' was not found uniquely in the configured catalog/cache."
    }
    if ([string]$matches[0].PackageType -ne 'Driver') {
        throw "Repository package '$Id' is PackageType '$($matches[0].PackageType)', not Driver."
    }

    if (-not $PSCmdlet.ShouldProcess($Id, 'Stage repository driver package for SetupComplete')) {
        return
    }

    Add-OSDStage -Name $Id -WindowsPath $WindowsPath -SkipCacheRefresh:$SkipCacheRefresh -Confirm:$false
}
