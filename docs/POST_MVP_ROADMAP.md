# Post-MVP roadmap

This roadmap turns the MVP into a dependable daily Git client while preserving
gift's clean-room workflow research and minimal 2D pixel-game interface.
Task 15 was marked safe done under WSL because the remaining native bundle
check is CI-only in this environment. Tasks 16 through 20 are complete;
Task 21 is next.
Do not start a later post-MVP task until its dependencies are complete and its
visible behavior has been recorded in the behavior ledger without copying
proprietary implementation details or assets.

## Delivery order

| Phase | Tasks | Outcome |
|---|---|---|
| Daily workflow | 16–19 | Multiple repositories, partial staging, richer commits, and useful history exploration |
| Safe power tools | 20–22 | Advanced branch operations, conflict resolution, stash, tags, and remote management |
| Product readiness | 23–25 | Large-repository resilience, accessibility, preferences, and signed releases |

Every task must include backend tests with isolated Git fixtures, controller
tests for async state changes, responsive widget tests, beginner-oriented
comments for non-obvious flows, and updates to the behavior ledger and
architecture documentation.

## Task 16 — Multi-repository workspace

**Depends on:** Task 15.

**Goal:** Let a user keep several repositories open without mixing their
handles, mutation queues, selection, or progress state.

- Persist an ordered workspace containing canonical repository paths and the
  last active repository; never persist opaque session IDs.
- Add open, close, reorder, reopen, and missing-folder recovery behavior.
- Give each repository independent Changes, History, branch, remote, and
  operation state.
- Add repository tabs plus `Ctrl+Tab`, `Ctrl+Shift+Tab`, and close shortcuts
  with visible focus and narrow-window behavior.
- Cover restart restoration, duplicate canonical paths, moved folders, and a
  mutation running while another tab is selected.

**Done when:** A restarted app restores valid tabs, explains unavailable tabs,
and tests prove operations cannot cross repository boundaries.

## Task 17 — Hunk and line staging

**Depends on:** Task 16.

**Status:** Complete.

**Goal:** Stage or unstage selected hunks and lines without invoking a shell or
silently applying a patch to changed content.

- Produce machine-owned patch selections from parsed diff structures rather
  than accepting arbitrary patch text from the UI.
- Apply patches through `git apply --cached` or its reverse form using stdin,
  bounded output, and repository mutation serialization.
- Bind every selection to repository, path, diff scope, and content hash;
  reject stale selections after a refresh.
- Add hunk and line checkboxes, keyboard range selection, and explicit staged
  versus working-tree labels.
- Cover additions, deletions, no-newline markers, renames, binary files,
  partially staged files, and failed patch application.

**Done when:** Partial stage and unstage round-trip against real Git fixtures
and stale diffs can never mutate a newer file version.

## Task 18 — Complete commit workflow

**Depends on:** Task 17.

**Status:** Complete.

**Goal:** Support routine commit options while keeping each resulting Git
command understandable and recoverable.

- Add amend, sign-off, cleanup mode, commit template loading, and optional
  author override as typed backend options.
- Detect missing user name/email before mutation and provide exact local versus
  global configuration guidance.
- Keep hook and signing failures redacted and distinguish “commit not created”
  from “commit created but refresh failed.”
- Add a collapsible options panel, character guidance, template reset, and
  clear destructive warning for amend.
- Cover empty messages, empty staged sets, amend on unborn branches, UTF-8,
  rejected hooks, and configured signing failures.

**Done when:** Each option has a real-repository test and the UI always states
whether repository history changed.

## Task 19 — Searchable history and commit inspection

**Depends on:** Task 16. May run in parallel with Tasks 17–18.

**Status:** Complete.

**Goal:** Make the graph useful for investigating changes rather than only
listing commits.

- Replace offset pagination with a stable cursor or snapshot boundary so live
  ref movement cannot duplicate or omit rows.
- Add bounded filters for text, author, date, branch/ref, and path.
- Load changed files and a selected file's commit diff lazily with output
  limits and binary states.
- Show refs, parent navigation, copyable OIDs, and keyboard-driven result
  traversal while retaining graph-lane continuity.
- Cover merge commits, root commits, deleted paths, unusual UTF-8 metadata,
  filter changes during requests, and repositories that advance while open.

**Done when:** Filtered pagination remains deterministic and selecting a commit
cannot display details from an older request.

## Task 20 — Safe advanced branch operations

**Depends on:** Tasks 18 and 19.

**Status: Complete.**

**Goal:** Add branch rename/delete, merge, rebase, and cherry-pick with previews
that make history-changing effects explicit.

