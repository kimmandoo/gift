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
- Windows setup bundle: `build/windows/x64/runner/gift-setup.zip`

For macOS, the helper also stages the upload-ready desktop artifact at
`build/macos/Distribution/`; it contains `gift.app` and executable
`Run-Gift.command` side by side.

The portable Windows executable is a self-extracting wrapper around the
complete Flutter release bundle. It expands the bundle into a temporary
directory, runs `gift.exe`, waits for it to close, and removes the temporary
files. It behaves as one file for copying and launching, but it still requires
Git to be installed separately because the app uses the system Git executable.

The Windows setup bundle follows the same layout as the reference Spull
package. Extract `gift-setup.zip` and double-click `Install-Gift.vbs`; the
Windows Script Host launcher starts the hidden PowerShell WinForms wizard.
The wizard lets the user choose the install directory and whether to create
Start Menu and Desktop shortcuts, then installs gift under
`%LOCALAPPDATA%\Programs\gift`, adds a Start Menu uninstall shortcut, and
registers an uninstaller under the current user's Windows uninstall entries.
The installed folder contains `Uninstall-Gift.vbs`. Neither package requires
administrator access. Git remains a separate system dependency.
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
`release(v1.0.1): publish desktop artifacts`; otherwise verification fails.
The tag version must also match the `major.minor.patch` part of `pubspec.yaml`.
For example:

```bash
git commit -m "release(v1.0.1): publish desktop artifacts"
git tag release-v1.0.1
git push origin main release-v1.0.1
```

Ordinary branch pushes create no workflow run. Use manual dispatch when a
maintainer needs a deliberate build/check rerun. macOS builds use the
`macos-14` Apple Silicon runner and produce an unsigned universal bundle.
Both tagged pushes and manual dispatch package the macOS distribution archive;
only tagged pushes create the versioned release package set. The release
packages are:

- `gift-<version>-linux-x64.tar.gz`
- `gift-<version>-macos-universal.app.zip`
- `gift-<version>-windows-x64.zip`

The Actions desktop artifact named `gift-macos-universal` also contains
`gift.app` and the executable `Run-Gift.command` side by side. The
`gift-release-macos-universal` artifact contains the distributable ZIP used by
the release job.

The Windows archive contains the Flutter `Release` directory, the portable
launcher, and the Spull-style `gift-setup.zip` bundle. Public release
packaging requires no signing secrets. Windows executables are intentionally
unsigned; SHA-256 checksums and GitHub's OIDC-backed build provenance provide
the release integrity evidence.

The macOS archive contains `gift.app` and `Run-Gift.command` in the same
top-level directory. Extract the complete archive and launch it with
`Run-Gift.command`; the launcher clears the download quarantine attribute only
from that local app before opening it. No Apple certificate or notarization
account is used, so macOS may require explicit first-launch approval.

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
gh attestation verify gift-1.0.1-linux-x64.tar.gz \
  --repo <owner>/<repository>
```

On macOS, the unsigned universal bundle is launched through
`Run-Gift.command`, which clears the download quarantine attribute from this
local app only. It does not provide an Apple developer identity or
notarization, so macOS may require explicit first-launch approval. On Windows,
the executables are unsigned and may trigger SmartScreen or an equivalent
download warning. Checksums and the GitHub attestation are the release trust
signals. The release metadata is informational and opt-in; GIFT does not
silently download updates, send telemetry, or collect crash data.

Before a public release, a maintainer must still perform a clean-machine pass
for install, launch, upgrade, downgrade warning, uninstall, and Git-missing
first-run diagnostics on all three platforms.

The Flutter version is pinned in the workflow and in
[`tool/versions.json`](../tool/versions.json), which keeps local and CI
failures easier to reproduce.
