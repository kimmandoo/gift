# Branchline Dart MVP Implementation Plan

**Goal:** Reverse-engineer the user-visible behavior and information
architecture of the JetBrains IDE Git GUI through black-box observation, then
build a clean-room, cross-platform equivalent with a minimal 2D pixel-game UI,
a Flutter Desktop frontend, and a pure Dart backend.

**Architecture:** Flutter owns presentation, navigation, keyboard handling,
and UI state. Dart backend services own repository identity, direct system-Git
execution, machine-readable parsing, mutations, cancellation, and typed
errors. The UI consumes the backend through `GitGateway`, which is a normal
Dart interface rather than a native bridge.

The JetBrains behavior ledger is the product source of truth for workflow
equivalence. The pixel UI specification is the source of truth for spacing,
palette, focus treatment, responsive layout, and original visual assets.

**Tooling:** Flutter stable, Dart 3.13+, Material 3, Riverpod, `dart:io`, and
system Git 2.35+.

## Execution rules

- Apply test-driven development to each behavior change.
- Keep Git execution shell-free: pass executable, arguments, working directory,
  and stdin as separate values to `Process.start`.
- Bound captured output and continuously drain both process pipes.
- Redact credential URLs and sensitive values before putting Git output in a
  diagnostic.
- Treat JetBrains behavior as a black-box behavioral target; do not copy
  proprietary source, binaries, assets, screenshots, or private protocols.
- Implement every workflow with explicit loading, empty, success, warning, and
  error states in the minimal 2D pixel-game visual system.
- Keep one mutation per repository at a time and validate opaque IDs against
  the in-memory registry that created them.
- Follow `AGENTS.md`: update `CHANGELOG.md`, maintain the checkpoint, and use a
  conventional commit for each query session.

## Dart backend file map

- `lib/src/backend/domain.dart` — public value objects and health contract.
- `lib/src/backend/error.dart` — typed Git error categories.
- `lib/src/backend/executor.dart` — direct process runner, bounded output, and
  redaction.
- `lib/src/backend/git_installation_service.dart` — Git discovery, version
  parsing, and explicit path validation.
- `lib/src/backend/repository_service.dart` — repository root validation and
  opaque handle registry.
- `lib/src/backend/status.dart` — porcelain v2 parser, change facets, and
  generation-aware snapshots.
- `lib/src/backend/diff.dart` — bounded unified diff models and parser for
  hunk lines, rename metadata, and binary output.
- `lib/src/backend/dart_git_backend.dart` — backend service facade.
- `lib/src/backend/dart_git_gateway.dart` — Flutter-facing adapter.
- `lib/src/features/repository/changes_controller.dart` — Riverpod-backed
  polling controller and selection state.
- `lib/src/features/repository/changes_screen.dart` — grouped changes UI.
- `test/backend/diff_parser_test.dart` — parser coverage for hunk, rename,
  binary, and empty output states.

## Foundation status

- [x] Flutter shell and Dart backend health contract.
- [x] Clean-room temporary Git fixture coverage.
- [x] Direct argv process execution with bounded output.
- [x] Git discovery, version validation, and redacted diagnostics.
- [x] Canonical repository opening and session-local opaque IDs.
- [x] Recent repository persistence and configurable Git path UI.
- [x] Porcelain v2 status parsing, independent change facets, and
  generation-aware snapshots.
- [x] Grouped Changes screen with timer refresh and selection retention.
- [x] Bounded staged/working-tree diff snapshots and lazy selected-file view.
- [x] Removed the previous native implementation and generated bridge assets.

## Product direction

- [ ] Capture each target workflow as a neutral JetBrains behavior-ledger
  scenario before implementation.
- [ ] Apply the 4 px/8 px grid, restrained dark palette, crisp borders, and
  original pixel motifs from the UI specification.
- [ ] Preserve keyboard-first navigation, visible focus, semantic labels, and
  text-backed status indicators throughout the pixel treatment.

## Completed vertical: status and changes

1. Added failing tests for porcelain v2 `-z` records and each status facet.
2. Implemented a bounded status invocation and parser in the backend.
3. Added generation-aware snapshots and a polling `ChangesController`.
4. Rendered grouped changes in Flutter.
5. Passed `flutter analyze` and `flutter test`.

## Completed vertical: unified diff

1. Added failing tests for staged and unstaged unified diff output.
2. Implemented bounded diff parsing and rename-aware file details.
3. Rendered a lazy diff view while preserving the selected change.
4. Passed `flutter analyze` and `flutter test`.

## Next vertical: staging and mutation

1. Add failing tests for staging and un-staging selected paths.
2. Implement serialized `git add` and `git restore --staged` operations.
3. Add selection-aware actions and refresh the status snapshot after mutation.
