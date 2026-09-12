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

## Completed vertical: Diff and comparison workbench (Task 23)

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
   the full Flutter suite.
6. Added a RED real-Git transfer fixture; it initially failed because the
   comparison transfer action and backend contract did not exist.
7. Implemented reviewed Apply and Revert actions from parsed backend diffs,
   checked the patch before mutation, refreshed status, and passed the focused
   transfer and compact dialog tests. Continue with clipboard/external-text
   and three-way sources.
8. Added bounded clipboard/external-text source contracts, hashed external
   content identities, synthetic text diffs, and three-way base/left/right
   content snapshots with explicit binary, missing, unreadable, and oversized
   states.
9. Added compact external-source entry, clipboard paste, three-way panes,
   conflict indication, and keyboard-friendly changed-file navigation. Added
   backend and widget fixtures for external text, three-way conflict content,
   repeated file navigation, and rejection of non-historical transfers.
10. Passed the focused comparison backend/UI tests, formatting, analysis, and
    the full Flutter suite. Task 23 is complete.

## Completed vertical: Shelves, changelists, and patch exchange (Task 24)

1. Activated Task 24 after recording the changelist, shelf, repeated
   unshelving, external patch, base-loss, and no-stash-mutation scenarios in
   the behavior ledger.
2. Added a RED fixture for persistence, reusable shelf application, repeated
   unshelving conflict, and the missing shelf contract before implementation.
3. Implemented app-local JSON shelf storage below Git metadata, validated
   changelist mutations, selected tracked-path shelving, reusable
   unshelving/restoration, base-loss reporting, and bounded patch exchange.
4. Added compact shelf/changelist controls and explicit stash/unversioned
   semantics, then passed shelf backend/UI fixtures, analysis, formatting, and
   the full Flutter suite (`140` tests). Task 24 is complete.

## Completed vertical: File history, blame, and revision recovery (Task 25)

1. Activated Task 25 after recording file, directory, line-range, rename,
   binary, and stale-selection scenarios in the behavior ledger.
2. Added the first RED file-history/blame contract test before introducing the
   bounded history and annotation models.
3. Added the first RED fixture; it failed because the file-history model and
   gateway methods did not exist. Implemented bounded file/directory/selection
   history, rename metadata, line-porcelain blame parsing, and typed blame
   movement options.
4. Added compact history/blame controls and a fingerprint-guarded
   Get-from-Revision action with explicit missing, binary, oversized, and stale
   outcomes. Passed the focused backend/UI tests, formatting, analysis, and
   the full Flutter suite. Task 25 is complete.

## Completed follow-up: gift product-identity logo refresh

1. Generated and inspected an original transparent 2D pixel-art chubby Shiba
   Inu face wearing a gift ribbon, preserving the `gift` identity formed from
   Git + Flutter.
2. Rebuilt `assets/images/gift_logo.png` from the canonical mascot and
   regenerated the Windows ICO and macOS AppIcon PNG sizes.
3. Updated README, release documentation, architecture notes, task records,
   changelog, and this checkpoint to describe the new product identity.

## Completed vertical: Undo, reset, and revert safety (Task 26)

1. Activated Task 26 after recording reset impact, unpushed undo, revert
   conflict, protected-branch, and stale-confirmation scenarios in the
   behavior ledger.
2. Added the first RED reset fixture; it fails until the typed rollback preview
   and backend gateway contract exist.
3. Implemented typed reset, undo, and revert models, short-lived stale-bound
   previews, protected/pushed/dirty/detached/in-progress preflight, and
   explicit revert conflict recovery.
4. Added the responsive preview-first rollback dialog to Changes and History;
   hard reset execution requires a separate acknowledgement after preview.
5. Added real-Git and widget coverage for all reset modes, multi-commit revert,
   undo preservation, conflict recovery, safety refusals, stale previews, and
   the full rollback UI. Passed formatting, analysis, the full Flutter suite,
   and all 151 tests. Task 26 is complete.

## Completed follow-up: History commit-file viewer polish

1. Replaced the plain selected-file diff text with a file-aware diff card
   rendered directly below the selected file row.
2. Added addition/deletion totals, copyable diff text, old/new line numbers,
   semantic line colors, selectable content, and bounded independent scrolling.
3. Added widget regression coverage and passed the focused History tests.
4. Added a recent-commit target picker for rollback, automatically selecting
   the current commit's parent while retaining an Advanced revision escape
   hatch for branches and special expressions.

## Completed follow-up: repository UI polish

1. Unified History detail scrolling so the commit detail pane owns vertical
   movement and the diff card only scrolls horizontally for long code lines.
2. Automatically revealed the selected file's diff near the file row and
   clarified search, restore, stash, empty-state, and status-summary copy.
