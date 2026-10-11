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
        [Parameter(Mandatory)][string]$CacheEntryPath
    )

    $relativeFile = switch ($Id) {
        'Microsoft365Apps'         { 'setup.exe'; break }
        'MicrosoftTeams'           { 'teamsbootstrapper.exe'; break }
        'GoogleChromeEnterprise'   { 'Package.msi'; break }
        'CiscoWebex'               { 'Package.msi'; break }
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

    $path = Join-Path $CacheEntryPath $relativeFile
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
        return [pscustomobject]@{
            Status=$status
            Scope=$scope
            File=$path
            Signer=$signer
            Detail=if ($signature.StatusMessage) { [string]$signature.StatusMessage } else { $status }
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
