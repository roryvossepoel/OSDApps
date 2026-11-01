function Save-OSDStageDownload {
    [CmdletBinding(DefaultParameterSetName='Exact')]
    param(
        [Parameter(Mandatory)][uri]$Uri,
        [Parameter(Mandatory,ParameterSetName='Exact')][string]$DestinationPath,
        [Parameter(Mandatory,ParameterSetName='Vendor')][string]$DestinationDirectory,
        [Parameter(Mandatory,ParameterSetName='Vendor')][string]$ExpectedExtension,
        [Parameter(Mandatory)][string]$Activity,
        [int]$ProgressId = 20,
        [int]$ParentProgressId = -1
    )
    Add-Type -AssemblyName System.Net.Http -ErrorAction Stop
    $directory = if ($PSCmdlet.ParameterSetName -eq 'Vendor') { $DestinationDirectory } else { Split-Path -Path $DestinationPath -Parent }
    $extension = if ($PSCmdlet.ParameterSetName -eq 'Vendor') { $ExpectedExtension } else { [IO.Path]::GetExtension($DestinationPath) }
    New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop | Out-Null
    $tempPath = Join-Path $directory ('.osdstage-download-' + [guid]::NewGuid().ToString('N'))
    $handler = [Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect = $true
    $client = [Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromHours(1)
    $response = $null
    $source = $null
    $target = $null
    $watch = [Diagnostics.Stopwatch]::StartNew()
    try {
        $response = $client.GetAsync($Uri, [Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        $response.EnsureSuccessStatusCode() | Out-Null
        $name = Get-OSDStageDownloadFileName -Response $response -ExpectedExtension $extension
        if ($PSCmdlet.ParameterSetName -eq 'Exact' -and $name -cne (Split-Path -Path $DestinationPath -Leaf)) {
            throw [IO.InvalidDataException]::new('The vendor response filename differs from the requested exact filename.')
        }
        $DestinationPath = Join-Path $directory $name
        $source = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $target = [IO.FileStream]::new($tempPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $buffer = New-Object byte[] (1024 * 1024)
        [long]$downloaded = 0
        $totalBytes = $response.Content.Headers.ContentLength
        $lastSecond = -1
        while (($read = $source.Read($buffer,0,$buffer.Length)) -gt 0) {
            $target.Write($buffer,0,$read)
            $downloaded += $read
            $second = [int]$watch.Elapsed.TotalSeconds
            if ($second -ne $lastSecond) {
                $speed = [math]::Round(($downloaded / 1MB) / [math]::Max(0.001,$watch.Elapsed.TotalSeconds),1)
                $percent = if ($totalBytes -and $totalBytes -gt 0) { [math]::Min(100,[int](100 * $downloaded / $totalBytes)) } else { -1 }
                Write-Progress -Id $ProgressId -ParentId $ParentProgressId -Activity $Activity -Status ("{0}: {1:N1} MB at {2:N1} MB/s" -f $name,($downloaded/1MB),$speed) -PercentComplete $percent
                $lastSecond = $second
            }
        }
        $target.Dispose(); $target = $null
        if ($downloaded -le 0 -or ($null -ne $totalBytes -and $downloaded -ne $totalBytes)) {
            throw [IO.InvalidDataException]::new('Downloaded payload is empty or does not match Content-Length.')
        }
        Move-Item -LiteralPath $tempPath -Destination $DestinationPath -Force -ErrorAction Stop
        Get-Item -LiteralPath $DestinationPath -ErrorAction Stop
    }
    finally {
        if ($target) { $target.Dispose() }
        if ($source) { $source.Dispose() }
        if ($response) { $response.Dispose() }
        $client.Dispose(); $handler.Dispose(); $watch.Stop()
        Write-Progress -Id $ProgressId -Activity $Activity -Completed
        if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue }
    }
}
