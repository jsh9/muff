# Muff Release Scripts

Use one machine as the main machine, usually macOS. Run the builds on the
machines listed below, copy their outputs back to the main machine, then run the
release and publish scripts from there.

## 1. Run the step 1 builds

Run these from the repository root.

1. macOS Apple Silicon:

    ```sh
    release_scripts/step-1-build-macos.sh --sdist
    ```

1. Linux x86_64, on an x86_64 Linux machine:

    ```sh
    release_scripts/step-1-build-linux.sh
    ```

1. Linux ARM64, on an aarch64 Linux machine:

    ```sh
    release_scripts/step-1-build-linux.sh
    ```

1. Windows x86_64, in PowerShell:

    ```powershell
    powershell -ExecutionPolicy Bypass -File release_scripts/step-1-build-windows.ps1
    ```

## 2. Collect the outputs

After each step 1 script finishes, look in these two folders on that build
machine:

- `dist/`: Python package files for PyPI.
- `artifacts/`: standalone binary archives and their checksums.

Copy these files back to the main machine where you will run steps 2 and 3:

| Build machine  | Copy from the build machine                              | Put on the main machine |
| -------------- | -------------------------------------------------------- | ----------------------- |
| macOS          | `dist/*.whl`                                             | `dist/`                 |
| macOS          | `dist/muff-*.tar.gz`                                     | `dist/`                 |
| macOS          | `artifacts/muff-aarch64-apple-darwin.tar.gz`             | `artifacts/`            |
| macOS          | `artifacts/muff-aarch64-apple-darwin.tar.gz.sha256`      | `artifacts/`            |
| Linux x86_64   | `dist/*.whl`                                             | `dist/`                 |
| Linux x86_64   | `artifacts/muff-x86_64-unknown-linux-gnu.tar.gz`         | `artifacts/`            |
| Linux x86_64   | `artifacts/muff-x86_64-unknown-linux-gnu.tar.gz.sha256`  | `artifacts/`            |
| Linux ARM64    | `dist/*.whl`                                             | `dist/`                 |
| Linux ARM64    | `artifacts/muff-aarch64-unknown-linux-gnu.tar.gz`        | `artifacts/`            |
| Linux ARM64    | `artifacts/muff-aarch64-unknown-linux-gnu.tar.gz.sha256` | `artifacts/`            |
| Windows x86_64 | `dist/*.whl`                                             | `dist/`                 |
| Windows x86_64 | `artifacts/muff-x86_64-pc-windows-*.tar.gz`              | `artifacts/`            |
| Windows x86_64 | `artifacts/muff-x86_64-pc-windows-*.tar.gz.sha256`       | `artifacts/`            |

Only one source distribution is needed. The macOS command in step 1 creates
`dist/muff-*.tar.gz`; if another machine also creates the same file, leave that
duplicate behind.

The Windows script may create one or two binary archives, depending on the
available toolchains. Copy every matching
`artifacts/muff-x86_64-pc-windows-*.tar.gz` file and every matching `.sha256`
file.

Do not copy `target/`. The standalone binaries to publish are already packaged
inside the `artifacts/*.tar.gz` files.

Before continuing, the main machine should have:

- `dist/*.whl` from macOS, Linux x86_64, Linux ARM64, and Windows.
- one `dist/muff-*.tar.gz` source distribution.
- `artifacts/muff-*.tar.gz` for every standalone binary.
- `artifacts/muff-*.tar.gz.sha256` for every standalone binary.

## 3. Run the remaining scripts

Create the GitHub release from the main machine:

```sh
release_scripts/step-2-create-github-release.sh vX.Y.Z
```

Publish to PyPI from the main machine:

```sh
PYPI_API_TOKEN=<token> release_scripts/step-3-publish-to-pypi.sh
```

Step 2 uploads `artifacts/muff-*.tar.gz`,
`artifacts/muff-*.tar.gz.sha256`, `dist/*.whl`, and `dist/*.tar.gz`.
Step 3 publishes everything in `dist/`.
