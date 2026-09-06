<div align="center">

<img src="assets/images/gift_logo.png" alt="GIFT pixel Shiba with a gift ribbon" width="360" style="image-rendering: pixelated;" />

# GIFT

**A small, keyboard-first Git client for desktop.**

GIFT combines Git and Flutter; the original `gitft` shorthand was shortened
to the friendlier `gift`.

Flutter UI · Dart backend · Windows · macOS · Linux

</div>

gift is an open-source desktop Git client for developers who want a calm,
focused way to review and manage local repositories. It combines a compact
workflow with a minimal 2D pixel-game visual language: dark surfaces, crisp
pixel edges, small status markers, and clear feedback for every Git action.

The project is intentionally easy to read. Flutter owns the interface and
navigation, while a pure Dart backend talks to the Git executable installed on
the user's machine.

> **Project status:** Early development. The repository, change review,
> history, branch, remote workflows, desktop builds, and release-only CI are in
> place.

## Highlights

- Review local changes, diffs, branches, history, and remote operations from
  one desktop workspace.
- Use keyboard-first workflows with visible focus and discoverable actions.
- Run Git directly with `dart:io` and explicit argument lists; no shell command
  strings are built.
- Discover and validate Git installations, including a user-selected path.
- Keep repository handles opaque and scoped to the current application session.
- Bound captured output and redact credential-bearing values in diagnostics.
- Keep screens, controllers, backend services, and tests separated so a new
  contributor can follow one feature from button to Git result.

## Architecture

```text
Flutter screen
    ↓
Controller and visible state
    ↓
GitGateway
    ↓
DartGitBackend
    ├─ GitInstallationService
    └─ RepositoryService
         ↓
    ProcessGitRunner
         ↓
    System Git executable
```

The UI never assembles raw Git commands. A feature begins with a typed backend
contract, passes through a small gateway, and ends in an explicit loading,
success, warning, or error state on screen.

## Visual direction

The interface is inspired by compact 2D pixel games without turning Git into a
game. The visual system uses:

- a restrained dark palette with mint, amber, sky, and coral status accents;
- a 4 px base grid, 8 px primary spacing, and crisp stepped borders;
- flat surfaces instead of gradients, glass effects, or heavy shadows;
- original pixel motifs for repositories, branches, commits, and status; and
- normal Flutter semantics, text labels, keyboard support, and visible focus.

The visual and interaction contract lives in
[`docs/superpowers/specs/2026-09-02-jetbrains-git-gui-pixel-ui-design.md`](docs/superpowers/specs/2026-09-02-jetbrains-git-gui-pixel-ui-design.md).

## Requirements

- Flutter stable with desktop support enabled.
- Dart SDK 3.13 or newer, provided by the matching Flutter SDK.
- Git 2.35 or newer available in `PATH`.

The repository's pinned tool versions are documented in
[`tool/versions.json`](tool/versions.json).

## Flutter setup

Install the Flutter SDK, not just the standalone Dart SDK. This repository was
verified with Flutter `3.47.2` and Dart `3.13.2`; use the stable Flutter
channel and check the pinned versions before choosing another SDK.

