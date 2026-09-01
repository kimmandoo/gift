# Branchline MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a clean-room, cross-platform Git GUI with a Flutter Desktop interface and a Rust system-Git core for Windows, macOS, and Linux.

**Architecture:** Flutter owns presentation, navigation, keyboard handling, and Riverpod state. Rust owns repository identity, shell-free Git execution, machine-readable parsing, mutations, cancellation, and typed errors; `flutter_rust_bridge` is the only boundary. Each vertical task adds a tested Rust behavior and the Flutter surface that consumes it.

**Tech Stack:** Flutter stable, Dart, Material 3, Riverpod, `flutter_rust_bridge`, Rust stable, Tokio, system Git 2.35+, GitHub Actions

---

## Execution rules

- Read `docs/superpowers/specs/2026-09-01-rust-flutter-git-gui-design.md` before starting.
- Create an isolated feature worktree with `@superpowers:using-git-worktrees` before Task 1.
- Apply `@superpowers:test-driven-development` to every behavior change: failing test, observed failure, minimal implementation, observed pass.
- Use `@superpowers:systematic-debugging` for unexpected failures and `@superpowers:verification-before-completion` before every completion claim.
- Run repository commands through `rtk` as required by `AGENTS.md`. If `rtk` is still absent, document that diagnostic once and use raw commands only for debugging.
- Do not add JetBrains code, binaries, screenshots, icons, fonts, trademarks, or license-bypass behavior.
- Commit `pubspec.lock` and `native/Cargo.lock`. Do not hand-edit files generated under `lib/src/rust/generated/`.
- Keep one mutation per repository at a time. Never construct a shell command string from paths, refs, commit messages, remote names, or credentials.
- Whenever a Rust source file is added under `api`, `domain`, `executor`, `parser`, or `service`, update that directory's `mod.rs` in the same step. Re-export every bridge function through `api/mod.rs`, regenerate FRB bindings, and require `cargo check` before the step is complete.

## File and responsibility map

### Root and tooling

- Create `pubspec.yaml` — Flutter dependencies, assets, and desktop package metadata.
- Create `analysis_options.yaml` — strict Dart analysis.
- Create `flutter_rust_bridge.yaml` — bridge input/output locations.
- Create `rust-toolchain.toml` — Rust stable toolchain and formatter/clippy components.
- Create `tool/versions.json` — exact Flutter, Dart, Rust, Git, and FRB codegen versions used by the initial scaffold.
- Create `tool/verify.ps1` and `tool/verify.sh` — equivalent full local verification entry points.
- Create `.github/workflows/ci.yml` — three-OS checks.
- Create `.github/workflows/release.yml` — platform artifacts and checksums.

### Flutter application

- Create `lib/main.dart` — process entry point and Rust initialization.
- Create `lib/src/app/branchline_app.dart` — `MaterialApp`, theme, shortcuts, and top-level routing.
- Create `lib/src/app/app_theme.dart` — light/dark theme tokens.
- Create `lib/src/app/app_shortcuts.dart` — platform-aware shortcut intents.
- Create `lib/src/rust/git_gateway.dart` — UI-facing abstract Git contract.
- Create `lib/src/rust/frb_git_gateway.dart` — generated bridge adapter only.
- Generate `lib/src/rust/generated/**` — FRB Dart bindings.
- Create `lib/src/shared/error/error_presenter.dart` — typed error to user-facing text mapping.
- Create `lib/src/shared/widgets/operation_bar.dart` — active operation progress and cancel UI.
- Create `lib/src/features/repository/**` — welcome screen, recent repositories, open/reopen controller.
- Create `lib/src/features/settings/**` — Git executable discovery, explicit path selection, and retry UI.
- Create `lib/src/features/changes/**` — grouped change state and changes list.
- Create `lib/src/features/diff/**` — lazy unified diff viewer.
- Create `lib/src/features/commit/**` — commit message and action state.
- Create `lib/src/features/log/**` — paginated graph, commit details, historical diff.
- Create `lib/src/features/branches/**` — branch search/create/switch/tracking UI.
- Create `lib/src/features/remotes/**` — fetch/pull/push/upstream flows.

### Rust core

- Create `native/Cargo.toml` and `native/src/lib.rs` — one Rust crate and FRB entry point.
- Create `native/src/api/mod.rs` — public bridge module wiring; no raw Git command API.
- Create `native/src/domain/mod.rs` — IDs, snapshots, diffs, commits, refs, remotes, operations.
- Create `native/src/executor/mod.rs` — executor module wiring.
- Create `native/src/parser/mod.rs` — parser module wiring.
- Create `native/src/service/mod.rs` — service module wiring.
- Create `native/src/api/**` — intent-based bridge functions.
- Create `native/src/domain/**` — typed domain modules.
- Create `native/src/error.rs` — typed error taxonomy and redaction-safe diagnostics.
- Create `native/src/executor/**` — shell-free process execution, bounded output, session isolation, cancellation.
- Create `native/src/parser/**` — porcelain v2, diff, log, refs, and progress parsers.
- Create `native/src/service/**` — repository, changes, commit, log, branch, remote, and operation services.
- Create `native/src/state.rs` — repository/operation registries, generations, and mutation locks.
- Create `native/tests/support/**` — temporary repositories, local bare remotes, and Git fixture helpers.
- Create `native/tests/*.rs` — real-Git integration tests organized by vertical feature.

### Tests, research, and release docs

- Create `test/**` — Dart controller and widget tests using fake `GitGateway` implementations.
- Create `integration_test/app_smoke_test.dart` — desktop bridge smoke test.
- Create `docs/research/jetbrains-git-mvp-behavior.md` — clean-room behavior ledger.
- Create `docs/release/macos-ad-hoc.md` — truthful Gatekeeper first-launch instructions.
- Create `tool/package_windows.ps1`, `tool/package_linux.sh`, and `tool/package_macos.sh` — deterministic packaging scripts.

## Task 1: Scaffold Flutter, Rust, and the generated bridge

**Files:**
- Create: `pubspec.yaml`
- Create: `analysis_options.yaml`
- Create: `flutter_rust_bridge.yaml`
- Create: `rust-toolchain.toml`
- Create: `tool/versions.json`
- Create: `lib/main.dart`
- Create: `lib/src/app/branchline_app.dart`
- Create: `native/Cargo.toml`
- Create: `native/src/lib.rs`
- Create: `native/src/api/mod.rs`
- Generate: `lib/src/rust/generated/**`
- Test: `native/src/api/mod.rs`
- Test: `test/app_boot_test.dart`

