# Local verification and desktop releases

This guide describes the commands used by the GitHub Actions workflow. They
are intentionally small so a first-time contributor can run the same checks
before opening a pull request.

## Verify a change

From the repository root, run:

```bash
dart run tool/verify.dart
```

The script installs Dart/Flutter packages, checks formatting for `lib/`,
`test/`, `integration_test/`, and `tool/`, runs the analyzer, and runs every
Flutter test. It invokes programs with argument lists, so it works from Bash,
PowerShell, and the supported desktop platforms.

If you only want an individual check, the equivalent commands are:

```bash
dart format --output=none --set-exit-if-changed lib test integration_test tool
flutter analyze
flutter test
```

## Build one desktop bundle

Build the target for the operating system you are currently using:

```bash
./tool/build_linux.sh
./tool/build_macos.sh
./tool/build_windows.sh
```

Use only the target that matches the host's Flutter desktop toolchain. Flutter
does not promise that a Linux host can produce a macOS or Windows desktop
bundle. Windows users can double-click `tool\\build_windows.bat` or run
`tool\\build_windows.ps1` from PowerShell.

The scripts select the repository root, enable the matching Flutter desktop
target, install Dart packages, and call the release build. The Linux and macOS
scripts require Bash; the Windows `.bat` and `.ps1` wrappers are provided for
native Windows use.

The helper prints the output location after a successful build:

- Linux: `build/linux/x64/release/bundle/`
- macOS: `build/macos/Build/Products/Release/gift.app`
- Windows: `build/windows/x64/runner/Release/`

## Continuous integration

`.github/workflows/ci.yml` runs verification on Ubuntu, macOS, and Windows.
The workflow starts automatically only for a `release-*` tag. The tagged
commit must have a subject such as
`release(v1.0.0): publish desktop artifacts`; otherwise verification fails.
For example:

```bash
git commit -m "release(v1.0.0): publish desktop artifacts"
git tag release-v1.0.0
git push origin main release-v1.0.0
```

Ordinary branch pushes create no workflow run. Use manual dispatch when a
maintainer needs a deliberate rerun.
After all three checks pass, it builds one release bundle per platform and
uploads the bundles as workflow artifacts. A tagged public release can attach
those artifacts after a maintainer has reviewed and signed them.

The Flutter version is pinned in the workflow and in
[`tool/versions.json`](../tool/versions.json), which keeps local and CI
failures easier to reproduce.