- Delegate ref-name validation to `git check-ref-format --branch` and map
  failures to typed user messages.
- Add ahead/behind, merge-base, dirty-worktree, detached-HEAD, and in-progress
  operation preflight checks.
- Model merge, rebase, and cherry-pick as explicit start, continue, skip, and
  abort state machines; never guess recovery actions.
- Require expiring confirmation tokens for force delete or other data-losing
  actions.
- Add preview dialogs that identify source, target, expected commits, and the
  exact recovery action available after failure.

**Done when:** Real fixtures cover fast-forward, divergent, conflicted,
cancelled, aborted, and stale-preview paths without losing reachable commits.

## Task 21 — Conflict resolution workspace

**Depends on:** Task 20.

**Goal:** Turn merge/rebase/cherry-pick conflicts into a guided resolution flow.

- Parse unmerged index stages and operation metadata into typed base, ours,
  theirs, and working-result models.
- Load each side with bounded binary and missing-file states.
- Add safe “accept ours,” “accept theirs,” editable result, mark resolved,
  continue, and abort operations.
- Present a responsive three-pane comparison with conflict navigation and
  accessible non-color status labels.
- Guard every resolution mutation with current index and worktree fingerprints.

**Done when:** Add/add, modify/delete, rename, binary, merge, rebase, and
cherry-pick conflicts are covered by fixtures and stale resolutions are
rejected.

## Task 22 — Stash, tag, remote, and upstream management

**Depends on:** Task 20.

**Goal:** Complete the common Git object-management workflows surrounding
branches.

- Add stash list, create, apply, pop, drop, and branch-from-stash with safe
  stale-entry checks and conflict reporting.
- Add lightweight and annotated tag creation, deletion, inspection, and
  explicit remote push behavior.
- Add remote add, rename, URL edit, remove, prune preview, and credential-safe
  display.
- Add upstream set/unset and publish-branch flows with ahead/behind feedback.
- Use confirmation previews for stash drop, tag deletion, remote removal, and
  pruning operations.

**Done when:** Object identities, not list positions or display labels, bind
every mutation and destructive actions have real Git fixture coverage.

## Task 23 — Large-repository performance and resilience

**Depends on:** Tasks 16–22.

**Goal:** Keep the app responsive under large histories, many changed files,
slow disks, and misbehaving Git subprocesses.

- Replace fixed polling with debounced filesystem and Git metadata watching,
  retaining a low-frequency fallback refresh.
- Add request coalescing, bounded caches, explicit invalidation, and operation
  tracing that never records credentials or commit-message stdin.
- Supervise cancellation and timeout cleanup, including helper/child processes
  where each platform permits it.
- Virtualize large lists and diffs, cap rendered lines, and expose truncation
  with a deliberate load-more action.
- Add benchmark fixtures and budgets for startup, 10k commits, 10k changes,
  large diffs, memory growth, and rapid repository switching.

**Done when:** Documented performance budgets pass in CI and repeated refresh,
cancel, and tab switching do not leak processes, timers, tokens, or listeners.

## Task 24 — Accessibility, localization, and preferences

**Depends on:** Task 23.

**Goal:** Make the pixel interface adaptable without losing its visual
identity or keyboard-first workflow.

- Introduce versioned preference models with migration and corrupt-data
  recovery.
- Add UI scale, reduced motion, high contrast, color-safe graph palettes,
  configurable shortcuts, default branch/remote choices, and refresh policy.
- Move user-visible text into localization resources and ship English first;
  keep diagnostics separate from translated user messages.
- Audit semantics, focus order, screen-reader labels, text scaling, and
  keyboard-only operation on every supported platform.
- Add golden tests at supported scales plus semantic and shortcut-conflict
  tests.

**Done when:** The entire core workflow is usable without a mouse or color
distinction and settings survive upgrades safely.

## Task 25 — Signed public release pipeline

**Depends on:** Tasks 23 and 24.

**Goal:** Produce trustworthy installable releases rather than unsigned build
folders.

- Define semantic versioning, release notes, compatibility policy, and a
  repeatable release checklist.
- Produce Windows installer/archive, signed and notarized macOS app/package,
  and Linux archive plus an agreed package format.
- Generate checksums, SBOM, provenance, pinned-action verification, and
  dependency/license audit reports.
- Add opt-in update metadata and first-run diagnostics; do not collect
  telemetry or crash data without an explicit privacy design and consent.
- Verify clean-machine install, launch, upgrade, downgrade warning, uninstall,
  and artifact naming on all three platforms.

**Done when:** A `release-*` tag on a matching release commit creates reviewed,
signed, checksum-verifiable artifacts and the public documentation explains
installation and trust verification.
