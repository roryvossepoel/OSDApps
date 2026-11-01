function Add-OSDStageFile {
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName='Content')]
    param(
        [Parameter(Mandatory,ParameterSetName='Content')]
        [Parameter(Mandatory,ParameterSetName='Remove')][ValidateNotNullOrEmpty()][string]$Path,
        [Parameter(ParameterSetName='Content')][AllowEmptyString()][string]$Content = '',
        [Parameter(ParameterSetName='Content')][ValidateSet('UTF8','UTF8BOM','Unicode','ASCII')][string]$Encoding = 'UTF8',
        [Parameter(Mandatory,ParameterSetName='Copy')][ValidateNotNullOrEmpty()][string]$SourcePath,
        [Parameter(Mandatory,ParameterSetName='Copy')][ValidateNotNullOrEmpty()][string]$DestinationPath,
        [Parameter(Mandatory,ParameterSetName='Remove')][switch]$Remove,
        [switch]$Force,
        [string]$WindowsPath
    )
    Assert-OSDStageSourceEnabled -Source BuiltIn
    if (-not (Test-OSDStageWinPE)) { throw 'Stage file operations in WinPE after OSDCloud.' }
    if ($PSCmdlet.ParameterSetName -eq 'Remove' -and -not $Remove) { throw 'Remove must be explicitly enabled.' }
    $destination = if ($PSCmdlet.ParameterSetName -eq 'Copy') { $DestinationPath } else { $Path }
    Assert-OSDStageFileSystemPath -Path $destination
    $operation = [pscustomobject]@{Kind='File';Action=if($Remove){'Remove'}else{'Create'};Path=$destination;Force=[bool]$Force;Recurse=$false;Data=''}
    if ($PSCmdlet.ParameterSetName -eq 'Copy') {
        $source = Get-Item -LiteralPath $SourcePath -Force -ErrorAction Stop
        if ($source -isnot [IO.FileInfo]) { throw 'SourcePath must be one file.' }
        Assert-OSDStageFileSystemNoLink -Path $source.FullName
        if ($source.Length -gt 16MB) { throw 'File content is limited to 16 MiB per operation.' }
        $operation.Data = [Convert]::ToBase64String([IO.File]::ReadAllBytes($source.FullName))
    }
    elseif (-not $Remove) {
        $encoder = switch ($Encoding) {
            'UTF8' { [Text.UTF8Encoding]::new($false, $true) }
            'UTF8BOM' { [Text.UTF8Encoding]::new($true, $true) }
            'Unicode' { [Text.UnicodeEncoding]::new($false, $true, $true) }
            'ASCII' { [Text.Encoding]::GetEncoding('us-ascii', [Text.EncoderFallback]::ExceptionFallback, [Text.DecoderFallback]::ExceptionFallback) }
        }
        $operation.Data = [Convert]::ToBase64String([byte[]]($encoder.GetPreamble() + $encoder.GetBytes($Content)))
    }
    Assert-OSDStageFileSystemOperation -Operation $operation
    if ($PSCmdlet.ShouldProcess($destination, 'Stage file operation for SetupComplete')) {
        Save-OSDStageFileSystemStaging -Operations @($operation) -WindowsPath $WindowsPath
    }
}
