<p align="center">
  <img src="assets/readme-banner.png" alt="TinyCC-builder — Build the latest TinyCC compiler" width="680">
</p>

# [Download latest version of TinyC Compiler for Windows](https://github.com/DosX-dev/TinyCC-builder/releases/latest)

One click. A complete, current TinyCC toolchain for Windows.

Releases offer two ZIPs: **standard** and **UPX**. The UPX version has smaller
compiler EXEs and DLLs, packed with `--lzma --best`; both include the complete
kit. Programs you compile are not automatically packed.

## Why TinyCC?

TinyCC is a small, fast C compiler with its own assembler and linker. It is useful
for quick experiments, command-line tools and native Windows applications without
installing a large development environment.

-   **Compile and run immediately:** `tcc -run hello.c` runs C code directly, without creating an EXE.
-   **Create native binaries:** build standalone EXEs or DLLs with `-shared`.
-   **Choose your target:** `tcc.exe` builds x64 programs, `i386-win32-tcc.exe` builds x86, and `arm64-win32-tcc.exe` targets ARM64.
-   **Embed the compiler:** `libtcc.dll` lets applications compile and run C code in memory.
-   **Skip CRT startup:** on Windows, use `void _start(void)` instead of `main` for a direct entry point without the usual C runtime initialization; terminate with `ExitProcess` or `exit`.

For a first try, save this as `hello.c` next to `tcc.exe`:

```c
#include <stdio.h>

int main(void) {
    puts("Hello from TinyCC!");
    return 0;
}
```

Open a terminal in that directory and run:

```bat
tcc -run hello.c
```

To keep an executable instead, use `tcc hello.c -o hello.exe`.

> [!TIP]
> Put a ⭐️ on this repository to keep the latest TinyCC builds within easy reach!

## What's included?

The resulting portable directory contains:

-   `tcc.exe`, `i386-win32-tcc.exe`, and `arm64-win32-tcc.exe`.
-   `libtcc.dll`, its development headers, and runtime libraries for all three targets.
-   Current TinyCC headers plus the extended Windows API headers recommended upstream.
-   Complete import definitions for common Windows system libraries.
-   Documentation, examples, licenses, upstream source archives, and SHA256 build metadata.
-   `obfh-update.cmd`, downloaded directly from the obfus.h repository, beside `tcc.exe`.

### Optional: obfh-update.cmd

`obfh-update.cmd` downloads the latest header from [obfus.h](https://github.com/DosX-dev/obfus.h),
a library for protecting C programs with polymorphic obfuscation, into your current
project directory. Run it manually or call it before compilation in your build
pipeline. The header is not bundled with the compiler. If you do not need it,
simply delete the script; TinyCC works independently of it.

Pass an existing directory's relative or absolute path to save `obfus.h` there:

```bat
call "C:\TinyCC\obfh-update.cmd" "include"
:: or
call "C:\TinyCC\obfh-update.cmd" "C:\My project\include"
```

## Builds and updates

Download this repository as a ZIP, extract it, and double-click **`build.cmd`**.
The script downloads the compiler sources and bootstrap compiler automatically,
builds the distribution, checks it, and puts everything in **`bin`**.
No Git, GCC, Visual Studio, PATH changes, or manual configuration are required.
No API keys or tokens need to be entered. GitHub Actions uses its automatically
provided repository token; local builds use public download URLs.
Requirements: 64-bit Windows 10/11, its built-in PowerShell, and internet access.

Or [build on GitHub](https://github.com/DosX-dev/TinyCC-builder/actions/workflows/build.yml) using **Run workflow**.

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
EXEs and DLLs are built and run on x86 and x64; libtcc execution is checked too.
Actions also downloads the latest stable [UPX](https://github.com/upx/upx),
verifies its archive SHA256, and creates `tinycc-windows-upx-DATE.zip` with its own
checksum. The packed compilers repeat the build and runtime checks before
publication; the UPX version and file hashes are recorded in `build-info.json`.
Local `build.cmd` builds only the standard distribution and does not download UPX.
ARM64 is compile-tested on the x64 runner, not runtime-tested.
These checks do not certify every Windows API or application.

GitHub Actions automatically rebuilds and publishes after seven days since the
last release. A daily scheduled check enforces the interval; the actual release
date depends on GitHub Actions' mood. Repository maintainers can also select **Run workflow** to publish
immediately. Failed builds do not produce releases. The three latest published
releases are kept; older releases are removed only after a successful publication.
Same-day rebuilds get a separate release tag; published downloads are not overwritten.

Builder scripts are MIT licensed. TinyCC and the bundled header packages retain
their own licenses, included with the distribution.
