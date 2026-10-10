$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$root = Split-Path $PSScriptRoot
. (Join-Path $root 'scripts/build-support.ps1')
$testRoot = Join-Path $root ('.work/builder-tests-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
function Assert($value, $message) { if (-not $value) { throw $message } }
function Fixture($name) {
    $dir = Join-Path $testRoot $name
    $work = Join-Path $dir '.work'
    $payload = Join-Path $work 'payload'
    New-Item -ItemType Directory -Path $payload -Force | Out-Null
    foreach ($file in @('tcc.exe', 'i386-win32-tcc.exe', 'arm64-win32-tcc.exe', 'libtcc.dll', 'obfh-update.cmd', 'build-info.json')) {
        $path = Join-Path $payload $file
        New-Item -ItemType Directory -Path (Split-Path $path) -Force | Out-Null
        'new' | Set-Content -LiteralPath $path
    }
    New-Item -ItemType Directory -Path (Join-Path $dir 'bin'), (Join-Path $dir 'dist') | Out-Null
    'old bin' | Set-Content (Join-Path $dir 'bin/old.txt')
    'old zip' | Set-Content (Join-Path $dir 'dist/tinycc-windows-2026-10-10.zip')
    'old checksum' | Set-Content (Join-Path $dir 'dist/tinycc-windows-2026-10-10.zip.sha256')
    return @($dir, $work, $payload, 'tinycc-windows-2026-10-10.zip')
}
$fixture = Fixture 'success'
Publish-Local @fixture
Assert (Test-Path (Join-Path $fixture[0] 'bin/tcc.exe')) 'New bin missing.'
Assert ((Get-Content (Join-Path $fixture[1] 'previous-bin/old.txt')) -eq 'old bin') 'Previous bin not retained.'
$zip = Join-Path $fixture[0] ('dist/' + $fixture[3])
Assert ((Get-Content ($zip + '.sha256')).StartsWith((Get-FileHash $zip).Hash.ToLower())) 'Archive checksum incorrect.'

$fixture = Fixture 'rollback'
$lockedPath = Join-Path $fixture[0] ('dist/' + $fixture[3] + '.sha256')
$lock = [IO.File]::Open($lockedPath, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
$failed = $false
try { Publish-Local @fixture } catch { $failed = $true } finally { $lock.Dispose() }
Assert $failed 'Locked output should fail publication.'
Assert ((Get-Content (Join-Path $fixture[0] 'bin/old.txt')) -eq 'old bin') 'Old bin not restored.'
Assert ((Get-Content (Join-Path $fixture[0] ('dist/' + $fixture[3]))) -eq 'old zip') 'Old ZIP not restored.'
Assert ((Get-Content $lockedPath) -eq 'old checksum') 'Old checksum changed.'

$fixture = Fixture 'incomplete'
[IO.File]::WriteAllText((Join-Path $fixture[2] 'tcc.exe'), '')
$failed = $false
try { Publish-Local @fixture } catch { $failed = $true }
Assert $failed 'Incomplete archive should be rejected.'
Assert (Test-Path (Join-Path $fixture[0] 'bin/old.txt')) 'Validation touched existing output.'

$fixture = Fixture 'unwanted-header'
New-Item -ItemType Directory -Path (Join-Path $fixture[2] 'include') | Out-Null
'test-only header' | Set-Content (Join-Path $fixture[2] 'include/obfus.h')
$failed = $false
try { Publish-Local @fixture } catch { $failed = $true }
Assert $failed 'Test-only obfus.h must not be distributed.'
Assert (Test-Path (Join-Path $fixture[0] 'bin/old.txt')) 'Rejected header touched existing output.'

# Exercise the native argv path in a directory with spaces.
$source = Join-Path $testRoot 'argument check.c'
@'
#include <string.h>
int main(int argc, char **argv) {
    return argc != 5 || strcmp(argv[1], "with space") || strcmp(argv[2], "quote\"")
        || strcmp(argv[3], "ends\\") || strcmp(argv[4], "a&b");
}
'@ | Set-Content -LiteralPath $source -Encoding ASCII
Native (Join-Path $root 'bin/tcc.exe') @('-run', $source, 'with space', 'quote"', 'ends\', 'a&b')

$script = Join-Path $testRoot 'hang.ps1'
'Start-Sleep -Seconds 30' | Set-Content $script
$failed = $false
$timer = [Diagnostics.Stopwatch]::StartNew()
try { Native "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" @('-NoProfile', '-File', $script) 1 }
catch { $failed = $_.Exception.Message -like '*timed out*' }
Assert ($failed -and $timer.Elapsed.TotalSeconds -lt 10) 'Native watchdog failed.'
Write-Host 'BUILDER_RELIABILITY_PASS: publication, rollback, archive contents, argv and timeout.'
