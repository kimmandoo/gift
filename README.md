<div align="center">

<img src="assets/images/gitflu_logo.jpg" alt="gitflu logo" width="260" style="border-radius: 16px; box-shadow: 0 4px 20px rgba(0,0,0,0.3);" />

# gitflu

**`gitflow` + `flutter` + `git gui`**

*A keyboard-first, clean-room Git GUI built entirely with Dart and Flutter.*

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20macOS%20%7C%20Linux-lightgrey)](https://github.com)

</div>

## About gitflu

gitflu is a lightweight, cross-platform Git GUI for a smooth, keyboard-centric
workflow. Flutter owns the desktop UI, while a pure Dart backend runs the
system Git executable directly and exposes typed domain services to the UI.

The backend uses `Process.start` with an argument list and
`runInShell: false`. Git commands never cross a shell, credentials are
redacted from diagnostics, and captured output is bounded.

처음 코드를 읽는다면 [코드 흐름 안내](docs/ARCHITECTURE.md)에서 화면부터
백엔드와 system Git까지 이어지는 호출 순서를 먼저 확인하세요.

## Architecture

```mermaid
flowchart TD
    subgraph Flutter["Flutter Desktop UI"]
        UI[App Shell & Features\nChanges · Log · Branches · Diff]
        State[Riverpod / Controller State]
        Gateway[GitGateway Contract]
    end

    subgraph Dart["Dart Backend"]
        API[DartGitBackend]
        Service[Repository & Git Services]
        Executor[ProcessGitRunner\nargv · bounded output · redaction]
    end

    subgraph System["Operating System"]
        GitCLI[System Git CLI 2.35+\nSSH Keys · GPG · Credential Helpers]
    end

    UI --> State
    State --> Gateway
    Gateway --> API
    API --> Service
    Service --> Executor
    Executor --> GitCLI
```

## Features

- Flutter Desktop frontend with Material 3.
- Dart-only backend with no FFI, native bridge, or generated bindings.
- System Git discovery and validation for Git 2.35+.
- Opaque, session-local repository handles.
- Recent repository persistence and configurable Git executable path.
- Shell-free process execution with bounded output and credential-safe errors.

## Getting started

### Prerequisites

- System Git `2.35+` available in `PATH`.
- Flutter stable with Windows, macOS, or Linux desktop enabled.
- Dart SDK `3.13+` (provided by the matching Flutter SDK).

### Build and verify

```bash
git clone https://github.com/your-org/gitflu.git
cd gitflu
flutter pub get
flutter analyze
flutter test
```

Run the desktop app with `flutter run -d windows`, `flutter run -d macos`, or
`flutter run -d linux`.

## Roadmap

- [x] Dart backend scaffold, safe Git executor, Git discovery, and repository opening.
- [ ] Repository status and grouped changes view.
- [ ] Bounded unified diff viewer.
- [ ] Staging, discard, and commit workflows.
- [ ] Branch graph, branch management, and remote operations.
- [ ] Packaging and multi-OS CI.

## Contributing

Follow the commit convention `type(scope): subject`, keep Git execution
argument-based, and run `flutter analyze` plus `flutter test` before opening a
pull request.

## License

Distributed under the MIT License. See [LICENSE](LICENSE) for more
information.
