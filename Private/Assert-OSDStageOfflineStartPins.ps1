function Assert-OSDStageOfflineStartPins {
    param([Parameter(Mandatory)][string]$WindowsPath)
    Invoke-OSDStageOfflineSoftware -WindowsPath $WindowsPath -Action {
        param($Software)
        $cv=$Software.OpenSubKey('Microsoft\Windows NT\CurrentVersion')
        try {
            if (-not $cv) { throw 'Missing target Windows version information.' }
            Assert-OSDStageStartPinsPlatform -Build ([int]$cv.GetValue('CurrentBuildNumber')) -Revision ([int]$cv.GetValue('UBR')) -InstallationType ([string]$cv.GetValue('InstallationType')) -EditionId ([string]$cv.GetValue('EditionID'))
        }
        finally { if ($cv) { $cv.Dispose() } }
    }
    Get-OSDStageStartPinsPolicy -WindowsDirectory (Join-Path $WindowsPath 'Windows') | Out-Null
}
