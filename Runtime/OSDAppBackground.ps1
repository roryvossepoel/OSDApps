# Shared validation and native Windows background processing. No entry-point side effects.
function Assert-OSDAppBackgroundOperation {
    param([Parameter(Mandatory)]$Operation)
    if ([string]$Operation.FutureSystemRoot -notmatch '^[A-Za-z]:\\Windows$' -or $Operation.Kind -cnotin @('Wallpaper','LockScreen') -or $Operation.Enforce -isnot [bool] -or
        [string]$Operation.Id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or [string]$Operation.Id -match '\.\.' -or
        [string]$Operation.ImageSha256 -notmatch '^[A-Fa-f0-9]{64}$' -or [string]$Operation.Extension -cnotin @('.jpg','.jpeg','.png')) {
        throw 'Invalid background operation.'
    }
    $expected='OEM\OSDApps\Branding\' + $Operation.Id + '\' + $Operation.ImageSha256 + $Operation.Extension
    if ([string]$Operation.ImageRelativePath -cne $expected) { throw 'Invalid background image destination.' }
}

function Assert-OSDAppBackgroundPlatform {
    param([int]$Build,[string]$InstallationType,[string]$EditionId,[Parameter(Mandatory)]$Operation)
    if ($Build -lt 22000 -or $InstallationType -ne 'Client') { throw 'Background configuration requires Windows 11 client.' }
    if ($Operation.Enforce -or $Operation.Kind -eq 'LockScreen') {
        if ($EditionId -notmatch '^(Enterprise|Education|IoTEnterprise)') { throw 'Lock screen and enforced backgrounds require Windows 11 Enterprise/Education in this release; ordinary Pro is not supported for these modes.' }
    }
    elseif ($EditionId -notmatch '^(Professional|Enterprise|Education|IoTEnterprise)') { throw 'Default wallpaper requires a Windows 11 business edition.' }
}

function Assert-OSDAppBackgroundPath {
    param([Parameter(Mandatory)][string]$Path)
    $current=[IO.Path]::GetFullPath($Path)
    while ($current) {
        if (Test-Path -LiteralPath $current) {
            if ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Background paths must not contain reparse points.' }
        }
        $parent=[IO.Path]::GetDirectoryName($current)
        if ($parent -eq $current) { break }
        $current=$parent
    }
}

