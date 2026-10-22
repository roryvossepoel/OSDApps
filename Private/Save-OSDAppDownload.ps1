function Save-OSDAppDownload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [uri]$Uri,

        [Parameter(Mandatory)]
        [string]$DestinationPath,

        [Parameter(Mandatory)]
        [string]$Activity,

        [int]$ProgressId = 20,

        [int]$ParentProgressId = -1,
        [switch]$PreserveFileName
    )

    Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue

    $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.AllowAutoRedirect = $true
    $client = New-Object System.Net.Http.HttpClient($handler)
    $client.Timeout = [TimeSpan]::FromHours(1)

    $directory = Split-Path -Path $DestinationPath -Parent
    if ($directory) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $tempPath = "$DestinationPath.download"
    if (Test-Path -LiteralPath $tempPath) {
        Remove-Item -LiteralPath $tempPath -Force
    }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        $response = $client.GetAsync($Uri, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        $response.EnsureSuccessStatusCode() | Out-Null
        if ($PreserveFileName) {
            $name = Get-OSDAppDownloadFileName -Response $response -ExpectedExtension ([IO.Path]::GetExtension($DestinationPath))
            $DestinationPath = Join-Path $directory $name
        }

        $totalBytes = $response.Content.Headers.ContentLength
        $source = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()

        $target = New-Object System.IO.FileStream(
            $tempPath,
            [System.IO.FileMode]::Create,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None
        )

        try {
            $buffer = New-Object byte[] (1024 * 1024)
            [int64]$downloaded = 0
            $lastPercent = -1
            $lastProgressSecond = -1

            while (($read = $source.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $target.Write($buffer, 0, $read)
                $downloaded += $read

                $elapsedSeconds = [math]::Max($stopwatch.Elapsed.TotalSeconds, 0.001)
                $speedBytesPerSecond = $downloaded / $elapsedSeconds
                $speedMBps = [math]::Round($speedBytesPerSecond / 1MB, 1)
                $downloadedGB = [math]::Round($downloaded / 1GB, 2)
                $elapsed = $stopwatch.Elapsed.ToString('hh\:mm\:ss')

                if ($totalBytes -and $totalBytes -gt 0) {
                    $percent = [math]::Min(100, [int](($downloaded / $totalBytes) * 100))
                    $totalGB = [math]::Round($totalBytes / 1GB, 2)
                    $remainingSeconds = if ($speedBytesPerSecond -gt 0) { [math]::Max(0, ($totalBytes - $downloaded) / $speedBytesPerSecond) } else { 0 }
                    $remaining = [TimeSpan]::FromSeconds($remainingSeconds).ToString('hh\:mm\:ss')

                    if ($percent -ne $lastPercent -or [int]$stopwatch.Elapsed.TotalSeconds -ne $lastProgressSecond) {
                        $status = "$downloadedGB GB / $totalGB GB · $percent% · $speedMBps MB/s · $elapsed elapsed · ~$remaining remaining"
                        Write-Progress -Id $ProgressId -ParentId $ParentProgressId -Activity $Activity -Status $status -PercentComplete $percent
                        $lastPercent = $percent
                        $lastProgressSecond = [int]$stopwatch.Elapsed.TotalSeconds
                    }
                }
                elseif ([int]$stopwatch.Elapsed.TotalSeconds -ne $lastProgressSecond) {
                    $status = "$downloadedGB GB · $speedMBps MB/s · $elapsed elapsed"
                    Write-Progress -Id $ProgressId -ParentId $ParentProgressId -Activity $Activity -Status $status -PercentComplete -1
                    $lastProgressSecond = [int]$stopwatch.Elapsed.TotalSeconds
                }
            }
        }
        finally {
            $target.Dispose()
            $source.Dispose()
            Write-Progress -Id $ProgressId -Activity $Activity -Completed
        }

        if (Test-Path -LiteralPath $DestinationPath) {
            Remove-Item -LiteralPath $DestinationPath -Force
        }
        Move-Item -LiteralPath $tempPath -Destination $DestinationPath -Force
    }
    catch {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
        throw
    }
    finally {
        $stopwatch.Stop()
        $client.Dispose()
        $handler.Dispose()
    }

    Get-Item -LiteralPath $DestinationPath
}
