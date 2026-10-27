function Set-OSDAppOfflineTaskbar {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$WindowsPath,[Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Pins,[Parameter(Mandatory)][scriptblock]$Commit)
    $mapping=Get-OSDAppTaskbarPinsPolicy -WindowsDirectory (Join-Path $WindowsPath 'Windows')
    $xml=ConvertTo-OSDAppTaskbarXml -Pins $Pins
    $path=Join-Path $WindowsPath 'Windows\OEM\OSDApps\TaskbarLayoutModification.xml'
    Invoke-OSDAppOfflineSoftware -WindowsPath $WindowsPath -Action {
        param($Software)
        $cv=$Software.OpenSubKey('Microsoft\Windows NT\CurrentVersion')
        try {
            if (-not $cv) { throw 'The target Windows version is missing.' }
            Assert-OSDAppTaskbarPinsPlatform -Build ([int]$cv.GetValue('CurrentBuildNumber')) -Revision ([int]$cv.GetValue('UBR')) -InstallationType ([string]$cv.GetValue('InstallationType')) -EditionId ([string]$cv.GetValue('EditionID'))
            $systemRoot=[string]$cv.GetValue('SystemRoot')
        }
        finally { if ($cv) { $cv.Dispose() } }
        if ($systemRoot -notmatch '^[A-Za-z]:\\Windows$') { throw 'Cannot resolve the future Windows directory from the target SOFTWARE hive.' }
        $futurePath=$systemRoot + '\OEM\OSDApps\TaskbarLayoutModification.xml'
        $key=$null;$owner=$null
        $old=$null;$oldKind=$null;$oldEnabled=$null;$oldEnabledKind=$null;$oldHash=$null;$oldBytes=$null;$written=$false
        try {
            $key=$Software.CreateSubKey($mapping.Key)
            if ($key.GetValue('ReapplyStartLayoutEveryLogon',0) -ne 0) { throw 'An existing policy forces the layout to apply again at every logon. Nothing was replaced.' }
            $owner=$Software.CreateSubKey('OSDApps\DesktopSettings')
            $old=$key.GetValue($mapping.FileName,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            if ($null -ne $old) { $oldKind=$key.GetValueKind($mapping.FileName) }
            $oldEnabled=$key.GetValue($mapping.EnabledName)
            if ($null -ne $oldEnabled) { $oldEnabledKind=$key.GetValueKind($mapping.EnabledName) }
            $oldHash=$owner.GetValue('TaskbarSha256')
            if ($null -ne $old -or $null -ne $oldEnabled -or (Test-Path -LiteralPath $path) -or $oldHash) {
                if ($old -ne $futurePath -or $oldEnabled -ne 1 -or $oldKind -ne $mapping.FileKind -or $oldEnabledKind -ne [Microsoft.Win32.RegistryValueKind]::DWord -or -not $oldHash -or -not (Test-Path -LiteralPath $path -PathType Leaf) -or
                    (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $oldHash) { throw 'Existing taskbar configuration is not an intact OSDApps-owned layout. Nothing was replaced.' }
                $oldBytes=[IO.File]::ReadAllBytes($path)
            }
            New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force -ErrorAction Stop | Out-Null
            $written=$true;[IO.File]::WriteAllText($path,$xml,[Text.UTF8Encoding]::new($false))
            $key.SetValue($mapping.FileName,$futurePath,$mapping.FileKind)
            $key.SetValue($mapping.EnabledName,1,[Microsoft.Win32.RegistryValueKind]::DWord)
            $owner.SetValue('TaskbarSha256',(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash,[Microsoft.Win32.RegistryValueKind]::String)
            & $Commit
        }
        catch {
            if ($written) {
                if ($null -ne $oldBytes) { [IO.File]::WriteAllBytes($path,$oldBytes) } else { [IO.File]::Delete($path) }
                if ($null -ne $old) { $key.SetValue($mapping.FileName,$old,$oldKind) } else { $key.DeleteValue($mapping.FileName,$false) }
                if ($null -ne $oldEnabled) { $key.SetValue($mapping.EnabledName,$oldEnabled,$oldEnabledKind) } else { $key.DeleteValue($mapping.EnabledName,$false) }
                if ($oldHash) { $owner.SetValue('TaskbarSha256',$oldHash,[Microsoft.Win32.RegistryValueKind]::String) } else { $owner.DeleteValue('TaskbarSha256',$false) }
            }
            throw
        }
        finally { if ($owner) { $owner.Dispose() };if ($key) { $key.Dispose() } }
    }
}
