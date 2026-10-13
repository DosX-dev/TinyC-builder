$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.IO.Compression.FileSystem
$root = Split-Path $PSScriptRoot
. (Join-Path $PSScriptRoot 'build-support.ps1')
$work = Join-Path $root ('.work/upx-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null
$headers = @{ 'User-Agent' = 'TinyCC-builder' }
if ($env:GITHUB_TOKEN) { $headers.Authorization = 'Bearer ' + $env:GITHUB_TOKEN }
function Download($url, $destination) {
    Invoke-Retry {
        Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $destination -TimeoutSec 120
        if ((Get-Item -LiteralPath $destination).Length -eq 0) { throw "Empty download: $url" }
    }
}

$buildLock = $null
try {
    $buildLock = [IO.File]::Open((Join-Path $root '.work/build.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    $original = Join-Path $root 'bin'
    $info = Get-Content -LiteralPath (Join-Path $original 'build-info.json') -Raw | ConvertFrom-Json
    # Pack precisely the distribution that passed the normal build checks.
    Test-DistributionManifest $original $info
    Write-Host 'Downloading the latest stable official UPX...'
    $release = Invoke-Retry { Invoke-RestMethod -Uri 'https://api.github.com/repos/upx/upx/releases/latest' -Headers $headers -TimeoutSec 60 }
    if ($release.draft -or $release.prerelease) { throw 'UPX release must be stable.' }
    $assets = @($release.assets | Where-Object { $_.name -match '^upx-[0-9]+\.[0-9]+\.[0-9]+-win64\.zip$' })
    if ($assets.Count -ne 1) { throw 'Could not identify the official Windows x64 UPX archive.' }
    $asset = $assets[0]
    if ($asset.digest -notmatch '^sha256:([0-9a-f]{64})$') { throw 'UPX archive has no SHA256 digest.' }
    $digest = $Matches[1]
    if ($asset.browser_download_url -notmatch '^https://github\.com/upx/upx/releases/download/') { throw 'Unexpected UPX download URL.' }
    $download = Join-Path $work 'upx.zip'
    Download $asset.browser_download_url $download
    if ((Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash.ToLower() -ne $digest) { throw 'UPX archive checksum mismatch.' }
    [IO.Compression.ZipFile]::ExtractToDirectory($download, (Join-Path $work 'tool'))
    $tools = @(Get-ChildItem -LiteralPath (Join-Path $work 'tool') -Filter 'upx.exe' -File -Recurse)
    if ($tools.Count -ne 1) { throw 'UPX executable missing or ambiguous.' }
    $upx = $tools[0].FullName
    $payload = Join-Path $work 'bin'
    Copy-Item -LiteralPath $original -Destination $payload -Recurse
    Test-DistributionManifest $payload $info
    Write-Host 'Packing compiler EXEs and DLLs with --lzma --best...'
    $binaries = @(Get-ChildItem -LiteralPath $payload -File -Recurse | Where-Object { $_.Extension -in @('.exe', '.dll') })
    if ($binaries.Count -eq 0) { throw 'No compiler binaries to pack.' }
    foreach ($file in $binaries) {
        Native $upx @('--lzma', '--best', $file.FullName)
        Native $upx @('-t', $file.FullName)
    }
    $info | Add-Member -NotePropertyName packaging -NotePropertyValue ([ordered]@{
        tool = 'UPX'; version = $release.tag_name; flags = @('--lzma', '--best')
        source = $asset.browser_download_url; archiveSha256 = $digest
    }) -Force
    $info.files = @(Get-ChildItem -LiteralPath $payload -File -Recurse | Where-Object { $_.FullName -ne (Join-Path $payload 'build-info.json') } | ForEach-Object {
        @{ path = $_.FullName.Substring($payload.Length + 1).Replace('\', '/'); sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLower() }
    })
    $info | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $payload 'build-info.json') -Encoding UTF8

    Write-Host 'Checking the packed compilers and libtcc...'
    if ($info.obfusCommit -notmatch '^[0-9a-f]{40}$') { throw 'Invalid obfus.h test revision.' }
    $testInclude = Join-Path $work 'protected-include'
    New-Item -ItemType Directory -Path $testInclude | Out-Null
    Download "https://raw.githubusercontent.com/DosX-dev/obfus.h/$($info.obfusCommit)/include/obfus.h" (Join-Path $testInclude 'obfus.h')
    foreach ($compiler in @('tcc.exe', 'i386-win32-tcc.exe')) {
        $exe = Join-Path $work ($compiler + '-smoke.exe')
        Native (Join-Path $payload $compiler) @('-w', (Join-Path $root 'tests/smoke.c'), '-o', $exe, '-luser32', '-lws2_32', '-ladvapi32')
        Native $exe @() 60
        $protectedExe = Join-Path $work ($compiler + '-protected.exe')
        $protectedDll = Join-Path $work ($compiler + '-protected.dll')
        Native (Join-Path $payload $compiler) @('-w', '-I', $testInclude, '-shared', '-DOBFH_TEST_DLL=1', (Join-Path $root 'tests/protected.c'), '-o', $protectedDll)
        Native (Join-Path $payload $compiler) @('-w', '-I', $testInclude, (Join-Path $root 'tests/protected.c'), '-o', $protectedExe)
        Native $protectedExe @($protectedDll) 60
    }
    Native (Join-Path $payload 'tcc.exe') @('-I', (Join-Path $payload 'libtcc'), (Join-Path $payload 'libtcc/libtcc.def'), '-run', (Join-Path $payload 'examples/libtcc_test.c'))
    Native (Join-Path $payload 'arm64-win32-tcc.exe') @('-w', (Join-Path $root 'tests/smoke.c'), '-o', (Join-Path $work 'arm64-smoke.exe'), '-luser32', '-lws2_32', '-ladvapi32')

    $date = [DateTimeOffset]::Parse($info.builtUtc).UtcDateTime.ToString('yyyy-MM-dd')
    $name = "tinycc-windows-upx-$date.zip"
    $staged = Join-Path $work $name
    [IO.Compression.ZipFile]::CreateFromDirectory($payload, $staged, [IO.Compression.CompressionLevel]::Optimal, $false)
    $archive = [IO.Compression.ZipFile]::OpenRead($staged)
    try {
        if ($archive.Entries | Where-Object { $_.FullName.Replace('\', '/') -ieq 'include/obfus.h' }) { throw 'Test-only header must not be bundled.' }
        foreach ($required in @('tcc.exe', 'i386-win32-tcc.exe', 'arm64-win32-tcc.exe', 'libtcc.dll', 'obfh-update.cmd', 'build-info.json')) {
            if (-not ($archive.Entries | Where-Object { $_.FullName -eq $required -and $_.Length -gt 0 })) { throw "Packed archive is missing $required" }
        }
    } finally { $archive.Dispose() }
    $hash = (Get-FileHash -LiteralPath $staged -Algorithm SHA256).Hash.ToLower()
    "$hash  $name" | Set-Content -LiteralPath ($staged + '.sha256') -Encoding ASCII
    # The original bin and ZIP are never modified by this step.
    Publish-ArchivePair $root $work $staged $name
    Write-Host "UPX_DISTRIBUTION_PASS: $name"
} catch {
    Write-Error $_ -ErrorAction Continue
    Write-Host "UPX packaging failed; diagnostic files: $work"
    exit 1
} finally { if ($buildLock) { $buildLock.Dispose() } }
