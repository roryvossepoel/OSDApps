[CmdletBinding()]
param([string]$ConfigPath = (Join-Path $PSScriptRoot 'config.json'))

function ConvertTo-OSDAppDesktopPins {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Pins)
    $seen = @{}
    foreach ($pin in $Pins) {
        if ($null -eq $pin -or ($pin -isnot [System.Collections.IDictionary] -and $pin -isnot [pscustomobject])) { throw 'Each pin must be an object with exactly one app ID or link.' }
        $names = @(if ($pin -is [System.Collections.IDictionary]) { $pin.Keys } else { $pin.PSObject.Properties.Name })
        if ($names.Count -ne 1 -or $names[0] -cnotin @('desktopAppId','packagedAppId','desktopAppLink')) { throw 'Use exactly one of desktopAppId, packagedAppId or desktopAppLink per pin.' }
        $name = [string]$names[0]
        $value = $pin.$name
        if ($value -isnot [string] -or [string]::IsNullOrWhiteSpace($value) -or $value.Length -gt 2048 -or $value -ne $value.Trim() -or $value -match '[\x00-\x1F]') { throw 'Pin values must be nonempty literal strings without control characters.' }
        if ($name -eq 'desktopAppLink') {
            if ($value -notmatch '^(?:[A-Za-z]:\\|%(?:ALLUSERSPROFILE|ProgramData|APPDATA|LOCALAPPDATA|ProgramFiles|ProgramFiles\(x86\)|SystemRoot|windir)%\\).+\.lnk$' -or $value -match '["<>|*?]' -or $value -match '(^|\\)\.\.(\\|$)') { throw 'A desktopAppLink must be a local absolute .lnk path, optionally rooted in a supported Windows environment variable.' }
        }
        elseif ($value -match '[\\/"<>|*?\s]') { throw 'Use an app ID, not a display name, executable path or command.' }
        $identity = $name + ':' + $value
        if ($seen.ContainsKey($identity)) { throw 'Duplicate pin.' }
        $seen[$identity] = $true
        [pscustomobject]@{$name=$value}
    }
}

function Assert-OSDAppDesktopOperation {
    param([Parameter(Mandatory)]$Operation)
    switch ([string]$Operation.Kind) {
        'TimeZone' {
            if ([string]::IsNullOrWhiteSpace([string]$Operation.Id) -or [string]$Operation.Id -notmatch '^[A-Za-z0-9 +()._-]{1,128}$' -or [string]$Operation.Id -ne ([string]$Operation.Id).Trim()) { throw 'Specify a Windows time zone ID, for example W. Europe Standard Time.' }
        }
        { $_ -in @('StartPins','TaskbarPins') } {
            if ($null -eq $Operation.Pins -or $Operation.Pins -isnot [System.Collections.IList]) { throw 'Pins must be an array, which may be empty.' }
            $null = @(ConvertTo-OSDAppDesktopPins -Pins @($Operation.Pins))
        }
        default { throw 'Unsupported desktop setting.' }
    }
}

function Assert-OSDAppDesktopConfiguration {
    param([Parameter(Mandatory)]$Configuration)
    $id = [guid]::Empty
    if ([int]$Configuration.SchemaVersion -ne 1 -or -not [guid]::TryParse([string]$Configuration.DeploymentId,[ref]$id) -or
        [string]::IsNullOrWhiteSpace([string]$Configuration.ResultPath) -or @($Configuration.Operations).Count -eq 0) { throw 'Invalid DesktopSettings configuration.' }
    $seen = @{}
    foreach ($op in @($Configuration.Operations)) {
        Assert-OSDAppDesktopOperation -Operation $op
        if ($seen.ContainsKey([string]$op.Kind)) { throw 'Duplicate desktop setting.' }
        $seen[[string]$op.Kind]=$true
    }
}

