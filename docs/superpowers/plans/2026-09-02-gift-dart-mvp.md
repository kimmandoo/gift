# Gift Dart MVP Implementation Plan

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
- `lib/src/backend/commit.dart` — commit ID and post-commit status result.
- `lib/src/backend/history.dart` — bounded commit records and graph lanes.
- `lib/src/backend/error.dart` — typed Git error categories.
- `lib/src/backend/executor.dart` — direct process runner, bounded output, and
  redaction.
- `lib/src/backend/git_installation_service.dart` — Git discovery, version
  parsing, and explicit path validation.
- `lib/src/backend/repository_service.dart` — repository root validation and
  opaque handle registry.
- `lib/src/backend/status.dart` — porcelain v2 parser, change facets, and
  generation-aware snapshots.
- `lib/src/backend/discard.dart` — path-bound discard preview value object.
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
- [x] Serialized stage/unstage mutations with refreshed status snapshots and
  selection actions.
- [x] Expiring path-bound discard previews, safe restore, and confirmation UI.
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

## Completed vertical: staging and mutation

1. Added failing tests for staging and un-staging selected paths.
2. Implemented serialized `git add` and `git restore --staged` operations.
3. Added selection-aware actions and refreshed the status snapshot after
   mutation.
4. Passed `flutter analyze` and `flutter test`.

## Completed vertical: discard changes

1. Added failing tests for preview tokens and tracked working-tree discard.
2. Implemented expiring, path-bound discard operations.
3. Added a confirmation dialog and refreshed the selected change after discard.
4. Passed `flutter analyze` and `flutter test`.

## Completed vertical: commit panel

1. Added real Git coverage for UTF-8 commit messages and rejected hooks.
2. Implemented serialized `git commit --file=-` with UTF-8 stdin, staged
   preflight, post-commit status, and typed hook errors.
3. Added a staged-only commit editor with loading, success, error, and clean
   state feedback.
4. Passed `flutter analyze` and the backend and Changes screen tests.

## Completed vertical: history and graph

1. Added parser and real Git tests for bounded pages, metadata, and merge
   parents.
2. Implemented bounded `git log` pages with deterministic graph lane slots.
3. Added a History screen with commit details, selection, and load-more state.
4. Passed `flutter analyze`, history tests, and the backend suite.

## Completed vertical: branch management

1. Added parser and real Git tests for local refs, invalid names, and branch
   switches.
2. Implemented validated branch listing, creation, and serialized switching.
3. Added a current-branch popup with create, switch, loading, and error states.
4. Passed `flutter analyze`, branch tests, and the backend suite.

## Completed vertical: remotes and cancellation

1. Added parser, local-remote, cancellation, and remote popup tests.
2. Implemented cancellable fetch, pull, and push with serialized remote
   mutations and typed failure mapping.
3. Added remote URL redaction, progress, cancellation, and refresh feedback.
4. Passed `flutter analyze`, remote tests, and the backend suite.

## Completed vertical: UX and pixel theme

1. Added theme, focus, shortcut, and responsive layout tests.
2. Applied the dark pixel palette and shared shell components.
3. Added keyboard-first navigation, responsive layouts, and diagnostic
   feedback polish.
4. Passed `flutter analyze`, the full Flutter test suite, and responsive widget
   tests.

## Completed vertical: packaging and CI

1. Added a cross-platform Dart verification entry point.
2. Added desktop build helpers and CI coverage for Linux, macOS, and Windows.
3. Documented local verification and release artifact creation.
4. Passed the local verification command, desktop build, and Linux integration
   smoke test.

## Completed vertical: hardening and product identity

1. Added regression tests for process deadlines, discard revocation, history
   page lane continuity, canonical Git settings, and controller disposal.
2. Added non-interactive bounded process execution and deterministic
   completion-versus-cancellation reporting.
3. Unified package and native desktop metadata under the `gift` identity.
4. Full verification passed. The Linux native bundle check was marked safe
   done under WSL and delegated to CI because this host cannot provide
   `libgtk-3-dev` without an available sudo password.

## Completed UI stabilization pass

1. Replaced commit-only graph markers with typed row segments for incoming
   lines, continuations, forks, merges, lane shifts, and wide-graph spacing.
2. Added persisted light/dark themes and bundled the readable OFL Jersey 15
   pixel font with an explicit desktop type scale.
3. Added compact-window handling for core screens, commit controls, and
   operation dialogs.
4. Generated macOS and Windows release icon resources from the canonical
   `assets/images/gift_icon.png` source.
5. Passed full formatting, analysis, and all 70 tests; Linux release
   compilation still awaits the host GTK development package.

## Completed vertical: multi-repository workspace

1. Recorded workspace restoration, tab lifecycle, duplicate-path,
   missing-folder, and cross-repository mutation isolation scenarios in the
   behavior ledger.
2. Added the first failing workspace-store/controller test before implementing
   persistence or tab state.
3. Implemented canonical-path workspace persistence with session-local opaque
   handles and independent per-tab controllers.
4. Added a responsive tab shell with open, close, reorder, and keyboard
   actions.
5. Passed formatting, analysis, the full Flutter test suite, and responsive
   workspace widget tests. Task 17 followed this vertical.

## Completed vertical: hunk and line staging

1. Recorded partial-stage behavior for hunk selection, line selection,
   stale diffs, binary/rename-only files, and rejected patches.
