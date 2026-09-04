# Post-MVP roadmap

This roadmap turns the MVP into a dependable daily Git client while preserving
gift's clean-room workflow research and minimal 2D pixel-game interface.
Task 15 was marked safe done under WSL because the remaining native bundle
check is CI-only in this environment. Tasks 16 through 37 are complete;
Task 40 is complete, Task 38A is the next priority for private-remote access,
Tasks 41 through 47 follow, Task 39 is the final visual-regression pass, and
Task 38 is the deferred signed public release milestone.
Tasks 40 through 47 may run before Tasks 36 through 39 because their listed
dependencies are already complete. Task 38A uses the completed remote, hosting,
and process-safety foundations; Task 39 follows the product UX backlog, while
Task 38 is scheduled last for the stable product surface.
Do not start a later post-MVP task until its dependencies are complete and its
visible behavior has been recorded in the behavior ledger without copying
proprietary implementation details or assets.

## Delivery order

| Phase | Tasks | Outcome |
|---|---|---|
| Daily workflow | 16–19 | Multiple repositories, partial staging, richer commits, and useful history exploration |
| Safe power tools | 20–22 | Advanced branch operations, conflict resolution, stash, tags, and remote management |
| Inspection & local recovery | 23–27 | Diff comparison, shelves, file history, blame, reset, revert, and history rewriting |
| Remote & repository topology | 28–34 | Remote branches, update/push safety, worktrees, ignore rules, submodules, recovery, and setup |
| Optional integrations | 35 | GitHub/GitLab links and review handoff without coupling the core backend to a host API |
| Product readiness foundation | 36–37 | Large-repository resilience and accessibility/preferences |
| Credential and account access | 38A | Secure GitHub, GitLab, self-hosted, HTTPS, and SSH authentication |
| Desktop interaction UX | 40–47 | Discoverable context actions, direct cherry-pick entry points, and browse-assisted path selection |
| Visual regression QA | 39 | Final overflow, theme, font, and interaction-state validation |
| Public release | 38 | Signed, provenance-backed installers and update metadata after the product surface stabilizes |

Every task must include backend tests with isolated Git fixtures, controller
tests for async state changes, responsive widget tests, beginner-oriented
comments for non-obvious flows, and updates to the behavior ledger and
architecture documentation.

## Scope audit: JetBrains Git workflows

The additional tasks below were derived from the current public IntelliJ IDEA
Git documentation. The audit found that the existing plan covered basic
changes, commits, branches, history, conflicts, stash, tags, remotes, and
upstream tracking, but not the surrounding inspection, local-recovery, and
repository-topology workflows. The product will reproduce the observable
workflow contracts with its own pixel UI; it will not copy proprietary source,
assets, or host-service implementations.

