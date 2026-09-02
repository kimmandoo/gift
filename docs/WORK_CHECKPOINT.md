# Work Checkpoint

This file is the handoff record for continuing work across query sessions.

## Current checkpoint

- Date: 2026-09-02
- Milestone: Task 9, Commit Panel, is complete; Task 10, History & graph, is
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
  `/tmp/codex-flutter`, then passed `dart format --output=none
  --set-exit-if-changed lib test integration_test`, `git diff --check`,
  `flutter analyze` (`No issues found!`), the full `flutter test` suite
  (42 tests), `flutter test test/backend/dart_git_backend_test.dart` (17
  tests), and `flutter test
  test/features/repository/changes_screen_test.dart` (6 tests).
  `flutter test integration_test/app_smoke_test.dart` also passed (1 test)
  after building the Linux desktop bundle with GTK dependencies staged under
  `/tmp/codex-gtk`.
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
- Current Task 9 changes: added `GitCommitResult`, extended the gateway and
  backend facades, implemented serialized `git commit --file=-` with UTF-8
  stdin, staged preflight, post-commit status refresh, and typed hook rejection
  mapping; added controller commit state and a staged-only editor with
  loading, success, error, and clean states; updated all fake gateways and
  added backend/widget coverage; updated `TASKS.md`, the implementation
  plan, behavior ledger, `README.md`, `docs/ARCHITECTURE.md`,
  `CHANGELOG.md`, and this checkpoint.
- Changed files in this session: `lib/src/backend/commit.dart`,
  `lib/src/backend/git_gateway.dart`, `lib/src/backend/dart_git_backend.dart`,
  `lib/src/backend/dart_git_gateway.dart`,
  `lib/src/backend/repository_service.dart`,
  `lib/src/features/repository/changes_controller.dart`,
  `lib/src/features/repository/changes_screen.dart`, the three affected
  gateway test fakes, `test/backend/dart_git_backend_test.dart`,
  `test/features/repository/changes_screen_test.dart`, and the six
  documentation/checkpoint files above.
- Blockers: none. The pre-existing untracked `.serena/` directory was left
  untouched and is not part of the commit.
- Next action: begin Task 10 by adding failing bounded-log, pagination, and
  merge-parent tests, then implement the typed history page.

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
