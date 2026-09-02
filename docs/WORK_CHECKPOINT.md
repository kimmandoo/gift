# Work Checkpoint

This file is the handoff record for continuing work across query sessions.

## Current checkpoint

- Date: 2026-09-02
- Milestone: Task 7, Staging & Mutation, is complete; Task 8, Discard Changes,
  is the next active product task.
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
  found!`), the full `flutter test` suite (36 tests),
  `flutter test test/backend/dart_git_backend_test.dart` (17 tests),
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
- Current Task 7 changes: extended `GitGateway`, `DartGitBackend`,
  `DartGitGateway`, and `RepositoryService` with shell-free stage/unstage
  mutations and a per-repository `AppState` queue; added mutation state and
  selected-file actions to the Changes controller/screen; added real Git,
  queue, and widget coverage; updated all fake gateways; and updated
  `TASKS.md`, the implementation plan, the behavior ledger, `README.md`,
  `docs/ARCHITECTURE.md`, `CHANGELOG.md`, and this checkpoint.
- Next action: start Task 8 by writing the failing discard preview-token and
  confirmation tests, then implement the path-bound discard operation.

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
