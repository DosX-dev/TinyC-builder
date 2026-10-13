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

$fixture = Fixture 'packed-rollback'
$name = 'tinycc-windows-upx-2026-10-10.zip'
$staged = Join-Path $fixture[1] $name
'new packed ZIP' | Set-Content -LiteralPath $staged
((Get-FileHash $staged).Hash.ToLower() + '  ' + $name) | Set-Content -LiteralPath ($staged + '.sha256')
$published = Join-Path $fixture[0] ('dist/' + $name)
'old packed ZIP' | Set-Content -LiteralPath $published
'old packed checksum' | Set-Content -LiteralPath ($published + '.sha256')
$lock = [IO.File]::Open(($published + '.sha256'), [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
$failed = $false
try { Publish-ArchivePair $fixture[0] $fixture[1] $staged $name } catch { $failed = $true } finally { $lock.Dispose() }
Assert $failed 'Locked packed checksum should fail publication.'
Assert ((Get-Content $published) -eq 'old packed ZIP') 'Old packed ZIP not restored.'
Assert ((Get-Content ($published + '.sha256')) -eq 'old packed checksum') 'Old packed checksum changed.'
Publish-ArchivePair $fixture[0] $fixture[1] $staged $name
Assert ((Get-Content $published) -eq 'new packed ZIP') 'New packed ZIP missing.'
Assert ((Get-Content ($published + '.sha256')).StartsWith((Get-FileHash $published).Hash.ToLower())) 'Packed checksum incorrect.'

$fixture = Fixture 'manifest'
$manifest = @{ files = @(Get-ChildItem -LiteralPath $fixture[2] -File | Where-Object { $_.Name -ne 'build-info.json' } | ForEach-Object {
    @{ path = $_.Name; sha256 = (Get-FileHash -LiteralPath $_.FullName).Hash.ToLower() }
}) }
Test-DistributionManifest $fixture[2] $manifest
'unlisted' | Set-Content -LiteralPath (Join-Path $fixture[2] 'extra.dll')
$failed = $false
try { Test-DistributionManifest $fixture[2] $manifest } catch { $failed = $true }
Assert $failed 'Unlisted distribution files should be rejected.'
$manifest.files += @{ path = 'extra.dll'; sha256 = (Get-FileHash (Join-Path $fixture[2] 'extra.dll')).Hash.ToLower() }
Test-DistributionManifest $fixture[2] $manifest
'changed' | Set-Content -LiteralPath (Join-Path $fixture[2] 'extra.dll')
$failed = $false
try { Test-DistributionManifest $fixture[2] $manifest } catch { $failed = $true }
Assert $failed 'Modified distribution files should be rejected.'
$failed = $false
try { Test-DistributionManifest $fixture[2] @{ files = @() } } catch { $failed = $true }
Assert $failed 'Empty manifest should be rejected.'
$failed = $false
try { Test-DistributionManifest $fixture[2] @{ files = @($manifest.files[0], $manifest.files[0]) } } catch { $failed = $true }
Assert $failed 'Duplicate manifest paths should be rejected.'

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

# Execute the actual Actions publication script with a fake gh command.
# No requests or releases are made by this test.
$workflow = Get-Content -LiteralPath (Join-Path $root '.github/workflows/build.yml') -Raw
$releaseCode = [regex]::Match($workflow, '(?s)- name: Publish tested distribution.*?run: \|\r?\n(.*?)(?=            - name:)').Groups[1].Value
Assert ([bool]$releaseCode) 'Publication script missing.'
$releaseScript = [scriptblock]::Create([regex]::Replace($releaseCode, '(?m)^                  ', ''))
$fixture = Fixture 'release-script'
@{ builtUtc = '2026-10-10T12:00:00Z'; version = 'test' } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $fixture[0] 'bin/build-info.json')
foreach ($name in @('tinycc-windows-2026-10-10.zip', 'tinycc-windows-upx-2026-10-10.zip')) {
    $zip = Join-Path $fixture[0] ('dist/' + $name)
    'tested archive' | Set-Content -LiteralPath $zip
    ((Get-FileHash $zip).Hash.ToLower() + '  ' + $name) | Set-Content -LiteralPath ($zip + '.sha256')
}
function gh {
    $tokens = @($args)
    $script:ghCalls.Add($tokens)
    $global:LASTEXITCODE = 0
    if ($tokens[0] -eq 'api') {
        if ($script:releaseExists) { '{"draft":false}' }
        else { $global:LASTEXITCODE = 1; 'HTTP 404' }
    } elseif ($tokens[1] -eq 'create' -and $script:failUpload) {
        $global:LASTEXITCODE = 1
    }
}
$savedEnvironment = @{}
$savedNativeExitCode = $global:LASTEXITCODE
foreach ($name in @('GITHUB_REPOSITORY', 'GITHUB_RUN_ID', 'GITHUB_RUN_ATTEMPT', 'GITHUB_SHA')) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name)
}
try {
    $env:GITHUB_REPOSITORY = 'test/test'; $env:GITHUB_RUN_ID = '123'; $env:GITHUB_RUN_ATTEMPT = '2'; $env:GITHUB_SHA = 'abc123'
    Push-Location $fixture[0]
    try {
        foreach ($scenario in @('new', 'same-day', 'upload-failure')) {
            $script:releaseExists = $scenario -eq 'same-day'
            $script:failUpload = $scenario -eq 'upload-failure'
            $script:ghCalls = New-Object Collections.Generic.List[object]
            $failed = $false
            try { & $releaseScript } catch { $failed = $true }
            Assert ($failed -eq $script:failUpload) 'Unexpected publication result.'
            $create = @($script:ghCalls | Where-Object { $_[0] -eq 'release' -and $_[1] -eq 'create' })
            $edit = @($script:ghCalls | Where-Object { $_[0] -eq 'release' -and $_[1] -eq 'edit' })
            Assert ($create.Count -eq 1 -and $create[0] -contains '--draft' -and $create[0] -contains '--target' -and $create[0] -contains $env:GITHUB_SHA) 'Release must start as a draft at the tested commit.'
            $expectedTag = if ($script:releaseExists) { '2026-10-10-123-2' } else { '2026-10-10' }
            Assert ($create[0][2] -eq $expectedTag) 'Incorrect release tag.'
            Assert ($edit.Count -eq [int](-not $script:failUpload)) 'Failed uploads must remain unpublished.'
            Assert (-not ($script:ghCalls | Where-Object { $_ -contains '--clobber' })) 'Published assets must not be overwritten.'
        }
    } finally { Pop-Location }
} finally {
    foreach ($name in $savedEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name]) }
    Remove-Item Function:gh
    $global:LASTEXITCODE = $savedNativeExitCode
}
Write-Host 'BUILDER_RELIABILITY_PASS: publication, rollback, manifests, argv, timeout and release failures.'
