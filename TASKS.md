# 📋 gift Task Management

> **Project Goal:** Build a clean-room, cross-platform desktop Git client with
> familiar IDE-style workflows, a minimal 2D pixel-game UI, a Flutter Desktop
> frontend, and a pure Dart backend for Windows, macOS, and Linux.

## Progress

- **Total Tasks:** 38
- **Completed:** 26 / 38
- **Current Active Task:** `Task 26 follow-up — repository UI polish`

| # | Scope | Dart backend deliverables | Flutter deliverables | Status |
|---|---|---|---|:---:|
| **1** | Scaffold & contract | `DartGitBackend.health()` and backend contracts | `GiftApp` shell | ✅ |
| **2** | Behavior ledger & harness | Isolated Git fixtures and direct process helpers | Clean-room scenario ledger | ✅ |
| **3** | Git executor & discovery | `ProcessGitRunner`, typed errors, redaction, PATH scan | Git settings bridge contract | ✅ |
| **4** | Repository registry & open | `AppState`, opaque IDs, root validation | Welcome screen and recent paths | ✅ |
| **5** | Status parser & changes | Porcelain v2 `-z` parser and snapshots | Grouped changes list | ✅ |
| **6** | Unified diff | Bounded diff parser and rename detection | Lazy unified diff view | ✅ |
| **7** | Staging & mutation | Serialized `git add`/`restore --staged` | Selection and action buttons | ✅ |
| **8** | Discard changes | Expiring preview token and safe restore | Confirmation dialog | ✅ |
| **9** | Commit panel | UTF-8 message stdin and hook mapping | Commit editor and shortcuts | ✅ |
| **10** | History & graph | Paginated log and deterministic lanes | History screen and details | ✅ |
| **11** | Branch management | Ref parsing, validation, and switch | Branch popup and tracking flow | ✅ |
| **12** | Remotes & cancellation | Fetch/pull/push and operation cancellation | Progress bar and controls | ✅ |
| **13** | JetBrains-equivalent UX & pixel theme | Redacted diagnostics and classification | Minimal 2D pixel-game shell, responsive layout, theme, shortcuts | ✅ |
| **14** | Packaging & CI | Cross-platform verification scripts | Desktop release artifacts | ✅ |
| **15** | Hardening, UI & identity | Process safety, connected graph edges, preview revocation | Responsive pixel UI, theme switching, font and release identity | ✅ |
| **16** | Workspace | Multi-repository sessions and persisted workspace state | Repository tabs, reopen, and keyboard navigation | ✅ |
| **17** | Partial staging | Hunk and line patch operations with stale-content guards | Interactive diff selection and stage controls | ✅ |
| **18** | Commit workflow | Amend, templates, sign-off, and identity preflight | Guided commit options and validation | ✅ |
| **19** | History exploration | Search, filters, commit details, and bounded commit diffs | Searchable graph and changed-file inspector | ✅ |
| **20** | Advanced branches | Rename, delete, merge, rebase, and cherry-pick safety | Preview-driven branch actions | ✅ |
| **21** | Conflict resolution | Conflict-state parser and safe resolution mutations | Three-pane merge workflow | ✅ |
| **22** | Git objects | Stash, tags, remotes, and upstream management | Focused object-management dialogs | ✅ |
| **23** | Diff & compare | Revision, branch, folder, clipboard, and 3-way comparisons | Diff workbench and apply/revert actions | ✅ |
| **24** | Shelf & changelists | Shelf storage, changelist grouping, and patch import/export | Shelf/changelist workflow | ✅ |
| **25** | File history & blame | File/directory/selection history and blame metadata | History and annotation views | ✅ |
| **26** | Undo & reset | Revert commit, undo commit, and safe reset modes | Destructive history controls | ⬜ |
| **27** | Interactive rebase | Reorder, reword, edit, squash, fixup, drop, and recovery | Rebase plan and conflict flow | ⬜ |
| **28** | Remote branches & update | Remote branch checkout, compare, update, and tracking | Incoming/update information | ⬜ |
| **29** | Push safety | Push review, force-with-lease, tags, and protected branches | Push review and rejection recovery | ⬜ |
| **30** | Worktrees | Worktree list, create, open, remove, lock, and prune | Worktree manager | ⬜ |
| **31** | Ignore & metadata | `.gitignore`, `.git/info/exclude`, ignored files, and attributes | Ignore/metadata actions | ⬜ |
| **32** | Submodules & nested roots | Submodule status, sync, update, and nested repository mapping | Nested-root workspace | ⬜ |
| **33** | Recovery diagnostics | Reflog browsing, recovery refs, and Git operation console | Recovery and command diagnostics | ⬜ |
| **34** | Repository setup | Clone, init, publish, shallow/unshallow, and root mapping | Repository setup flows | ⬜ |
| **35** | Hosting integration | Optional GitHub/GitLab links and review handoff contracts | Hosting links and review entry points | ⬜ |
| **36** | Scale & resilience | File watching, cache invalidation, process supervision | Large-repository responsiveness | ⬜ |
| **37** | Accessibility & preferences | Versioned settings and locale-ready text contracts | Scaling, remapping, themes, and accessibility | ⬜ |
| **38** | Public release | Signed packages, provenance, update metadata, and release checks | Installers and first-run diagnostics | ⬜ |

