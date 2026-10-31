function Add-OSDStageSetupComplete {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$WindowsPath,

        [string]$StagedRelativePath = 'Windows\Temp\OSDStage'
    )

    $scriptsPath = Join-Path $WindowsPath 'Windows\Setup\Scripts'
    $setupComplete = Join-Path $scriptsPath 'SetupComplete.cmd'
    $stagedRoot = Join-Path $WindowsPath $StagedRelativePath

    $moduleRoot = Split-Path $PSScriptRoot -Parent
    $runnerSource = Join-Path $moduleRoot 'Runtime\Invoke-OSDStageRunner.ps1'
    $preInstallSource = Join-Path $moduleRoot 'Runtime\Invoke-OSDStagePreInstall.ps1'
    $lockSource = Join-Path $moduleRoot 'Runtime\Enter-OSDStageCacheLock.ps1'
    $spaceSource = Join-Path $moduleRoot 'Runtime\Assert-OSDStageTransactionSpace.ps1'
    $officeCompatibilitySource = Join-Path $moduleRoot 'Runtime\Test-OSDStageOfficeCacheCompatibility.ps1'
    if (-not (Test-Path -LiteralPath $officeCompatibilitySource -PathType Leaf)) { throw 'Office cache compatibility runtime was not found.' }
    $sleepSource = Join-Path $moduleRoot 'Runtime\OSDStageSleepPrevention.ps1'
    if (-not (Test-Path -LiteralPath $sleepSource -PathType Leaf)) { throw 'Sleep prevention runtime was not found.' }
    $recoverySource = Join-Path $moduleRoot 'Runtime\Restore-OSDStageCacheGeneration.ps1'

    if (-not (Test-Path -LiteralPath $runnerSource -PathType Leaf)) {
        throw "OSD App runner was not found: $runnerSource"
    }

    if (-not (Test-Path -LiteralPath $preInstallSource -PathType Leaf)) {
        throw "OSD App pre-install runtime was not found: $preInstallSource"
    }
    if (-not (Test-Path -LiteralPath $recoverySource -PathType Leaf)) {
        throw "OSD App cache recovery runtime was not found: $recoverySource"
    }

    if (-not (Test-Path -LiteralPath $spaceSource -PathType Leaf)) {
        throw "OSD App cache space runtime was not found: $spaceSource"
    }

    if (-not (Test-Path -LiteralPath $lockSource -PathType Leaf)) {
        throw "OSD App cache lock runtime was not found: $lockSource"
    }

    if ($PSCmdlet.ShouldProcess($stagedRoot, 'Stage OSDStage runtime scripts')) {
        New-Item -ItemType Directory -Path $scriptsPath -Force | Out-Null
        New-Item -ItemType Directory -Path $stagedRoot -Force | Out-Null
        foreach ($helper in @('OSDStagePayloadFile.ps1','OSDStage7Zip.ps1','OSDStageVisualStudioCode.ps1','OSDStagePrerequisite.ps1','OSDStageFont.ps1','OSDStageCertificate.ps1','OSDStageDriver.ps1','Invoke-OSDStageBuiltInCacheTransaction.ps1')) {
            Copy-Item -LiteralPath (Join-Path $moduleRoot (Join-Path 'Runtime' $helper)) -Destination (Join-Path $stagedRoot $helper) -Force
        }
        Copy-Item -LiteralPath $runnerSource -Destination (Join-Path $stagedRoot 'Invoke-OSDStageRunner.ps1') -Force
        Copy-Item -LiteralPath $preInstallSource -Destination (Join-Path $stagedRoot 'Invoke-OSDStagePreInstall.ps1') -Force
        Copy-Item -LiteralPath $lockSource -Destination (Join-Path $stagedRoot 'Enter-OSDStageCacheLock.ps1') -Force
        Copy-Item -LiteralPath $spaceSource -Destination (Join-Path $stagedRoot 'Assert-OSDStageTransactionSpace.ps1') -Force
        Copy-Item -LiteralPath $officeCompatibilitySource -Destination (Join-Path $stagedRoot 'Test-OSDStageOfficeCacheCompatibility.ps1') -Force
        Copy-Item -LiteralPath $sleepSource -Destination (Join-Path $stagedRoot 'OSDStageSleepPrevention.ps1') -Force
        Copy-Item -LiteralPath $recoverySource -Destination (Join-Path $stagedRoot 'Restore-OSDStageCacheGeneration.ps1') -Force
    }

    $preInstallMarker = ':: OSDStage PreInstall'
    $begin = ':: OSDStage Begin'
    $end   = ':: OSDStage End'

    $preInstallPath = "%SystemDrive%\$StagedRelativePath\Invoke-OSDStagePreInstall.ps1"
    $runnerPath = "%SystemDrive%\$StagedRelativePath\Invoke-OSDStageRunner.ps1"

    $preInstallBlock = @(
        $preInstallMarker
        ('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "{0}" -StagedPath "%SystemDrive%\{1}"' -f $preInstallPath, $StagedRelativePath)
        'set "OSDStage_PREINSTALL_EXITCODE=%ERRORLEVEL%"'
        'if not "%OSDStage_PREINSTALL_EXITCODE%"=="0" exit /b %OSDStage_PREINSTALL_EXITCODE%'
    )

    $runnerBlock = @(
        $begin
        ('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "{0}" -StagedPath "%SystemDrive%\{1}"' -f $runnerPath, $StagedRelativePath)
        'set "OSDStage_EXITCODE=%ERRORLEVEL%"'
        'if not "%OSDStage_EXITCODE%"=="0" exit /b %OSDStage_EXITCODE%'
        $end
    )

    if (-not (Test-Path -LiteralPath $setupComplete)) {
        if ($PSCmdlet.ShouldProcess($setupComplete, 'Create SetupComplete.cmd and append OSDStage blocks')) {
            '@echo off' | Set-Content -LiteralPath $setupComplete -Encoding ASCII
            Add-Content -LiteralPath $setupComplete -Value $preInstallBlock -Encoding ASCII
            Add-Content -LiteralPath $setupComplete -Value $runnerBlock -Encoding ASCII
        }

        if (Test-Path -LiteralPath $setupComplete -PathType Leaf) {
            return Get-Item -LiteralPath $setupComplete
        }
        return
    }

    $existing = Get-Content -LiteralPath $setupComplete -Raw -ErrorAction Stop
    $hasPreInstall = $existing -match [regex]::Escape($preInstallMarker)
    $hasRunner = $existing -match [regex]::Escape($begin)

    # Reject inconsistent or duplicate markers instead of appending more
    # blocks and silently changing execution order.
    $preMarkerCount = [regex]::Matches($existing, '(?m)^:: OSDStage PreInstall\r?$').Count
    $beginMarkerCount = [regex]::Matches($existing, '(?m)^:: OSDStage Begin\r?$').Count
    $endMarkerCount = [regex]::Matches($existing, '(?m)^:: OSDStage End\r?$').Count

    if ($preMarkerCount -gt 1 -or $beginMarkerCount -gt 1 -or $endMarkerCount -gt 1) {
        throw 'Duplicate OSDStage markers were found in SetupComplete.cmd. Review the file before staging again.'
    }
    if ($hasPreInstall -and -not $hasRunner) {
        throw 'OSDStage PreInstall marker was found without a runner block in SetupComplete.cmd.'
    }
    if ($hasRunner -and $endMarkerCount -ne 1) {
        throw 'OSDStage runner block is incomplete in SetupComplete.cmd.'
    }

    if ($hasPreInstall -and $hasRunner) {
        if ($PSCmdlet.ShouldProcess($setupComplete, 'Refresh existing OSDStage SetupComplete blocks')) {
            $existingText = [System.IO.File]::ReadAllText($setupComplete)
            $lineEnding = if ($existingText.Contains(([string][char]13 + [string][char]10))) {
                [string][char]13 + [string][char]10
            } else {
                [string][char]10
            }

            # Refresh the *two owned blocks separately*. In particular, do not
            # delete unrelated SetupComplete commands between the blocks.
            $prePattern = '(?m)^:: OSDStage PreInstall\r?\n^powershell\.exe[^\r\n]*\r?\n^set "OSDStage_PREINSTALL_EXITCODE=[^\r\n]*\r?\n^if not [^\r\n]*(?:\r?\n|$)'
            $runnerPattern = '(?ms)^:: OSDStage Begin\r?\n.*?^:: OSDStage End(?:\r?\n|$)'

            if (-not [regex]::IsMatch($existingText, $prePattern) -or
                -not [regex]::IsMatch($existingText, $runnerPattern)) {
                throw 'Existing OSDStage SetupComplete blocks are incomplete or could not be parsed. File left unchanged.'
            }

            $newPre = ($preInstallBlock -join $lineEnding) + $lineEnding
            $newRunner = ($runnerBlock -join $lineEnding) + $lineEnding

            $updatedText = [regex]::Replace(
                $existingText, $prePattern,
                [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $newPre }, 1
            )
            $updatedText = [regex]::Replace(
                $updatedText, $runnerPattern,
                [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $newRunner }, 1
            )

            # Keep BOM/encoding where possible; SetupComplete is normally ASCII.
            $bytes = [System.IO.File]::ReadAllBytes($setupComplete)
            $encoding = [System.Text.Encoding]::Default
            if ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) {
                $encoding = [System.Text.UTF8Encoding]::new($true)
            }
            elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 255 -and $bytes[1] -eq 254) {
                $encoding = [System.Text.Encoding]::Unicode
            }
            elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 254 -and $bytes[1] -eq 255) {
                $encoding = [System.Text.Encoding]::BigEndianUnicode
            }

            [System.IO.File]::WriteAllText($setupComplete, $updatedText, $encoding)
            Write-Verbose 'Existing OSDStage SetupComplete blocks were refreshed without changing external commands.'
        }

        return Get-Item -LiteralPath $setupComplete
    }

    if ($hasRunner -and -not $hasPreInstall) {
        if ($PSCmdlet.ShouldProcess($setupComplete, 'Insert OSDStage pre-install block before existing OSDStage runner block')) {
            $bytes = [System.IO.File]::ReadAllBytes($setupComplete)
            $markerBytes = [System.Text.Encoding]::ASCII.GetBytes($begin)

            $markerIndex = -1
            for ($i = 0; $i -le ($bytes.Length - $markerBytes.Length); $i++) {
                $match = $true
                for ($j = 0; $j -lt $markerBytes.Length; $j++) {
                    if ($bytes[$i + $j] -ne $markerBytes[$j]) {
                        $match = $false
                        break
                    }
                }

                if ($match) {
                    $markerIndex = $i
                    break
                }
            }

            if ($markerIndex -lt 0) {
                throw 'Existing OSDStage runner marker could not be located in SetupComplete.cmd.'
            }

            $lineEnding = [Environment]::NewLine
            if ($markerIndex -gt 0 -and $bytes[$markerIndex - 1] -eq 10 -and ($markerIndex -lt 2 -or $bytes[$markerIndex - 2] -ne 13)) {
                $lineEnding = [char]10
            }

            $insertText = ($preInstallBlock -join $lineEnding) + $lineEnding
            $insertBytes = [System.Text.Encoding]::ASCII.GetBytes($insertText)

            $newBytes = New-Object byte[] ($bytes.Length + $insertBytes.Length)
            [System.Buffer]::BlockCopy($bytes, 0, $newBytes, 0, $markerIndex)
            [System.Buffer]::BlockCopy($insertBytes, 0, $newBytes, $markerIndex, $insertBytes.Length)
            [System.Buffer]::BlockCopy($bytes, $markerIndex, $newBytes, ($markerIndex + $insertBytes.Length), ($bytes.Length - $markerIndex))

            [System.IO.File]::WriteAllBytes($setupComplete, $newBytes)
        }

        return Get-Item -LiteralPath $setupComplete
    }

    if ($PSCmdlet.ShouldProcess($setupComplete, 'Append OSDStage pre-install and runner blocks to existing SetupComplete.cmd')) {
        $bytes = [System.IO.File]::ReadAllBytes($setupComplete)
        if ($bytes.Length -gt 0) {
            $lastByte = $bytes[$bytes.Length - 1]
            if ($lastByte -ne 10 -and $lastByte -ne 13) {
                Add-Content -LiteralPath $setupComplete -Value '' -Encoding ASCII
            }
        }

        Add-Content -LiteralPath $setupComplete -Value $preInstallBlock -Encoding ASCII
        Add-Content -LiteralPath $setupComplete -Value $runnerBlock -Encoding ASCII
    }

    Get-Item -LiteralPath $setupComplete
}
