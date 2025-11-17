# Troubleshooting Guide

## 1. `stdbool.h` error (Linux)

If you run into this error:

```
  thread 'main' (36931) panicked at /home/ubuntu/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/codspeed-4.0.4/build.rs:39:10:
  Unable to generate bindings: ClangDiagnostic("instrument-hooks/includes/core.h:7:10: fatal error: 'stdbool.h' file not found\n")
  note: run with `RUST_BACKTRACE=1` environment variable to display a backtrace
```

**Root cause:**

Your build environment is missing a working C toolchain with standard library headers. `codspeed` uses `bindgen`, which calls `clang` → and clang can’t find the system headers.

** Solution:**

On Ubuntu/Debian:

Install Clang and the libc development headers:

```bash
sudo apt update
sudo apt install llvm clang libc6-dev build-essential
```

If you already have them, clang may be missing its default search path. Verify:

```bash
clang -E -x c - -v </dev/null
```

Look under `#include <...> search starts here:` — if `/usr/include` isn’t listed, something’s wrong with your clang install.

## 2. `link.exe` not found (Windows)

You need to install Visual Studio (not Visual Studio Code) on your Windows 
computer. Download the installer from Microsoft website.

During installation, choose "Desktop development with C++".