## Completed foundations

### ✅ Tasks 1–4: Dart-only backend foundation

- [x] Flutter Desktop shell and Material 3 app entry point.
- [x] Clean-room Git behavior ledger and temporary repository fixtures.
- [x] Shell-free `dart:io` process execution using exact argument vectors.
- [x] Bounded capture/stream output handling and credential-safe diagnostics.
- [x] Git executable discovery, explicit path validation, and Git 2.35+ checks.
- [x] Session-local opaque repository IDs and canonical root validation.
- [x] Recent repository persistence and Git settings retry flow.
- [x] Porcelain v2 status parsing, independent change facets, content hashes,
  and generation-aware snapshots.
- [x] Polling `ChangesController` and grouped changes screen.
- [x] Bounded staged/working-tree unified diff parsing, rename metadata, and
  lazy selected-file rendering.
- [x] Serialized stage/unstage mutations with immediate status snapshots and
  selection actions.
- [x] Expiring, path-bound discard previews with safe working-tree restore and
  confirmation dialog.
- [x] UTF-8 stdin commits, hook rejection mapping, and staged commit editor
  feedback.
- [x] Bounded history pages, merge-aware lane slots, and commit details.
- [x] Local branch ref parsing, name validation, serialized switching, and
  branch popup feedback.
- [x] Remote parsing, cancellable fetch/pull/push, typed failures, and
  progress feedback.
- [x] Dark pixel theme, crisp focusable surfaces, responsive workflow panes,
  keyboard shortcuts, and visible status feedback.
- [x] Removed FFI, generated bindings, native build plugins, and the former
  native implementation.

## Product contracts

- `docs/research/jetbrains-git-mvp-behavior.md` is the clean-room behavior
  ledger for the desktop Git workflow target.
- `docs/superpowers/specs/2026-09-02-jetbrains-git-gui-pixel-ui-design.md`
  defines the original minimal 2D pixel-game visual system, desktop shell,
  interaction states, accessibility, and acceptance criteria.
- A task is complete only when its behavior is independently testable and its
  visible states fit both contracts. Proprietary source, assets, captures, and
  implementation details are never copied.

## Completed task

### ✅ Task 5: Porcelain v2 Status & Changes View

- [x] Lossy NUL-delimited `git status --porcelain=v2 -z --branch` parser.
- [x] Independent staged, unstaged, untracked, and conflicted facets.
- [x] Snapshot content hashing and generation increments.
- [x] Riverpod `ChangesController` with timer-based polling and selection
  retention.
- [x] Grouped `ChangesScreen` for conflicts, staged, unstaged, untracked, and
  conflicted files.

### ✅ Task 6: Unified Diff

- [x] Added staged and working-tree unified diff parser/backend tests.
- [x] Added a 4 MiB bounded diff invocation with rename-aware path arguments.
- [x] Added lazy selected-file rendering with line numbers, binary handling,
  and scope switching.

### ✅ Task 7: Staging & Mutation

- [x] Added shell-free `git add -- path` and
  `git restore --staged -- path` backend operations.
- [x] Serialized mutations per repository handle and returned a refreshed
  status snapshot after each operation.
- [x] Added selected-file Stage/Unstage actions with loading and error state.

