# 📋 gitshiba Task Management

> **Project Goal:** Build a clean-room, cross-platform desktop Git client with
> familiar IDE-style workflows, a minimal 2D pixel-game UI, a Flutter Desktop
> frontend, and a pure Dart backend for Windows, macOS, and Linux.

## Progress

- **Total Tasks:** 25
- **Completed:** 16 / 25
- **Current Active Task:** `17 — Partial staging`

| # | Scope | Dart backend deliverables | Flutter deliverables | Status |
|---|---|---|---|:---:|
| **1** | Scaffold & contract | `DartGitBackend.health()` and backend contracts | `GitshibaApp` shell | ✅ |
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
| **17** | Partial staging | Hunk and line patch operations with stale-content guards | Interactive diff selection and stage controls | ⬜ |
| **18** | Commit workflow | Amend, templates, sign-off, and identity preflight | Guided commit options and validation | ⬜ |
| **19** | History exploration | Search, filters, commit details, and bounded commit diffs | Searchable graph and changed-file inspector | ⬜ |
| **20** | Advanced branches | Rename, delete, merge, rebase, and cherry-pick safety | Preview-driven branch actions | ⬜ |
| **21** | Conflict resolution | Conflict-state parser and safe resolution mutations | Three-pane merge workflow | ⬜ |
| **22** | Git objects | Stash, tags, remotes, and upstream management | Focused object-management dialogs | ⬜ |
| **23** | Scale & resilience | File watching, cache invalidation, process supervision | Large-repository responsiveness | ⬜ |
| **24** | Accessibility & preferences | Versioned settings and locale-ready text contracts | Scaling, remapping, themes, and accessibility | ⬜ |
| **25** | Public release | Signed packages, provenance, update metadata, and release checks | Installers and first-run diagnostics | ⬜ |

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
- [x] Unified Dart and desktop product metadata under `gitshiba`.
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
  `assets/images/gitshiba_icon.png`.
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

Task 16 is complete. Task 17 is the next implementation task.

## Post-MVP backlog

Tasks 16–25 are specified in
[`docs/POST_MVP_ROADMAP.md`](docs/POST_MVP_ROADMAP.md). Start them in numeric
order unless a task explicitly lists no dependency. Before implementation,
move exactly one task to active, add its behavior-ledger scenarios, and record
the first failing test in the checkpoint.
