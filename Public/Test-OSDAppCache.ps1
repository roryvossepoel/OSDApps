function Test-OSDAppCache {
    [CmdletBinding()]
    param(
        [string[]]$Name,
        [switch]$ResolveVersions,
        [switch]$VerifySignatures,
        [ValidateNotNullOrEmpty()]
        [string]$CachePath
    )

    $resolvedCachePath = $null
    if ($PSBoundParameters.ContainsKey('CachePath')) {
        $resolvedCachePath = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($CachePath))
    }
    else {
        try { $resolvedCachePath = Get-OSDAppCachePath } catch { }
    }

    if (-not $resolvedCachePath -or -not (Test-Path -LiteralPath $resolvedCachePath -PathType Container)) {
        return [pscustomobject]@{
            PSTypeName               = 'OSDApps.CacheValidation'
            CachePath                = $resolvedCachePath
            CacheAvailable           = $false
            EntryCount               = 0
            ValidEntryCount          = 0
            InvalidEntryCount        = 0
            TotalSizeMB              = 0
            SignatureChecksRequested = [bool]$VerifySignatures
            SignatureChecksComplete  = $false
            SignatureFailureCount    = 0
            Entries                  = @()
            Valid                    = $false
        }
    }

    $inventoryParameters = @{
        Name             = $Name
        ResolveVersions  = [bool]$ResolveVersions
        VerifySignatures = [bool]$VerifySignatures
        CachePath        = $resolvedCachePath
    }
    $entries = @(Get-OSDAppCache @inventoryParameters)
    $invalidEntries = @($entries | Where-Object { -not $_.Valid })
    $validEntries = @($entries | Where-Object { $_.Valid })
    $signatureCandidates = @(
        $entries | Where-Object {
            $_.Source -eq 'BuiltIn' -and
            $_.SignatureStatus -ne 'Not assessed' -and
            $_.SignatureScope
        }
    )
    $signatureFailures = @(
        $signatureCandidates | Where-Object {
            $_.SignatureStatus -notin @('Valid', 'Unavailable in WinPE')
        }
    )
    $signatureChecksComplete = if (-not $VerifySignatures) {
        $false
    }
    else {
        @($signatureCandidates | Where-Object { $_.SignatureStatus -ne 'Valid' }).Count -eq 0
    }
    $totalSize = ($entries | Measure-Object -Property SizeMB -Sum).Sum
    if ($null -eq $totalSize) { $totalSize = 0 }

    [pscustomobject]@{
        PSTypeName               = 'OSDApps.CacheValidation'
        CachePath                = $resolvedCachePath
        CacheAvailable           = $true
        EntryCount               = $entries.Count
        ValidEntryCount          = $validEntries.Count
        InvalidEntryCount        = $invalidEntries.Count
        TotalSizeMB              = [math]::Round([double]$totalSize, 1)
        SignatureChecksRequested = [bool]$VerifySignatures
        SignatureChecksComplete  = $signatureChecksComplete
        SignatureFailureCount    = $signatureFailures.Count
        Entries                  = @($entries)
        Valid                    = (
            $entries.Count -gt 0 -and
            $invalidEntries.Count -eq 0 -and
            (-not $VerifySignatures -or $signatureChecksComplete)
        )
    }
}