2. Added parsed hunk models and machine-owned selections bound to repository,
   path, scope, and diff content hash.
3. Implemented forward working-tree staging and reverse staged unstage with
   serialized `git apply --cached` stdin and direction-aware replacement-line
   handling.
4. Added hunk/line controls, Shift+Space range selection, compact scrolling,
   typed failure recovery, and beginner-oriented flow documentation.
5. Passed the partial-staging backend fixtures, full Flutter test suite,
   formatting, analysis, and responsive Changes screen coverage. Task 17 is
   complete; Task 18 is next.

## Completed vertical: complete commit workflow

1. Recorded identity preflight, commit options, template reset, amend warning,
   and history-change outcome scenarios in the behavior ledger.
2. Added failing real-Git coverage for empty messages and staged sets, missing
   identity, amend on an unborn branch, UTF-8, sign-off/cleanup/author options,
   templates, rejected hooks, and configured signing failures.
3. Implemented typed commit options and preflight, bounded template loading,
   redacted failure classification, and refresh outcome tracking.
4. Added a collapsible guided options panel and responsive widget coverage.
5. Passed the commit workflow backend tests, full Flutter test suite,
   formatting, and analysis. Task 18 is complete; Task 19 is next.

## Completed vertical: searchable history and commit inspection

1. Added a snapshot-bound history query with validated text, author, date, ref,
   and path filters; page cursors remained tied to the original ref tips.
2. Added bounded commit-file and selected-file diff contracts for root, merge,
   deleted, and binary changes.
3. Added request-generation guards, ref/parent navigation, copyable OIDs, and
   keyboard traversal to the History controller and screen.
4. Passed filter determinism, live-ref movement, UTF-8 metadata, and stale
   selection response coverage with real-Git and widget tests. Task 19 is
   complete; Task 20 is next.

## Completed vertical: safe advanced branch operations

1. Recorded branch rename/delete, merge, rebase, and cherry-pick behavior with
   explicit preflight and recovery scenarios.
2. Added the first failing real-Git test for expiring preview tokens, Git-backed
   branch-name validation, and a fast-forward operation.
3. Implemented preview-bound branch mutations and explicit
   start/continue/skip/abort states with typed dirty, detached, conflict,
   cancellation, and stale-preview outcomes.
4. Added responsive branch-operation controls and widget coverage.
5. Focused backend/UI tests passed; the full suite completed with 109 passing
   and the two documented Windows-platform expectation failures.

## Completed vertical: conflict resolution workspace (Task 21)

1. Recorded conflict inspection, side selection, explicit mark-resolved,
   operation recovery, stale fingerprints, and add/add, modify/delete,
   rename-related, and binary scenarios in the behavior ledger.
2. Added the first failing test for parsing Git's unmerged index stages before
   introducing the conflict workspace contract.
3. Implemented a bounded conflict snapshot, explicit operation metadata, and
   fingerprint-guarded resolution mutations.
4. Added controller and responsive three-pane UI coverage and verified the
   full suite. Task 21 is complete; Task 22 is next.

## Follow-up repair: history graph compatibility

1. Added regression coverage for Git's line ending after record separators,
   merge topology in a single-tip view, and annotated tag refs pointing at
   historical commits.
2. Normalized history record OIDs, peeled annotated tags to commit tips, and
   limited the single-lane optimization to genuinely linear pages.
3. Passed the focused history parser/exploration tests and retained the full
   graph lane recomputation across pagination.

## Completed vertical: Git object management (Task 22)

1. Recorded stash identity/apply/drop/branch flows, lightweight and annotated
   tags, remote configuration/prune, explicit tag push, and upstream tracking
   scenarios in the behavior ledger.
2. Added the first failing parser test for stable stash/tag object identities
   before introducing the object-management contract.
3. Implemented bounded stash/tag/ref models and a shared confirmation preview
   contract before adding serialized Git mutations.
4. Added focused object-management dialogs and upstream feedback, including
   credential-safe remote display and stateful remote selection.
5. Passed focused backend/UI tests, formatting, analysis, and the full suite.
   Task 22 is complete.

## Active vertical: Diff and comparison workbench (Task 23)

1. Audited the public IntelliJ IDEA Git workflow documentation against the
   completed Tasks 1–22 and recorded the missing comparison, shelf, history,
   reset, rebase, remote-branch, worktree, metadata, recovery, setup, and
   optional hosting scenarios in the behavior ledger.
2. Added Tasks 23–35 to the post-MVP roadmap in dependency order, then moved
   the existing scale, accessibility, and release work to Tasks 36–38.
3. Activated Task 23 after recording its revision, branch, folder, and
   three-way comparison scenarios.
4. Added the first RED comparison test; it failed because the comparison
   contract and backend methods did not exist. Implemented the bounded model,
   revision/folder diff, selected-file loading, and responsive workbench.
5. Passed the focused comparison backend/UI tests, formatting, analysis, and
   the full Flutter suite. Task 23 remains active for clipboard/external-text,
   and three-way flows; keep Task 24 planned until that work is complete.
6. Added a RED real-Git transfer fixture; it initially failed because the
   comparison transfer action and backend contract did not exist.
7. Implemented reviewed Apply and Revert actions from parsed backend diffs,
   checked the patch before mutation, refreshed status, and passed the focused
   transfer and compact dialog tests. Continue with clipboard/external-text
   and three-way sources.