- [ ] **Step 1: Record the available toolchain**

Run:

    rtk flutter --version
    rtk dart --version
    rtk rustc --version
    rtk cargo --version
    rtk git --version

Expected: Flutter desktop support is enabled, Rust is stable, and Git is at least 2.35. Record the exact values in `tool/versions.json`.

- [ ] **Step 2: Generate the desktop shell and Rust crate**

Run:

    rtk flutter create --platforms=windows,macos,linux --org dev.branchline --project-name branchline .
    rtk cargo init --lib native
    rtk flutter pub add flutter_riverpod flutter_rust_bridge file_selector path_provider shared_preferences collection
    rtk cargo add flutter_rust_bridge thiserror semver async-trait bstr serde_json sha2 base64 --manifest-path native/Cargo.toml
    rtk cargo add tokio --features macros,rt-multi-thread,process,io-util,sync,time --manifest-path native/Cargo.toml
    rtk cargo add tokio-util --features rt --manifest-path native/Cargo.toml
    rtk cargo add uuid --features v4 --manifest-path native/Cargo.toml
    rtk cargo add serde --features derive --manifest-path native/Cargo.toml
    rtk cargo add nix --target "cfg(unix)" --features process,signal --manifest-path native/Cargo.toml
    rtk cargo add windows-sys --target "cfg(windows)" --features Win32_Foundation,Win32_System_Console,Win32_System_JobObjects,Win32_System_Threading --manifest-path native/Cargo.toml
    rtk cargo add tempfile --dev --manifest-path native/Cargo.toml
    rtk cargo install flutter_rust_bridge_codegen --locked

Add the Flutter SDK test dependency directly under `dev_dependencies`:

    integration_test:
      sdk: flutter

Remove Flutter's generated counter-app `test/widget_test.dart` before adding Branchline tests. Configure `native/Cargo.toml` with:

    [lib]
    crate-type = ["cdylib", "staticlib"]

Resolve one compatible FRB release and pin that exact version in Dart, Rust, and the installed codegen; record it in `tool/versions.json`. Do not allow three independent unversioned FRB resolutions to remain in the lockfiles.

- [ ] **Step 3: Write a failing Rust bridge health test**

First add `pub mod api;` to `native/src/lib.rs` so Cargo discovers tests in `api/mod.rs`. Then add to `native/src/api/mod.rs`:

    #[cfg(test)]
    mod tests {
        use super::health;

        #[test]
        fn health_exposes_product_and_core_version() {
            let result = health();
            assert_eq!(result.product, "Branchline");
            assert!(!result.core_version.is_empty());
        }
    }

- [ ] **Step 4: Run the targeted Rust test and observe failure**

Run:

    rtk cargo test --manifest-path native/Cargo.toml health_exposes_product_and_core_version

Expected: FAIL because `health` and `Health` do not exist.

- [ ] **Step 5: Implement the minimal health API**

In `native/src/api/mod.rs` define a FRB-visible `Health { product: String, core_version: String }` and `pub fn health() -> Health` using `env!("CARGO_PKG_VERSION")`.

- [ ] **Step 6: Configure and generate the bridge**

Set `flutter_rust_bridge.yaml` to:

    rust_input: crate::api
    rust_root: native/
    dart_output: lib/src/rust/generated

Run:

    rtk flutter_rust_bridge_codegen generate
    rtk dart format lib
    rtk cargo fmt --manifest-path native/Cargo.toml

Expected: generated Dart/Rust bindings compile without manual edits.

- [ ] **Step 7: Write a failing Flutter boot test**

Create `test/app_boot_test.dart`:

    import 'package:branchline/src/app/branchline_app.dart';
    import 'package:flutter/material.dart';
    import 'package:flutter_test/flutter_test.dart';

    void main() {
      testWidgets('boots into the repository welcome screen', (tester) async {
        await tester.pumpWidget(const BranchlineApp());
        expect(find.text('Open Repository'), findsOneWidget);
        expect(find.byType(MaterialApp), findsOneWidget);
      });
    }

- [ ] **Step 8: Run the Flutter test and observe failure**

Run:

    rtk flutter test test/app_boot_test.dart

Expected: FAIL because `BranchlineApp` is absent.

- [ ] **Step 9: Implement the minimal app shell**

Create `BranchlineApp` as a `ConsumerWidget` returning a Material 3 `MaterialApp` with an `Open Repository` label and a disabled scaffold control; Task 4 replaces it with the real repository action. Initialize generated Rust bindings in `main.dart` before `runApp`.

- [ ] **Step 10: Verify scaffold and commit**

Run:

    rtk cargo test --manifest-path native/Cargo.toml
    rtk cargo clippy --manifest-path native/Cargo.toml --all-targets -- -D warnings
    rtk flutter analyze
    rtk flutter test
    rtk flutter build windows --debug

Use `macos` or `linux` instead of `windows` on those platforms. Expected: all commands exit 0 and the current platform links the Rust library.

Commit:

    rtk git add .gitignore .metadata README.md pubspec.yaml pubspec.lock analysis_options.yaml flutter_rust_bridge.yaml rust-toolchain.toml tool lib native test windows macos linux
    rtk git commit -m "build: scaffold branchline desktop bridge"

## Task 2: Freeze the clean-room behavior ledger and test harness

**Files:**
- Create: `docs/research/jetbrains-git-mvp-behavior.md`
- Create: `native/tests/support/mod.rs`
- Create: `native/tests/support/test_repo.rs`
- Create: `native/tests/behavior_contract.rs`

- [ ] **Step 1: Write the behavior ledger**

Document these neutral scenario IDs with input state, user intent, expected visible state, expected Git state, and source type `approved design`: `STATUS-01`, `DIFF-01`, `STAGE-01`, `DISCARD-01`, `COMMIT-01`, `LOG-01`, `BRANCH-01`, `REMOTE-01`. State that later authorized observations append versioned notes without storing proprietary captures.

- [ ] **Step 2: Write a failing test-repository harness test**

