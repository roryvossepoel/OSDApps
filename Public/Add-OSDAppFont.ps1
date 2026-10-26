function Add-OSDAppFont {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position=0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string[]]$Id,
        [string]$WindowsPath,
        [switch]$SkipCacheRefresh
    )

    begin {
        Assert-OSDAppSourceEnabled -Source Repository
        $requested = [System.Collections.Generic.List[string]]::new()
    }
    process {
        foreach ($item in $Id) {
            if (-not [string]::IsNullOrWhiteSpace($item)) { $requested.Add($item) }
        }
    }
    end {
        $ids = @($requested | Select-Object -Unique)
        if ($ids.Count -eq 0) { throw 'No font package Ids were supplied.' }

        foreach ($idValue in $ids) {
            $matches = @(Get-OSDApp -Name $idValue | Where-Object Source -eq 'Repository')
            if ($matches.Count -ne 1) {
                throw "Repository font package '$idValue' could not be resolved uniquely."
            }
            if ([string]$matches[0].PackageType -ne 'Font') {
                throw "Repository package '$idValue' has PackageType '$($matches[0].PackageType)', not Font."
            }
        }

        if (-not $PSCmdlet.ShouldProcess(($ids -join ', '), 'Stage repository font package(s) for SetupComplete')) { return }

        Add-OSDApp -Name $ids -WindowsPath $WindowsPath -SkipCacheRefresh:$SkipCacheRefresh -Confirm:$false
    }
}
