function Test-OSDAppPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PackagePath,

        [ValidateSet('App','Script','Font','Certificate')]
        [string]$PackageType = 'App',

        [ValidateSet('Root','CA')][string]$CertificateStore
    )

    $resolved = (Resolve-Path -LiteralPath $PackagePath -ErrorAction Stop).Path
    $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("OSDApps-" + [guid]::NewGuid().Guid)

    # Validation reads the input and owns only this unique temporary directory.
    # A caller's WhatIf/Confirm must not skip its cleanup or prompt for scratch
    # operations. These preferences are local to this function: the caller still
    # decides whether its destination changes are approved via ShouldProcess.
    $WhatIfPreference = $false
    $ConfirmPreference = 'None'

    try {
        New-Item -ItemType Directory -Path $temp -Force | Out-Null
        Expand-Archive -LiteralPath $resolved -DestinationPath $temp -Force

        $packageFolder = Join-Path $temp 'Package'
        $installScript = Join-Path $packageFolder 'Install.ps1'
        $packageFolderExists = Test-Path -LiteralPath $packageFolder -PathType Container
        $installScriptExists = Test-Path -LiteralPath $installScript -PathType Leaf
        $fontFiles = @(
            if ($packageFolderExists) {
                Get-ChildItem -LiteralPath $packageFolder -File -Recurse -ErrorAction SilentlyContinue |
                    Where-Object { $_.Extension.ToLowerInvariant() -in @('.ttf','.otf') }
            }
        )
        $certificateCount=0
        $validationError=$null
        $valid = if ($PackageType -eq 'Certificate') {
            try {
                if (-not $packageFolderExists -or @(Get-ChildItem -LiteralPath $temp -Force).Count -ne 1) { throw 'Certificate ZIP must contain only the Package directory.' }
                $store=if($CertificateStore){$CertificateStore}else{'CA'}
                $operations=@(Get-OSDAppCertificatePackageOperations -PayloadRoot $packageFolder -Store $store)
                $certificateCount=$operations.Count
                $true
            }
            catch { $validationError=$_.Exception.Message;$false }
        }
        elseif ($PackageType -eq 'Font') {
            ($packageFolderExists -and $fontFiles.Count -gt 0)
        }
        else {
            ($packageFolderExists -and $installScriptExists)
        }

        [pscustomobject]@{
            PSTypeName          = 'OSDApps.PackageValidation'
            PackagePath         = $resolved
            PackageFolderExists = $packageFolderExists
            PackageType         = $PackageType
            InstallPs1Exists    = $installScriptExists
            FontCount           = $fontFiles.Count
            CertificateCount    = $certificateCount
            Error               = $validationError
            Sha256              = (Get-FileHash -LiteralPath $resolved -Algorithm SHA256).Hash
            Valid               = $valid
        }
    }
    finally {
        Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
