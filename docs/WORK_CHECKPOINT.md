# Work Checkpoint

This file is the handoff record for continuing work across query sessions.

## Current checkpoint

- Date: 2026-09-02
- Milestone: Task 15 hardening, UI stabilization, and product identity are
  implemented; local Linux bundle verification remains active.
- Source of truth: `TASKS.md` and
  `docs/superpowers/plans/2026-09-02-gitflu-dart-mvp.md`.
- Completed scope: removed the native implementation, FFI bridge, generated
  bindings, native build plugin, and native build metadata; added a `dart:io`
  Git backend with direct argv execution, bounded output, redacted errors,
  Git discovery/version validation, repository root validation, and
  session-local opaque handles; rewired Flutter screens and tests; added
  `docs/ARCHITECTURE.md` and beginner-oriented source comments.
- Verification: restored the pinned Flutter 3.47.2 SDK with Dart 3.13.2 in
  `/home/mgkim/.local/flutter`; passed `flutter analyze`, the full Flutter test
  suite, and `PATH=/home/mgkim/.local/flutter/bin:$PATH dart run
  tool/verify.dart` (formatting, analysis, and all 70 tests).
- Commit identity cleanup: rewrote all reachable commits to
  `kimmandoo <mingyu5675@gmail.com>`, removed the temporary rewrite refs, and
  force-pushed `main` to GitHub. `git log --all` reports only that identity.
  The pre-rewrite history remains recoverable from
  `/tmp/gitflu-before-author-rewrite.bundle`.
- Final Task 13 changes added the shared dark pixel theme, square focusable
  surfaces, responsive Changes/History layouts and operation dialog sizing,
  keyboard shortcuts, bottom status feedback, responsive widget tests, and
  beginner-oriented architecture documentation.
- Final Task 14 changes added `tool/verify.dart`,
  `tool/build_desktop.dart`, `.github/workflows/ci.yml`, and
  `docs/RELEASING.md`; the task board, README, changelog, plan, and this
  checkpoint were updated for the completed 14-task MVP.
- Follow-up documentation changes added platform-specific manual Linux, macOS,
  and Windows build steps to `README.md` and linked each release output path.
- Follow-up setup documentation added common Flutter SDK verification plus
  Linux, macOS, and Windows PATH and desktop toolchain instructions to
  `README.md`.
- Follow-up CI changes gated Actions jobs to `release(scope):` commits, added
  Linux desktop dependencies and target activation, made the macOS build
  unsigned for CI, and removed Unix-only commands from cross-platform tests.
- CI repair verification passed `dart run tool/verify.dart`, the Linux release
  build helper, Dart analysis for the build helper, and workflow YAML parsing.
  macOS and Windows runners are configured in the matrix but are not available
  in this Linux workspace for local execution.
- Follow-up build ergonomics added one-command Linux/macOS/Windows shell
  wrappers plus native Windows PowerShell and batch launchers. The desktop
  helper now enables the requested Flutter target before building.
- Added `.gitattributes` so Git Bash shell wrappers keep LF endings and native
  Windows launchers keep Windows-friendly line endings after checkout.
- Task 15 added bounded non-interactive Git execution, deterministic
  cancellation outcomes, continuous paginated history lanes, stale settings
  request guards, canonical Git path persistence, discard-preview revocation,
  and expiry cleanup.
- Task 15 unified the Dart package, app shell, Linux binary/application ID,
  macOS product/bundle ID, Windows executable metadata, docs, tests, and build
  output paths under the lowercase `gitflu` product identity.
- Release automation now starts only for `release-*` tags whose commit uses a
  `release(scope): subject` message. Third-party Actions are pinned by commit.
- Added the MIT `LICENSE` and updated the public README license statement.
- Verification: `dart run tool/verify.dart` passed formatting, analysis, and
  all 66 tests. Workflow YAML parsing and release-subject matching passed.
- Local build note: `./tool/build_linux.sh` reached native compilation but the
  host lacks `libgtk-3-dev`; installing it requires a sudo password unavailable
  to this session. CI already installs this dependency before Linux builds.
- Added Tasks 16–25 as an ordered post-MVP backlog in
  `docs/POST_MVP_ROADMAP.md`. The roadmap covers multi-repository workspaces,
  partial staging, commit and history depth, advanced branches, conflicts,
  Git object management, scale, accessibility, and signed public releases.
- Task 15 remains active; creating the backlog did not skip its pending Linux
  bundle verification. After Task 15 passes, Task 16 is the first post-MVP
  implementation task.
- UI stabilization replaced one-line commit markers with graph-row segment
  models for incoming, continuation, fork, merge, and compressed wide-lane
  rendering. Pagination recomputes the complete visible graph.
- Replaced the first-pass Silkscreen font with the more legible OFL Pixelify
  Sans font and applied a compact 12/13/15/16/18/22/24 px type scale with
  explicit line spacing, button sizing, and centralized heading tokens.
- Added persisted light/dark theme switching, compact 360x640 layout coverage,
  and responsive dialog bounds.
- `assets/images/gitflu_icon.png` is now the release icon source. Generated
  macOS AppIcon PNGs and the Windows multi-size ICO use that asset; Flutter
  also bundles it for Linux packaging.
- UI verification: `dart run tool/verify.dart` passed formatting, analysis,
  and all 70 tests. Added compact 320x480 welcome, compact 360x640 Changes and
  History, theme persistence, wide graph, merge/fork, and already-active
  parent lane coverage. Font and icon asset validation passed.
- Palette pass replaced generated/direct color mixing with explicit semantic
  light and dark roles, matching `on*` text colors for status containers, and
  a 4.5:1 contrast regression suite. Direct red error text was removed.
- Current UI refinement lowered the overall type scale, strengthened Pixelify
  Sans body weight and line spacing, moved screen headings to shared theme
  tokens, and added common button text/padding rules.
- Current layout hardening made narrow summary/status rows wrap safely, added
  branch-input stacking below 300 px, and enabled dialog action overflow
  spacing so text and buttons do not collide.
- Current session verification passed `flutter analyze`, `flutter test`, and
  `PATH=/home/mgkim/.local/flutter/bin:$PATH dart run tool/verify.dart`.
- Changed implementation files: `lib/src/app/gitflu_app.dart`,
  `lib/src/app/pixel_theme.dart`, `lib/src/backend/history.dart`, core
  repository screens/dialogs, `pubspec.yaml`, desktop icon resources, tests,
  and UI documentation.
- Concurrent work note: the unstaged README Windows registry command was not
  created or staged by this task and remains untouched for its owner.
- Blockers: no source blocker. The pre-existing untracked `.serena/` directory
  was left untouched and is not part of the commit.
- Next action: install `libgtk-3-dev` on this Linux host and rerun
  `./tool/build_linux.sh` when local bundle verification is needed.

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
