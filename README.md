# TinyCC-builder

# [Download latest version of TinyC Compiler for Windows](https://github.com/DosX-dev/TinyCC-builder/releases/latest)

**One click. A complete, current TinyCC toolchain for Windows.**

[Download a ready-made build](https://github.com/DosX-dev/TinyCC-builder/releases/latest) · [Build on GitHub](https://github.com/DosX-dev/TinyCC-builder/actions/workflows/build.yml)

Download this repository as a ZIP, extract it, and double-click **`build.cmd`**.
The script downloads the compiler sources and bootstrap compiler automatically,
builds the distribution, checks it, and puts everything in **`bin`**.
No Git, GCC, Visual Studio, PATH changes, or manual configuration are required.
No API keys or tokens need to be entered. GitHub Actions uses its automatically
provided repository token; local builds use public download URLs.
Requirements: 64-bit Windows 10/11, its built-in PowerShell, and internet access.

The resulting portable directory contains:

- `tcc.exe`, `i386-win32-tcc.exe`, and `arm64-win32-tcc.exe`.
- `libtcc.dll`, its development headers, and runtime libraries for all three targets.
- Current TinyCC headers plus the extended Windows API headers recommended upstream.
- Complete import definitions for common Windows system libraries.
- Documentation, examples, licenses, upstream source archives, and SHA256 build metadata.
- `obfh-update.cmd`, downloaded directly from the obfus.h repository, beside `tcc.exe`.

The build uses the latest `mob` snapshot from the [TinyCC mirror](https://github.com/TinyCC/tinycc).
The exact commit is recorded in `bin/build-info.json`. TinyCC development snapshots
are currently named **0.9.28rc**; they are not a final 0.9.28 release.
The [canonical upstream repository](https://repo.or.cz/w/tinycc.git) is maintained separately.

The bootstrap compiler is the upstream 0.9.27 Windows binary. It builds the current
compiler, which then rebuilds itself and the cross-compilers. Downloaded bootstrap
and extended-header archives have pinned SHA256 checksums. Current headers are
preserved except for the enhanced replacements explicitly recommended in
[TinyCC's Windows guide](https://github.com/TinyCC/tinycc/blob/mob/win32/tcc-win32.txt).
The supplementary archive is `winapi-full-for-0.9.27.zip`; it is not a current Windows SDK.
Import definitions are generated from the build machine's Windows system DLLs;
Microsoft DLLs are not redistributed.

The build preserves explicitly named PE sections with a small linker patch.
The original upstream source and the reproducible patch are included in the ZIP.

Every successful build produces a ZIP and SHA256 file in `dist`.
Existing output is kept in the build's `.work` directory before replacement.
x64/x86 programs run during validation; DLL builds and libtcc JIT are checked too.
ARM64 is compile-tested on the x64 runner, not runtime-tested.
GitHub releases also pass the full obfus.h test suite on x86 and x64.
These checks do not certify every Windows API or application.

GitHub Actions automatically rebuilds and publishes after five days since the
last release. A daily scheduled check enforces the interval; GitHub may delay
scheduled jobs. Repository maintainers can also select **Run workflow** to publish
immediately. Failed builds do not produce releases.

Builder scripts are MIT licensed. TinyCC and the bundled header packages retain
their own licenses, included with the distribution.