3. Hardened compact app-bar and dialog layouts, then passed repository widget
   tests, analysis, formatting, and the full Flutter suite.
4. Unified historical diff row backgrounds to the widest rendered line and
   covered the short-line/long-line width invariant in a widget test.

## Completed vertical: Interactive rebase and history rewriting (Task 27)

1. Activated Task 27 after recording plan editing, action validation,
   protected-state, option, and continue/skip/abort recovery scenarios in the
   behavior ledger.
2. Added the first RED test for an immutable plan that preserves original
   commit OIDs and positions while allowing reorder and action edits.
3. Implemented the typed plan model for pick, reword, edit, squash, fixup,
   drop, autosquash, root, and update-refs, including duplicate identity,
   invalid OID, root/upstream, and squash/fixup sequence validation.
4. Added a RED real-Git preview fixture; it covered a clean linear branch,
   dirty and detached worktrees, protected and pushed branches, in-progress
   operation metadata, and a plan that no longer matched the captured range.
5. Implemented repository-state-bound preview tokens and exposed the preview
   through the backend and `GitGateway`; the focused fixture, analysis,
   formatting, and full test suite passed.
6. Added RED real-Git execution fixtures for reorder, edit pause/continue,
   squash/fixup/drop, abort, and stale-preview rejection.
7. Implemented machine-owned todo injection, persistent recovery refs,
   rewritten-OID reporting, and explicit continue/skip/abort recovery states.
8. Added a History interactive-rebase dialog with upstream selection,
   reorder/action controls, preview, execution, and recovery actions.
9. Added conflict, hook rejection, cancellation, root/update-refs limitation,
   recovery-ref, and reachable-history fixtures, plus a narrow-layout Cancel
   control test.
10. Added reviewed reword subjects and pause-reason reporting for edit,
    conflict, hook, and cancellation states. Passed the full Flutter suite;
    Task 27 is complete. Task 28 remains pending activation.

## Completed follow-up: interactive UI layout audit

1. Audited repository workflow controls at compact desktop widths and enlarged
   text scales, focusing on input/action rows, dialog-title actions, dense
   checkboxes, and rebase plan rows.
2. Stacked History search and stash actions below their fields when space is
   constrained, and replaced the compact comparison mode label with a
   tooltip-backed icon action so it cannot cover the title.
3. Expanded the rebase upstream selector to constrain long commit labels and
   stacked move buttons in compact rows to preserve subject width.
4. Tightened conflict deletion control spacing and added widget assertions for
   non-overlapping and overflow-free layouts. Task 28 was then activated.

## Completed vertical: Remote branches and update project (Task 28)

1. Activated Task 28 after recording remote-ref grouping, remote checkout,
   tracking, divergence, local-change protection, update conflict, reset-to-
   remote, stale-ref, and incoming/outgoing refresh scenarios in the behavior
   ledger.
2. Added the first RED remote-branch/update fixture before introducing the
   backend contract, then proved it GREEN with real bare-remote fixtures.
3. Implemented grouped remote refs with tracking and incoming/outgoing counts,
   OID-bound remote checkout, compare entry points, remote deletion with a
   just-in-time published-tip check, and Update Project merge/rebase/reset,
   stash handling, stale previews, and conflict recovery.
4. Added responsive Branch and Changes controls plus focused tests for remote
   checkout, deletion confirmation, update choices, reset, stale state, and
   merge abort recovery. Task 28 is complete.

## Completed follow-up: History diff viewer UX after Task 28

1. The selected commit file diff must paint semantic backgrounds to the
   available viewer width, independently of the longest code line.
2. The selected file row must toggle the inline diff closed as well as open;
   long lines remain horizontally scrollable inside the detail pane.
3. Kept the vertical detail pane at its available width, moved only long code
   content into the horizontal scroller, and added regression coverage for
   full-width backgrounds and collapse behavior. Task 28 is fully complete;
   Task 29 is next.

## Completed follow-up: compact History and revision UI hardening

1. Reproduced compact-window failures with 320px-wide History, File History,
   and Advanced revision widget scenarios at enlarged text scales.
2. Bounded the History filter expansion and kept its fields vertically
   scrollable so the detail pane and status strip retain usable space.
3. Made File History results share one dialog scroll surface, constrained
   rollback controls to the available width, and ellipsized long labels and
   branch names.
4. Made the historical diff viewport derive its fallback width from the window
   instead of an arbitrary fixed width, and added compact regression coverage.
5. Kept diff backgrounds in a fixed viewport layer so horizontally scrolling a
   long line cannot expose its text against an uncolored strip.
6. Exposed a direct Push entry point from Changes while retaining the existing
   cancellable remote operation flow. The full Flutter suite passed; Task 29's
   remaining push-review work is still next.

