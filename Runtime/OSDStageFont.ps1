function Initialize-OSDStageFontNativeApi {
    [CmdletBinding()]
    param()

    if ('OSDStage.FontNativeApi' -as [type]) { return }

    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace OSDStage {
    public static class FontNativeApi {
        [DllImport("gdi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern int AddFontResourceEx(string lpszFilename, uint fl, IntPtr pdv);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern IntPtr SendMessageTimeout(
            IntPtr hWnd, uint Msg, UIntPtr wParam, IntPtr lParam,
            uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
    }
}
'@ -ErrorAction Stop
}

function Get-OSDStageFontRegistrationName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.IO.FileInfo]$File)

    $suffix = if ($File.Extension.ToLowerInvariant() -eq '.otf') { 'OpenType' } else { 'TrueType' }
    '{0} ({1})' -f [IO.Path]::GetFileNameWithoutExtension($File.Name), $suffix
}

function Install-OSDStageFontFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.IO.FileInfo]$File,
        [string]$FontsDirectory = (Join-Path $env:WINDIR 'Fonts'),
        [string]$RegistryPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts',
        [switch]$SkipNativeActivation
    )

    $extension = $File.Extension.ToLowerInvariant()
    if ($extension -notin @('.ttf','.otf')) {
        return [pscustomobject]@{
            FileName=$File.Name;RegistrationName=$null;Status='Ignored';Outcome='Unsupported'
            SourceSha256=$null;Destination=$null;ActivationLoaded=$null;Error=$null
        }
    }

    $destination = Join-Path $FontsDirectory $File.Name
    $registrationName = Get-OSDStageFontRegistrationName -File $File
    $sourceHash = (Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
    $copied = $false
    $registrationCreated = $false

    try {
        New-Item -ItemType Directory -Path $FontsDirectory -Force -ErrorAction Stop | Out-Null
        if (-not (Test-Path -LiteralPath $RegistryPath)) {
            New-Item -Path $RegistryPath -Force -ErrorAction Stop | Out-Null
        }

        $registry = Get-ItemProperty -LiteralPath $RegistryPath -ErrorAction Stop
        $registrations = @(
            $registry.PSObject.Properties |
                Where-Object { $_.Name -notmatch '^PS' }
        )
        $matchingRegistration = @(
            $registrations |
                Where-Object { [string]$_.Value -ieq $File.Name }
        )
        $namedRegistration = @(
            $registrations |
                Where-Object { [string]$_.Name -ieq $registrationName }
        )

        if (Test-Path -LiteralPath $destination -PathType Leaf) {
            $destinationHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256 -ErrorAction Stop).Hash
            if ($destinationHash -ne $sourceHash) {
                return [pscustomobject]@{
                    FileName=$File.Name;RegistrationName=$registrationName;Status='Failed';Outcome='FileConflict'
                    SourceSha256=$sourceHash;Destination=$destination;ActivationLoaded=$null
                    Error='A different font file with the same destination filename already exists.'
                }
            }

            if ($matchingRegistration.Count -gt 0) {
                return [pscustomobject]@{
                    FileName=$File.Name;RegistrationName=[string]$matchingRegistration[0].Name
                    Status='AlreadyPresent';Outcome='AlreadyPresent'
                    SourceSha256=$sourceHash;Destination=$destination;ActivationLoaded=$null;Error=$null
                }
            }
        }

        if ($namedRegistration.Count -gt 0 -and [string]$namedRegistration[0].Value -ine $File.Name) {
            return [pscustomobject]@{
                FileName=$File.Name;RegistrationName=$registrationName;Status='Failed';Outcome='RegistrationConflict'
                SourceSha256=$sourceHash;Destination=$destination;ActivationLoaded=$null
                Error='The derived machine font registration name already points to another file.'
            }
        }

        if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) {
            Copy-Item -LiteralPath $File.FullName -Destination $destination -ErrorAction Stop
            $copied = $true
        }

        New-ItemProperty -LiteralPath $RegistryPath -Name $registrationName -Value $File.Name -PropertyType String -Force -ErrorAction Stop | Out-Null
        $registrationCreated = $true

        $activationLoaded = $null
        if (-not $SkipNativeActivation) {
            try {
                Initialize-OSDStageFontNativeApi
                $activationLoaded = ([OSDStage.FontNativeApi]::AddFontResourceEx($destination, 0, [IntPtr]::Zero) -gt 0)
                $broadcastResult = [UIntPtr]::Zero
                [void][OSDStage.FontNativeApi]::SendMessageTimeout(
                    [IntPtr]0xffff, 0x001D, [UIntPtr]::Zero, [IntPtr]::Zero,
                    0x0002, 1000, [ref]$broadcastResult
                )
            }
            catch {
                # Registry + %WINDIR%\Fonts are the persistent machine-wide contract.
                # Session activation is best-effort and must not convert a durable install into failure.
                $activationLoaded = $false
            }
        }

        [pscustomobject]@{
            FileName=$File.Name;RegistrationName=$registrationName;Status='Installed';Outcome='Installed'
            SourceSha256=$sourceHash;Destination=$destination;ActivationLoaded=$activationLoaded;Error=$null
        }
    }
    catch {
        if ($registrationCreated) {
            try { Remove-ItemProperty -LiteralPath $RegistryPath -Name $registrationName -ErrorAction SilentlyContinue } catch {}
        }
        if ($copied) {
            try { Remove-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue } catch {}
        }
        [pscustomobject]@{
            FileName=$File.Name;RegistrationName=$registrationName;Status='Failed';Outcome='Failed'
            SourceSha256=$sourceHash;Destination=$destination;ActivationLoaded=$null;Error=$_.Exception.Message
        }
    }
}