1. Download and extract Flutter for your operating system from the
   [official installation guide](https://docs.flutter.dev/get-started/install).
2. Add the extracted Flutter `bin` directory to `PATH`.
3. Open a new terminal and verify the installation:

```bash
flutter --version
dart --version
flutter doctor -v
git --version
```

`flutter doctor -v` should finish without an error for the desktop target you
plan to use. If the command is not found, the Flutter `bin` directory was not
added to `PATH` or the terminal was not reopened.

### Linux Flutter setup

On Ubuntu/Debian, install the SDK prerequisites and Linux desktop toolchain:

```bash
sudo apt-get update
sudo apt-get install git curl unzip xz-utils zip libglu1-mesa \
  clang cmake ninja-build pkg-config libgtk-3-dev
flutter config --enable-linux-desktop
flutter devices
```

For a temporary PATH setup when Flutter is extracted to
`$HOME/development/flutter`, run:

```bash
export PATH="$PATH:$HOME/development/flutter/bin"
```

To keep it for future Bash terminals, add that line to `~/.bashrc` and run
`source ~/.bashrc`. For Zsh, add it to `~/.zshrc` instead.

### macOS Flutter setup

Install Xcode from the App Store, then install its command-line tools:

```bash
xcode-select --install
flutter config --enable-macos-desktop
flutter devices
```

If Flutter is extracted to `$HOME/development/flutter`, make it available in
the current terminal with:

```bash
export PATH="$PATH:$HOME/development/flutter/bin"
```

Add the same line to `~/.zshrc` to keep it after restarting Terminal.

### Windows Flutter setup

Install the following before running the project:

- Git for Windows.
- Visual Studio 2022 with **Desktop development with C++** selected.
- The Windows 10 or Windows 11 SDK and the C++ CMake tools included by that
  Visual Studio workload.

After extracting Flutter, add its `bin` directory (for example,
`C:\src\flutter\bin`) to the Windows user `Path` environment variable. Open
a new PowerShell window, then run:

```powershell
flutter config --enable-windows-desktop
flutter devices
flutter doctor -v
```

The `flutter` command must be available in that new window before continuing.

## Getting started

```bash
git clone https://github.com/kimmandoo/gift.git
cd gift
flutter pub get
flutter run -d linux   # or windows / macos
```

The first screen lets you choose a working repository. Git settings can be
opened from the same screen when Git is not found automatically.

## Manual desktop builds

Run the build on the same operating system as the target. Flutter desktop
builds are not cross-compiled by this project.

### Linux

Install the Linux desktop toolchain first. On Ubuntu/Debian, the usual
packages are:

```bash
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev
flutter config --enable-linux-desktop
flutter pub get
flutter build linux --release
```

The bundle is written to `build/linux/x64/release/bundle/`.
After the toolchain is installed, the same build is one command:

```bash
./tool/build_linux.sh
```

### macOS

Install Xcode and its command-line tools, then run:

```bash
flutter config --enable-macos-desktop
flutter pub get
flutter build macos --release
```

The application bundle is written to
`build/macos/Build/Products/Release/gift.app`.
After the toolchain is installed, the same build is one command:

```bash
./tool/build_macos.sh
```

### Windows

Install Visual Studio with the **Desktop development with C++** workload and
the Windows SDK, then run from PowerShell:

```powershell
flutter config --enable-windows-desktop
reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" /t REG_DWORD /f /v "AllowDevelopmentWithoutDevLicense" /d "1"
flutter clean
flutter pub get
flutter build windows --release
```

If the compiler reports unrelated Flutter types such as `BuildContext` or
`ChangeNotifier` as missing after switching commits, clear the generated
frontend state and restore packages before retrying:

```powershell
flutter clean
flutter pub get
flutter build windows --release
```

The release files are written to `build/windows/x64/runner/Release/`.
The Windows helper creates a single-file portable launcher at
`build/windows/x64/runner/gift-portable.exe` and an interactive per-user
installation wizard at `build/windows/x64/runner/gift-setup.exe`. The setup
wizard lets you choose the install directory and Start Menu/Desktop shortcut
options, then installs gift under `%LOCALAPPDATA%\Programs\gift`, adds a
Start Menu uninstall shortcut, and registers an uninstaller for the current
Windows user. The setup executable enters through the bundled
VBScript/Windows Script Host launcher by default; the hidden PowerShell
script only renders the WinForms wizard and performs the file operations.
This keeps the user-facing entry point aligned with the reference Windows
packaging flow. The portable launcher only extracts to a temporary directory,
runs the app, and cleans up without installing files or creating shortcuts.
Git must still be installed separately because the app uses the system Git
executable.
For a one-click build, use PowerShell or double-click the batch file:

```powershell
.\tool\build_windows.ps1
```

Git Bash and WSL users can run the matching shell script:

```bash
./tool/build_windows.sh
```

The double-clickable file is `tool\build_windows.bat`.

The equivalent beginner-friendly helper is available for every platform:

```bash
dart run tool/build_desktop.dart linux   # macos or windows
```

## Development

Run the formatter, analyzer, and test suite before opening a pull request:

```bash
dart run tool/verify.dart
```

See [`docs/RELEASING.md`](docs/RELEASING.md) for release output paths and the
GitHub Actions workflow used for release-only cross-platform checks. CI runs
automatically only when a `release-*` tag points to a
`release(scope): subject` commit; normal pushes do not create workflow runs.

For a quick map of the call flow, read
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md). For behavior scenarios and
state expectations, read the
[Git behavior ledger](docs/research/jetbrains-git-mvp-behavior.md). The active
work is tracked in [`TASKS.md`](TASKS.md).

## Roadmap

- [x] Flutter desktop shell and Dart Git backend foundation.
- [x] Git discovery, safe process execution, repository validation, and recent
  repositories.
- [x] Repository status and grouped changes view.
- [x] Unified diff viewer with staged and unstaged scopes.
- [x] Staging selected paths with serialized backend mutations.
- [x] Safe confirmation-based discard for tracked working-tree changes.
- [x] Commit staged changes with UTF-8 messages and hook feedback.
- [x] Use guided commit options for amend, sign-off, cleanup, templates, and author overrides.
- [x] Bounded local history with merge-aware graph lanes and pagination.
- [x] Search and filter history, inspect changed files, and load bounded commit diffs lazily.
- [x] Local branch listing, creation, switching, and popup feedback.
- [x] Fetch, pull, push, cancellation, and remote progress feedback.
- [x] Responsive pixel UI and desktop shortcuts.
- [x] Cross-platform verification, desktop release builds, and CI artifacts.

## Contributing

Small, focused pull requests are welcome. Please keep backend operations
typed, keep Git execution shell-free, add tests for behavior changes, and
explain visible UI states in beginner-friendly terms. Use the commit format
`type(scope): subject`.

## License

gift is open-source software released under the [MIT License](LICENSE).