## Completed vertical: Push safety (Task 29)

1. Activated Task 29 after recording push review, explicit target refspec,
   all-tags, expected remote tip, protected branch, rejection, and
   merge/rebase recovery scenarios in the behavior ledger.
2. Added the first RED test: `/home/mgkim/.local/flutter/bin/flutter test
   test/backend/push_test.dart` failed because the typed push preview contract
   did not exist yet.
3. Implemented the preview and execution contract, then added real bare-remote
   fixtures for normal publication, new target branches, selected commit
   targets, tags, stale remote tips, force-with-lease, protected branches, and
   rejection recovery.
4. Added the responsive Push review dialog, explicit force confirmation, and
   merge/rebase recovery entry points; routed Remote operations push actions
   through the same review flow.
5. Passed formatting, analysis, the focused push/UI tests, and the full suite
   of 187 Flutter tests. Task 30 is next.

## Completed vertical: Git worktrees (Task 30)

1. Activated Task 30 after recording linked worktree listing, add/open,
   occupied branches, dirty removal, lock state, missing-path prune,
   current/main protection, and cross-worktree isolation scenarios.
2. First RED test: `/home/mgkim/.local/flutter/bin/flutter test
   test/backend/worktree_test.dart` failed because the typed worktree contract
   had not been added yet.
3. Implemented NUL-delimited porcelain parsing, isolated add/open behavior,
   dirty/current/main/locked safety checks, expiring action previews, and
   stale-record pruning.
4. Added the responsive Worktree manager with compact add-form disclosure,
   state chips, dirty-removal confirmation, lock reason entry, and prune/open
   controls. Opening a linked root routes through WorkspaceController so it
   becomes an isolated repository tab.
5. Added real-Git fixtures for branch occupancy, cross-worktree status
   isolation, dirty confirmation, lock/unlock, current/main protection, and
   missing-path prune, plus compact scaled-text widget coverage. Focused tests,
   analysis, formatting, and the full Flutter suite passed. Task 30 is
   complete; Task 31 is next.

## Completed vertical: Ignore files and repository metadata (Task 31)

1. Activated Task 31 after recording nested ignore, negation, local exclude,
   tracked-modified, source-aware ignore, safe append, and attribute inspection
   scenarios as IGNORE-02/03/04.
2. First RED test: `/home/mgkim/.local/flutter/bin/flutter test
   test/backend/ignore_test.dart` failed because the typed ignore and
   attributes contract did not exist yet.
3. Implemented source-aware ignored/untracked/tracked-modified status,
   safe scoped metadata writes, bounded attribute inspection, and responsive
   metadata controls.
4. Added real-Git coverage for nested negation, local excludes, tracked
   modifications, source/pattern provenance, safe path validation, and
   attributes. Added compact 360x640/1.2x scaled-text UI coverage and fixed a
   narrow status-label overflow discovered by that test.
5. Verification passed formatting, analysis, focused backend/UI tests, and the
   full Flutter suite with 195 tests. Task 31 is complete; Task 32 is next.

## Completed vertical: Submodules and nested roots (Task 32)

1. Activated Task 32 after recording initialized/uninitialized, dirty,
   detached, changed-gitlink, recursive scope, and nested-root mapping
   scenarios as SUBMODULE-02/03/04.
2. First RED test: `/home/mgkim/.local/flutter/bin/flutter test
   test/backend/submodule_test.dart` failed because the typed submodule and
   nested-root contracts had not been added yet.
3. Implemented bounded `.gitmodules` parsing, recursive submodule status with
   initialized/uninitialized, dirty, detached, changed-gitlink, conflict, and
   missing states, plus explicit init, sync, update, and deinit actions.
4. Added independent nested-root mapping and a compact scaled-text manager
   with explicit all-versus-selected scope, lifecycle controls, and child-root
   opening through the workspace.
5. Added real-Git and widget coverage for child status isolation, changed
   gitlinks, detached and uninitialized states, lifecycle refresh, safe scope
   validation, and 360x640/1.2x rendering. Verification passed formatting,
   analysis, and the full Flutter suite with 197 tests. Task 32 is complete;
   Task 33 is next.

## Completed vertical: Recovery diagnostics (Task 33)

1. Activated Task 33 after recording reflog recovery, stale confirmation,
   operation history, output bounds, and credential-redaction scenarios as
   RECOVERY-02/03.
2. First RED test: `/home/mgkim/.local/flutter/bin/flutter test
   test/backend/recovery_test.dart` failed because the typed reflog, recovery
   branch, and operation-console contracts had not been added yet.
3. Implemented bounded reflog parsing, OID- and fingerprint-bound recovery
   branch previews, non-destructive branch creation, and a process-local
   redacted operation history that omits stdin.