In `native/tests/behavior_contract.rs` create a test that calls `TestRepo::new()`, writes `hello.txt`, commits it, and asserts `git status --porcelain` is empty. The helper must set repository-local `user.name` and `user.email` so tests never depend on global configuration.

- [ ] **Step 3: Run it and observe failure**

Run:

    rtk cargo test --manifest-path native/Cargo.toml --test behavior_contract

Expected: FAIL because `TestRepo` is absent.

- [ ] **Step 4: Implement the test harness**

Implement `TestRepo` with `tempfile::TempDir` and direct `std::process::Command` calls used only by tests. Provide `write`, `git`, `commit_all`, `path`, and `bare_remote` helpers. Each helper must include stdout/stderr in assertion failures and use argument arrays rather than a shell.

- [ ] **Step 5: Verify and commit**

Run:

    rtk cargo test --manifest-path native/Cargo.toml --test behavior_contract

Expected: `STATUS-01` harness test passes.

Commit:

    rtk git add docs/research native/tests
    rtk git commit -m "test: add clean-room git behavior harness"

## Task 3: Build typed errors, redaction, Git discovery, and shell-free execution

**Files:**
- Create: `native/src/error.rs`
- Create: `native/src/domain/mod.rs`
- Create: `native/src/domain/operation.rs`
- Create: `native/src/executor/mod.rs`
- Create: `native/src/executor/invocation.rs`
- Create: `native/src/executor/process_runner.rs`
- Create: `native/src/executor/redaction.rs`
- Create: `native/src/service/mod.rs`
- Create: `native/src/service/git_installation.rs`
- Create: `native/src/api/settings_api.rs`
- Modify: `native/src/api/mod.rs`
- Modify: `native/src/lib.rs`
- Test: `native/tests/git_executor.rs`

- [ ] **Step 1: Write failing parsing and redaction tests**

Cover:

    assert_eq!(parse_git_version(b"git version 2.51.0.windows.1\n")?.major, 2);
    assert_eq!(
        redact_remote("https://alice:secret@example.com/org/repo.git"),
        "https://***@example.com/org/repo.git"
    );

Also create a real process test in a temporary directory whose name contains spaces and `&`; run `git rev-parse --show-toplevel` with discrete argv and assert the returned path is exact.

- [ ] **Step 2: Run tests and observe failure**

Run:

    rtk cargo test --manifest-path native/Cargo.toml --test git_executor

Expected: FAIL because discovery, invocation, and redaction modules are absent.

- [ ] **Step 3: Implement the error contract**

Define `GitErrorCategory` with every category from design section 11 and a `GitError { category, user_message, diagnostic, retryable, exit_code }`. Add constructors that accept byte stderr, perform lossy display conversion only after redaction, and never include stdin or raw credential-bearing URLs.

- [ ] **Step 4: Implement `GitInvocation` and bounded process execution**

`GitInvocation` must hold `program: PathBuf`, `args: Vec<OsString>`, `cwd: PathBuf`, `stdin: Option<Vec<u8>>`, `kind: Read | Mutation | Remote`, and an `OutputPolicy`. Support `Capture { max_bytes }` for small machine-readable commands and `Stream` for parsers/progress consumers. `ProcessGitRunner` must use `tokio::process::Command::new`, pipe stdout/stderr concurrently, enforce the requested capture bound, set `kill_on_drop(true)`, and return a typed overflow error only for `Capture`. `Stream` must apply backpressure or drain discarded data so a large child output cannot deadlock or allocate without bound.

- [ ] **Step 5: Implement Git discovery**

Search the explicit configured path first, then PATH. Run `git --version`, parse semantic components including vendor suffixes, and reject versions below 2.35 with `UnsupportedGitVersion`.

Expose `get_git_installation()` and `configure_git_path(path)` from `settings_api.rs`. The latter must canonicalize a file path, run the same version check, update only the in-memory executor after success, and leave the previous valid installation unchanged after failure.

- [ ] **Step 6: Verify and commit**

Run:

    rtk cargo test --manifest-path native/Cargo.toml --test git_executor
    rtk cargo clippy --manifest-path native/Cargo.toml --all-targets -- -D warnings

Expected: tests pass; clippy reports no warnings.

Commit:

    rtk git add native/src/error.rs native/src/domain native/src/executor native/src/service/git_installation.rs native/src/api/settings_api.rs native/tests/git_executor.rs
    rtk git commit -m "feat: add safe system git executor"

## Task 4: Open repositories through opaque IDs and persist recent paths

**Files:**
- Create: `native/src/domain/repository.rs`
- Create: `native/src/state.rs`
- Create: `native/src/service/repository_service.rs`
- Create: `native/src/api/repository_api.rs`
- Modify: `native/src/domain/mod.rs`
- Modify: `native/src/service/mod.rs`
- Modify: `native/src/api/mod.rs`
- Modify: `native/src/lib.rs`
- Create: `lib/src/rust/git_gateway.dart`
- Create: `lib/src/rust/frb_git_gateway.dart`
- Create: `lib/src/features/repository/repository_controller.dart`
- Create: `lib/src/features/repository/recent_repository_store.dart`
- Create: `lib/src/features/repository/welcome_screen.dart`
- Create: `lib/src/features/settings/git_settings_controller.dart`
- Create: `lib/src/features/settings/git_settings_dialog.dart`
- Test: `native/tests/repository_open.rs`
- Test: `test/features/repository/welcome_screen_test.dart`
- Test: `test/features/settings/git_settings_dialog_test.dart`

- [ ] **Step 1: Write failing Rust repository tests**

Test that opening a nested directory returns the canonical top-level path and an opaque `RepositoryId`. Test that a non-repository returns `NotRepository` and a deleted repository returns `RepositoryMoved` on the next lookup. Assert that IDs from one registry cannot resolve in another.

- [ ] **Step 2: Run and observe failure**

Run:

    rtk cargo test --manifest-path native/Cargo.toml --test repository_open

Expected: FAIL because repository state and APIs are absent.

- [ ] **Step 3: Implement repository registry and API**

Use a random UUID token as `RepositoryId` and store canonical `PathBuf`, generation, and a Tokio mutation mutex in `AppState`. `open_repository` must run `rev-parse --show-toplevel` and `rev-parse --is-bare-repository`, reject bare repositories for UI opening, then return `RepositoryOpened`. Every later lookup must revalidate that the root still exists.

