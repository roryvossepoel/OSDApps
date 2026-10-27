function Assert-OSDAppOfflineStartPins {
    param([Parameter(Mandatory)][string]$WindowsPath)
    Invoke-OSDAppOfflineSoftware -WindowsPath $WindowsPath -Action {
        param($Software)
        $cv=$Software.OpenSubKey('Microsoft\Windows NT\CurrentVersion')
        try {
            if (-not $cv) { throw 'Missing target Windows version information.' }
            Assert-OSDAppStartPinsPlatform -Build ([int]$cv.GetValue('CurrentBuildNumber')) -Revision ([int]$cv.GetValue('UBR')) -InstallationType ([string]$cv.GetValue('InstallationType')) -EditionId ([string]$cv.GetValue('EditionID'))
        }
        finally { if ($cv) { $cv.Dispose() } }
    }
    Get-OSDAppStartPinsPolicy -WindowsDirectory (Join-Path $WindowsPath 'Windows') | Out-Null
}