4. Added the responsive Recovery diagnostics dialog with reflog selection,
   branch review/confirmation, and bounded operation records. Invalid refs,
   existing branch names, stale previews, and non-commit objects are rejected.
5. Added real-Git and widget coverage for recovery branch creation, operation
   output bounds, secret redaction, and compact 360x640/1.2x rendering.
   Verification passed formatting, analysis, and the full Flutter suite with
   200 tests. Task 33 is complete; Task 34 is next.

## Completed vertical: Repository setup (Task 34)

1. Activated Task 34 after recording clone/init, destination safety, shallow
   recovery, cancellation, and nested-root discovery scenarios as SETUP-02/03.
2. The first RED fixture failed before implementation because the typed setup
   and root-discovery contracts did not exist.
3. Implemented validated local/URL clone, empty-folder initialization,
   shallow-repository detection and unshallow recovery, bounded non-symlink
   nested-root discovery, and responsive Welcome/repository setup controls.
4. Verification passed formatting, analysis, and the full Flutter suite with
   203 tests. Task 34 is complete; Task 35 is now active.

## Completed vertical: Hosting integration (Task 35)

1. Activated Task 35 after recording provider parsing, credential redaction,
   hosted links, and optional review-handoff scenarios as HOST-02/03.
2. The first RED fixture failed before implementation because the typed
   hosting adapter and link contracts did not exist.
3. Implemented provider-neutral GitHub/GitLab adapters for SSH and HTTPS
   remotes, credential-free repository metadata, commit/file/blame links,
   and an explicit optional review capability. Unsupported hosts return an
   unavailable state without affecting local Git operations.
4. Added bounded responsive hosting controls with copy and browser-open
   actions, plus Changes and History entry points. Verification passed
   formatting, analysis, and the full Flutter suite with 206 tests. Task 35
   is complete; Task 36 is next.

## Completed follow-up: post-Task-35 UI/UX audit

1. Replaced the crowded Changes toolbar with one categorized repository
   actions menu, keeping sync/navigation, review/history, and repository tools
   discoverable without a row of competing icons.
2. Kept History's high-frequency rollback, rebase, hosting, and refresh
   actions visible while retaining keyboard shortcuts for navigation.
3. Improved the Welcome screen's primary action hierarchy and recent-repository
   cards so available, missing, and removable entries are easy to scan.
4. Added shared dialog and popup-menu surface spacing, stronger action padding,
   and safer compact sizing for hosting and repository setup flows.
5. Passed formatting, analysis, and the complete feature widget suite with
   69 tests. The repository-wide verification command completed formatting and
   analysis but retained 15 known Windows-only backend fixture failures
   (newline/path normalization, rebase process cleanup, and Windows file
   locking); no UI test failed.

## Completed follow-up: expandable controls and action visibility

1. Removed compact `ListTile` density from expandable controls where it could
   compress wrapped titles and subtitles into the tile bounds.
2. Kept advanced revision and commit options text fully readable, added
   expansion content breathing room, and tightened compact reset spacing so the
   control remains reachable before scrolling.
3. Restored History's rollback, rebase, hosting, and refresh actions directly
   to the app bar.
4. Exposed Push, Update project, Branches, and History directly on wider
   Changes toolbars while retaining the grouped menu below the compact
   breakpoint.
5. Passed focused Changes, History, and Reset widget tests.

## Completed follow-up: portable Windows packaging

1. Added an IExpress-based self-extracting Windows wrapper that embeds the
   complete Flutter Release bundle as a ZIP payload.
2. Added temporary extraction, process waiting, and cleanup so
   `gift-portable.exe` can be copied and launched as one file.
3. Kept the normal Release directory available for standard deployment and
   published both artifacts from the Windows CI job. Git remains a separate
   system dependency.

## Completed follow-up: Push review clarity

1. Added an upfront explanation that review performs no remote write and that
   the final Push action is the publishing step.
2. Reworked the preview card into explicit ready/blocked states with readable
   destination, commit, file, and remote-tip labels.
3. Renamed the actions to `Review changes` and `Push to <remote>` and covered
   the flow with a responsive widget test.

## Completed follow-up: dropdown label readability

1. Increased floating-label line height and shared input vertical padding so
   labels do not clip against dropdown borders.
2. Added narrow-window, larger-text Push coverage that verifies the Remote
   label remains inside the visible test surface.

## Completed follow-up: portable window and dropdown clipping

1. Replaced the portable package's visible CMD entry point with a Windows
   Script Host launcher so the PowerShell extraction process does not open a
   terminal window.
2. Increased shared floating-label line height and vertical input padding
   again, and removed the dense attribute dropdown override.
3. Verified Push, Ignore, Reset, Update Project, and Branch dialog layouts at
   narrow widths and larger text scales.

