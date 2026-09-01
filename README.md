# branchline

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

## Desktop build verification

The current Windows verification command is:

```powershell
& C:\Users\USER\flutter\bin\flutter.bat build windows --debug
```

It currently fails because Flutter plugin builds require Windows Developer Mode
or symlink support. Enable Windows Developer Mode, or otherwise allow Developer
Mode/symlink support, before rerunning the command.

The app uses the generated Cargokit FFI plugin at `rust_builder/` to build and
bundle the `native` Rust crate for Windows, Linux, and macOS. Once the Windows
build is permitted, run the non-UI bridge smoke check with:

```powershell
& C:\Users\USER\flutter\bin\flutter.bat test integration_test/bridge_smoke_test.dart -d windows
```

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
