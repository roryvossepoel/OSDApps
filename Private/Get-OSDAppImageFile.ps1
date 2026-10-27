function Get-OSDAppImageFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$PayloadRoot)
    Assert-OSDAppBackgroundPath -Path $PayloadRoot
    $items=@(Get-ChildItem -LiteralPath $PayloadRoot -Force -ErrorAction Stop)
    if ($items.Count -ne 1 -or $items[0].PSIsContainer -or $items[0].Extension.ToLowerInvariant() -notin @('.jpg','.jpeg','.png')) { throw 'Image packages must contain exactly one JPG, JPEG or PNG file at the Package root, with no scripts or subdirectories.' }
    $file=$items[0];Assert-OSDAppBackgroundPath -Path $file.FullName
    if ($file.Length -lt 24 -or $file.Length -gt 20MB) { throw 'Image size must be between 24 bytes and 20 MiB.' }
    $bytes=[IO.File]::ReadAllBytes($file.FullName)
    if ($file.Extension -ieq '.png') {
        if ([BitConverter]::ToString($bytes,0,8) -ne '89-50-4E-47-0D-0A-1A-0A' -or [Text.Encoding]::ASCII.GetString($bytes,12,4) -ne 'IHDR') { throw 'Invalid PNG signature.' }
    }
    elseif ($bytes[0] -ne 255 -or $bytes[1] -ne 216 -or $bytes[2] -ne 255 -or $bytes[$bytes.Length-2] -ne 255 -or $bytes[$bytes.Length-1] -ne 217) { throw 'Invalid JPEG signature.' }
    $file
}

function Assert-OSDAppImageArchive {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    if ((Get-Item -LiteralPath $Path).Length -gt 21MB) { throw 'Image archive exceeds 21 MiB.' }
    $zip=[IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $files=@($zip.Entries | Where-Object { $_.FullName -ne 'Package/' })
        if ($files.Count -ne 1 -or $files[0].FullName -notmatch '^Package/[A-Za-z0-9][A-Za-z0-9 _.-]*\.(jpg|jpeg|png)$' -or
            $files[0].FullName -match '\.\.' -or $files[0].Length -lt 24 -or $files[0].Length -gt 20MB) { throw 'Image ZIP must contain one bounded image directly inside Package; other entries and traversal are forbidden.' }
    }
    finally { $zip.Dispose() }
}