## Completed follow-up: dropdown and pixel button polish

1. Standardized dropdown option rendering with one-line ellipsis behavior
   across push, update, branch, ignore, rebase, object, and commit controls.
2. Replaced the initial heavy square-button treatment with a restrained
   hierarchy: solid primary actions, neutral outlined secondary actions,
   lightweight text/destructive actions, and borderless icon controls.
3. Kept crisp zero-duration interaction feedback, small pixel-compatible
   corners, and matching chip and segmented-control surfaces.
4. Kept automatic status polling visually silent when repository content is
   unchanged while preserving explicit refresh progress and changed-status
   updates.
5. Added regression coverage for push labels, button hierarchy, and silent
   background polling.
6. Increased label line height and primary/secondary button hit areas, then
   hardened compact action wrapping with 1.6× text-scale coverage for
   constrained hosting and conflict surfaces.
7. Separated Push guidance from the Remote selector and locked the gap with a
   geometry regression assertion.
8. Reverted the display-face button experiment and standardized every labeled
   button family on the UI font, 12-pixel horizontal padding, 18-pixel icons,
   and a 38-pixel control height; icon-only controls use the same height.

## Completed follow-up: Windows setup packaging

1. Added a Spull-style `gift-setup.zip` bundle containing the complete
   Windows release as `gift-runtime.zip`, `Install-Gift.vbs`, and
   `Uninstall-Gift.vbs` with their PowerShell implementations.
2. Added wizard-controlled install-directory selection, Start Menu and Desktop
   shortcut options, current-user uninstall registration, and hidden
   PowerShell/VBScript setup and uninstall launchers.
3. Kept `gift-portable.exe` as a temporary self-extracting launcher without
   an installation wizard, shortcut creation, or persistent installation, and
   published both Windows artifacts alongside the Release bundle.
4. Kept VBScript/Windows Script Host as the default setup entry point, then
   added a visible Start Menu uninstall shortcut, confirmation-aware uninstall
   handoff, target-checked shortcut cleanup, and guarded current-user
   uninstall registration removal.

## Planned follow-up: contextual actions and path selection

1. Prioritized a shared mouse/keyboard context-action foundation, direct
   History cherry-pick entry, ordered multi-commit operations, and complete
   file, branch, remote, workspace, worktree, and nested-root menus.
2. Preserved every existing preview, confirmation, stale-state, and conflict
   workflow instead of adding direct menu mutations.
3. Planned editable native folder fields for absolute paths and bounded,
   searchable repository-relative path navigation for file/folder inputs.
4. Split the work into Tasks 40–47 so action routing, object-specific menus,
   batch history operations, and the two path-selection models can be verified
   independently.


## Completed vertical: Scale and resilience (Task 36)

1. Activated Task 36 after recording PERF-01/02/03/04 for debounced metadata
   watching, refresh coalescing, process lifecycle cleanup, and bounded large
   list/diff rendering.
2. The first RED fixture
   `test/features/repository/repository_refresh_coordinator_test.dart`
   failed before the watcher coordinator existed.
3. Implemented debounced repository-root watching with a low-frequency
   fallback, refresh coalescing, bounded diff caching with explicit mutation
   invalidation, paged diff rendering, and process-tree cleanup diagnostics.
4. Kept explicit budgets in the implementation: 180 ms event debounce, 30 s
   fallback polling, eight diff-cache entries, 500 rendered diff lines per
   page, and bounded process-tree escalation.
5. Focused watcher, Changes, and backend executor verification passed.

## Completed vertical: Accessibility and preferences (Task 37)

1. Activated Task 37 after recording ACCESS-01/02/03/04 for preference
   migration/recovery, visual and motion settings, shortcut conflicts, and
   semantic/locale boundaries.
2. The first RED fixture
   `test/app_preferences_test.dart` failed before the versioned preference
   contract existed.
3. Implemented versioned, validated preference persistence with legacy theme
   migration, corrupt-data recovery, canonical shortcut conflict detection,
   refresh policy, default branch/remote choices, and rewrite-on-recovery.
4. Applied UI scale, reduced motion, high contrast, color-safe graph colors,
   configurable keyboard bindings, English locale resources, semantic labels,
   focus-safe shortcuts, and preference-aware branch/remote ordering at the
   app and workspace boundaries.
5. Added persistence, migration, semantics, contrast, locale, dialog,
   shortcut, and compact-workflow coverage.
6. Focused accessibility and repository UI verification passed; the full
   Flutter verification suite passed with 224 tests.

## Completed vertical: Contextual action foundation (Task 40)

1. Activated Task 40 after recording shared action-descriptor,
   secondary-click/keyboard/overflow parity, disabled-reason, stale-selection,
   focus-restoration, dismissal, and destructive-routing scenarios as
   ACTION-01/02/03/04.
