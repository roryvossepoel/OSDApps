function Test-OSDAppOfficeCacheGeneration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$OfficeRoot,
        [string]$ExpectedVersion,
        [ValidateSet('x64','x86')][string]$Architecture = 'x64',
        [switch]$PassThru
    )

    $setupPath = Join-Path $OfficeRoot 'setup.exe'
    $configPath = Join-Path $OfficeRoot 'configuration.xml'
    $dataPath = Join-Path $OfficeRoot 'Office\Data'
    $prefix = if ($Architecture -eq 'x64') { 'v64' } else { 'v32' }
    $errors = [System.Collections.Generic.List[string]]::new()

    if (-not (Test-Path -LiteralPath $setupPath -PathType Leaf)) { $errors.Add('setup.exe is missing.') }
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { $errors.Add('configuration.xml is missing.') }
    if (-not (Test-Path -LiteralPath $dataPath -PathType Container)) { $errors.Add('Office\Data is missing.') }

    $versions = @()
    if (Test-Path -LiteralPath $dataPath -PathType Container) {
        $versions = @(Get-ChildItem -LiteralPath $dataPath -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' })
    }
    if ($versions.Count -ne 1) { $errors.Add("Expected exactly one Office version directory; found $($versions.Count).") }
    $version = if ($versions.Count -eq 1) { $versions[0].Name } else { $null }
    if ($ExpectedVersion -and $version -ne $ExpectedVersion) { $errors.Add("Office version '$version' does not match expected version '$ExpectedVersion'.") }

    $sharedCab = Join-Path $dataPath "$prefix.cab"
    $versionCab = if ($version) { Join-Path $dataPath ("{0}_{1}.cab" -f $prefix,$version) } else { $null }
    if (-not (Test-Path -LiteralPath $sharedCab -PathType Leaf)) { $errors.Add("$prefix.cab is missing.") }
    if (-not $versionCab -or -not (Test-Path -LiteralPath $versionCab -PathType Leaf)) { $errors.Add("The version-specific $prefix CAB is missing.") }

    $sharedHash = $null
    $versionHash = $null
    if ((Test-Path -LiteralPath $sharedCab -PathType Leaf) -and $versionCab -and (Test-Path -LiteralPath $versionCab -PathType Leaf)) {
        $sharedHash = (Get-FileHash -LiteralPath $sharedCab -Algorithm SHA256).Hash
        $versionHash = (Get-FileHash -LiteralPath $versionCab -Algorithm SHA256).Hash
        if ($sharedHash -ne $versionHash) { $errors.Add("$prefix.cab does not match the active version-specific CAB.") }
    }

    $versionFileCount = if ($versions.Count -eq 1) { @(Get-ChildItem -LiteralPath $versions[0].FullName -File -Recurse -ErrorAction SilentlyContinue).Count } else { 0 }
    if ($versionFileCount -eq 0) { $errors.Add('The active Office version directory contains no files.') }

    $result = [pscustomobject]@{
        Valid = $errors.Count -eq 0
        Version = $version
        Architecture = $Architecture
        SharedCab = $sharedCab
        VersionCab = $versionCab
        SharedCabSha256 = $sharedHash
        VersionCabSha256 = $versionHash
        VersionFileCount = $versionFileCount
        Errors = @($errors)
    }
    if ($PassThru) { return $result }
    if (-not $result.Valid) { throw "Microsoft 365 Apps cache generation is inconsistent: $(@($errors) -join ' ')" }
    $true
}
