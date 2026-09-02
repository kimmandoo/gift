# Work Checkpoint

This file is the handoff record for continuing work across query sessions.

## Current checkpoint

- Date: 2026-09-02
- Milestone: Task 8, Discard Changes, is complete; Task 9, Commit Panel, is
  the next active product task.
- Source of truth: `TASKS.md` and
  `docs/superpowers/plans/2026-09-02-branchline-dart-mvp.md`.
- Completed scope: removed the native implementation, FFI bridge, generated
  bindings, native build plugin, and native build metadata; added a `dart:io`
  Git backend with direct argv execution, bounded output, redacted errors,
  Git discovery/version validation, repository root validation, and
  session-local opaque handles; rewired Flutter screens and tests; added
  `docs/ARCHITECTURE.md` and beginner-oriented source comments.
- Verification: installed the pinned Flutter 3.47.2 SDK with Dart 3.13.2 in
  `/tmp/codex-flutter`, then passed `flutter pub get`,
  `dart format lib test integration_test`, `flutter analyze` (`No issues
  found!`), the full `flutter test` suite (39 tests),
  `flutter test test/backend/dart_git_backend_test.dart` (15 tests),
  `flutter test test/backend/diff_parser_test.dart` (5 tests), and
  `flutter test test/features/repository/changes_screen_test.dart` (5 tests).
  `flutter test integration_test/app_smoke_test.dart` also passed (1 test)
  with GTK dependencies staged under `/tmp/codex-gtk`. `git diff --check`
  passed before this checkpoint update.
- Commit identity cleanup: rewrote all reachable commits to
  `kimmandoo <mingyu5675@gmail.com>`, removed the temporary rewrite refs, and
  force-pushed `main` to GitHub. `git log --all` reports only that identity.
  The pre-rewrite history remains recoverable from
  `/tmp/gitflu-before-author-rewrite.bundle`.
- Current session: rewrote the README in English as an open-source desktop Git
  client introduction, kept the methodology wording in design documentation,
  and removed it from public-facing project docs. Replaced the README logo with
  `assets/images/gitflu_logo.png`, an original transparent RGBA pixel-game Git
  mascot based on the existing shiba identity. The old JPEG logo was removed.
- Current Task 8 changes: added `DiscardPreview` and expiring token storage;
  extended `GitGateway`, `DartGitBackend`, `DartGitGateway`, and
  `RepositoryService` with fingerprint-checked, path-bound discard; added
  safe working-tree restore that preserves staged content and rejects
  untracked/conflicted paths; added controller loading/error state and a
  confirmation dialog; added real Git and widget coverage; updated all fake
  gateways; and updated `TASKS.md`, the implementation plan, the behavior
  ledger, `README.md`, `docs/ARCHITECTURE.md`, `CHANGELOG.md`, and this
  checkpoint.
- Next action: start Task 9 by writing the failing UTF-8 commit-message and
  hook-failure tests, then implement the stdin-based commit operation.

## Resume procedure

1. Read this file, `AGENTS.md`, `TASKS.md`, and the active section of the
   implementation plan.
2. Run `git status --short --branch` and inspect the latest commit before
   touching files.
3. Continue the exact active task and recorded next action. Do not infer
   completion from a clean tree or a commit title.
4. Re-run the recorded verification command before changing implementation if
   this checkpoint describes an unresolved failure.
5. Update this file before ending the session with exact files changed, tests
   run, observed results, blockers, and the next action.