2. The first RED fixture
   `test/features/repository/context_action_menu_test.dart` failed before
   implementation because the typed presenter contract did not exist.
3. Implemented immutable repository/object snapshots, typed action targets,
   availability results, route descriptors, and a shared presenter with
   secondary-click placement, Shift+F10/Menu invocation, arrow/Escape menu
   behavior, semantic labels, edge clamping, stale selection rejection, and
   focus restoration.
4. Added a per-change overflow affordance in Changes. Inspect, stage, unstage,
   and discard actions use the existing controller and discard confirmation
   paths; menu presentation never runs Git or creates a preview.
5. Added pointer, keyboard, overflow, disabled-reason, focus, stale-refresh,
   edge-clamping, and Changes routing coverage. Formatting, analysis, and the
   full Flutter verification suite passed with 213 tests.
6. Audited compact dialog control spacing and added explicit vertical gaps for
   File History follow-renames/line/blame controls, interactive rebase
   options, object-management options, and remote actions.

## Completed vertical: Commit context actions and direct cherry-pick (Task 41)

1. Activated Task 41 after recording History commit-menu identity, reviewed
   routing, and refresh-staleness scenarios as ACTION-05/06.
2. Added an OID-bound History commit-row menu with inspect, compare, copy,
   cherry-pick, revert, branch, tag, and reset entry points.
3. Added direct branch creation at a full commit OID without switching the
   current branch, and deep-linked the existing preview-first dialogs for
   cherry-pick, rollback, tag, and comparison.
4. Kept Git mutations behind existing preview/confirmation flows and bound
   menu descriptors to the repository snapshot and full commit OID.
5. Covered the menu inventory, cherry-pick prefill, refreshed copy binding, and
   exact branch-ref creation in focused widget and real-Git tests.

## Completed vertical: Ordered multi-commit operations (Task 42)

1. Added immutable non-contiguous History selection with explicit clear
   controls while leaving single-commit details selection independent.
2. Added full-OID previews for cherry-pick and revert, including deterministic
   execution direction, target branch, combined paths, duplicate and contained
   commits, merge mainline requirements, dirty state, and active operations.
3. Executed reviewed OIDs one at a time with completed/current/remaining
   progress and cancellation, conflict, and typed-failure stop behavior.
4. Added token- and fingerprint-bound current-operation recovery for continue,
   skip, abort, and an explicit continue-or-abort remaining decision.
5. Covered reverse-visible order, revert order, merge mainlines, duplicates,
   containment, stale previews, cancellation, conflicts, recovery, and the
   reviewed progress dialog in focused real-Git and widget tests.

## Completed vertical: Change and file context actions (Task 43)

1. Activated Task 43 after recording ACTION-09/10 for path-scoped Changes,
   History-file, comparison-file, stale-selection, and reveal behavior.
2. Added the first RED fixture in
   `test/features/repository/changes_screen_test.dart`, then exposed the
   complete changed-file action inventory through the shared context menu.
3. Added immutable path, original-path, diff-scope, fingerprint, and repository
   bindings; stale rows are rejected before a route can mutate or open state.
4. Reused staging, discard preview, shelves/changelists, ignore, file history,
   blame, comparison, clipboard, and native file-manager workflows.
5. Added historical changed-file and comparison-file menus with revision-aware
   compare/blame/reveal availability and platform-safe path resolution.
6. Verified focused action-menu tests, path traversal/reveal boundaries,
   `flutter analyze`, and the full Flutter feature suite.

## Completed vertical: Branch and remote context actions (Task 44)

1. Activated Task 44 after recording ACTION-11/12 for local branch and
   remote-tracking branch menus, ref freshness, and non-mutating selection.
2. Added the first RED local and remote branch action-inventory fixtures.
3. Added immutable local/remote ref identities, snapshots, and stale-row guards.
4. Reused reviewed checkout, merge, rebase, rename, delete, push, upstream,
   comparison, History cherry-pick, clipboard, and hosting flows.
5. Preserved non-mutating row selection while making explicit Checkout the only
   route that changes the checked-out branch.
6. Verified branch-dialog regressions, `flutter analyze`, and the focused
   branch/history/comparison/object/push/context-menu suite.

## Completed follow-up: multi-file stage selection

1. Added ACTION-13 for independently selected changed paths and staged facets.
2. Added the first RED screen fixture, then implemented path-based selection
   state with refresh pruning and a serialized Stage selected operation.
3. Added a visible selected-count bar, explicit batch staging, and square pixel
   checkbox controls without changing diff-focused row selection.
4. Added pointer focus restoration and explicit Space-key handling for keyboard
   parity; selected paths clear or remain recoverable according to refreshed
   status and operation success.