- [ ] **Step 4: Write a failing Flutter welcome-screen test**

Create a hand-written `FakeGitGateway`. Test successful folder selection, recent-path insertion, missing recent-path display, removal, and `NotRepository` error presentation. Also test Git-not-found startup, executable selection, version rejection, persistence of a valid explicit Git path, and retry. Do not call the static generated bridge from widget tests.

- [ ] **Step 5: Run and observe failure**

Run:

    rtk flutter test test/features/repository/welcome_screen_test.dart

Expected: FAIL because controller/store/widgets are absent.

- [ ] **Step 6: Implement the Flutter repository boundary**

Define `GitGateway` as the only feature-facing interface. Implement `FrbGitGateway` by adapting generated types. Store recent repository paths and the explicit Git executable path with `shared_preferences`, cap the ordered recent list at 10, and reopen paths through Rust to obtain fresh IDs. On startup, validate the stored Git path before enabling repository actions; keep the settings dialog reachable when validation fails.

- [ ] **Step 7: Regenerate, verify, and commit**

Run:

    rtk flutter_rust_bridge_codegen generate
    rtk cargo test --manifest-path native/Cargo.toml --test repository_open
    rtk flutter test test/features/repository/welcome_screen_test.dart
    rtk flutter test test/features/settings/git_settings_dialog_test.dart
    rtk flutter analyze

Expected: all commands exit 0.

Commit:

    rtk git add native lib test pubspec.lock
    rtk git commit -m "feat: open repositories with opaque handles"

## Task 5: Parse porcelain v2 status and render the Changes screen

**Files:**
- Create: `native/src/domain/change.rs`
- Create: `native/src/domain/snapshot.rs`
- Create: `native/src/parser/mod.rs`
- Create: `native/src/parser/status.rs`
- Create: `native/src/service/status_service.rs`
- Create: `native/src/api/status_api.rs`
- Modify: `native/src/domain/mod.rs`
- Modify: `native/src/service/mod.rs`
- Modify: `native/src/api/mod.rs`
- Modify: `native/src/lib.rs`
- Create: `lib/src/features/changes/changes_controller.dart`
- Create: `lib/src/features/changes/changes_screen.dart`
- Create: `lib/src/features/changes/change_group.dart`
- Create: `lib/src/features/changes/change_row.dart`
- Test: `native/tests/status_snapshot.rs`
- Test: `test/features/changes/changes_screen_test.dart`

- [ ] **Step 1: Write failing status parser tests**

Use byte fixtures containing NUL-delimited porcelain v2 records for ordinary, renamed, copied, untracked, conflicted, detached HEAD, unborn branch, upstream, and ahead/behind states. Include tabs and newlines in path bytes and a Unix-gated non-UTF-8 path fixture. Assert that display paths are separate from opaque change IDs and that staged and unstaged facets are preserved independently.

- [ ] **Step 2: Run and observe parser failure**

Run:

    rtk cargo test --manifest-path native/Cargo.toml --test status_snapshot

Expected: FAIL because `parse_status_v2` is absent.

- [ ] **Step 3: Implement status parsing and snapshot identity**

Run `git -c core.quotepath=false status --porcelain=v2 -z --branch`. Parse bytes without locale assumptions. Store raw path bytes and status facets in the repository registry, expose only lossy display paths and change IDs, hash the normalized snapshot, and increment generation only when repository state changes.

- [ ] **Step 4: Write failing Changes-screen tests**

Test group order `Conflicts, Staged, Unstaged, Untracked`, empty repository state, selection preservation across equal snapshots, selection clearing for removed IDs, and stale generation response rejection.

- [ ] **Step 5: Implement status controller and polling**

Use a Riverpod controller with explicit `loading/data/error` states. Refresh on open, app foreground, mutation completion, manual refresh, and a 3-second active timer. Skip polling while a request or mutation is active and avoid replacing state when snapshot hash is unchanged.

- [ ] **Step 6: Implement the grouped Changes UI**

Render semantic group labels, file status icon plus text, multi-selection, branch/upstream/ahead/behind summary, and a no-changes state. No stage/discard buttons become active until their API tasks are implemented.

- [ ] **Step 7: Verify and commit**

Run:

    rtk cargo test --manifest-path native/Cargo.toml --test status_snapshot
    rtk flutter test test/features/changes/changes_screen_test.dart
    rtk flutter analyze

Expected: all tests pass.

Commit:

    rtk git add native lib test
    rtk git commit -m "feat: show typed repository changes"

## Task 6: Parse and display bounded unified diffs

**Files:**
- Create: `native/src/domain/diff.rs`
- Create: `native/src/parser/diff.rs`
- Create: `native/src/service/diff_service.rs`
- Create: `native/src/api/diff_api.rs`
- Modify: `native/src/domain/mod.rs`
- Modify: `native/src/parser/mod.rs`
- Modify: `native/src/service/mod.rs`
- Modify: `native/src/api/mod.rs`
- Create: `lib/src/features/diff/diff_controller.dart`
- Create: `lib/src/features/diff/unified_diff_view.dart`
- Create: `lib/src/features/diff/diff_hunk_view.dart`
- Test: `native/tests/file_diff.rs`
- Test: `test/features/diff/unified_diff_view_test.dart`

- [ ] **Step 1: Write failing diff tests**

Cover added/deleted/context lines, old/new line numbering, no-newline markers, rename headers, binary output, invalid/stale change IDs, staged versus working-tree selection, a tracked path beginning with `-`, 5 MiB truncation, 20,000-line truncation, and a valid diff larger than the executor's 16 MiB capture ceiling that still returns a truncated preview rather than an overflow error.

- [ ] **Step 2: Run and observe failure**

Run:

    rtk cargo test --manifest-path native/Cargo.toml --test file_diff

Expected: FAIL because diff models and parser are absent.

- [ ] **Step 3: Implement diff lookup and parsing**

Resolve the selected change ID to stored raw paths. Use `git diff --no-ext-diff --no-color --find-renames` and add `--cached` only for the staged facet. Append an explicit `--` before every raw path argument so a leading-dash path can never become an option. Select executor `OutputPolicy::Stream`, parse stdout incrementally in Rust, stop retaining UI lines at 5 MiB or 20,000 lines, and continue draining the remaining stdout without retaining it until Git exits. Return `truncated` or `binary` explicitly; an arbitrarily larger valid diff must not become the executor's capture-overflow error.

