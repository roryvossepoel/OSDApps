function Test-OSDAppPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PackagePath,

        [ValidateSet('App','Script','Font')]
        [string]$PackageType = 'App'
    )

    $resolved = (Resolve-Path -LiteralPath $PackagePath -ErrorAction Stop).Path
    $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("OSDApps-" + [guid]::NewGuid().Guid)
    $WhatIfPreference = $false
    $ConfirmPreference = 'None'

    try {
        New-Item -ItemType Directory -Path $temp -Force | Out-Null
        Expand-Archive -LiteralPath $resolved -DestinationPath $temp -Force

        $packageFolder = Join-Path $temp 'Package'
        $installScript = Join-Path $packageFolder 'Install.ps1'
        $packageFolderExists = Test-Path -LiteralPath $packageFolder -PathType Container
        $installScriptExists = Test-Path -LiteralPath $installScript -PathType Leaf
        $fontFiles = @()
        if ($packageFolderExists) {
            $fontFiles = @(Get-ChildItem -LiteralPath $packageFolder -File -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension.ToLowerInvariant() -in @('.ttf','.otf') })
        }

        $valid = if ($PackageType -eq 'Font') {
            $packageFolderExists -and $fontFiles.Count -gt 0
        }
        else {
            $packageFolderExists -and $installScriptExists
        }

        [pscustomobject]@{
            PSTypeName          = 'OSDApps.PackageValidation'
            PackagePath         = $resolved
            PackageType         = $PackageType
            PackageFolderExists = $packageFolderExists
            InstallPs1Exists    = $installScriptExists
            FontFileCount       = $fontFiles.Count
            Sha256              = (Get-FileHash -LiteralPath $resolved -Algorithm SHA256).Hash
            Valid               = $valid
        }
    }
    finally {
        Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
