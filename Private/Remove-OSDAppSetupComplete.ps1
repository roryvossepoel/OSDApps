function Remove-OSDAppSetupComplete {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$WindowsPath
    )

    $setupPath = Join-Path $WindowsPath 'Windows\Setup\Scripts\SetupComplete.cmd'
    if (-not (Test-Path -LiteralPath $setupPath -PathType Leaf)) { return }

    # Only delete complete, canonical OSDApps-owned blocks. Preserve third-party
    # commands anywhere else, including between the two OSDApps blocks.
    # Preserve every byte outside OSDApps-owned lines. Use Latin-1 as a
    # lossless byte-to-character mapping for ANSI and UTF-8 cmd files;
    # UTF-16 BOM files are decoded and re-encoded with their original endian.
    $bytes = [System.IO.File]::ReadAllBytes($setupPath)
    $encoding = [System.Text.Encoding]::GetEncoding(28591)
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 255 -and $bytes[1] -eq 254) {
        $encoding = [System.Text.Encoding]::Unicode
    }
    elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 254 -and $bytes[1] -eq 255) {
        $encoding = [System.Text.Encoding]::BigEndianUnicode
    }
    $text = $encoding.GetString($bytes)
    $preMarker = '(?m)^:: OSDApps PreInstall\r?$'
    $beginMarker = '(?m)^:: OSDApps Begin\r?$'
    $endMarker = '(?m)^:: OSDApps End\r?$'
    $preCount = [regex]::Matches($text, $preMarker).Count
    $beginCount = [regex]::Matches($text, $beginMarker).Count
    $endCount = [regex]::Matches($text, $endMarker).Count

    if ($preCount -eq 0 -and $beginCount -eq 0 -and $endCount -eq 0) {
        throw 'SetupComplete.cmd contains no recognizable OSDApps markers. Refusing to remove unrelated content.'
    }
    if ($preCount -ne 1 -or $beginCount -ne 1 -or $endCount -ne 1) {
        throw 'SetupComplete.cmd has missing or duplicate OSDApps markers; leaving it unchanged.'
    }

    # Match exactly the four PreInstall lines and the five Runner lines.
    # Never let a dot-star swallow commands belonging to other installers.
    $prePattern = '(?m)^:: OSDApps PreInstall\r?\n^powershell\.exe -NoProfile -ExecutionPolicy Bypass -File "[^\r\n]*Invoke-OSDAppPreInstall\.ps1" -StagedPath "[^\r\n]*"\r?\n^set "OSDAPPS_PREINSTALL_EXITCODE=%ERRORLEVEL%"\r?\n^if not "%OSDAPPS_PREINSTALL_EXITCODE%"=="0" exit /b %OSDAPPS_PREINSTALL_EXITCODE%(?:\r?\n|$)'
    $runnerPattern = '(?m)^:: OSDApps Begin\r?\n^powershell\.exe -NoProfile -ExecutionPolicy Bypass -File "[^\r\n]*Invoke-OSDAppRunner\.ps1" -StagedPath "[^\r\n]*"\r?\n^set "OSDAPPS_EXITCODE=%ERRORLEVEL%"\r?\n^if not "%OSDAPPS_EXITCODE%"=="0" exit /b %OSDAPPS_EXITCODE%\r?\n^:: OSDApps End(?:\r?\n|$)'

    if ([regex]::Matches($text, $prePattern).Count -ne 1 -or
        [regex]::Matches($text, $runnerPattern).Count -ne 1) {
        throw 'OSDApps SetupComplete blocks could not be parsed safely; nothing was removed.'
    }

    $pre = [regex]::Match($text, $prePattern)
    $runner = [regex]::Match($text, $runnerPattern)
    if ($pre.Index -ge $runner.Index) {
        throw 'OSDApps SetupComplete markers are out of order; nothing was removed.'
    }

    if (-not $PSCmdlet.ShouldProcess($setupPath, 'Remove only OSDApps PreInstall and Runner blocks')) {
        return
    }

    # Replace separately, not the entire PreInstall-to-Runner span.
    $updated = [regex]::Replace($text, $prePattern, '', 1)
    $updated = [regex]::Replace($updated, $runnerPattern, '', 1)

    [System.IO.File]::WriteAllBytes($setupPath, $encoding.GetBytes($updated))
    Get-Item -LiteralPath $setupPath
}