- [ ] **Step 4: Write failing Flutter diff tests**

Test lazy hunk rendering, line numbers, non-color +/- semantics, binary notice, truncation banner, loading replacement on selection change, and stale response rejection.

- [ ] **Step 5: Implement the diff controller and viewer**

Keep one selected change ID, cancel or ignore its previous request, and render hunks with `ListView.builder`. Use a monospace system fallback without bundling a JetBrains font.

- [ ] **Step 6: Verify and commit**

Run:

    rtk cargo test --manifest-path native/Cargo.toml --test file_diff
    rtk flutter test test/features/diff/unified_diff_view_test.dart
    rtk flutter analyze

Expected: all commands exit 0.

Commit:

    rtk git add native lib test
    rtk git commit -m "feat: render bounded unified diffs"

## Task 7: Stage and unstage files through serialized mutations

**Files:**
- Create: `native/src/service/change_mutation_service.rs`
- Create: `native/src/api/change_mutation_api.rs`
- Modify: `native/src/state.rs`
- Modify: `native/src/service/mod.rs`
- Modify: `native/src/api/mod.rs`
- Modify: `lib/src/features/changes/changes_controller.dart`
- Modify: `lib/src/features/changes/change_row.dart`
- Test: `native/tests/stage_unstage.rs`
- Test: `test/features/changes/stage_actions_test.dart`

- [ ] **Step 1: Write failing real-Git mutation tests**

Create files containing spaces, a leading dash, Unicode, and shell metacharacters. Assert stage changes only selected IDs, unstage preserves working-tree content, a stale ID returns `StaleOpaqueId`, and two simultaneous mutations for one repository execute serially.

- [ ] **Step 2: Run and observe failure**

Run:

    rtk cargo test --manifest-path native/Cargo.toml --test stage_unstage

Expected: FAIL because mutation services are absent.

- [ ] **Step 3: Implement stage and unstage**

Hold the repository mutation mutex. Revalidate IDs against the current snapshot. Send NUL-delimited raw paths over stdin to `git add --pathspec-from-file=- --pathspec-file-nul` or `git restore --staged --pathspec-from-file=- --pathspec-file-nul`. On success increment generation and return a fresh snapshot.

- [ ] **Step 4: Write failing UI action tests**

Assert action availability by facet, multi-select behavior, disabled state while a mutation runs, selection cleanup after success, and typed error retention after failure.

- [ ] **Step 5: Implement action buttons and keyboard focus**

Add explicit Stage/Unstage controls and checkbox selection without making the entire row destructive. Use returned snapshots rather than optimistic staging.

- [ ] **Step 6: Verify and commit**

Run:

    rtk cargo test --manifest-path native/Cargo.toml --test stage_unstage
    rtk flutter test test/features/changes/stage_actions_test.dart

Expected: all tests pass.

Commit:

    rtk git add native lib test
    rtk git commit -m "feat: stage and unstage selected files"

## Task 8: Add safe discard preview and expiring confirmation

**Files:**
- Create: `native/src/domain/discard.rs`
- Create: `native/src/service/discard_service.rs`
- Create: `native/src/api/discard_api.rs`
- Modify: `native/src/domain/mod.rs`
- Modify: `native/src/service/mod.rs`
- Modify: `native/src/api/mod.rs`
- Create: `lib/src/features/changes/discard_dialog.dart`
- Modify: `lib/src/features/changes/changes_controller.dart`
- Test: `native/tests/discard.rs`
- Test: `test/features/changes/discard_dialog_test.dart`

- [ ] **Step 1: Write failing discard safety tests**

Cover tracked modified/deleted/type-changed files, staged+unstaged preservation, staged-only rejection, staged-added rejection after unstage, untracked/conflicted/renamed rejection, 60-second expiry, generation change, token replay, and token use against another repository. Drive expiry with an injected `Clock` and fake monotonic clock; do not sleep in tests.

- [ ] **Step 2: Run and observe failure**

Run:

    rtk cargo test --manifest-path native/Cargo.toml --test discard

Expected: FAIL because preview/token handling is absent.

- [ ] **Step 3: Implement `prepare_discard`**

Re-read status under the mutation lock, validate allowed facets, bind a cryptographically random token to repository ID, generation, exact change IDs, effect descriptions, and expiry, and store only a SHA-256 digest of the token in memory. Inject a monotonic `Clock` into the service so production uses real time and tests advance deterministically. Return the plain token only in `DiscardPreview`.

- [ ] **Step 4: Implement `discard_files`**

Consume the token exactly once, revalidate generation and facets, then run `git restore --worktree` with NUL pathspec input. Never call `git clean` or delete filesystem entries. Refresh status even after cancellation or partial Git failure.

- [ ] **Step 5: Write and implement the confirmation dialog**

Widget tests must assert the dialog lists discarded working-tree state and preserved staged state, requires explicit confirmation, disables itself after expiry, and shows why unsupported items cannot be discarded.

- [ ] **Step 6: Verify and commit**

Run:

    rtk cargo test --manifest-path native/Cargo.toml --test discard
    rtk flutter test test/features/changes/discard_dialog_test.dart

Expected: all tests pass.

Commit:

    rtk git add native lib test
    rtk git commit -m "feat: safely discard tracked worktree changes"

## Task 9: Commit staged changes and refresh state

**Files:**
- Create: `native/src/domain/commit.rs`
- Create: `native/src/service/commit_service.rs`
- Create: `native/src/api/commit_api.rs`
- Modify: `native/src/domain/mod.rs`
- Modify: `native/src/service/mod.rs`
- Modify: `native/src/api/mod.rs`
- Create: `lib/src/features/commit/commit_controller.dart`
- Create: `lib/src/features/commit/commit_panel.dart`
- Test: `native/tests/commit.rs`
- Test: `test/features/commit/commit_panel_test.dart`

- [ ] **Step 1: Write failing commit integration tests**

Assert empty/whitespace-only message rejection, no-staged-change rejection, multiline UTF-8 message preservation via `git commit -F -`, hook failure classification, missing user config classification, and fresh status/commit ID on success.

- [ ] **Step 2: Run and observe failure**

Run:

    rtk cargo test --manifest-path native/Cargo.toml --test commit