function Assert-OSDAppBackgroundFile {
    param([Parameter(Mandatory)]$Operation,[string]$WindowsDirectory=$env:SystemRoot,[switch]$CheckAnswerFile)
    Assert-OSDAppBackgroundOperation -Operation $Operation
    $path=Join-Path $WindowsDirectory $Operation.ImageRelativePath
    Assert-OSDAppBackgroundPath -Path $path
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $Operation.ImageSha256) { throw 'Persistent background image is missing or its SHA-256 does not match staging.' }
    if ($CheckAnswerFile -and $Operation.Kind -eq 'Wallpaper' -and -not $Operation.Enforce) {
        $answer=Join-Path $WindowsDirectory 'Panther\unattend.xml'
        Assert-OSDAppBackgroundPath -Path $answer
        $doc=[xml]::new();$doc.XmlResolver=$null;$doc.Load($answer)
        $ns=[Xml.XmlNamespaceManager]::new($doc.NameTable);$ns.AddNamespace('u','urn:schemas-microsoft-com:unattend')
        $nodes=@($doc.SelectNodes('/u:unattend/u:settings[@pass="oobeSystem"]/u:component[@name="Microsoft-Windows-Shell-Setup"]/u:Themes/u:DesktopBackground',$ns))
        if ($nodes.Count -ne 1 -or $nodes[0].InnerText -ine ($Operation.FutureSystemRoot+'\'+$Operation.ImageRelativePath)) { throw 'The staged wallpaper answer-file setting is missing or modified.' }
    }
}

function Assert-OSDAppBackgroundPolicyState {
    param([Parameter(Mandatory)][Microsoft.Win32.RegistryKey]$Software,[Parameter(Mandatory)]$Operation)
    $checks=@(
        @{Key='Policies\Microsoft\Windows\Personalization';Name='LockScreenImage';Applies='LockScreen'},
        @{Key='Policies\Microsoft\Windows\Personalization';Name='NoChangingLockScreen';Applies='LockScreen'},
        @{Key='Microsoft\Windows\CurrentVersion\PersonalizationCSP';Name='LockScreenImagePath';Applies='LockScreen'},
        @{Key='Microsoft\Windows\CurrentVersion\PersonalizationCSP';Name='LockScreenImageUrl';Applies='LockScreen'},
        @{Key='Microsoft\Windows\CurrentVersion\PersonalizationCSP';Name='DesktopImagePath';Applies='Wallpaper'},
        @{Key='Microsoft\Windows\CurrentVersion\PersonalizationCSP';Name='DesktopImageUrl';Applies='Wallpaper'},
        @{Key='Microsoft\Windows\CurrentVersion\Policies\System';Name='Wallpaper';Applies='Wallpaper'}
    )
    foreach ($check in @($checks | Where-Object Applies -eq $Operation.Kind)) {
        $key=$Software.OpenSubKey($check.Key)
        try {
            if ($key -and $null -ne $key.GetValue($check.Name)) {
                $value=$key.GetValue($check.Name)
                if ([string]$value -ne '' -and [string]$value -ne '0') { throw ('Existing background policy conflicts with staging: ' + $check.Key + '\' + $check.Name) }
            }
        }
        finally { if ($key) { $key.Dispose() } }
    }
}

function Get-OSDAppLockScreenPolicy {
    param([string]$WindowsDirectory=$env:SystemRoot)
    $path=Join-Path $WindowsDirectory 'PolicyDefinitions\ControlPanelDisplay.admx'
    $doc=[xml]::new();$doc.XmlResolver=$null;$doc.Load($path)
    $policy=$doc.SelectSingleNode("//*[local-name()='policy' and @name='CPL_Personalization_ForceDefaultLockScreen']")
    $text=if ($policy) { $policy.SelectSingleNode("./*[local-name()='elements']/*[local-name()='text' and @valueName='LockScreenImage']") } else { $null }
    if (-not $policy -or $policy.GetAttribute('class') -ne 'Machine' -or
        $policy.GetAttribute('key') -ine 'Software\Policies\Microsoft\Windows\Personalization' -or -not $text) { throw 'The target does not expose the supported default lock screen policy mapping.' }
    [pscustomobject]@{Key='Policies\Microsoft\Windows\Personalization';Name='LockScreenImage'}
}

function Set-OSDAppBackgroundCsp {
    param([Parameter(Mandatory)]$Operation,[Parameter(Mandatory)][string]$ImagePath)
    $namespace='root\cimv2\mdm\dmmap';$class='MDM_Personalization'
    $property=if ($Operation.Kind -eq 'Wallpaper') { 'DesktopImageUrl' } else { 'LockScreenImageUrl' }
    $statusProperty=if ($Operation.Kind -eq 'Wallpaper') { 'DesktopImageStatus' } else { 'LockScreenImageStatus' }
    $instances=@(Get-CimInstance -Namespace $namespace -ClassName $class -ErrorAction Stop)
    if ($instances.Count -gt 1) { throw 'Ambiguous Personalization CSP instance.' }
    $previous=$null;$created=$false;$changed=$false
    if ($instances.Count) {
        $previous=$instances[0].$property
        if (-not [string]::IsNullOrWhiteSpace([string]$previous)) { throw 'An existing CSP image is already configured. Nothing was replaced.' }
    }
    try {
        # File URI avoids a download and keeps source assets outside temporary staging.
        $uri=([uri]$ImagePath).AbsoluteUri
        if ($instances.Count) {
            $changed=$true
            Set-CimInstance -CimInstance $instances[0] -Property @{$property=$uri} -ErrorAction Stop | Out-Null
        }
        else {
            $values=@{ParentID='./Vendor/MSFT';InstanceID='Personalization'};$values[$property]=$uri
            $instance=New-CimInstance -Namespace $namespace -ClassName $class -Property $values -ErrorAction Stop
            $created=$true;$changed=$true
        }
        $current=@(Get-CimInstance -Namespace $namespace -ClassName $class -ErrorAction Stop)
        if ($current.Count -ne 1 -or [string]$current[0].$property -ne $uri) { throw 'Personalization CSP did not retain the requested image URL.' }
        $status=$current[0].$statusProperty
        if ($null -eq $status -or [int]$status -notin @(1,2)) { throw "Personalization CSP reported image status '$status'." }
        [pscustomobject]@{Outcome=if ([int]$status -eq 1) {'Applied'}else{'Submitted'};Technique='PersonalizationCSP/WmiBridge';ImagePath=$ImagePath;Enforced=$true;CspStatus=[int]$status;Note='Provider state, not proof of the rendered screen. No retry or follow-up task is scheduled.'}
    }
    catch {
        $original=$_.Exception.Message
        if ($changed) {
            try {
                if ($created) { Remove-CimInstance -CimInstance $instance -ErrorAction Stop }
                else { Set-CimInstance -CimInstance $instances[0] -Property @{$property=[string]$previous} -ErrorAction Stop | Out-Null }
            }
            catch { throw ($original + ' CSP rollback also failed: ' + $_.Exception.Message) }
        }
        throw $original
    }
}

function Set-OSDAppBackgroundConfiguration {
    param([Parameter(Mandatory)]$Operation)
    Assert-OSDAppBackgroundFile -Operation $Operation
    if ($env:SystemRoot -ine $Operation.FutureSystemRoot) { throw 'The running Windows directory differs from the staged target.' }
    if ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-18') { throw 'Background runtime requires SYSTEM.' }
    $software=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SOFTWARE',$true)
    try {
        $cv=$software.OpenSubKey('Microsoft\Windows NT\CurrentVersion')
        try { Assert-OSDAppBackgroundPlatform -Operation $Operation -Build ([int]$cv.GetValue('CurrentBuildNumber')) -EditionId ([string]$cv.GetValue('EditionID')) -InstallationType ([string]$cv.GetValue('InstallationType')) }
        finally { if ($cv) { $cv.Dispose() } }
        Assert-OSDAppBackgroundPolicyState -Software $software -Operation $Operation
        $path=Join-Path $env:SystemRoot $Operation.ImageRelativePath
        if ($Operation.Enforce) { return Set-OSDAppBackgroundCsp -Operation $Operation -ImagePath $path }
        if ($Operation.Kind -eq 'Wallpaper') {
            return [pscustomobject]@{Outcome='PreparedOffline';Technique='WindowsSetup/Themes';ImagePath=$path;Enforced=$false;Note='Answer file was prepared before first boot; visual first-sign-in behavior requires acceptance testing.'}
        }
        $mapping=Get-OSDAppLockScreenPolicy
        $key=$software.CreateSubKey($mapping.Key)
        try { $key.SetValue($mapping.Name,$path,[Microsoft.Win32.RegistryValueKind]::String) }
        finally { if ($key) { $key.Dispose() } }
        [pscustomobject]@{Outcome='ConfiguredDefault';Technique='NativeDefaultLockScreenPolicy';ImagePath=$path;Enforced=$false;Note='Default also applies to the sign-in screen. No prevent-changing policy is enabled.'}
    }
    finally { if ($software) { $software.Dispose() } }
}