### ✅ Task 8: Discard Changes

- [x] Added two-minute preview tokens bound to repository, path, status, and
  diff fingerprints.
- [x] Added safe `git restore --worktree -- path` with staged-change
  preservation and untracked/conflict rejection.
- [x] Added confirmation dialog, stale-token feedback, and selection refresh.

### ✅ Task 9: Commit Panel

- [x] Added UTF-8 commit messages through shell-free `git commit --file=-`
  stdin.
- [x] Added staged preflight, serialized commit mutations, post-commit status,
  and hook rejection error mapping.
- [x] Added a staged-only commit editor with loading, success, error, and clean
  state feedback.

### ✅ Task 10: History & graph

- [x] Added bounded `git log` parsing with metadata and merge parents.
- [x] Added deterministic graph lane slots and pagination.
- [x] Added History screen selection, commit details, and Load more feedback.

### ✅ Task 11: Branch management

- [x] Added local `for-each-ref` parsing with current and upstream metadata.
- [x] Added validated branch creation and serialized switching with dirty
  worktree feedback.
- [x] Added a branch popup with create, switch, loading, and error states.

### ✅ Task 12: Remotes & cancellation

- [x] Added remote URL parsing and credential-safe display.
- [x] Added cancellable fetch, pull, and push operations with serialized
  remote mutations and typed authentication/network/conflict failures.
- [x] Added indeterminate progress, cancellation control, and completion
  refresh feedback.

## Completed task

### ✅ Task 13: JetBrains-equivalent UX & pixel theme

- [x] Applied the dark pixel palette with flat surfaces, crisp borders, and
  visible focus treatment.
- [x] Added Ctrl+R, Ctrl+H, Ctrl+Shift+B, Ctrl+Shift+R, Ctrl+Enter, and Esc
  shortcuts with discoverable status-strip hints.
- [x] Added narrow-window stacked layouts for Changes and History, plus
  responsive operation dialogs and visible operation status.

## Completed task

### ✅ Task 14: Packaging & CI

- [x] Added a shell-free, cross-platform Dart verification entry point.
- [x] Added Linux, macOS, and Windows desktop release build helpers.
- [x] Added CI checks and release artifact workflows for all three targets.
- [x] Documented local verification, release output paths, and CI behavior.

Task 15 was marked safe done under WSL; its native Linux bundle check is
covered by CI.

### ✅ Task 15: Hardening, UI & product identity (safe done under WSL)

- [x] Added bounded Git process deadlines and disabled interactive credential
  prompts.
- [x] Preserved history graph lanes when another page is appended.
- [x] Prevented stale Git settings requests from updating disposed UI state.
- [x] Revoked cancelled discard confirmations and cleaned expired tokens.
- [x] Unified Dart and desktop product metadata under `gift`.
- [x] Added an MIT license and tag-only release workflow triggers.
- [x] Replaced isolated history markers with connected multi-lane fork, merge,
  and continuation segments that survive pagination.
- [x] Added persistent light/dark theme switching and bundled the readable
  OFL-licensed Jersey 15 pixel font.
- [x] Replaced mixed generated/direct colors with explicit semantic light and
  dark `ColorScheme` roles and contrast regression checks.
- [x] Hardened compact-window layouts for the welcome, changes, history, and
  operation-dialog surfaces.
- [x] Generated Windows and macOS release icons from
  `assets/images/gift_icon.png`.
- [x] Marked safe done under WSL; Linux GTK/native bundle execution remains a
  CI-only verification because the host cannot provide the required desktop
  package.

### ✅ Task 16: Multi-repository workspace

- [x] Persist an ordered workspace of canonical paths and the last active path.
- [x] Restore valid repositories after restart and explain unavailable tabs.
- [x] Open, close, reorder, and deduplicate repository tabs safely.
- [x] Keep each repository's Changes, History, branch, remote, and mutation
  state isolated by repository session.
- [x] Add keyboard navigation for next, previous, and close tab actions.
- [x] Cover narrow-window tab layout and text-scaled tab labels.

### ✅ Task 17: Hunk and line staging

- [x] Built machine-owned patches from parsed hunk and changed-line indexes.
- [x] Added serialized `git apply --cached` and reverse unstage operations
  with bounded stdin/output and typed patch errors.
