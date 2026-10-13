function Resolve-OSDAppCatalogPackageVariant {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Package,

        [ValidateSet('x64','arm64')]
        [string]$Architecture = (Get-OSDAppHostArchitecture)
    )

    $resolved = [System.Collections.Generic.List[object]]::new()

    foreach ($group in @($Package | Group-Object Id)) {
        $exact = @(
            $group.Group |
                Where-Object {
                    ([string]$_.Architecture).ToLowerInvariant() -eq $Architecture
                }
        )
        $neutral = @(
            $group.Group |
                Where-Object {
                    ([string]$_.Architecture).ToLowerInvariant() -eq 'any'
                }
        )

        if ($exact.Count -gt 1) {
            throw "Catalog contains more than one '$Architecture' package variant for '$($group.Name)'."
        }
        if ($neutral.Count -gt 1) {
            throw "Catalog contains more than one 'any' package variant for '$($group.Name)'."
        }

        if ($exact.Count -eq 1) {
            $resolved.Add($exact[0])
        }
        elseif ($neutral.Count -eq 1) {
            $resolved.Add($neutral[0])
        }
        else {
            throw "No compatible package variant for '$($group.Name)' on '$Architecture'. Available: $((@($group.Group.Architecture) -join ', '))"
        }
    }

    @($resolved)
}
