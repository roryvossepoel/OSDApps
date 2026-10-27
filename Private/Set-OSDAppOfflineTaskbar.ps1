function Set-OSDAppOfflineTaskbar {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$WindowsPath,[Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Pins,[Parameter(Mandatory)][scriptblock]$Commit)
    $xml=ConvertTo-OSDAppTaskbarXml -Pins $Pins
    $path=Join-Path $WindowsPath 'Windows\OEM\OSDApps\TaskbarLayoutModification.xml'
    Invoke-OSDAppOfflineSoftware -WindowsPath $WindowsPath -Action {
        param($Software)
        $cv=$Software.OpenSubKey('Microsoft\Windows NT\CurrentVersion')
        try {
            if (-not $cv -or [string]$cv.GetValue('InstallationType') -ne 'Client' -or [int]$cv.GetValue('CurrentBuildNumber') -lt 22000) { throw 'Offline taskbar pins require a freshly applied Windows 11 client image.' }
            $systemRoot=[string]$cv.GetValue('SystemRoot')
        }
        finally { if ($cv) { $cv.Dispose() } }
        if ($systemRoot -notmatch '^[A-Za-z]:\\Windows$') { throw 'Cannot resolve the future Windows directory from the target SOFTWARE hive.' }
        $futurePath=$systemRoot + '\OEM\OSDApps\TaskbarLayoutModification.xml'
        $key=$null;$owner=$null
        $old=$null;$oldKind=$null;$oldHash=$null;$oldBytes=$null;$written=$false
        try {
            $key=$Software.CreateSubKey('Microsoft\Windows\CurrentVersion\Explorer')
            $owner=$Software.CreateSubKey('OSDApps\DesktopSettings')
            $old=$key.GetValue('LayoutXMLPath',$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            if ($null -ne $old) { $oldKind=$key.GetValueKind('LayoutXMLPath') }
            $oldHash=$owner.GetValue('TaskbarSha256')
            if ($null -ne $old -or (Test-Path -LiteralPath $path) -or $oldHash) {
                if ($old -ne $futurePath -or -not $oldHash -or -not (Test-Path -LiteralPath $path -PathType Leaf) -or
                    (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $oldHash) { throw 'Existing taskbar configuration is not an intact OSDApps-owned layout. Nothing was replaced.' }
                $oldBytes=[IO.File]::ReadAllBytes($path)
            }
            New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force -ErrorAction Stop | Out-Null
            [IO.File]::WriteAllText($path,$xml,[Text.UTF8Encoding]::new($false));$written=$true
            $key.SetValue('LayoutXMLPath',$futurePath,[Microsoft.Win32.RegistryValueKind]::String)
            $owner.SetValue('TaskbarSha256',(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash,[Microsoft.Win32.RegistryValueKind]::String)
            & $Commit
        }
        catch {
            if ($written) {
                if ($null -ne $oldBytes) { [IO.File]::WriteAllBytes($path,$oldBytes) } else { [IO.File]::Delete($path) }
                if ($null -ne $old) { $key.SetValue('LayoutXMLPath',$old,$oldKind) } else { $key.DeleteValue('LayoutXMLPath',$false) }
                if ($oldHash) { $owner.SetValue('TaskbarSha256',$oldHash,[Microsoft.Win32.RegistryValueKind]::String) } else { $owner.DeleteValue('TaskbarSha256',$false) }
            }
            throw
        }
        finally { if ($owner) { $owner.Dispose() };if ($key) { $key.Dispose() } }
    }
}
