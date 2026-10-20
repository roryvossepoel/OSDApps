function Get-OSDAppExpectedPublisher {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id)

    # Expected certificate organization. No thumbprint pinning: vendor
    # signing certificates rotate. Treat a changed publisher as a release
    # blocker requiring review, not a reason to silently trust a new one.
    switch ($Id) {
        'Microsoft365Apps'         { 'Microsoft Corporation'; break }
        'MicrosoftTeams'           { 'Microsoft Corporation'; break }
        'VisualStudioCode'         { 'Microsoft Corporation'; break }
        'VisualCppRedist'          { 'Microsoft Corporation'; break }
        'DotNetRuntime'            { 'Microsoft Corporation'; break }
        'GoogleChromeEnterprise'   { 'Google LLC'; break }
        'CiscoWebex'               { 'Cisco Systems, Inc.'; break }
        'ZoomWorkplace'            { 'Zoom Communications, Inc.'; break }
        'MozillaFirefoxEnterprise' { 'Mozilla Corporation'; break }
        default                    { $null }
    }
}

function Test-OSDAppExpectedPublisher {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [string]$SignerSubject
    )

    $expected = Get-OSDAppExpectedPublisher -Id $Id
    if (-not $expected -or [string]::IsNullOrWhiteSpace($SignerSubject)) { return $false }

    # Extract the O= organization attribute, accepting quoted commas in an
    # RFC 2253-style subject such as Cisco Systems, Inc. Other attributes
    # including OU and CN do NOT grant publisher approval.
    $match = [regex]::Match($SignerSubject, '(?:^|,\s*)O=(?:"(?<quoted>(?:[^"]|"")*)"|(?<plain>[^,]+))(?=,|$)')
    if (-not $match.Success) { return $false }
    $org = if ($match.Groups['quoted'].Success) {
        $match.Groups['quoted'].Value.Replace('""','"')
    } else { $match.Groups['plain'].Value.Trim() }
    return [string]::Equals($org,$expected,[StringComparison]::OrdinalIgnoreCase)
}

function Assert-OSDAppBuiltInSignature {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$FilePath
    )

    $signature = Get-OSDAppBuiltInSignature -Id $Id -FilePath $FilePath -CheckPublisher
    if ($signature.Status -ne 'Valid') {
        throw "Built-in '$Id' was rejected: signature status '$($signature.Status)' for '$FilePath'. Expected publisher: $(Get-OSDAppExpectedPublisher -Id $Id). Actual signer: $($signature.Signer)."
    }
    return $signature
}

function Get-OSDAppBuiltInSignature {
    <#
    .SYNOPSIS
    Inspects a cached built-in package's Authenticode signature without changing it.
    .NOTES
    Windows trust evaluation is environment- and time-dependent. A valid signature
    is not a guarantee of a current package or malware-free content. Windows may
    contact a revocation service when checking certificate trust.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [string]$CacheEntryPath,
        [string]$FilePath,
        [switch]$CheckPublisher
    )

    if ($Id -eq '7Zip') {
        return [pscustomobject]@{ Status='Not assessed'; Scope='Release SHA-256 (checked separately)'; File=$null; Signer=$null; Detail='7Zip uses the official release digest, not Authenticode publisher validation.' }
    }

    $relativeFile = switch ($Id) {
        'Microsoft365Apps'         { 'setup.exe'; break }
        'MicrosoftTeams'           { 'teamsbootstrapper.exe'; break }
        'VisualStudioCode'         { 'Package.exe'; break }
        'VisualCppRedist'          { 'Package.exe'; break }
        'DotNetRuntime'            { 'Package.exe'; break }
        'GoogleChromeEnterprise'   { 'Package.msi'; break }
        'CiscoWebex'               { 'Package.msi'; break }
        'ZoomWorkplace'            { 'Package.msi'; break }
        'MozillaFirefoxEnterprise' { 'Package.msi'; break }
        default                    { $null }
    }

    if (-not $relativeFile) {
        return [pscustomobject]@{
            Status='Not assessed'; Scope='ZIP / unsupported type'
            File=$null; Signer=$null; Detail='An Authenticode signature was not checked for this cache format.'
        }
    }

    $scope = if ($Id -eq 'MicrosoftTeams') {
        'Bootstrapper EXE only (MSIX not checked)'
    } elseif ($Id -eq 'Microsoft365Apps') {
        'Office setup.exe only (Office data not checked)'
    } elseif ($relativeFile.EndsWith('.msi')) {
        'MSI package'
    } else {
        'EXE file'
    }

    if (-not $FilePath -and -not $CacheEntryPath) {
        throw 'Specify -CacheEntryPath or -FilePath.'
    }
    $path = if ($FilePath) { $FilePath } else { Join-Path $CacheEntryPath $relativeFile }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return [pscustomobject]@{
            Status='File missing';Scope=$scope;File=$path;Signer=$null
            Detail='Required signature target is missing.'
        }
    }
    if (Test-OSDAppWinPE) {
        return [pscustomobject]@{
            Status='Unavailable in WinPE';Scope=$scope;File=$path;Signer=$null
            Detail='Full Windows Authenticode inspection was not attempted in WinPE.'
        }
    }

    try {
        # Use the installed Windows trust provider in read-only mode.
        $signature = Get-AuthenticodeSignature -LiteralPath $path -ErrorAction Stop
        $status = [string]$signature.Status
        if (-not $status) { $status = 'UnknownError' }
        $signer = if ($signature.SignerCertificate) {
            [string]$signature.SignerCertificate.Subject
        } else { $null }
        $expectedPublisher = Get-OSDAppExpectedPublisher -Id $Id
        $publisherMatches = if ($signer -and $expectedPublisher) {
            Test-OSDAppExpectedPublisher -Id $Id -SignerSubject $signer
        } else { $false }
        if ($CheckPublisher -and $status -eq 'Valid' -and $expectedPublisher -and -not $publisherMatches) {
            $status = 'PublisherMismatch'
        }
        return [pscustomobject]@{
            Status=$status
            Scope=$scope
            File=$path
            Signer=$signer
            ExpectedPublisher=$expectedPublisher
            PublisherMatches=$publisherMatches
            Detail=if ($status -eq 'PublisherMismatch') {
                "The valid signature was not issued to expected publisher '$expectedPublisher'."
            } elseif ($signature.StatusMessage) {
                [string]$signature.StatusMessage
            } else { $status }
        }
    }
    catch {
        Write-Verbose "Authenticode inspection unavailable for '$path': $($_.Exception.Message)"
        return [pscustomobject]@{
            Status='Check failed';Scope=$scope;File=$path;Signer=$null
            Detail=$_.Exception.Message
        }
    }
}
