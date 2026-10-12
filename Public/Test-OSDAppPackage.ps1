function Test-OSDAppPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PackagePath
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

        [pscustomobject]@{
            PSTypeName          = 'OSDApps.PackageValidation'
            PackagePath         = $resolved
            PackageFolderExists = $packageFolderExists
            InstallPs1Exists    = $installScriptExists
            Sha256              = (Get-FileHash -LiteralPath $resolved -Algorithm SHA256).Hash
            Valid               = ($packageFolderExists -and $installScriptExists)
        }
    }
    finally {
        Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
