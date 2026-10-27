# Run on the full Windows preparation PC with the OSDCloud USB connected.
[CmdletBinding()]
param([Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{40}$')][string]$Revision,[string]$WallpaperPath,[string]$LockScreenPath)
$ErrorActionPreference='Stop'
if (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT') { throw 'Prepare this test module on full Windows, not WinPE.' }
$volumes=@(Get-Volume | Where-Object { $_.FileSystemLabel -eq 'OSDCloud' -and $_.DriveLetter })
if ($volumes.Count -ne 1) { throw 'Expected exactly one mounted volume labeled OSDCloud.' }
$usbRoot=('{0}:\' -f $volumes[0].DriveLetter)
$destination=Join-Path $usbRoot ('TestModules\OSDApps-Background-' + $Revision.Substring(0,7).ToLowerInvariant())
if (Test-Path -LiteralPath $destination) { throw ('Test module directory already exists: ' + $destination) }
$temp=Join-Path ([IO.Path]::GetTempPath()) ('OSDAppsBackground-' + [guid]::NewGuid().ToString('N'))
$promoted=$false
try {
    New-Item -ItemType Directory -Path $temp -Force | Out-Null
    $archive=Join-Path $temp 'source.zip'
    [Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri ('https://github.com/roryvossepoel/OSDApps/archive/' + $Revision + '.zip') -OutFile $archive -UseBasicParsing
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::ExtractToDirectory($archive,(Join-Path $temp 'source'))
    $source=Join-Path (Join-Path $temp 'source') ('OSDApps-' + $Revision)
    $manifest=Join-Path $source 'OSDApps.psd1'
    if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { throw 'The pinned source archive does not contain the expected module.' }
    $info=Test-ModuleManifest -Path $manifest -ErrorAction Stop
    foreach ($command in @('Add-OSDAppWallpaper','Add-OSDAppLockScreen')) {
        if (-not $info.ExportedFunctions.ContainsKey($command)) { throw ('Missing command: ' + $command) }
    }
    New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Recurse -ErrorAction Stop
    $Revision | Set-Content -LiteralPath (Join-Path $destination 'TestRevision.txt') -Encoding ASCII
    Remove-Module OSDApps -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $destination 'OSDApps.psd1') -Force -Global
    $repo=Join-Path $temp 'Repository'
    New-OSDAppRepository -Path $repo | Out-Null
    Add-Type -AssemblyName System.Drawing
    foreach ($kind in @('Wallpaper','LockScreen')) {
        $id='OSDAppsTest'+$kind
        $payload=Join-Path $temp $id
        New-Item -ItemType Directory -Path $payload | Out-Null
        $inputPath=if ($kind -eq 'Wallpaper') { $WallpaperPath } else { $LockScreenPath }
        if ($inputPath) {
            $image=Get-Item -LiteralPath $inputPath -ErrorAction Stop
            Copy-Item -LiteralPath $image.FullName -Destination (Join-Path $payload ('test'+$image.Extension.ToLowerInvariant()))
        }
        else {
            $bitmap=[Drawing.Bitmap]::new(1920,1080)
            $graphics=[Drawing.Graphics]::FromImage($bitmap)
            $font=[Drawing.Font]::new('Segoe UI',48)
            try {
                $color=if ($kind -eq 'Wallpaper') { [Drawing.Color]::DarkGreen } else { [Drawing.Color]::DarkBlue }
                $graphics.Clear($color)
                $graphics.DrawString(('OSDApps '+$kind+' test'),$font,[Drawing.Brushes]::White,240,450)
                $bitmap.Save((Join-Path $payload 'test.png'),[Drawing.Imaging.ImageFormat]::Png)
            }
            finally { $font.Dispose();$graphics.Dispose();$bitmap.Dispose() }
        }
        $package=New-OSDAppPackage -Id $id -Version 1.0.0 -PackageType Image -SourcePath $payload -OutputPath (Join-Path $temp ($id+'Build'))
        Add-OSDAppPackage -Id $id -DisplayName ('OSDApps '+$kind+' test') -Version 1.0.0 -PackageType Image -Architecture any -PackagePath $package.PackagePath -RepositoryPath $repo | Out-Null
    }
    $cache=Join-Path $usbRoot 'OSDApps'
    $module=Get-Module OSDApps
    & $module { param($Catalog,$Cache) Sync-OSDAppCache -CatalogPath $Catalog -CachePath $Cache -Name @('OSDAppsTestWallpaper','OSDAppsTestLockScreen') -Confirm:$false | Out-Null } (Join-Path $repo 'catalog.json') $cache
    & $module { param($Cache) $checks=@(Test-OSDAppRepositoryCache -CachePath $Cache -Name @('OSDAppsTestWallpaper','OSDAppsTestLockScreen'));if ($checks.Count -ne 2 -or @($checks | Where-Object { -not $_.Valid }).Count) { throw 'Test image cache validation failed.' } } $cache
    $promoted=$true
    [pscustomobject]@{Revision=$Revision;ModulePath=(Join-Path $destination 'OSDApps.psd1');ExamplePath=(Join-Path $destination 'Examples\Stage-OSDAppsBackgroundTest.ps1')}
}
catch {
    if (-not $promoted -and (Test-Path -LiteralPath $destination)) { Remove-Item -LiteralPath $destination -Recurse -Force }
    throw
}
finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force } }
