function Get-OSDAppBackgroundTarget {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$WindowsPath,[Parameter(Mandatory)]$Operation)
    Invoke-OSDAppOfflineSoftware -WindowsPath $WindowsPath -Action {
        param($Software)
        $cv=$Software.OpenSubKey('Microsoft\Windows NT\CurrentVersion')
        try {
            if (-not $cv) { throw 'Target Windows version is missing.' }
            Assert-OSDAppBackgroundPlatform -Operation $Operation -Build ([int]$cv.GetValue('CurrentBuildNumber')) -InstallationType ([string]$cv.GetValue('InstallationType')) -EditionId ([string]$cv.GetValue('EditionID'))
            $platform=[pscustomobject]@{Build=[int]$cv.GetValue('CurrentBuildNumber');EditionId=[string]$cv.GetValue('EditionID');InstallationType=[string]$cv.GetValue('InstallationType')}
        }
        finally { if ($cv) { $cv.Dispose() } }
        Assert-OSDAppBackgroundPolicyState -Software $Software -Operation $Operation
        # Never expand an offline SystemRoot using the WinPE process environment.
        $platform
    }
}

function Get-OSDAppBackgroundAnswerFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$WindowsPath)
    $path=Join-Path $WindowsPath 'Windows\Panther\unattend.xml'
    Assert-OSDAppBackgroundPath -Path $path
    # Never silently compete with another answer-file selection.
    foreach ($relative in @('Windows\Panther\Unattend\unattend.xml','Windows\System32\Sysprep\unattend.xml','unattend.xml','autounattend.xml')) {
        if (Test-Path -LiteralPath (Join-Path $WindowsPath $relative)) { throw "Another answer file exists at '$relative'. Resolve the answer-file selection before staging default wallpaper." }
    }
    Invoke-OSDAppOfflineSoftware -WindowsPath $WindowsPath -HiveName SYSTEM -Action {
        param($System)
        $setup=$System.OpenSubKey('Setup')
        try {
            $selected=if ($setup) { [string]$setup.GetValue('UnattendFile',$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) } else { '' }
            if ($selected -and $selected -inotmatch '^%(WINDIR|SystemRoot)%\\Panther\\unattend\.xml$') { throw 'The target SYSTEM hive selects an absolute or different answer file. Resolve this override before staging; its future drive letter cannot be inferred in WinPE.' }
        }
        finally { if ($setup) { $setup.Dispose() } }
    }
    $path
}

function ConvertTo-OSDAppWallpaperAnswerFile {
    [CmdletBinding()]
    param([AllowNull()][string]$ExistingXml,[Parameter(Mandatory)][string]$ImagePath,[ValidateSet('amd64','arm64')][string]$Architecture)
    $namespace='urn:schemas-microsoft-com:unattend'
    $doc=[xml]::new();$doc.PreserveWhitespace=$true;$doc.XmlResolver=$null
    if ($ExistingXml) {
        $settings=[Xml.XmlReaderSettings]::new();$settings.DtdProcessing=[Xml.DtdProcessing]::Prohibit;$settings.XmlResolver=$null
        $reader=[Xml.XmlReader]::Create([IO.StringReader]::new($ExistingXml),$settings)
        try { $doc.Load($reader) } finally { $reader.Dispose() }
        if ($doc.DocumentElement.LocalName -ne 'unattend' -or $doc.DocumentElement.NamespaceURI -ne $namespace) { throw 'Unsupported answer-file XML root.' }
    }
    else { $null=$doc.AppendChild($doc.CreateElement('unattend',$namespace)) }
    $ns=[Xml.XmlNamespaceManager]::new($doc.NameTable);$ns.AddNamespace('u',$namespace)
    if ($doc.SelectNodes('//u:Themes/u:DesktopBackground | //u:Themes/u:CustomDefaultThemeFile',$ns).Count) { throw 'The answer file already defines a background or custom theme. Nothing was replaced.' }
    $passes=@($doc.SelectNodes('/u:unattend/u:settings[@pass="oobeSystem"]',$ns))
    if ($passes.Count -gt 1) { throw 'Duplicate oobeSystem settings.' }
    if ($passes.Count) { $pass=$passes[0];if ($pass.GetAttribute('wasPassProcessed') -eq 'true') { throw 'The oobeSystem pass was already processed; stage on a fresh image.' } }
    else { $pass=$doc.CreateElement('settings',$namespace);$pass.SetAttribute('pass','oobeSystem');$null=$doc.DocumentElement.AppendChild($pass) }
    $components=@($pass.SelectNodes('u:component[@name="Microsoft-Windows-Shell-Setup"]',$ns))
    if ($components.Count -gt 1) { throw 'Ambiguous Shell-Setup components in oobeSystem.' }
    if ($components.Count) {
        $component=$components[0]
        if ($component.GetAttribute('processorArchitecture') -ne $Architecture) { throw 'Shell-Setup architecture does not match the target kernel.' }
    }
    else {
        $component=$doc.CreateElement('component',$namespace)
        foreach ($pair in @{name='Microsoft-Windows-Shell-Setup';processorArchitecture=$Architecture;publicKeyToken='31bf3856ad364e35';language='neutral';versionScope='nonSxS'}.GetEnumerator()) { $component.SetAttribute($pair.Key,$pair.Value) }
        $null=$pass.AppendChild($component)
    }
    $themes=@($component.SelectNodes('u:Themes',$ns))
    if ($themes.Count -gt 1) { throw 'Duplicate Themes elements.' }
    if ($themes.Count) { $theme=$themes[0] } else { $theme=$doc.CreateElement('Themes',$namespace);$null=$component.AppendChild($theme) }
    if (-not $theme.SelectSingleNode('u:ThemeName',$ns)) { $name=$doc.CreateElement('ThemeName',$namespace);$name.InnerText='OSDApps';$null=$theme.AppendChild($name) }
    $background=$doc.CreateElement('DesktopBackground',$namespace);$background.InnerText=$ImagePath;$null=$theme.AppendChild($background)
    # The commit writes UTF-8; preserve content without retaining a conflicting declaration.
    if ($doc.FirstChild -is [Xml.XmlDeclaration]) { $doc.FirstChild.Encoding='utf-8' }
    $doc.OuterXml
}