5. Verified the complete Changes screen suite, pixel theme contract, and
   `flutter analyze`.

## Completed vertical: Workspace context actions (Task 45)

1. Added root-bound workspace and recent-repository action descriptors with
   canonical-path fingerprints and stale-row guards.
2. Added tab actions for activation, closing, closing other tabs, copying the
   repository path, revealing the root, and opening nested roots; recent rows
   expose opening, removal, copying, and file-manager reveal.
3. Reused the shared contextual menu and direct platform file-manager boundary
   without treating tab removal as filesystem deletion.
4. Verified the workspace/recent repository fixtures and `flutter analyze`.

## Completed vertical: Native folder chooser UX (Task 46)

1. Recorded PATH-01 for purpose-scoped absolute folder validation, safe
   remembered locations, and native browse/manual-entry parity.
2. Added one editable folder-field control with native picker injection, clear
   and paste support, keyboard submission, full-path tooltips, and inline
   validation for missing, inaccessible, file, and non-empty paths.
3. Applied it to repository open/replacement, clone local source and
   destination, initialization, nested-root scans, and worktree destinations;
   relative worktree input remains supported without traversal.
4. Reused the history through Welcome, workspace replacement, Changes, setup,
   and worktree flows, and verified the folder workflow suites plus analysis.

## Completed vertical: Repository path navigation (Task 47)

1. Recorded PATH-02 for bounded tracked/changed/original repository-relative
   path lookup, separator normalization, stale-root safety, and kind checks.
2. Added a bounded Git `ls-files --cached -z` path snapshot that merges
   changed, deleted, renamed, and derived directory entries with a stable
   fingerprint and truncation flag.
3. Added a debounced searchable path field with manual entry, keyboard
   submission, clear, browse suggestions, parent context, file/folder modes,
   separator normalization, and traversal validation.
4. Applied the field to History path filters, File History/Blame, folder
   comparison, and hosting file links; stale gateway responses are ignored.
5. Added widget coverage for browse/search/normalization/traversal and verified
   affected repository flows plus analysis.

## Completed vertical: Visual regression QA (Task 39)

1. Added deterministic Welcome-screen fixtures for compact, standard, and wide
   windows in dark and light themes, including a 1.2x compact text-scale case.
2. Added representative Push and Repository Setup dialog fixtures for compact
   dark 1.2x text and standard light 1.0x text, with bounds and spacing checks
   in `test/app/visual_regression_test.dart`.
3. Captured and reviewed the Windows golden matrix for all welcome and dialog
   fixtures. CI captures Linux and macOS runner-specific goldens as review
   artifacts without pretending their rasterization matches Windows.
4. Passed focused visual verification and the full Windows verification suite;
   Task 39 is complete.

## Completed follow-up: cross-platform CI hardening

1. Serialized Git integration verification and forced LF Git fixtures on
   Windows so CRLF conversion and teardown races cannot block CI.
2. Made interactive-rebase editor scripts run through Git's portable `sh`
   command path on every desktop platform, including Windows Git Bash.
3. Added release-bundle structure checks, Windows packaging-script checks,
   and Linux/macOS runner-specific golden capture to the GitHub Actions matrix.

## Active vertical: public release pipeline (Task 38)

1. Added semver validation for `release-v<version>` tags and deterministic
   Linux, macOS, and Windows release archive names.
2. Removed signing-secret requirements: Windows archives contain unsigned
   executables, and macOS release archives now contain an unsigned universal
   app plus `Run-Gift.command`, matching the Spull local-distribution flow.
3. Added SHA-256 checksums, opt-in release metadata, CycloneDX SBOM,
   dependency/license audit reports, full-SHA action verification, and GitHub
   OIDC provenance attestations for the release archives.
4. Added a first-run Git diagnostics card that routes users to Git settings
   when the required executable is unavailable.
5. Next: complete the native three-platform clean-machine release pass and do
   not mark Task 38 complete before those checks pass.

## Completed follow-up: visible push progress

1. Added a pixel-themed transfer card that appears as soon as the reviewed push
   starts and names the exact remote destination.
2. Kept the indeterminate progress bar honest because the current Git gateway
   exposes cancellation but not byte-level transfer progress.
3. Added an explicit `Cancel push` action that remains available until the
   gateway operation returns, with regression coverage for cancellation and
   result rendering.

## Completed follow-up: remote tracking and intuitive push

1. Made the current branch’s configured upstream the authoritative default
   push destination, ahead of repository preferences and generic remote order.
2. Added reviewed first-push linking so an untracked local branch can publish
   to a chosen remote branch and establish its upstream in the same safe
   operation.