Expected: FAIL because commit service is absent.

- [ ] **Step 3: Implement commit service**

Validate non-empty message and staged facets under the mutation lock. Pass the exact UTF-8 message through stdin, preserve hooks, classify stderr without logging the message, increment generation only on success, and return `CommitResult { object_id, snapshot }`.

- [ ] **Step 4: Write failing commit-panel tests**

Test disabled reasons, `Ctrl/Cmd+K` focus, `Ctrl/Cmd+Enter` submit, in-flight lockout, message preservation on failure, and clearing on success.

- [ ] **Step 5: Implement commit panel**

Connect staged count, message controller, platform shortcut intents, progress state, and returned snapshot. Do not add amend, sign, bypass-hook, or author override controls.

- [ ] **Step 6: Verify and commit**

Run:

    rtk cargo test --manifest-path native/Cargo.toml --test commit
    rtk flutter test test/features/commit/commit_panel_test.dart

Expected: all tests pass.

Commit:

    rtk git add native lib test
    rtk git commit -m "feat: commit staged changes"

## Task 10: Add paginated history, graph lanes, and historical diffs

**Files:**
- Create: `native/src/domain/history.rs`
- Create: `native/src/parser/log.rs`
- Create: `native/src/service/log_service.rs`
- Create: `native/src/service/graph_lanes.rs`
- Create: `native/src/api/log_api.rs`
- Modify: `native/src/domain/mod.rs`
- Modify: `native/src/parser/mod.rs`
- Modify: `native/src/service/mod.rs`
- Modify: `native/src/api/mod.rs`
- Create: `lib/src/features/log/log_controller.dart`
- Create: `lib/src/features/log/log_screen.dart`
- Create: `lib/src/features/log/commit_graph.dart`
- Create: `lib/src/features/log/commit_details_panel.dart`
- Test: `native/tests/log_history.rs`
- Test: `test/features/log/log_screen_test.dart`

- [ ] **Step 1: Write failing log and graph tests**

Build linear, branched, merged, root, and rename histories. Assert 200-item page boundaries, generation-bound cursors, topology order, stable lane assignment, refs, full commit message, per-parent file lists, root `parent_index=None`, non-root `Some(0)`, merge parent switching, and stale history file ID rejection.

- [ ] **Step 2: Run and observe failure**

Run:

    rtk cargo test --manifest-path native/Cargo.toml --test log_history

Expected: FAIL because log services are absent.

- [ ] **Step 3: Implement paginated log parsing**

Use `git log --topo-order` with explicit NUL separators and a `LogCursor { generation, skip }`. Reject cursors when generation changes. Parse parents and refs in Rust and compute graph lanes with deterministic tests.

- [ ] **Step 4: Implement commit details and historical diff APIs**

For root commits compare against the empty-tree object and require `None`. For other commits require an in-range parent index. Generate `HistoryFileChange` IDs bound to commit, chosen parent, paths, and generation; use those IDs for historical file diff. Historical diff invocation must put `--` after the base/commit revisions and before every stored raw path; add a leading-dash historical path fixture to enforce the boundary.

- [ ] **Step 5: Write failing Flutter history tests**

Test lazy pagination, selection, graph semantics independent of color, root/merge parent controls, detail loading, historical diff, stale page reset, and empty history.

- [ ] **Step 6: Implement the Log screen**

Render a lazy 200-item page, compact graph/subject/author/time rows, and a details panel. Reuse the unified diff view with a historical diff controller rather than duplicating diff widgets.

- [ ] **Step 7: Verify and commit**

Run:

    rtk cargo test --manifest-path native/Cargo.toml --test log_history
    rtk flutter test test/features/log/log_screen_test.dart

Expected: all tests pass.

Commit:

    rtk git add native lib test
    rtk git commit -m "feat: browse paginated git history"

## Task 11: List, create, and switch local/tracking branches

**Files:**
- Create: `native/src/domain/reference.rs`
- Create: `native/src/parser/refs.rs`
- Create: `native/src/service/branch_service.rs`
- Create: `native/src/api/branch_api.rs`
- Modify: `native/src/domain/mod.rs`
- Modify: `native/src/parser/mod.rs`
- Modify: `native/src/service/mod.rs`
- Modify: `native/src/api/mod.rs`
- Create: `lib/src/features/branches/branch_controller.dart`
- Create: `lib/src/features/branches/branch_popup.dart`
- Test: `native/tests/branches.rs`
- Test: `test/features/branches/branch_popup_test.dart`

- [ ] **Step 1: Write failing branch integration tests**

Cover local/remote grouping, current branch, upstream and ahead/behind, ref-name validation, create from HEAD, dirty switch rejection, local switch, stale and cross-repository branch-ID rejection, remote selection that reuses an existing tracking branch, and remote selection that creates `git switch --track -c` without detached HEAD.

- [ ] **Step 2: Run and observe failure**

Run:

    rtk cargo test --manifest-path native/Cargo.toml --test branches

Expected: FAIL because ref parsing and services are absent.

- [ ] **Step 3: Implement typed branch IDs and mutations**

Parse `git for-each-ref` with explicit NUL-delimited fields. Store raw full refs behind opaque IDs. Validate proposed local names with `git check-ref-format --branch`. Revalidate the current snapshot before mutation and refresh branch/status data after success or failure.

- [ ] **Step 4: Write failing branch-popup tests**

Test search, local/remote grouping, current indicator, create validation, dirty error, tracking confirmation, and keyboard navigation.

- [ ] **Step 5: Implement the branch popup**

Use local switch for local IDs. For remote IDs, show the proposed local name and call `create_tracking_branch_and_switch` only after confirmation. Never expose a detached checkout action.

- [ ] **Step 6: Verify and commit**

Run:

    rtk cargo test --manifest-path native/Cargo.toml --test branches
    rtk flutter test test/features/branches/branch_popup_test.dart

Expected: all tests pass.

Commit:

    rtk git add native lib test
    rtk git commit -m "feat: create and switch git branches"

## Task 12: Stream, cancel, and classify remote operations