function Invoke-OSDStageFontPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PayloadRoot,
        [Parameter(Mandatory)][string]$PackageId,
        [Parameter(Mandatory)][string]$DeploymentId,
        [Parameter(Mandatory)][string]$ResultPath,
        [string]$FontsDirectory = (Join-Path $env:WINDIR 'Fonts'),
        [string]$RegistryPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts',
        [switch]$SkipNativeActivation
    )

    $fontFiles = @(
        Get-ChildItem -LiteralPath $PayloadRoot -File -Recurse -ErrorAction Stop |
            Where-Object { $_.Extension.ToLowerInvariant() -in @('.ttf','.otf') } |
            Sort-Object FullName
    )
    if ($fontFiles.Count -eq 0) {
        throw "Font package '$PackageId' contains no supported .ttf or .otf files."
    }

    $items = [System.Collections.Generic.List[object]]::new()
    foreach ($font in $fontFiles) {
        $items.Add((Install-OSDStageFontFile -File $font -FontsDirectory $FontsDirectory -RegistryPath $RegistryPath -SkipNativeActivation:$SkipNativeActivation))
    }

    $failed = @($items | Where-Object Status -eq 'Failed').Count
    $record = [ordered]@{
        SchemaVersion=2
        DeploymentId=$DeploymentId
        Id=$PackageId
        Status=if($failed -gt 0){'Failed'}else{'Succeeded'}
        FontCount=$items.Count
        InstalledCount=@($items | Where-Object Status -eq 'Installed').Count
        AlreadyPresentCount=@($items | Where-Object Status -eq 'AlreadyPresent').Count
        FailedCount=$failed
        Items=@($items)
        Error=if($failed -gt 0){"$failed font(s) failed."}else{$null}
    }

    New-Item -ItemType Directory -Path (Split-Path $ResultPath -Parent) -Force | Out-Null
    $record | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $ResultPath -Encoding UTF8

    [pscustomobject]@{
        ExitCode=if($failed -gt 0){1}else{0}
        Integrity='Sha256Validated'
        ResultPath=$ResultPath
        Items=@($items)
    }
}
