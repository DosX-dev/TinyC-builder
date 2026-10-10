$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.IO.Compression.FileSystem
$root = $PSScriptRoot
$work = Join-Path $root ('.work/' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null
$headers = @{ 'User-Agent' = 'TinyC-builder' }
if ($env:GITHUB_TOKEN) { $headers.Authorization = 'Bearer ' + $env:GITHUB_TOKEN }

function Download($url, $destination, $sha = '') {
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $destination -TimeoutSec 120
            if ($sha -and (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $sha) {
                throw "Checksum mismatch: $url"
            }
            return
        } catch { if ($attempt -eq 3) { throw }; Start-Sleep -Seconds 2 }
    }
}
function Native($program, $arguments) {
    & $program @arguments
    if ($LASTEXITCODE -ne 0) { throw "$program failed ($LASTEXITCODE)" }
}
function Extract($archive, $directory) {
    [IO.Compression.ZipFile]::ExtractToDirectory($archive, $directory)
}
function Api($url) { Invoke-RestMethod -Uri $url -Headers $headers -TimeoutSec 60 }

try {
    if (-not [Environment]::Is64BitOperatingSystem) { throw '64-bit Windows is required.' }
    Write-Host '[1/7] Downloading the latest official TinyCC source...'
    $revision = (Api 'https://api.github.com/repos/TinyCC/tinycc/commits/mob').sha
    if ($revision -notmatch '^[0-9a-f]{40}$') { throw 'Invalid upstream revision.' }
    Download "https://codeload.github.com/TinyCC/tinycc/zip/$revision" (Join-Path $work 'source.zip')
    Extract (Join-Path $work 'source.zip') (Join-Path $work 'source')
    $source = Join-Path $work "source/tinycc-$revision"
    $win32 = Join-Path $source 'win32'
    # ZIP sources have no .git directory. Do not pick up an unrelated parent repository.
    $batch = Join-Path $win32 'build-tcc.bat'
    $batchText = [IO.File]::ReadAllText($batch)
    $batchText = [regex]::Replace($batchText, '(?sm)^:git_hash\r?\n.*?(?=^:git_done)', ":git_hash`r`nset GITHASH=mob@$($revision.Substring(0, 12))`r`n")
    [IO.File]::WriteAllText($batch, $batchText, [Text.Encoding]::ASCII)

    Write-Host '[2/7] Downloading the bootstrap compiler and full Windows headers...'
    Download 'https://download.savannah.gnu.org/releases/tinycc/tcc-0.9.27-win64-bin.zip' (Join-Path $work 'bootstrap.zip') '34A721949A2583FDFF725312DA092FA0F5F1F284B702E6F811C6954714FAABB2'
    Download 'https://download.savannah.gnu.org/releases/tinycc/winapi-full-for-0.9.27.zip' (Join-Path $work 'headers.zip') '8915D4EA9E7E3252A0E54A15E754EC524C4C39746948D5F39FAD10C23FAA31AA'
    Extract (Join-Path $work 'bootstrap.zip') (Join-Path $work 'bootstrap')
    Extract (Join-Path $work 'headers.zip') (Join-Path $work 'headers')
    $bootstrap = Join-Path $work 'bootstrap/tcc'
    $savedPath = $env:PATH
    $env:PATH = "$bootstrap;$savedPath"
    Push-Location $win32
    try {
        Write-Host '[3/7] Bootstrapping x64, then rebuilding with the new compiler...'
        Native $env:ComSpec @('/d', '/c', 'build-tcc.bat -c "tcc -w -Llib" -t x86_64')
        # Rebuild using a copy: Windows keeps running executables and DLLs locked.
        $self = Join-Path $work 'self'
        New-Item -ItemType Directory -Path $self | Out-Null
        Copy-Item -LiteralPath 'tcc.exe', 'libtcc.dll' -Destination $self
        $env:PATH = "$self;$savedPath"
        Native $env:ComSpec @('/d', '/c', 'build-tcc.bat -c "..\..\..\self\tcc -w -B." -t x86_64')
        Write-Host '[4/7] Building x86 and ARM64 compilers and runtime libraries...'
        Native $env:ComSpec @('/d', '/c', 'build-tcc.bat -c ".\tcc -w -B." -x i386')
        Native $env:ComSpec @('/d', '/c', 'build-tcc.bat -c ".\tcc -w -B." -x arm64')
    } finally { Pop-Location; $env:PATH = $savedPath }

    Write-Host '[5/7] Assembling the complete portable distribution...'
    $payload = Join-Path $work 'bin'
    New-Item -ItemType Directory -Path $payload | Out-Null
    foreach ($name in @('tcc.exe', 'libtcc.dll', 'i386-win32-tcc.exe', 'arm64-win32-tcc.exe', 'include', 'lib', 'libtcc', 'doc', 'examples')) {
        Copy-Item -LiteralPath (Join-Path $win32 $name) -Destination $payload -Recurse
    }
    $full = (Get-ChildItem -LiteralPath (Join-Path $work 'headers') -Directory -Recurse | Where-Object { $_.Name -eq 'include' } | Select-Object -First 1).FullName
    if (-not $full) { throw 'The full Windows headers archive has no include directory.' }
    # Preserve current upstream headers; supplement only files upstream does not ship.
    foreach ($file in Get-ChildItem -LiteralPath $full -File -Recurse) {
        $relative = $file.FullName.Substring($full.Length + 1)
        $target = Join-Path (Join-Path $payload 'include') $relative
        if (-not (Test-Path -LiteralPath $target)) {
            New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null
            Copy-Item -LiteralPath $file.FullName -Destination $target
        }
    }
    # Upstream's Windows guide explicitly recommends these enhanced replacements.
    # Its newer winsock2.h must remain intact.
    foreach ($relative in @('unistd.h', 'winapi/qos.h', 'winapi/winnls.h', 'winapi/ws2ipdef.h', 'winapi/ws2tcpip.h', 'winapi/windows.h')) {
        Copy-Item -LiteralPath (Join-Path $full $relative) -Destination (Join-Path (Join-Path $payload 'include') $relative)
    }
    # A header alone cannot link an API. Obtain complete import definitions from
    # the host's system DLLs; never copy Microsoft DLL binaries into the bundle.
    foreach ($dll in @('kernel32', 'user32', 'gdi32', 'advapi32', 'shell32', 'shlwapi', 'ole32', 'oleaut32', 'comdlg32', 'comctl32', 'rpcrt4', 'crypt32', 'winmm', 'version', 'wininet', 'winhttp', 'wtsapi32', 'ntdll', 'msimg32', 'psapi', 'ws2_32', 'iphlpapi', 'setupapi', 'cfgmgr32', 'dwmapi', 'uxtheme', 'imm32', 'bcrypt', 'ncrypt', 'secur32', 'dnsapi', 'netapi32', 'mpr', 'winspool.drv', 'd3d9', 'd3d10', 'd3d11', 'dxgi', 'urlmon', 'wintrust')) {
        $filename = if ($dll.EndsWith('.drv')) { $dll } else { $dll + '.dll' }
        $systemDll = Join-Path $env:windir ('System32/' + $filename)
        if (-not (Test-Path -LiteralPath $systemDll)) { throw "Required Windows system library missing: $filename" }
        $libraryName = $dll.Replace('.drv', '')
        Native (Join-Path $payload 'tcc.exe') @('-impdef', $systemDll, '-o', (Join-Path $payload ('lib/' + $libraryName + '.def')))
    }
    Copy-Item -LiteralPath (Join-Path $source 'COPYING') -Destination (Join-Path $payload 'COPYING.TinyCC')
    Copy-Item -LiteralPath (Join-Path $source 'tcc-doc.texi') -Destination (Join-Path $payload 'doc')
    Copy-Item -LiteralPath (Join-Path $bootstrap 'doc/tcc-doc.html') -Destination (Join-Path $payload 'doc/bootstrap-0.9.27-manual.html')
    New-Item -ItemType Directory -Path (Join-Path $payload 'source') | Out-Null
    Copy-Item -LiteralPath (Join-Path $work 'source.zip') -Destination (Join-Path $payload 'source/tinycc.zip')
    Copy-Item -LiteralPath (Join-Path $work 'headers.zip') -Destination (Join-Path $payload 'source/windows-headers.zip')
    $obfhRevision = (Api 'https://api.github.com/repos/DosX-dev/obfus.h/commits/main').sha
    Download "https://raw.githubusercontent.com/DosX-dev/obfus.h/$obfhRevision/include-updater/obfh-update.cmd" (Join-Path $payload 'obfh-update.cmd')
    Download "https://raw.githubusercontent.com/DosX-dev/obfus.h/$obfhRevision/include/obfus.h" (Join-Path $payload 'include/obfus.h')
    Copy-Item -LiteralPath (Join-Path $root 'tests/smoke.c') -Destination (Join-Path $work 'smoke.c')

    Write-Host '[6/7] Checking compilers, headers, DLL linkage and runtime...'
    foreach ($compiler in @('tcc.exe', 'i386-win32-tcc.exe')) {
        $exe = Join-Path $work ($compiler + '-smoke.exe')
        Native (Join-Path $payload $compiler) @('-w', (Join-Path $work 'smoke.c'), '-o', $exe, '-luser32', '-lws2_32', '-ladvapi32')
        Native $exe @()
        Native (Join-Path $payload $compiler) @('-shared', (Join-Path $root 'tests/library.c'), '-o', (Join-Path $work ($compiler + '-library.dll')))
    }
    Native (Join-Path $payload 'tcc.exe') @('-I', (Join-Path $payload 'libtcc'), (Join-Path $payload 'libtcc/libtcc.def'), '-run', (Join-Path $payload 'examples/libtcc_test.c'))
    Native (Join-Path $payload 'arm64-win32-tcc.exe') @('-w', (Join-Path $work 'smoke.c'), '-o', (Join-Path $work 'arm64-smoke.exe'), '-luser32', '-lws2_32', '-ladvapi32')
    $manifest = [ordered]@{
        upstream = 'https://github.com/TinyCC/tinycc'; branch = 'mob'; commit = $revision
        version = (Get-Content -LiteralPath (Join-Path $source 'VERSION') -Raw).Trim()
        builtUtc = [DateTime]::UtcNow.ToString('o'); obfusCommit = $obfhRevision
        importDefinitionsHost = [Environment]::OSVersion.VersionString
        runtimeTested = @('x86_64', 'i386'); compileTested = @('arm64')
        files = @(Get-ChildItem -LiteralPath $payload -File -Recurse | ForEach-Object {
            @{ path = $_.FullName.Substring($payload.Length + 1).Replace('\', '/'); sha256 = (Get-FileHash -LiteralPath $_.FullName).Hash.ToLower() }
        })
    }
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $payload 'build-info.json') -Encoding UTF8
    Write-Host '[7/7] Publishing local bin and release ZIP...'
    $destination = Join-Path $root 'bin'
    if (Test-Path -LiteralPath $destination) { Move-Item -LiteralPath $destination -Destination (Join-Path $work 'previous-bin') }
    Move-Item -LiteralPath $payload -Destination $destination
    $dist = Join-Path $root 'dist'
    New-Item -ItemType Directory -Force -Path $dist | Out-Null
    $zip = Join-Path $dist ('tinycc-windows-' + [DateTime]::UtcNow.ToString('yyyy-MM-dd') + '.zip')
    if (Test-Path -LiteralPath $zip) { Move-Item -LiteralPath $zip -Destination (Join-Path $work 'previous-release.zip') }
    [IO.Compression.ZipFile]::CreateFromDirectory($destination, $zip, [IO.Compression.CompressionLevel]::Optimal, $false)
    (Get-FileHash -LiteralPath $zip).Hash.ToLower() + '  ' + (Split-Path $zip -Leaf) | Set-Content -LiteralPath ($zip + '.sha256') -Encoding ASCII
    Write-Host "Ready: $destination"
    Write-Host "Archive: $zip"
} catch {
    Write-Error $_ -ErrorAction Continue
    Write-Host "Build failed. Existing bin was preserved. Diagnostic files: $work"
    exit 1
}
