function Invoke-Retry([scriptblock]$Action) {
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try { return & $Action }
        catch { if ($attempt -eq 3) { throw }; Start-Sleep -Seconds 2 }
    }
}

function Quote-NativeArgument([string]$Value) {
    # Windows argv quoting, including embedded quotes and trailing backslashes.
    return '"' + [regex]::Replace([regex]::Replace($Value, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1') + '"'
}

function Native($program, $arguments, [int]$TimeoutSeconds = 300) {
    $process = New-Object Diagnostics.Process
    $process.StartInfo.FileName = $program
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.WorkingDirectory = (Get-Location).Path
    if ($program -eq $env:ComSpec) {
        # cmd parses its command itself; backslash escaping is not cmd escaping.
        if ($arguments.Count -ne 3 -or $arguments[0] -ne '/d' -or $arguments[1] -ne '/c') { throw 'Unexpected cmd invocation.' }
        $process.StartInfo.Arguments = '/d /c ' + $arguments[2]
    } else {
        $process.StartInfo.Arguments = (@($arguments | ForEach-Object { Quote-NativeArgument $_ }) -join ' ')
    }
    try {
        if (-not $process.Start()) { throw "Cannot start $program" }
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            & "$env:windir\System32\taskkill.exe" /PID $process.Id /T /F | Out-Null
            throw "$program timed out after $TimeoutSeconds seconds."
        }
        if ($process.ExitCode -ne 0) { throw "$program failed ($($process.ExitCode))" }
    } finally { $process.Dispose() }
}

function Publish-Local($Root, $Work, $Payload, $ArchiveName) {
    # All moves are within this checkout; originals remain recoverable in Work.
    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    foreach ($path in @($Work, $Payload)) {
        if (-not [IO.Path]::GetFullPath($path).StartsWith($rootPath, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Output path is outside the checkout: $path"
        }
    }
    if ($ArchiveName -notmatch '^tinycc-windows-\d{4}-\d{2}-\d{2}\.zip$') { throw 'Invalid archive name.' }
    $stagedZip = Join-Path $Work $ArchiveName
    [IO.Compression.ZipFile]::CreateFromDirectory($Payload, $stagedZip, [IO.Compression.CompressionLevel]::Optimal, $false)
    $hash = (Get-FileHash -LiteralPath $stagedZip -Algorithm SHA256).Hash.ToLower()
    "$hash  $ArchiveName" | Set-Content -LiteralPath ($stagedZip + '.sha256') -Encoding ASCII
    $archive = [IO.Compression.ZipFile]::OpenRead($stagedZip)
    try {
        if ($archive.Entries | Where-Object { $_.FullName.Replace('\', '/') -ieq 'include/obfus.h' }) {
            throw 'obfus.h is for temporary validation, not the compiler distribution.'
        }
        foreach ($required in @('tcc.exe', 'i386-win32-tcc.exe', 'arm64-win32-tcc.exe', 'libtcc.dll', 'obfh-update.cmd', 'build-info.json')) {
            if (-not ($archive.Entries | Where-Object { $_.FullName.Replace('\', '/') -eq $required -and $_.Length -gt 0 })) {
                throw "Release archive is missing $required"
            }
        }
    } finally { $archive.Dispose() }
    $destination = Join-Path $Root 'bin'
    $dist = Join-Path $Root 'dist'
    New-Item -ItemType Directory -Force -Path $dist | Out-Null
    $zip = Join-Path $dist $ArchiveName
    $moves = New-Object Collections.Generic.List[object]
    try {
        foreach ($pair in @(
            @($destination, (Join-Path $Work 'previous-bin')),
            @($zip, (Join-Path $Work 'previous-release.zip')),
            @(($zip + '.sha256'), (Join-Path $Work 'previous-release.zip.sha256')),
            @($Payload, $destination), @($stagedZip, $zip), @(($stagedZip + '.sha256'), ($zip + '.sha256'))
        )) {
            if (Test-Path -LiteralPath $pair[0]) {
                Move-Item -LiteralPath $pair[0] -Destination $pair[1] -ErrorAction Stop
                $moves.Add($pair)
            }
        }
    } catch {
        $failure = $_
        for ($n = $moves.Count - 1; $n -ge 0; $n--) {
            $pair = $moves[$n]
            try { Move-Item -LiteralPath $pair[1] -Destination $pair[0] -ErrorAction Stop }
            catch { Write-Warning "Could not restore $($pair[0]); recover it from $($pair[1])." }
        }
        throw $failure
    }
    Write-Host "Ready: $destination"
    Write-Host "Archive: $zip"
}