- [x] Bound selections to repository, path, scope, and diff content hash;
  stale selections cannot mutate a refreshed file.
- [x] Added hunk and line checkboxes, Shift+Space range selection, and clear
  working-tree versus staged labels.
- [x] Covered real Git partial stage/unstage, replacement lines, no-newline
  markers, rename-only and binary states, patch rejection, compact UI, and
  recoverable controller errors.

Task 17 is complete.

### Task 18: Complete commit workflow

- [x] Added typed amend, sign-off, cleanup, and author override options.
- [x] Added local/global identity preflight and exact configuration guidance.
- [x] Added bounded commit-template loading and reset controls.
- [x] Distinguished unchanged history from a created commit with failed refresh.
- [x] Added guided responsive commit options and real-Git failure coverage.

Task 18 is complete.

### Task 19: Searchable history and commit inspection

- [x] Replaced offset-only paging with a stable snapshot cursor.
- [x] Added bounded text, author, date, ref, and path filters.
- [x] Loaded commit files and selected commit diffs lazily with binary states.
- [x] Preserved request ordering while exposing refs, parents, OIDs, and
  keyboard traversal.
- [x] Covered live-ref movement, merge/root commits, deleted paths, and
  unusual UTF-8 metadata.

Task 19 is complete.

### Task 20: Safe advanced branch operations

- [x] Recorded branch rename/delete, merge, rebase, and cherry-pick preview
  scenarios, including fast-forward, divergence, conflict, cancellation,
  abort, and stale-preview recovery.
- [x] Delegated branch-name validation to Git and exposed typed preflight errors
  for dirty, detached, and in-progress repository states.
- [x] Implemented expiring, repository-bound operation previews and explicit
  start/continue/skip/abort state transitions.
- [x] Added backend and widget coverage for safe history-changing
  operations and reachable-commit preservation.

Task 20 is complete. The first failing test was the initial
compile failure in `test/backend/advanced_branch_test.dart` before the preview
contract existed.

### Task 21: Conflict resolution workspace

- [x] Parse unmerged index stages and merge/rebase/cherry-pick metadata into a
  bounded conflict workspace model.
- [x] Load base, ours, theirs, and working-result content with explicit
  missing, binary, and bounded-output states.
- [x] Add fingerprint-guarded accept-ours, accept-theirs, edit-result, mark
  resolved, continue, and abort mutations.
- [x] Add responsive three-pane conflict UI with navigation and
  non-color-dependent status labels.
- [x] Cover add/add, modify/delete, rename, binary, merge, rebase,
  cherry-pick, and stale-resolution fixtures.

Task 21 is complete. The first failing test was the initial compile failure in
`test/backend/conflict_resolution_test.dart` before the conflict stage parser
contract existed.

### Task 22: Git object management

- [x] Parse stable stash and tag object identities, including annotated tag
  metadata and credential-safe remote records.
- [x] Implement stash create/apply/pop/drop/branch flows with fresh snapshot
  checks, conflict states, and identity-bound destructive previews.
- [x] Implement lightweight and annotated tag creation, inspection, deletion,
  and explicit single-tag publication.
- [x] Implement remote add/rename/URL edit/remove/prune and upstream
  set/unset/publish flows with refreshed status and ahead/behind feedback.
- [x] Add responsive stash, tag, remote, and upstream controls with
  confirmation details and credential-safe display.
- [x] Cover object identity, stale previews, remote configuration, tag push,
  stash recovery, and compact dialog rendering with isolated fixtures.

Task 22 is complete. Task 23 is active. The first failing test was the initial
compile failure in `test/backend/object_management_test.dart` before the
object-management contract existed.

### 🔄 Task 23: Diff and comparison workbench (active)

- [x] Added validated revision, branch, tag, and optional folder comparison
  requests with bounded NUL-delimited rename/copy-aware file parsing.
- [x] Included resolved endpoint OIDs, query scope, and raw comparison output
  in the stale-comparison fingerprint.
- [x] Added lazy selected-file unified diffs with path-scope and repository
  identity checks, explicit stale/missing errors, and bounded output.
- [x] Added a responsive Compare revisions dialog and Changes-screen entry
  points for compact and desktop layouts.
