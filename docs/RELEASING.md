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

The scripts select the repository root, clear generated Flutter build caches,
enable the matching Flutter desktop target, install Dart packages, and call
the release build. Clearing the cache keeps a changed Dart source file or
Flutter SDK from being misreported by an incremental `flutter_assemble`
project, which is particularly useful after updating a Windows checkout. The
Linux and macOS scripts require Bash; the Windows `.bat` and `.ps1` wrappers
are provided for native Windows use.

The helper prints the output locations after a successful build:

- Linux: `build/linux/x64/release/bundle/`
- macOS: `build/macos/Build/Products/Release/gift.app`
- Windows release bundle: `build/windows/x64/runner/Release/`
- Windows portable EXE: `build/windows/x64/runner/gift-portable.exe`
- Windows installer EXE: `build/windows/x64/runner/gift-setup.exe`

The portable Windows executable is a self-extracting wrapper around the
complete Flutter release bundle. It expands the bundle into a temporary
directory, runs `gift.exe`, waits for it to close, and removes the temporary
files. It behaves as one file for copying and launching, but it still requires
Git to be installed separately because the app uses the system Git executable.

The Windows installer is an interactive per-user setup wizard. It lets the
user choose the install directory and whether to create Start Menu and
Desktop shortcuts, then installs gift under `%LOCALAPPDATA%\Programs\gift`,
adds a Start Menu uninstall shortcut, and registers an uninstaller under the
current user's Windows uninstall entries. The executable enters through the
bundled VBScript/Windows Script Host launcher by default; PowerShell only
renders the hidden implementation of the WinForms wizard. The portable
executable only runs from a temporary extraction directory and does not
install files, create shortcuts, or show an install wizard. Neither package
requires administrator access. Git remains a separate system dependency.
The desktop identity is kept in the checked-in release assets. The canonical
pixel mascot is `assets/images/gift_icon.png`; Windows uses the derived
multi-size `windows/runner/resources/app_icon.ico`, and macOS uses the
matching PNG sizes in `macos/Runner/Assets.xcassets/AppIcon.appiconset/`.
The README wordmark is `assets/images/gift_logo.png` and shares the same
mascot source.

## Continuous integration

`.github/workflows/ci.yml` runs verification on Ubuntu, macOS, and Windows.
The workflow starts automatically only for a `release-*` tag. The tagged
commit must have a subject such as
`release(v1.0.0): publish desktop artifacts`; otherwise verification fails.
The tag version must also match the `major.minor.patch` part of `pubspec.yaml`.
For example:

```bash
git commit -m "release(v1.0.0): publish desktop artifacts"
git tag release-v1.0.0
git push origin main release-v1.0.0
```

Ordinary branch pushes create no workflow run. Use manual dispatch when a
maintainer needs a deliberate build/check rerun without publishing a release.
After all three checks pass, it builds and validates one release bundle per
platform. The release packages are:

- `gift-<version>-linux-x64.tar.gz`
- `gift-<version>-macos-<x64|arm64>.zip`
- `gift-<version>-windows-x64.zip`

The Windows archive contains the Flutter `Release` directory plus the portable
and setup executables. Public release packaging requires no signing secrets.
Windows executables are intentionally unsigned; SHA-256 checksums and GitHub's
OIDC-backed build provenance provide the release integrity evidence.

The macOS app is signed with an ad hoc identity (`codesign --sign -`) on the
native runner. This requires no Apple certificate or notarization account, but
it does not establish an Apple developer identity or provide notarization.

The release job publishes these verification files beside the packages:

- `SHA256SUMS.txt` — SHA-256 checksums for each installable archive.
- `release-metadata.json` — version, tag, commit, asset names, sizes, hashes,
  and release download URLs for opt-in update clients.
- `sbom.cdx.json` — CycloneDX 1.5 dependency inventory.
- `dependency-audit.json` — resolved dependency graph and discovered license
  files; missing hosted-package licenses fail the public release job.

Linux and macOS jobs capture their runner-specific visual goldens as separate
review artifacts; the reviewed Windows goldens live under
`test/app/goldens/windows/`.

### Trust verification

Download an archive and its checksum file from the same GitHub release, then
run:

```bash
sha256sum -c SHA256SUMS.txt
gh attestation verify gift-1.0.0-linux-x64.tar.gz \
  --repo <owner>/<repository>
```

On macOS, ad hoc signing verifies bundle integrity but does not provide an
Apple developer identity or notarization; a downloaded app may require the
user to approve its first launch. On Windows, the executables are unsigned and
may trigger SmartScreen or an equivalent download warning. Checksums and the
GitHub attestation are the release trust signals. The release metadata is
informational and opt-in; GIFT does not silently download updates, send
telemetry, or collect crash data.

Before a public release, a maintainer must still perform a clean-machine pass
for install, launch, upgrade, downgrade warning, uninstall, and Git-missing
first-run diagnostics on all three platforms.

The Flutter version is pinned in the workflow and in
[`tool/versions.json`](../tool/versions.json), which keeps local and CI
failures easier to reproduce.
