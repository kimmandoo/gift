# 📋 gitflu Task Management

> **Project Goal:** Build a clean-room, cross-platform desktop Git client with
> familiar IDE-style workflows, a minimal 2D pixel-game UI, a Flutter Desktop
> frontend, and a pure Dart backend for Windows, macOS, and Linux.

## Progress

- **Total Tasks:** 14
- **Completed:** 4 / 14 (28.6%)
- **Current Active Task:** `Task 5: Porcelain v2 Status & Changes View`

| # | Scope | Dart backend deliverables | Flutter deliverables | Status |
|---|---|---|---|:---:|
| **1** | Scaffold & contract | `DartGitBackend.health()` and backend contracts | `BranchlineApp` shell | ✅ |
| **2** | Behavior ledger & harness | Isolated Git fixtures and direct process helpers | Clean-room scenario ledger | ✅ |
| **3** | Git executor & discovery | `ProcessGitRunner`, typed errors, redaction, PATH scan | Git settings bridge contract | ✅ |
| **4** | Repository registry & open | `AppState`, opaque IDs, root validation | Welcome screen and recent paths | ✅ |
| **5** | Status parser & changes | Porcelain v2 `-z` parser and snapshots | Grouped changes list | ⏳ |
| **6** | Unified diff | Bounded diff parser and rename detection | Lazy unified diff view | ⏳ |
| **7** | Staging & mutation | Serialized `git add`/`restore --staged` | Selection and action buttons | ⏳ |
| **8** | Discard changes | Expiring preview token and safe restore | Confirmation dialog | ⏳ |
| **9** | Commit panel | UTF-8 message stdin and hook mapping | Commit editor and shortcuts | ⏳ |
| **10** | History & graph | Paginated log and deterministic lanes | History screen and details | ⏳ |
| **11** | Branch management | Ref parsing, validation, and switch | Branch popup and tracking flow | ⏳ |
| **12** | Remotes & cancellation | Fetch/pull/push and operation cancellation | Progress bar and controls | ⏳ |
| **13** | JetBrains-equivalent UX & pixel theme | Redacted diagnostics and classification | Minimal 2D pixel-game shell, responsive layout, theme, shortcuts | ⏳ |
| **14** | Packaging & CI | Cross-platform verification scripts | Desktop release artifacts | ⏳ |

## Completed foundations

### ✅ Tasks 1–4: Dart-only backend foundation

- [x] Flutter Desktop shell and Material 3 app entry point.
- [x] Clean-room Git behavior ledger and temporary repository fixtures.
- [x] Shell-free `dart:io` process execution using exact argument vectors.
- [x] Bounded capture/stream output handling and credential-safe diagnostics.
- [x] Git executable discovery, explicit path validation, and Git 2.35+ checks.
- [x] Session-local opaque repository IDs and canonical root validation.
- [x] Recent repository persistence and Git settings retry flow.
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

## Active task

### ⏳ Task 5: Porcelain v2 Status & Changes View

- [ ] Zero-copy/lossy NUL-delimited `git status --porcelain=v2 -z --branch` parser.
- [ ] Independent staged, unstaged, untracked, and conflicted facets.
- [ ] Snapshot content hashing and generation increments.
- [ ] Riverpod `ChangesController` with timer/mutation-based polling.
- [ ] Grouped `ChangesScreen` for conflicts, staged, unstaged, and untracked files.

Tasks 6–14 retain the same product scope above and will build on the Dart
backend contracts established here.