- [Investigate changes in a Git repository](https://www.jetbrains.com/help/idea/investigate-changes.html)
  covers project/file/directory/selection history, revision comparison, get
  from revision, and Git blame annotations.
- [Compare file and folder versions](https://www.jetbrains.com/help/idea/comparing-file-versions.html)
  and the [Diff Viewer](https://www.jetbrains.com/help/idea/differences-viewer.html)
  cover branch/tag comparisons, editable local panes, three-way views, and
  applying or reverting reviewed changes.
- [Shelve or stash changes](https://www.jetbrains.com/help/idea/shelving-and-unshelving-changes.html)
  covers changelists, shelves, repeated unshelving, external patch import, and
  stash diff inspection.
- [Manage Git branches](https://www.jetbrains.com/help/idea/manage-branches.html)
  covers remote branch checkout/tracking, compare-with-current, compare-with-
  working-tree, and branch cleanup.
- [Commit and push changes](https://www.jetbrains.com/help/idea/commit-and-push-changes.html)
  covers push review, target editing, push tags, rejection recovery, and safe
  force push.
- [Use Git worktrees](https://www.jetbrains.com/help/idea/use-git-worktrees.html)
  covers opening, deleting, and pruning linked worktrees, while [Git settings](https://www.jetbrains.com/help/idea/settings-version-control-git.html)
  covers update policy, incoming checks, tag fetching, credential helpers, and
  combined stash/shelf behavior.

GitHub/GitLab pull-request features remain an optional integration task because
they require external APIs, authentication, and account-specific behavior that
is outside the shell-free Git core contract.

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

**Status:** Complete.

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

**Status:** Complete.

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

## Task 23 — Diff and comparison workbench

**Depends on:** Tasks 6, 19, and 21.

**Status:** Complete — bounded source, three-way, navigation, and reviewed
transfer verticals are covered.

**Goal:** Make the diff surface useful for investigating and transferring
changes between revisions, branches, folders, and arbitrary text sources.

- Compare a file or folder with its current revision, another revision,
  branch, tag, commit range, clipboard, or external text source.
- Add bounded side-by-side, unified, and three-way views with binary,
  rename-only, missing, and oversized states.
- Apply, append, revert, or get reviewed file/chunk changes with explicit
  repository, path, revision, and content fingerprints.
- Preserve diff navigation, pane switching, copyable paths, and keyboard
  traversal at compact window sizes.

**Done when:** Isolated fixtures cover root, merge, deleted, binary, rename,
branch, folder, clipboard, and stale-apply comparisons without accepting
arbitrary patch text from the UI.

## Task 24 — Shelves, changelists, and patch exchange

**Depends on:** Tasks 17, 18, and 23.

**Status:** Complete — app-local changelists, reusable shelves, and bounded
patch exchange are covered.

**Goal:** Add JetBrains-style local change organization without confusing a
local shelf with a Git stash.

- Create, rename, activate, delete, and persist changelists; move files or
  selected hunks between them.
- Shelve selected tracked files or changelists, inspect their diff, unshelve
  repeatedly, restore already-unshelved entries, and delete shelves safely.
- Import and export external patch files with bounded size and path checks;
  retain a base revision for three-way conflict recovery.
- Keep unversioned-file limitations and shelf-versus-stash semantics explicit
  in the UI.

**Done when:** Shelf fixtures prove partial selection, repeated unshelving,
conflicts, base revision loss, deletion recovery, and no accidental mutation
of Git stash entries.

## Task 25 — File history, blame, and revision recovery

**Depends on:** Tasks 19 and 23.

**Status:** Complete — path history, rename following, blame, and guarded
Get-from-Revision flows are covered.

**Goal:** Let users explain and recover a file change without browsing only the
global commit graph.

- Add history tabs for a file, directory, and selected line or text range with
  branch, author, date, and path filters.
- Add Git blame annotations with author, date, revision, copy/move detection,
  whitespace options, and navigation to the commit and line diff.
- Annotate previous revisions, show all paths affected by a revision, and
  compare a selected revision with the working copy.
- Add a preview-bound Get from Revision action that restores only the selected
  file and reports deleted, binary, and conflict outcomes.

**Done when:** Real fixtures cover renamed files, root files, selection
history, `-w`/`-M`/`-C` blame modes, binary files, and stale file restoration.

## Task 26 — Undo, reset, and revert safety

**Depends on:** Tasks 18, 20, and 21.

**Goal:** Cover local history rollback while making data-loss boundaries clear.

- Revert one or more commits by creating new commits and return conflict
  resolution state when the inverse does not apply cleanly.
- Undo the latest unpushed commit while preserving its changes in the correct
  index/worktree state.
- Support soft, mixed, hard, and keep reset modes with exact previews of HEAD,
  index, worktree, and potentially discarded data.
- Detect protected branches, pushed commits, detached HEAD, dirty state, and
  in-progress operations before destructive actions.

**Done when:** Fixtures prove each reset mode, multi-commit revert, clean and
conflicted revert, undo preservation, stale previews, and refusal to hard-reset
without explicit confirmation.

## Task 27 — Interactive rebase and history rewriting

**Depends on:** Tasks 20, 21, and 26.

**Status:** Complete — reviewed plans, machine-owned execution, recovery
states, and real-Git safety fixtures are covered.

**Goal:** Provide a reviewed, recoverable plan for editing a branch history.

- Model pick, reword, edit, squash, fixup, drop, and reorder entries before
  starting the rebase.
- Support autosquash, root, and update-refs options only when the selected
  repository state permits them; explain merge-commit and protected-branch
  limitations.
- Show the planned graph and commit-message changes, then expose explicit
  continue, skip, and abort states for conflicts or hooks.
- Keep original OIDs, rewritten OIDs, and reflog recovery references in the
  result so a failed or surprising rewrite remains diagnosable.

**Done when:** Isolated histories cover every plan action, fixup/squash
messages, conflicts, hooks, cancellation, abort, protected branches, and
reachable-commit preservation.

## Task 28 — Remote branches and update project

**Depends on:** Tasks 11, 12, 19, 20, and 22.

**Goal:** Make remote-tracking branches first-class browsing and update targets.

- Parse and group local, remote, recent, and tag refs; check out a remote
  branch as a new tracking local branch or create a local branch from it.
- Compare a branch with the current branch or working tree, list two-dot
  differences, and apply a reviewed file from another branch.
- Add Update Project strategies for merge, rebase, and reset-to-remote with
  stash/shelf clean-worktree choices and explicit conflict recovery.
- Add incoming/outgoing indicators, update information, fetch policy, and
  remote-branch deletion with stale-ref checks.

**Done when:** Fixtures cover missing and moved remote refs, tracking setup,
divergence, local-change protection, update conflicts, reset-to-remote, and
incoming/outgoing refreshes.

## Task 29 — Push review, force-with-lease, and protection

**Depends on:** Tasks 18, 22, and 28.

**Goal:** Make publication a reviewable operation rather than a single opaque
push button.

- Show commits and affected files before pushing, allow a reviewed target
  branch, and support Push All up to Here for a selected commit.
- Support current-branch and all-tags publication modes without silently
  pushing unrelated refs.
- Add force-with-lease only after an explicit preview of the expected remote
  tip; protect configured branches from force push.
- Classify rejected pushes and offer merge or rebase update recovery while
  retaining redacted remote diagnostics.

**Done when:** Bare-remote fixtures cover review, new targets, tags,
non-fast-forward rejection, lease failure, protected branches, and merge or
rebase recovery without overwriting an unexpected remote tip.

## Task 30 — Git worktrees

**Depends on:** Tasks 16, 20, and 22.

**Goal:** Support parallel branch directories linked to one repository.

- List worktrees with branch, path, HEAD, locked, prunable, and current states.
- Create a worktree at a validated path, open it as an isolated repository
  session, and retain the shared object database relationship.
- Remove non-current linked worktrees only after a dirty-state confirmation;
  lock, unlock, and prune stale worktree records.
- Prevent deletion of the main or currently open worktree and keep workspace
  tabs associated with the correct root.

**Done when:** Fixtures cover add/open/remove, occupied branches, dirty
worktrees, locked worktrees, manually deleted paths, prune recovery, and
cross-worktree status isolation.

## Task 31 — Ignore files and repository metadata

**Depends on:** Tasks 5 and 16.

**Goal:** Make ignored and repository-managed files understandable and safe to
edit from the Git workflow.

- Show ignored files on demand and distinguish untracked, ignored, excluded,
  and tracked-but-modified states.
- Add a bounded Ignore action targeting `.gitignore` or `.git/info/exclude`,
  with correct scope and path escaping.
- Inspect and explain `.gitattributes`, line-ending, textconv, and filter
  effects without exposing secrets or executing arbitrary configuration.
- Refresh status and file colors after metadata changes.

**Done when:** Fixtures cover nested ignore patterns, local-only excludes,
negation rules, tracked files that match ignore rules, attributes, and compact
status rendering.

## Task 32 — Submodules and nested repository roots

**Depends on:** Tasks 16, 30, and 31.

**Goal:** Treat a superproject, its gitlinks, and nested repositories as
related but independently mutable roots.

- Parse `.gitmodules` and report initialized, uninitialized, dirty, detached,
  missing, and changed-commit submodule states.
- Add init, sync, update, deinit, and fetch flows with recursive and selected
  module scopes, progress, cancellation, and credential-safe diagnostics.
- Register nested repositories as child roots while keeping parent gitlink
  mutations separate from child commits.
- Show the exact child commit change that the superproject will record.

**Done when:** Fixtures cover nested paths, URL changes, missing modules,
detached module HEADs, recursive updates, child conflicts, and parent/child
mutation isolation.

## Task 33 — Reflog and recovery diagnostics

**Depends on:** Tasks 10, 19, 20, 26, and 27.

**Goal:** Give users a safe way to understand and recover from ref movement.

- Browse bounded HEAD and branch reflog entries with selector, OID, actor,
  timestamp, and reason metadata.
- Show recovery refs for reset, revert, merge, cherry-pick, and rebase flows;
  create a new branch from a reviewed reflog entry instead of moving refs
  implicitly.
- Add a redacted Git operation console showing argv shape, duration, exit
  state, and bounded output without credentials or commit-message stdin.
- Expire diagnostic records and clearly distinguish unreachable objects from
  currently referenced commits.

**Done when:** Fixtures cover branch deletion recovery, reset/rebase reflogs,
operation failures, output truncation, credential redaction, and exact
recovery-branch creation.

## Task 34 — Repository setup and root mapping

**Depends on:** Tasks 4, 12, 22, and 32.

**Goal:** Let users create or obtain repositories through the same safe Git
workflow instead of opening only an existing folder.

- Clone repositories with destination validation, progress, cancellation,
  shallow/depth options, branch selection, and optional submodule recursion.
- Initialize a repository, select or confirm its root, and publish it to a
  newly defined remote without leaking credentials.
- Fetch the remainder of a shallow clone through an explicit Unshallow action.
- Detect directory mappings and multiple/nested Git roots before assigning
  workspace tabs and opaque repository IDs.

**Done when:** Fixtures cover clone success/failure/cancellation, empty-folder
init, shallow/unshallow, invalid destinations, remote publication, and nested
root mapping.

## Task 35 — Optional hosting integration

**Depends on:** Tasks 19, 25, 28, 29, and 34.

**Goal:** Add host-specific links and review handoff without coupling the core
Git backend to a hosting provider.

- Define an adapter boundary for GitHub/GitLab repository and commit links,
  blame links, and optional pull-request discovery.
- Keep account tokens in the platform credential store, redact them from Git
  diagnostics, and make host integration unavailable without disabling local
  Git workflows.
- Add open-in-browser and copy-link actions for commits, files, and blame
  lines; keep URL construction provider-specific and testable.
- Treat pull-request creation, review, and checkout as optional capabilities
  rather than assumptions in the core repository model.

**Done when:** Mock provider tests cover no-provider, authentication failure,
private repository URLs, link generation, and local workflow operation while
the host service is unavailable.

## Task 36 — Large-repository performance and resilience

**Depends on:** Tasks 16–35.

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

## Task 37 — Accessibility, localization, and preferences

**Depends on:** Task 36.

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

Credential lifecycle is intentionally deferred to Task 38A so the hosting
adapter can remain link-focused while private Git remotes gain a dedicated,
secure account-management boundary.

## Task 38A — Credential management and private remote access

**Depends on:** Tasks 3, 12, 22, 28, 29, 34, 35, 36, and 37.

**Goal:** Make private GitHub, GitLab, self-hosted, and other Git remotes
usable without placing credentials in repository URLs, process arguments, logs,
or ordinary application storage.

- Model accounts and credentials separately from repository remotes, with
  explicit host/provider matching for GitHub, GitLab, self-hosted GitLab, and
  generic HTTPS or SSH hosts.
- Add account management for add, edit, remove, select, validate, revoke, and
  connection-test flows; explain authentication-required, invalid, expired,
  revoked, and host-mismatch failures.
- Store secrets only through platform secure storage such as Windows
  Credential Manager, macOS Keychain, or Linux Secret Service/libsecret; never
  persist raw secrets in `SharedPreferences`, repository config, URLs, logs,
  operation records, crash data, or analytics.
- Support HTTPS personal-access-token credentials and SSH key/agent
  selection without copying private key material into app-managed storage.
- Inject credentials into clone, fetch, pull, push, and publish operations
  through a bounded askpass/credential-helper boundary; keep cancellation,
  timeout, redaction, and child-process cleanup guarantees intact.
- Provide a clear account/credential selector from remote and repository setup
  surfaces while keeping local Git workflows available when no account is
  configured.
- Cover provider and host matching, multiple accounts, secure-store failures,
  revoked credentials, private remote access, credential-helper invocation,
  cancellation, and redacted diagnostics with isolated fixtures.

**Done when:** A user can add a supported account, test it, select it for a
private remote, clone/fetch/pull/push successfully, remove or revoke it, and
recover from authentication failure without a secret reaching argv, URLs,
ordinary app storage, logs, or operation history.

## Task 38 — Signed public release pipeline

**Depends on:** Tasks 36, 37, and 38A. **Priority:** Deferred until Task 39
and Tasks 41–47 are complete.

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

## Task 39 — Cross-platform visual regression QA

**Depends on:** Task 37 and Task 38A. **Priority:** Run after Tasks 41–47 and
before Task 38.

**Goal:** Keep released desktop surfaces visually stable across supported
window sizes, themes, text scales, and platform font rendering before the
signed release pipeline runs.

- Build deterministic UI fixture states for core screens, dialogs, progress,
  empty, error, disabled, and destructive-confirmation surfaces.
- Capture reviewed light/dark golden matrices at compact, standard, and wide
  desktop sizes with supported text scales.
- Add explicit overflow, clipping, minimum hit-area, focus-ring, and
  button-label alignment assertions around every shared control family.
- Separate platform font-rendering baselines and tolerances so Windows, macOS,
  and Linux differences remain reviewed rather than silently ignored.
- Require intentional baseline updates with a short visual-change rationale
  and retain a manual clean-machine pass for native window chrome.

**Done when:** CI rejects unreviewed layout or theme drift on every supported
platform and the release checklist covers the representative interaction-state
matrix.

## Task 40 — Contextual action foundation

**Depends on:** Tasks 16–35. It does not depend on Tasks 36–39.

**Goal:** Make existing Git operations discoverable where the selected object
already appears, without creating a second mutation path beside the reviewed
workflows.

- Define one typed action descriptor and availability result shared by
  right-click menus, existing overflow menus, keyboard invocation, and future
  command search. The selected repository, object identity, enabled state, and
  disabled reason must come from the same immutable snapshot.
- Add a shared Flutter context-menu presenter with secondary-click placement,
  `Shift+F10`/Menu-key invocation, arrow-key navigation, Escape dismissal,
  focus restoration, semantics, and compact-window edge clamping.
- Route every mutating action into its existing preview/confirmation dialog;
  opening or dismissing a menu must never run Git, refresh selection, or create
  a confirmation token.
- Keep destructive actions grouped and labeled independently of color. Omit
  actions that do not apply to an object; show a reason for temporarily
  disabled actions such as dirty state or an operation already in progress.
- Add shared widget-contract tests for pointer position, keyboard parity,
  disabled reasons, stale selection, focus restoration, and menu dismissal
  while the underlying list refreshes.

**Done when:** A fixture action produces the same label, enabled state, target,
preview route, and telemetry-free outcome from right click, keyboard, and the
existing overflow button, with no duplicate mutation implementation.

## Task 41 — Commit context actions and direct cherry-pick

**Depends on:** Tasks 20, 26, 33, and 40. It does not depend on Tasks 36–39.

**Goal:** Expose commit-scoped operations directly from History so users do not
have to discover cherry-pick inside the generic Advanced branch form.

- Add a History commit-row context menu for Cherry-pick onto current branch,
  Revert commit, Create branch here, Create tag here, Compare, Reset current
  branch to here, Copy full hash, and Copy short hash.
- Bind actions to the selected full commit OID rather than visible row index,
  abbreviation, subject, or the selection after an asynchronous refresh.
- Deep-link Cherry-pick into the existing `GitBranchOperation.cherryPick`
  preview with source OID and current target prefilled. Retain dirty-worktree,
  detached-HEAD, stale-token, cancellation, conflict, continue, skip, and abort
  behavior already implemented by Tasks 20 and 21.
- Deep-link revert/reset/tag/branch/compare into their existing reviewed
  dialogs. Destructive choices must remain preview-first and separated from
  copy/inspect choices.
- Keep the Advanced branch form as a manual fallback, but label its
  commit-or-ref input and provide a visible History shortcut so the feature no
  longer appears absent.

**Done when:** Right-clicking a History commit can preview and execute a
single-OID cherry-pick onto the current branch, conflicts enter the existing
resolution workspace, and every other menu item targets that same OID after a
list refresh.

## Task 42 — Ordered multi-commit operations

**Depends on:** Task 41. It does not depend on Tasks 36–39.

**Goal:** Support deliberate batch cherry-pick and revert without hiding commit
order or turning a partial failure into ambiguous repository state.

- Add keyboard-accessible, non-contiguous History selection while preserving
  the single-selection details workflow and providing an explicit Clear
  selection action.
- Preview the exact full OID sequence, execution direction, target branch,
  combined file impact, duplicates, already-contained commits, merge commits,
  dirty state, and in-progress operation before mutation.
- Execute one reviewed OID at a time in the displayed order, report completed,
  current, and remaining commits, and stop at cancellation, conflict, or typed
  failure without silently skipping work.
- Resume, skip, or abort only the current Git operation. After recovery,
  require an explicit choice to continue the remaining reviewed sequence and
  reject it if refs or selection fingerprints became stale.
- Cover reverse-visible history order, merge-commit mainline requirements,
  duplicate OIDs, mid-sequence conflicts, cancellation, stale previews, and
  recovery in isolated real-Git fixtures.

**Done when:** A reviewed multi-selection yields a deterministic cherry-pick or
revert sequence whose partial progress and remaining work survive conflict
resolution without replaying completed commits.

## Task 43 — Change and file context actions

**Depends on:** Tasks 17, 23–25, 31, and 40. It does not depend on Tasks 36–39.

**Goal:** Put path-scoped workflows beside changed files, diffs, and commit-file
rows while keeping staging and destructive operations selection-safe.

- Add Changes-row actions for Stage, Unstage, Stage selected lines/hunks,
  Discard working changes, Move to changelist, Shelve, Ignore locally, Ignore
  in repository, File history, Blame, Compare, Copy relative path, Copy
  absolute path, and Reveal in file manager.
- Add History changed-file and comparison-file actions for File history,
  Blame at revision where supported, Compare revisions, Copy path, and Reveal
  the current working-tree file only when it exists.
- Bind mutation requests to repository ID, path/original path, diff scope, and
  current fingerprint. Rename, deleted, conflicted, partially staged, ignored,
  missing, binary, and nested-root paths must expose only valid actions.
- Define a small platform boundary for reveal-in-file-manager rather than
  spawning a shell command; unsupported or missing paths remain explicit and
  copy actions still work.
- Reuse existing discard, shelf, ignore, history, blame, and comparison
  previews instead of duplicating backend commands in menu handlers.

**Done when:** Pointer and keyboard context menus on each path surface expose
the same valid operations, stale path selections cannot mutate another file,
and destructive items always enter their existing reviewed flow.

## Task 44 — Branch and remote context actions

**Depends on:** Tasks 20, 22, 28–30, and 40. It does not depend on Tasks 36–39.

**Goal:** Replace the limited trailing branch menus with complete,
selection-aware local and remote ref actions.

- Add local-branch actions for Checkout, Merge into current, Rebase current
  onto this branch, Compare with current, Rename, Delete, Push, Set/change
  upstream, Copy branch name, and Copy full ref.
- Add remote-branch actions for Checkout as local, Compare with current,
  Cherry-pick a selected commit through History rather than guessing a branch
  tip, Delete remote branch, Copy name/ref, and open host links when supported.
- Present the same descriptors from right click and the existing trailing
  popup. Current branch, symbolic remote HEAD, protected branch, detached
  state, dirty state, missing upstream, and active operations must have correct
  availability and explanations.
- Prefill the existing branch, comparison, push, remote, and hosting dialogs
  with full ref identities; revalidate refs and preview fingerprints before
  every mutation.
- Keep branch switching on primary click. Secondary click must select for
  context without checking out or otherwise mutating the branch.

**Done when:** Local and remote refs have complete right-click and keyboard
menus, every mutation is previewed against a fresh full ref, and ordinary
selection never switches branches accidentally.

## Task 45 — Workspace and repository context actions

**Depends on:** Tasks 16, 30, 32, 34, and 40. It does not depend on Tasks
36–39.

**Goal:** Make repository tabs, recent repositories, worktrees, submodules, and
nested roots manageable from the object the user is already viewing.

- Add workspace-tab actions for Select, Close, Close others, Close tabs to the
  right, Copy root path, Reveal root, Refresh, and Replace missing root.
- Add recent-repository actions for Open, Open in new tab, Remove from recent,
  Copy path, Reveal, and Choose replacement when the saved path is missing.
- Add worktree/nested-root/submodule actions for Open as tab, Copy path,
  Reveal, Refresh, and the already supported reviewed remove/lock/deinit flows
  where valid.
- Preserve active-tab and focus invariants when closing or replacing multiple
  tabs. Canonical roots and opaque repository IDs, not display names or list
  indices, identify actions across refreshes.
- Keep one-click primary behavior unchanged and make secondary-click selection
  non-destructive. Destructive menu items must retain their current
  confirmations and dirty-state checks.

**Done when:** Every repository-like row has a consistent pointer/keyboard
context menu and a refresh, reorder, disappearance, or duplicate canonical
root cannot redirect an action to another workspace.

## Task 46 — Browse-assisted absolute folder fields

**Depends on:** Tasks 16, 30, and 34. It does not depend on Tasks 36–39 or 40.

**Goal:** Keep paths editable for expert workflows while making normal folder
selection a native, remembered, validation-guided interaction.

- Introduce one editable folder-field control with a Browse button, paste,
  clear, keyboard submission, full-path tooltip, inline validation, and native
  directory picker injection for tests.
- Apply it to clone destination, local clone source, repository initialization,
  nested-root scan, worktree destination, missing-root replacement, and any
  other absolute directory input. URL clone sources keep URL entry and offer a
  local-folder chooser only when local source mode is selected.
- For clone and worktree destinations that may not exist, choose an existing
  parent folder and show an editable proposed child name before creation.
  Never imply that the native picker can select a nonexistent directory.
- Remember the last successful directory per purpose, seed from the active or
  recent repository where appropriate, and avoid leaking one repository's
  destination into an unrelated destructive flow.
- Normalize separators only after acceptance, preserve valid platform roots
  and UNC paths, expand no shell syntax, and distinguish missing, inaccessible,
  non-directory, non-empty, nested-repository, and already-open errors inline.
- Cover Windows drive/UNC paths, macOS/Linux roots, cancellation, permission
  failure, nonexistent child creation, manual typing, and narrow layouts.

**Done when:** Every absolute folder workflow supports both native browsing and
direct editing, reopens at a relevant safe location, and explains invalid
paths before the user reaches a backend error.

## Task 47 — Repository-relative path navigation

**Depends on:** Tasks 19, 23, 25, 31, and 35. It does not depend on Tasks
36–40 or 46.

**Goal:** Replace error-prone repository-relative path typing with bounded
search and browsing while preserving direct entry.

- Add a searchable repository path field that can query tracked files,
  directories, changed paths, and known deleted/renamed paths without scanning
  outside the canonical repository root.
- Support explicit file, directory, or either modes and apply them to History
  path filters, File History/Blame, folder comparison, three-way file paths,
  hosting file links, ignore/attribute inspection, and other relative-path
  inputs.
- Keep the text field editable with paste, separator normalization, exact
  keyboard submission, clear, recent in-repository selections, and a Browse
  affordance. Suggestions must show enough parent context to disambiguate
  duplicate filenames.
- Debounce and cancel queries, cap results, expose truncation, preserve input
  during refresh, and derive suggestions from bounded Git output rather than
  recursive UI-thread filesystem walks.
- Validate repository containment and path kind before action dispatch;
  handle spaces, Unicode, case-sensitive/case-insensitive collisions,
  submodules, nested roots, renames, deletions, ignored paths, and empty
  repositories explicitly.

**Done when:** Each repository-relative path flow can be completed by browsing
or typing, keyboard-only selection is equivalent to pointer selection, and no
suggestion or stale result can address a path outside the active repository.