function Get-OSDAppBackgroundArchitecture {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$WindowsPath)
    $stream=[IO.File]::OpenRead((Join-Path $WindowsPath 'Windows\System32\ntoskrnl.exe'))
    $reader=[IO.BinaryReader]::new($stream)
    try {
        if ($reader.ReadUInt16() -ne 0x5A4D) { throw 'Invalid target kernel header.' }
        $stream.Position=0x3C;$offset=$reader.ReadInt32()
        if ($offset -lt 64 -or $offset -gt $stream.Length-6) { throw 'Invalid target kernel PE offset.' }
        $stream.Position=$offset
        if ($reader.ReadUInt32() -ne 0x4550) { throw 'Invalid target kernel PE signature.' }
        switch ($reader.ReadUInt16()) { 0x8664 { 'amd64' };0xAA64 { 'arm64' };default { throw 'Background staging requires an x64 or ARM64 target.' } }
    }
    finally { $reader.Dispose() }
}

function Set-OSDAppOfflineBackground {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$WindowsPath,[Parameter(Mandatory)]$Operation,[Parameter(Mandatory)][string]$SourcePath,[Parameter(Mandatory)][scriptblock]$Commit)
    $ErrorActionPreference='Stop'
    Assert-OSDAppBackgroundOperation -Operation $Operation
    Get-OSDAppBackgroundTarget -WindowsPath $WindowsPath -Operation $Operation | Out-Null
    $path=Join-Path (Join-Path $WindowsPath 'Windows') $Operation.ImageRelativePath
    Assert-OSDAppBackgroundPath -Path $path
    if ((Get-FileHash -LiteralPath $SourcePath -Algorithm SHA256).Hash -ne $Operation.ImageSha256) { throw 'Image changed before commit.' }
    $exists=Test-Path -LiteralPath $path
    if ($exists -and (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $Operation.ImageSha256)) { throw 'An unowned or modified background file occupies the destination.' }
    $answerPath=$null;$answerBytes=$null;$answerXml=$null
    if (-not $Operation.Enforce -and $Operation.Kind -eq 'Wallpaper') {
        $answerPath=Get-OSDAppBackgroundAnswerFile -WindowsPath $WindowsPath
        if (Test-Path -LiteralPath $answerPath -PathType Leaf) { $answerBytes=[IO.File]::ReadAllBytes($answerPath);$existing=[IO.File]::ReadAllText($answerPath) } else { $existing=$null }
        $answerXml=ConvertTo-OSDAppWallpaperAnswerFile -ExistingXml $existing -ImagePath ($Operation.FutureSystemRoot+'\'+$Operation.ImageRelativePath) -Architecture (Get-OSDAppBackgroundArchitecture -WindowsPath $WindowsPath)
    }
    if (-not $Operation.Enforce -and $Operation.Kind -eq 'LockScreen') { Get-OSDAppLockScreenPolicy -WindowsDirectory (Join-Path $WindowsPath 'Windows') | Out-Null }
    $imageWritten=$false;$answerWritten=$false
    try {
        if (-not $exists) {
            New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force | Out-Null
            $imageWritten=$true;Copy-Item -LiteralPath $SourcePath -Destination $path -ErrorAction Stop
        }
        Assert-OSDAppBackgroundFile -Operation $Operation -WindowsDirectory (Join-Path $WindowsPath 'Windows')
        if ($answerPath) {
            New-Item -ItemType Directory -Path (Split-Path $answerPath -Parent) -Force | Out-Null
            $answerWritten=$true;[IO.File]::WriteAllText($answerPath,$answerXml,[Text.UTF8Encoding]::new($false))
        }
        & $Commit
    }
    catch {
        $original=$_.Exception.Message
        try {
            if ($answerWritten) {
                if ($null -ne $answerBytes) { [IO.File]::WriteAllBytes($answerPath,$answerBytes) } else { [IO.File]::Delete($answerPath) }
            }
            if ($imageWritten) { [IO.File]::Delete($path) }
        }
        catch { throw ($original+' Background rollback also failed: '+$_.Exception.Message) }
        throw $original
    }
}
