<div align="center">

<img src="assets/images/gitflu_logo.png" alt="gitflu pixel shiba Git mascot" width="260" style="image-rendering: pixelated;" />

# gitflu

**A small, keyboard-first Git client for desktop.**

Flutter UI · Dart backend · Windows · macOS · Linux

</div>

gitflu is an open-source desktop Git client for developers who want a calm,
focused way to review and manage local repositories. It combines a compact
workflow with a minimal 2D pixel-game visual language: dark surfaces, crisp
pixel edges, small status markers, and clear feedback for every Git action.

The project is intentionally easy to read. Flutter owns the interface and
navigation, while a pure Dart backend talks to the Git executable installed on
the user's machine.

> **Project status:** Early development. The repository and Git execution
> foundations are in place; the changes view is the next active milestone.

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

## Getting started

```bash
git clone https://github.com/kimmandoo/gitflu.git
cd gitflu
flutter pub get
flutter run -d linux   # or windows / macos
```

The first screen lets you choose a working repository. Git settings can be
opened from the same screen when Git is not found automatically.

## Development

Run the formatter, analyzer, and test suite before opening a pull request:

```bash
dart format lib test integration_test
flutter analyze
flutter test
```

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
- [ ] Discard, commit, branch, history, and remote workflows.
- [ ] Responsive pixel UI, desktop shortcuts, packaging, and CI.

## Contributing

Small, focused pull requests are welcome. Please keep backend operations
typed, keep Git execution shell-free, add tests for behavior changes, and
explain visible UI states in beginner-friendly terms. Use the commit format
`type(scope): subject`.

## License

gitflu is an open-source work in progress. Licensing terms will be added to
the repository before the first public release.