function ConvertTo-OSDAppTaskbarXml {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Pins)
    $items = @(ConvertTo-OSDAppDesktopPins -Pins $Pins)
    $builder = [Text.StringBuilder]::new()
    $settings = [Xml.XmlWriterSettings]::new()
    $settings.OmitXmlDeclaration=$true
    $writer = [Xml.XmlWriter]::Create($builder,$settings)
    $layoutNs='http://schemas.microsoft.com/Start/2014/LayoutModification'
    $fullNs='http://schemas.microsoft.com/Start/2014/FullDefaultLayout'
    $barNs='http://schemas.microsoft.com/Start/2014/TaskbarLayout'
    try {
        $writer.WriteStartElement('LayoutModificationTemplate',$layoutNs)
        $writer.WriteAttributeString('Version','1')
        $writer.WriteStartElement('CustomTaskbarLayoutCollection',$layoutNs)
        $writer.WriteAttributeString('PinListPlacement','Replace')
        $writer.WriteStartElement('defaultlayout','TaskbarLayout',$fullNs)
        $writer.WriteStartElement('taskbar','TaskbarPinList',$barNs)
        if ($items.Count -eq 0) {
            # Microsoft's empty replacement sentinel is internal, not a caller-supplied link.
            $writer.WriteStartElement('taskbar','DesktopApp',$barNs)
            $writer.WriteAttributeString('DesktopApplicationLinkPath','#leaveempty')
            $writer.WriteEndElement()
        }
        foreach ($pin in $items) {
            $name=@($pin.PSObject.Properties.Name)[0]
            $element=if ($name -eq 'packagedAppId') { 'UWA' } else { 'DesktopApp' }
            $attribute=@{packagedAppId='AppUserModelID';desktopAppId='DesktopApplicationID';desktopAppLink='DesktopApplicationLinkPath'}[$name]
            $writer.WriteStartElement('taskbar',$element,$barNs)
            $writer.WriteAttributeString($attribute,[string]$pin.$name)
            $writer.WriteAttributeString('PinGeneration','1')
            $writer.WriteEndElement()
        }
        $writer.WriteEndElement();$writer.WriteEndElement();$writer.WriteEndElement();$writer.WriteEndElement()
        $writer.Flush()
        $builder.ToString()
    }
    finally { $writer.Dispose() }
}

function Assert-OSDAppStartPinsPlatform {
    param([int]$Build, [int]$Revision, [string]$InstallationType, [string]$EditionId)
    if ($InstallationType -ne 'Client' -or $Build -lt 26100 -or ($Build -eq 26100 -and $Revision -lt 4770) -or
        $EditionId -notmatch '^(Professional|Enterprise|Education|IoTEnterprise)') {
        throw 'One-time Start pins require Windows 11 Pro, Enterprise, Education or IoT Enterprise, build 26100.4770 or later.'
    }
}

function Get-OSDAppStartPinsPolicy {
    param([string]$WindowsDirectory = $env:SystemRoot)
    # Read the target Windows ADMX, so the policy is never confused with the CSP JSON value.
    $path=Join-Path $WindowsDirectory 'PolicyDefinitions\StartMenu.admx'
    $settings=[Xml.XmlReaderSettings]::new();$settings.DtdProcessing=[Xml.DtdProcessing]::Prohibit;$settings.XmlResolver=$null
    $reader=[Xml.XmlReader]::Create($path,$settings)
    try { $doc=[Xml.XmlDocument]::new();$doc.XmlResolver=$null;$doc.Load($reader) } finally { $reader.Dispose() }
    $policy=$doc.SelectSingleNode("//*[local-name()='policy' and @name='ConfigureStartPins']")
    $text=if ($policy) { $policy.SelectSingleNode("./*[local-name()='elements']/*[local-name()='text']") }
    $enabled=if ($policy) { $policy.SelectSingleNode("./*[local-name()='enabledValue']/*[local-name()='decimal']") }
    if (-not $policy -or $policy.GetAttribute('key') -ine 'Software\Policies\Microsoft\Windows\Explorer' -or
        $policy.GetAttribute('valueName') -ne 'ConfigureStartPins' -or $policy.GetAttribute('class') -ne 'Both' -or
        -not $text -or $text.GetAttribute('valueName') -ne 'ConfigureStartPinsJSON' -or -not $enabled -or $enabled.GetAttribute('value') -ne '1') {
        throw 'The target StartMenu.admx does not contain the supported Configure Start Pins file policy.'
    }
    [pscustomobject]@{Key='SOFTWARE\Policies\Microsoft\Windows\Explorer';EnabledName='ConfigureStartPins';FileName='ConfigureStartPinsJSON'}
}