3. Kept the normal push surface focused on the local-to-remote destination and
   tracking state; selected commits, tags, alternate branch names, and
   force-with-lease now live under explicit advanced options.
4. Exposed push/link from the current branch row, remote configuration and
   upstream management from Remote operations, and routed object-management
   publication through the same reviewed push flow.
5. Covered real Git upstream creation, configured-upstream precedence,
   untracked-branch defaults, compact layouts, progress, branch discovery, and
   remote setup access.

## Completed follow-up: resilient remote ref parsing

1. Replaced ambiguous shortened remote ref output with full
   `refs/remotes/*` names and UTF-8 decoding.
2. Accepted Git output that omits an empty trailing symbolic-ref field and
   resolved externally-configured remote names against the actual remote list.
3. Added a simpler two-field `for-each-ref` fallback so one unsupported or
   malformed primary format no longer disables the branch workflow.
4. Preserved a combined primary/fallback diagnostic when both formats are
   genuinely unreadable instead of hiding repository corruption.
5. Covered fallback recovery, full refs, CRLF, optional fields, symbolic HEAD,
   configured remote names, and the existing unrecoverable diagnostics.

## Completed follow-up: Git account manager UX

1. Replaced the always-open credential form with a focused account list; the
   form opens only for the first account, a new account, or an edit.
2. Grouped saved accounts by host, added searchable account filtering, and
   moved row actions into a compact account-action menu.
3. Added clearer security, provider, credential-type, secret-preservation,
   default-account, and connection-test guidance without exposing secrets.
4. Added responsive host/name fields, compact editor coverage, and interaction
   tests for filtering, adding, and editing accounts.

## Completed follow-up: cohesive pixel controls and Changes layout

1. Replaced rounded Material button silhouettes with crisp pixel-cut geometry
   while preserving the filled, outlined, text, destructive, and disabled
   action hierarchy.
2. Added restrained bounded icon controls with immediate hover, focus, and
   pressed states; compact row overflow and tab-close affordances remain
   lightweight.
3. Aligned control and list sizing to the four-pixel grid, tightened change
   rows, widened the desktop change pane responsively, and exposed full paths
   through hover tooltips.
4. Grouped branch, synchronization, and changed-file metrics at the start of
   the summary strip; strengthened active-tab indication and replaced the
   isolated empty detail sentence with concise next-action guidance.

## Completed follow-up: square controls and complete action spacing

1. Replaced beveled controls with flat square pixel surfaces. Primary actions
   remain solid, secondary actions use a quiet raised fill and border, text
   actions stay lightweight, and icon actions gain a subtle resting tile plus
   explicit hover and focus borders.
2. Added one toolbar icon component that owns the four-pixel inter-control gap;
   Changes, History, Conflict, Welcome, theme, and refresh actions now share
   the same rhythm and retain an eight-pixel outer edge.
3. Standardized dialog overflow actions, wrapped action rows, compact icon
   groups, and button-to-card spacing at 8 px. Dialog action edges remain
   16 px, with 12 px between content and actions.
4. Moved explicit 10 px card and notice padding to the 12 px grid, and kept
   compact File History actions directly reachable by placing History and
   Blame side by side.

## Completed follow-up: macOS-friendly desktop UX excluding native integration

1. Added platform-aware macOS command defaults, adaptive toolbar labels,
   accessible icon semantics, shared spacing primitives, and stronger
   high-contrast action boundaries.
2. Kept Changes operations reachable with sticky multi-file staging,
   inline stage/unstage actions, guided Stage & commit, availability reasons,
   and a searchable repository-action overflow entry.
3. Split History rollback entry points, exposed active filter summaries, and
   bounded large repositories to the first 600 visible commits with an
   explicit refinement notice.
4. Reattached failed filesystem watchers through fallback polling, exposed
   watcher versus polling state independently from Git mutation state, and
   standardized retry/refresh recovery actions.
5. Enriched recent repository cards with repository names, full paths, and
   availability state.
6. Verified formatting, analysis, all 305 Flutter tests, and a macOS release
   build. Native macOS integration (#18) remained intentionally excluded.

## Completed follow-up: macOS launcher artifact packaging

1. Confirmed the release ZIP already contained `Run-Gift.command`; the
   missing file was limited to the separately uploaded desktop artifact,
   which previously contained only `gift.app`.
2. Made the macOS build helper stage an upload-ready
   `build/macos/Distribution/` directory with `gift.app` and an executable
   `Run-Gift.command` side by side.
3. Pointed the CI macOS desktop artifact at that staged directory, extended
   artifact verification to require the launcher, and made ZIP packaging
   fail when the launcher is absent.
4. Verified the macOS release build, staged artifact, packaged ZIP, workflow
   pins, formatting, analysis, and all 305 Flutter tests.
