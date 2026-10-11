function Get-OSDAppMsiProductVersion {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    if (Test-OSDAppWinPE) { return }

    $installer = $null
    $database = $null
    $view = $null
    $record = $null
    try {
        # Windows Installer COM opens the database read-only (mode 0).
        # Never invoke installation, extraction or cache updates.
        $installer = New-Object -ComObject WindowsInstaller.Installer -ErrorAction Stop
        $database = $installer.OpenDatabase($Path, 0)
        $query = ("SELECT {0}Value{0} FROM {0}Property{0} WHERE {0}Property{0} = 'ProductVersion'" -f [char]96)
        $view = $database.OpenView($query)
        $view.Execute()
        $record = $view.Fetch()
        if ($null -ne $record) {
            $version = [string]$record.StringData(1)
            if ($version -match '^\d+(?:\.\d+){1,3}$') { return $version }
        }
    }
    catch {
        Write-Verbose "MSI ProductVersion could not be read from '$Path': $($_.Exception.Message)"
    }
    finally {
        if ($view) { try { $view.Close() } catch { } }
        foreach ($comObject in @($record,$view,$database,$installer)) {
            if ($null -ne $comObject -and [System.Runtime.InteropServices.Marshal]::IsComObject($comObject)) {
                try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($comObject) } catch { }
            }
        }
    }
}

function Get-OSDAppAdobePatchVersion {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }

    $archive = $null
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
        # Opening the ZIP central directory does not unpack the multi-GB payload.
        $archive = [System.IO.Compression.ZipFile]::OpenRead($Path)
        $setupIni = @($archive.Entries |
            Where-Object { $_.FullName -match '(?i)(^|/)setup\.ini$' -and $_.Length -le 1MB } |
            Select-Object -First 1)
        if ($setupIni.Count -eq 0) { return }

        $reader = [System.IO.StreamReader]::new($setupIni[0].Open())
        try { $ini = $reader.ReadToEnd() }
        finally { $reader.Dispose() }

        $patch = [regex]::Match($ini,'(?im)^\s*PATCH\s*=\s*(?<patch>[^\r\n;]+)')
        if (-not $patch.Success) { return }
        $patchName = [System.IO.Path]::GetFileName($patch.Groups['patch'].Value.Trim().Trim('"'))
        # Example: AcrobatDCx64Upd2600221931.msp -> 26.002.21931
        $match = [regex]::Match($patchName,'(?i)^AcrobatDC(?:x64)?Upd(?<major>\d{2})(?<minor>\d{3})(?<build>\d{5})\.msp$')
        if ($match.Success) {
            return '{0}.{1}.{2}' -f $match.Groups['major'].Value,$match.Groups['minor'].Value,$match.Groups['build'].Value
        }
    }
    catch {
        Write-Verbose "Adobe Acrobat patch version could not be read from '$Path': $($_.Exception.Message)"
    }
    finally {
        if ($archive) { $archive.Dispose() }
    }
}

function Get-OSDAppCachedPackageVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$CacheEntryPath
    )

    $version = $null
    $source = $null
    switch ($Id) {
        { $_ -in @('GoogleChromeEnterprise','CiscoWebex','MozillaFirefoxEnterprise') } {
            $version = Get-OSDAppMsiProductVersion -Path (Join-Path $CacheEntryPath 'Package.msi')
            if ($version) { $source = 'MsiProductVersion' }
            break
        }
        'AdobeAcrobatUnified' {
            $version = Get-OSDAppAdobePatchVersion -Path (Join-Path $CacheEntryPath 'Package.zip')
            if ($version) { $source = 'AdobePatchFileName' }
            break
        }
    }

    [pscustomobject]@{
        Version = if ($version) { [string]$version } else { $null }
        VersionSource = $source
    }
}