function Assert-OSDAppTaskbarPinsPlatform {
    param([int]$Build, [int]$Revision, [string]$InstallationType, [string]$EditionId)
    # Use the same supported baseline as Start applyOnce; it includes the PinGeneration update.
    if ($InstallationType -ne 'Client' -or $Build -lt 26100 -or ($Build -eq 26100 -and $Revision -lt 4770) -or
        $EditionId -notmatch '^(Professional|Enterprise|Education|IoTEnterprise)') {
        throw 'User-editable taskbar pins require Windows 11 Pro, Enterprise, Education or IoT Enterprise, build 26100.4770 or later.'
    }
}

function Get-OSDAppTaskbarPinsPolicy {
    param([Parameter(Mandatory)][string]$WindowsDirectory)
    $path=Join-Path $WindowsDirectory 'PolicyDefinitions\StartMenu.admx'
    $settings=[Xml.XmlReaderSettings]::new();$settings.DtdProcessing=[Xml.DtdProcessing]::Prohibit;$settings.XmlResolver=$null
    $reader=[Xml.XmlReader]::Create($path,$settings)
    try { $doc=[Xml.XmlDocument]::new();$doc.XmlResolver=$null;$doc.Load($reader) } finally { $reader.Dispose() }
    $policy=$doc.SelectSingleNode("//*[local-name()='policy' and @name='LockedStartLayout']")
    $text=if ($policy) { $policy.SelectSingleNode("./*[local-name()='elements']/*[local-name()='text' and @valueName='StartLayoutFile']") }
    $enabled=if ($policy) { $policy.SelectSingleNode("./*[local-name()='enabledValue']/*[local-name()='decimal']") }
    if (-not $policy -or $policy.GetAttribute('key') -ine 'Software\Policies\Microsoft\Windows\Explorer' -or
        $policy.GetAttribute('valueName') -ne 'LockedStartLayout' -or $policy.GetAttribute('class') -ne 'Both' -or
        -not $text -or -not $enabled -or $enabled.GetAttribute('value') -ne '1') {
        throw 'The target StartMenu.admx does not contain the supported Start Layout file policy for taskbar pins.'
    }
    # Relative to the already-mounted SOFTWARE hive, never the host registry.
    [pscustomobject]@{Key='Policies\Microsoft\Windows\Explorer';EnabledName='LockedStartLayout';FileName='StartLayoutFile'}
}

function Set-OSDAppStartPinsConfiguration {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Pins)
    $cv=Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
    Assert-OSDAppStartPinsPlatform -Build ([int]$cv.CurrentBuildNumber) -Revision ([int]$cv.UBR) -InstallationType $cv.InstallationType -EditionId $cv.EditionID
    $mapping=Get-OSDAppStartPinsPolicy
    $json=([ordered]@{applyOnce=$true;pinnedList=@(ConvertTo-OSDAppDesktopPins -Pins $Pins)} | ConvertTo-Json -Depth 10)
    $directory=Join-Path $env:ProgramData 'OSDApps\Configuration'
    $path=Join-Path $directory 'StartPins.json'
    $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,[Microsoft.Win32.RegistryView]::Registry64)
    $key=$null;$oldBytes=$null;$written=$false;$old=@{}
    try {
        $key=$base.CreateSubKey($mapping.Key)
        foreach ($name in @($mapping.EnabledName,$mapping.FileName)) {
            if ($key.GetValueNames() -contains $name) { $old[$name]=@{Value=$key.GetValue($name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames);Kind=$key.GetValueKind($name)} }
        }
        if ($old.Count -gt 0 -and ($key.GetValue($mapping.FileName) -ne $path -or $key.GetValue($mapping.EnabledName) -ne 1)) { throw 'An existing Start pins policy belongs to another configuration. Nothing was replaced.' }
        if (Test-Path -LiteralPath $path) {
            if ($old.Count -ne 2) { throw 'An unowned StartPins.json already exists.' }
            $oldBytes=[IO.File]::ReadAllBytes($path)
        }
        New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop | Out-Null
        [IO.File]::WriteAllText($path,$json,[Text.UTF8Encoding]::new($false));$written=$true
        $key.SetValue($mapping.FileName,$path,[Microsoft.Win32.RegistryValueKind]::String)
        $key.SetValue($mapping.EnabledName,1,[Microsoft.Win32.RegistryValueKind]::DWord)
        [pscustomobject]@{Outcome='ConfiguredForFirstSignIn';Path=$path;PinCount=$Pins.Count;ApplyOnce=$true}
    }
    catch {
        if ($written) {
            if ($null -ne $oldBytes) { [IO.File]::WriteAllBytes($path,$oldBytes) } else { [IO.File]::Delete($path) }
            foreach ($name in @($mapping.EnabledName,$mapping.FileName)) {
                if ($old.ContainsKey($name)) { $key.SetValue($name,$old[$name].Value,$old[$name].Kind) } else { $key.DeleteValue($name,$false) }
            }
        }
        throw
    }
    finally { if ($key) { $key.Dispose() };$base.Dispose() }
}