- [x] Added reviewed Apply and Revert actions that use backend-generated
  patches, `git apply --check`, serialized mutations, and refreshed status.
- [x] Covered parser, real-Git revision/folder comparison, ref movement, stale
  selection rejection, reviewed transfer, and compact dialog rendering.
- [x] Added bounded clipboard/external-text sources, three-way panes, reviewed
  file navigation, and explicit binary/oversized/missing content states.
- [x] Covered external text, three-way conflict content, repeated file
  navigation, and non-historical transfer rejection with fixtures.

Task 23 is complete. Task 24 was activated after its behavior scenarios and
first RED were recorded in the implementation plan.

### ✅ Task 24: Shelves, changelists, and patch exchange

- [x] Create, rename, activate, delete, and persist app-local changelists
  without mutating Git stash entries.
- [x] Shelve selected tracked paths, inspect reusable patches, unshelve more
  than once, and report conflicts or missing base revisions explicitly.
- [x] Import and export bounded external patches with repository-relative path
  validation and safe deletion/recovery states.
- [x] Add responsive shelf/changelist controls with explicit untracked-file
  limitations and shelf-versus-stash explanations.

Task 24 is complete.

### ✅ Task 25: File history, blame, and revision recovery

- [x] Add bounded file, directory, and selected-line history queries with
  follow/rename metadata and revision navigation.
- [x] Add blame annotations with author/date/OID, movement options, and
  copyable line ownership without allowing arbitrary Git arguments.
- [x] Add responsive history and annotation views with empty, binary, missing,
  and stale selection states.
- [x] Cover root/rename/delete/binary files, path and line ranges, bounded
  output, and refresh races in backend and widget fixtures.

Task 25 is complete.

### ✅ Product identity follow-up: pixel Shiba gift-ribbon logo

- [x] Replaced the canonical icon with a transparent 2D pixel-art chubby
  Shiba Inu face wearing a gift ribbon.
- [x] Rebuilt the README wordmark and derived Windows and macOS release icons
  from the same canonical source.
- [x] Documented that `gift` combines Git and Flutter and that `gitft` was
  shortened to `gift`.

The logo follow-up is complete. Task 26 was activated after its behavior
scenarios and first failing test were recorded.

### ✅ Task 26: Undo, reset, and revert safety

- [x] Add previews for revert, undo, and soft/mixed/hard/keep reset effects.
- [x] Protect pushed/protected/detached/dirty/in-progress repository states
  before history-changing mutations.
- [x] Return explicit revert conflict recovery and preserve stale-preview
  protection for destructive reset modes.
- [x] Cover all rollback modes, multi-commit revert, conflict, undo
  preservation, protected branches, and stale confirmations.

Task 26 is complete.

### ✅ Task 26 follow-up: History commit-file viewer polish

- [x] Replaced the plain selected-file diff text with a bounded, independently
  scrollable diff card rendered directly below the selected file row.
- [x] Added file context, addition/deletion counts, copy action, line numbers,
  semantic addition/deletion/hunk colors, and selectable content.
- [x] Added regression coverage for the diff card, line rows, counts, and copy
  control without activating Task 27.
- [x] Added a recent-commit target picker with automatic parent selection and
  kept special revision expressions available under Advanced revision.

The Task 26 follow-up is complete. Keep Task 27 planned until it is explicitly
activated with its behavior scenarios and first failing test.

### ✅ Task 26 follow-up: repository UI polish

- [x] Unified the History detail pane under one vertical scroll while keeping
  horizontal scrolling only for long diff lines, and revealed selected diffs
  near the current file row.
- [x] Clarified repository action labels, status summaries, empty states, and
  compact file-history controls.
- [x] Hardened responsive app-bar and dialog layouts against narrow-width
  button overflow and added widget coverage for the updated controls.

The repository UI polish follow-up is complete. Keep Task 27 planned until it
is explicitly activated with its behavior scenarios and first failing test.

## Post-MVP backlog

Tasks 16–38 are specified in
[`docs/POST_MVP_ROADMAP.md`](docs/POST_MVP_ROADMAP.md). Start them in numeric
order unless a task explicitly lists no dependency. Before implementation,
move exactly one task to active, add its behavior-ledger scenarios, and record
the first failing test in the checkpoint.