**Files:**
- Create: `native/src/domain/remote.rs`
- Create: `native/src/service/remote_service.rs`
- Create: `native/src/service/operation_service.rs`
- Create: `native/src/executor/process_group.rs`
- Modify: `native/src/executor/process_runner.rs`
- Create: `native/src/parser/progress.rs`
- Create: `native/src/api/remote_api.rs`
- Modify: `native/src/domain/mod.rs`
- Modify: `native/src/executor/mod.rs`
- Modify: `native/src/parser/mod.rs`
- Modify: `native/src/service/mod.rs`
- Modify: `native/src/api/mod.rs`
- Create: `lib/src/features/remotes/remote_controller.dart`
- Create: `lib/src/features/remotes/upstream_dialog.dart`
- Create: `lib/src/shared/widgets/operation_bar.dart`
- Test: `native/tests/remotes.rs`
- Test: `native/tests/operation_cancel.rs`
- Test: `test/features/remotes/remote_actions_test.dart`

- [ ] **Step 1: Write failing remote-ID and local-bare-remote tests**

Test typed remote listing, redacted URLs, stale/cross-repository ID rejection, fetch, fast-forward-only pull, non-fast-forward refusal, normal push, first upstream push, upstream absence, detached HEAD refusal, and multiple remote selection. Reject empty, leading-dash, traversal-like, whitespace-invalid, and syntactically invalid remote branch names before push. For Fetch, assert the current upstream's remote is preferred, a sole remote is selected automatically, no-remotes disables the action, and multiple remotes without an upstream require an explicit `RemoteId`.

- [ ] **Step 2: Write failing cancellation and prompt-isolation tests**

Use a test child process that streams progress and waits. Assert bounded event delivery, cancel terminates the whole process tree, completion is terminal and emitted once, a subscriber created after immediate completion still receives that terminal state, stdin is closed, `GIT_TERMINAL_PROMPT=0` is present, and the remote process has no controlling terminal/console. Test authentication and permission stderr classification using synthetic fixtures with secrets that must be redacted.

- [ ] **Step 3: Run and observe failure**

Run:

    rtk cargo test --manifest-path native/Cargo.toml --test remotes
    rtk cargo test --manifest-path native/Cargo.toml --test operation_cancel

Expected: FAIL because remote/operation services are absent.

- [ ] **Step 4: Implement operation registry and platform process groups**

Create a Tokio `watch` channel containing the latest `OperationSnapshot` and a cancellation token for each `OperationId`. Register and expose the watch receiver before spawning the child; a late subscriber must immediately receive the latest progress or terminal snapshot. Keep a fixed-size redacted diagnostic tail separately, and retain terminal registry entries for the application session so fast completion cannot race subscription. Do not use a replay-free broadcast channel as the sole lifecycle source.

On Unix call `setsid` before exec and terminate the process group with TERM then KILL after a short grace period. On Windows create a Job Object with `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`, assign the child before reporting `Started`, use a new process group without a console, and terminate the Job Object on cancel. Close stdin for remote operations and preserve configured credential-helper, AskPass, and SSH-agent environments.

- [ ] **Step 5: Implement remote services**

`list_remotes` returns opaque IDs and redacted URLs. Implement `fetch(remote_id)`, upstream-only `pull_ff_only`, normal `push`, and `push_set_upstream(remote_id, remote_branch_name)`. Before constructing a refspec, Rust must reject empty/leading-dash input and validate `refs/heads/<remote_branch_name>` with a shell-free `git check-ref-format` invocation; use only that validated full ref in the push argv. Revalidate repository, local branch, upstream, and opaque remote immediately before execution, terminate Git options explicitly before remote/refspec operands, and never add force, rebase, merge, or auto-stash flags.

- [ ] **Step 6: Write failing Flutter remote-action tests**

Test toolbar enablement, Fetch's upstream/sole-remote automatic choice, the multiple-remote Fetch chooser, no-remote disablement, single/multiple remote upstream dialog, progress updates, error drawer, cancel, completion refresh, and no credential input UI.

- [ ] **Step 7: Implement remote UI and operation bar**

Add Fetch/Pull/Push to the top bar, a typed remote chooser, an upstream confirmation dialog, and an operation drawer. Fetch uses the current branch's upstream remote when present, otherwise the sole remote; when multiple remotes remain it opens the chooser and passes the selected opaque `RemoteId`. With no remotes it is disabled with an explanation. Treat external helper GUI waits as cancellable running operations.

- [ ] **Step 8: Verify and commit**

Run:

    rtk cargo test --manifest-path native/Cargo.toml --test remotes
    rtk cargo test --manifest-path native/Cargo.toml --test operation_cancel
    rtk flutter test test/features/remotes/remote_actions_test.dart

Expected: all tests pass and synthetic secret values are absent from captured diagnostics.

Commit:

    rtk git add native lib test
    rtk git commit -m "feat: add cancellable git remote workflows"

## Task 13: Finish the minimal responsive desktop experience

**Files:**
- Create: `lib/src/app/app_theme.dart`
- Create: `lib/src/app/app_shortcuts.dart`
- Create: `lib/src/app/workspace_shell.dart`
- Create: `lib/src/shared/error/error_presenter.dart`
- Create: `lib/src/shared/widgets/error_drawer.dart`
- Create: `lib/src/shared/widgets/copy_diagnostic_button.dart`
- Modify: `lib/src/app/branchline_app.dart`
- Test: `test/app/workspace_shell_test.dart`
- Test: `test/app/app_shortcuts_test.dart`
- Test: `test/app/theme_golden_test.dart`

- [ ] **Step 1: Write failing layout, theme, and accessibility tests**

At wide width assert Changes/Diff/Commit three-column layout. At narrow width assert commit moves to a drawer. Test Changes/Log navigation, system/light/dark themes, semantic labels that do not rely on color, keyboard focus order, all shortcuts from design section 9.3, and copying the complete redacted diagnostic through Flutter's clipboard API.

- [ ] **Step 2: Run and observe failure**

Run:

    rtk flutter test test/app

Expected: FAIL because workspace shell/theme/shortcuts are incomplete.

- [ ] **Step 3: Implement the workspace shell**

Use Material 3 with low elevation, no gradients, restrained animation, and system fonts. Keep repository/branch/actions in the top bar, Changes/Log as the only primary tabs, progress/errors in the bottom region, and responsive breakpoints covered by tests.

- [ ] **Step 4: Implement error presentation and shortcuts**