function Set-OSDAppTimeZoneConfiguration {
    param([Parameter(Mandatory)][string]$Id)
    # Validate against the installed Windows catalogue, not the WinPE host or localized names.
    $zoneKey=Join-Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Time Zones' $Id
    if (-not (Test-Path -LiteralPath $zoneKey)) { throw ('Unknown Windows time zone ID: ' + $Id) }
    $before=(Get-TimeZone -ErrorAction Stop).Id
    if ($before -ine $Id) { Set-TimeZone -Id $Id -ErrorAction Stop }
    $after=(Get-TimeZone -ErrorAction Stop).Id
    if ($after -ine $Id) { throw 'The requested time zone was not observed during this run.' }
    [pscustomobject]@{Outcome=if ($before -ieq $after) {'Unchanged'} else {'Applied'};Before=$before;After=$after}
}

function Invoke-OSDAppDesktopConfiguration {
    param([Parameter(Mandatory)]$Configuration)
    Assert-OSDAppDesktopConfiguration -Configuration $Configuration
    $items=@(foreach ($operation in @($Configuration.Operations)) {
        $item=[ordered]@{Kind=[string]$operation.Kind;Status='Failed';Detail=$null;Error=$null}
        try {
            switch ([string]$operation.Kind) {
                'TimeZone' { $item.Detail=Set-OSDAppTimeZoneConfiguration -Id $operation.Id }
                'StartPins' { $item.Detail=Set-OSDAppStartPinsConfiguration -Pins @($operation.Pins) }
                'TaskbarPins' { $item.Detail=[pscustomobject]@{Outcome='PreparedOffline';PinCount=@($operation.Pins).Count;Mode='Replace';PinGeneration=1;Note='Taskbar file policy was prepared in WinPE for first sign-in. Windows retains the policy; PinGeneration permits user unpinning. This is not proof of the rendered user layout.'} }
            }
            $item.Status='Succeeded'
        }
        catch { $item.Error=$_.Exception.Message }
        [pscustomobject]$item
    })
    $failed=@($items | Where-Object Status -eq 'Failed').Count
    [pscustomobject]@{
        SchemaVersion=1;DeploymentId=[string]$Configuration.DeploymentId;Status=if ($failed) {'Failed'} else {'Succeeded'}
        OperationCount=$items.Count;SuccessfulOperationCount=($items.Count-$failed);FailedOperationCount=$failed
        RestartNeeded=$false;RebootRequested=$false;Items=$items
    }
}

if ($MyInvocation.InvocationName -eq '.') { return }
$ErrorActionPreference='Stop'
try {
    if (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT') { throw 'Desktop settings runtime requires full Windows.' }
    if (-not [Environment]::Is64BitProcess) { throw 'Desktop settings runtime requires native 64-bit PowerShell.' }
    $configuration=Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    $record=Invoke-OSDAppDesktopConfiguration -Configuration $configuration
    $resultPath=[Environment]::ExpandEnvironmentVariables([string]$configuration.ResultPath)
    New-Item -ItemType Directory -Path (Split-Path $resultPath -Parent) -Force | Out-Null
    $record | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    if ($record.Status -eq 'Failed') { exit 1 }
    exit 0
}
catch { Write-Error $_.Exception.Message -ErrorAction Continue;exit 1 }