Map every Rust category to a short action-oriented message and a collapsible redacted diagnostic. Add an explicit `Copy Details` button that writes only the already-redacted diagnostic to `Clipboard` and confirms success without exposing commit messages, raw paths, or credential-bearing URLs. Map Ctrl to Cmd on macOS where specified, preserve F5 on Windows/Linux, display the actual platform shortcut in tooltips, and ensure Escape cancels only the active cancellable operation.

- [ ] **Step 5: Run full application verification**

Run:

    rtk dart format --output=none --set-exit-if-changed lib test integration_test
    rtk flutter analyze
    rtk flutter test
    rtk cargo fmt --manifest-path native/Cargo.toml -- --check
    rtk cargo clippy --manifest-path native/Cargo.toml --all-targets -- -D warnings
    rtk cargo test --manifest-path native/Cargo.toml

Expected: formatting, analysis, clippy, and all tests pass.

- [ ] **Step 6: Commit**

    rtk git add lib test
    rtk git commit -m "feat: finish minimal desktop git workspace"

## Task 14: Add three-OS CI, packaging, smoke tests, and macOS ad-hoc signing

**Files:**
- Create: `integration_test/app_smoke_test.dart`
- Create: `tool/verify.ps1`
- Create: `tool/verify.sh`
- Create: `tool/package_windows.ps1`
- Create: `tool/package_linux.sh`
- Create: `tool/package_macos.sh`
- Create: `.github/workflows/ci.yml`
- Create: `.github/workflows/release.yml`
- Create: `docs/release/macos-ad-hoc.md`
- Create: `docs/release/linux.md`
- Create: `docs/release/windows.md`

- [ ] **Step 1: Write a failing bridge smoke test**

The test must initialize the real Rust bridge, create a temporary Git repository, open it, create and stage a file through the public APIs, commit it, and assert the Changes screen becomes clean. It must not use network credentials.

- [ ] **Step 2: Run it on the current desktop and observe failure**

Run the command for the current OS:

    rtk flutter test integration_test/app_smoke_test.dart -d windows

Use `-d macos` or `-d linux` on those platforms. Expected: FAIL until the bridge smoke harness and platform native library integration are complete.

- [ ] **Step 3: Complete platform bridge integration**

Update the generated Windows, macOS, and Linux build files only as required by the FRB generator. Make the smoke test pass on the current OS, then run it on all three CI runners. Do not add a WebView or Tauri dependency.

- [ ] **Step 4: Add equivalent local verification scripts**

Both scripts must run Dart formatting, Flutter analysis/tests, Rust formatting/clippy/tests, bridge generation drift detection, and the current-OS desktop build. Generated bindings must be regenerated into a temporary copy or checked with a clean Git diff so stale bindings fail verification.

- [ ] **Step 5: Add CI**

`ci.yml` must use a Windows, macOS, and Ubuntu matrix; install pinned versions recorded in `tool/versions.json`; cache Pub/Cargo downloads; run verification; build the native desktop target; and upload test logs only on failure. Linux desktop integration runs under Xvfb.

- [ ] **Step 6: Implement Windows and Linux packaging**

Windows script runs `flutter build windows --release` and creates a portable x64 ZIP containing the complete runner directory. Linux script runs `flutter build linux --release`, creates a `.deb` with declared GTK dependencies, and creates an AppImage using pinned packaging tools. Each script emits SHA-256 checksums and fails if `git --version` detection cannot run in the packaged app smoke test.

- [ ] **Step 7: Implement macOS universal packaging and inside-out ad-hoc signing**

Run `flutter build macos --release` and verify the app's Flutter and Rust Mach-O slices include both `arm64` and `x86_64`. Enumerate nested frameworks, dylibs, and helper executables; sign each inner Mach-O with `codesign --force --sign -`; sign `Branchline.app` last; verify with:

    codesign --verify --deep --strict --verbose=2 build/macos/Build/Products/Release/Branchline.app

Create the DMG only after verification. Do not use `--deep` as the signing mechanism, remove quarantine attributes, modify Gatekeeper, claim notarization, or add a self-signed identity.

- [ ] **Step 8: Write truthful release documentation**

`macos-ad-hoc.md` must state: “ad-hoc signed, not Developer ID signed, and not notarized”; explain Finder right-click → Open and Privacy & Security → Open Anyway; and explain that future Developer ID signing/notarization is a separate release enhancement. Document Linux dependencies and Windows portable-ZIP extraction separately.

- [ ] **Step 9: Add release workflow**

On a version tag, build each artifact on its native runner, execute its packaging script, upload checksums, and keep platform artifacts separate. The workflow must not require Apple signing secrets for the MVP and must fail if macOS signature verification or any smoke test fails.

- [ ] **Step 10: Run final verification**

Run on each OS:

    rtk flutter analyze
    rtk flutter test
    rtk cargo test --manifest-path native/Cargo.toml
    rtk cargo clippy --manifest-path native/Cargo.toml --all-targets -- -D warnings
    rtk flutter build windows --release

Substitute `macos` or `linux` for the build target on those runners. Also run the matching package script and integration smoke test. Expected: every command exits 0 and expected artifacts/checksums exist.

- [ ] **Step 11: Commit**

    rtk git add integration_test tool .github docs/release
    rtk git commit -m "build: package branchline for three desktop platforms"

## Final acceptance checklist

- [ ] Run `tool/verify.ps1` on Windows and `tool/verify.sh` on macOS/Linux.
- [ ] Confirm Git 2.35 minimum detection and custom Git-path selection.
- [ ] Confirm all `STATUS/DIFF/STAGE/DISCARD/COMMIT/LOG/BRANCH/REMOTE` behavior IDs have passing Rust or Flutter tests.
- [ ] Confirm special-path and stale-ID security fixtures pass.
- [ ] Confirm local-bare-remote fetch/pull/push tests need no external network or credential.
- [ ] Confirm no force push, auto-stash, merge/rebase UI, credential input, updater, or JetBrains asset entered the build.
- [ ] Confirm Windows ZIP, Linux AppImage/DEB, macOS universal DMG, and SHA-256 checksums are produced.
- [ ] Confirm macOS nested signatures and outer ad-hoc signature pass `codesign --verify --deep --strict`.
- [ ] Confirm release text says the macOS artifact is not Developer ID signed or notarized and requires user-approved first launch.
- [ ] Run `rtk git status --short` and require an empty working tree after the final commit.
