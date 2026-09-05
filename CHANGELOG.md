# Changelog

## 2026-09-05
- fix(push): separated the repository push-account selector from the remote
  selector and constrained its labels for narrow dialogs.
- fix(ui): removed the redundant welcome repository-folder field so
  `Open Repository` opens the native folder chooser directly.
- fix(ui): removed hover tooltips from text fields and path rows where their
  popovers could cover adjacent controls, while keeping action tooltips and
  accessible labels intact.
- fix(ui): clarified the welcome startup hierarchy by using a single
  `Get started` section heading above the existing repository actions.
- fix(paths): polished repository-relative navigation with browse-all recovery,
  loading and no-match states, stale-refresh clearing, compact status
  indicators, and keyboard suggestion selection.
- feat(paths): added bounded repository-relative search with browse suggestions,
  separator normalization, file/folder validation, and stale-root protection.
- feat(paths): added purpose-scoped editable folder fields with native browse,
  remembered safe locations, keyboard submission, and inline validation.
- feat(workspace): added root-bound tab and recent-repository context actions
  with stale-target guards, nested-root opening, and direct file-manager reveal.
- feat(actions): added full-ref local and remote branch context menus with
  stale-row routing guards and reviewed workflow entry points.
- feat(changes): added multi-file path selection with keyboard-accessible
  pixel checkboxes and serialized Stage selected handling.
- feat(actions): added selection-safe change, history-file, and comparison-file context actions with platform file-manager reveal.
- feat(history): exposed OID-bound commit context actions and direct
  cherry-pick entry points.
- feat(history): added ordered multi-commit selection, preview, progress,
  and conflict recovery.
- fix(history): replaced persistent commit selectors with explicit selection
  mode and spaced changed-file rows.
- feat(typography): bundled Noto Sans KR fallback support for Korean paths.
- feat(auth): added Git Credential Manager browser sign-in, GitHub and GitLab
  provider marks, and per-repository account selection.
- fix(ui): aligned pixel-cut button states, toolbar controls, repository tabs,
  change-list density, pane sizing, summary metrics, and empty-detail guidance.
- fix(ui): redesigned controls as square pixel surfaces and standardized
  toolbar, dialog, card, and wrapped-action spacing on the 4/8/12/16 px grid.

## 2026-09-04
- fix(auth): improved Git account management with searchable host groups,
  clearer secure-storage guidance, and focused add/edit flows.
- fix(branches): recovered remote branch lists through full-ref parsing and a
  simpler fallback format instead of failing the entire branch workflow.
- fix(push): made tracked destinations the default, linked first pushes to
  their chosen upstream, and moved uncommon ref and force controls behind an
  advanced section.
- fix(remotes): exposed remote setup and branch tracking from the remote and
  branch workflows and routed branch publication through reviewed push.
- fix(branches): distinguished malformed remote-ref and local-branch parser
  failures so branch recovery diagnostics identify the actual source.
- feat(auth): added secure Git account management, provider and host matching,
  bounded credential injection, and private-remote recovery with redacted
  diagnostics.
- docs(roadmap): inserted credential management before visual QA and public
  release so private remotes have a secure account path.
- docs(roadmap): deferred the public release pipeline until the remaining
  desktop interaction UX and final visual regression pass are complete.
- fix(branches): surfaced fetch and checkout failures in modal error feedback
  after verifying real remote refs and tracking branches.
- fix(preferences): separated accessibility, repository, and shortcut fields
  to prevent compact-dialog text overlap.
- fix(branches): made remote fetching visible, cancellable, and reliable on
  compact dialogs, including fresh remote-only branch results.
- feat(resilience): added debounced repository watching, bounded diff paging,
  cache invalidation, and process-tree cleanup diagnostics.
- feat(accessibility): added versioned preferences for scale, motion, contrast,
  color-safe graph colors, locale-ready labels, and configurable shortcuts.
- fix(branches): exposed remote fetching and empty remote-cache guidance in the
  branch browser so remote-only branches can be retrieved and reviewed.
- feat(ui): added shared typed contextual actions for secondary click,
  Shift+F10/Menu, and per-row overflow entry points with stale-snapshot
  protection and existing mutation routing.
- fix(ui): restored vertical spacing around File History follow-renames,
  line-range, and blame controls and separated adjacent option groups in
  interactive rebase, object, and remote dialogs.
- fix(ui): constrained repository dropdown options to one line with ellipsis
  so long branch, commit, path, and mode labels remain readable.
- fix(ui): replaced the heavy boxed button treatment with a restrained
  primary, secondary, destructive hierarchy and lightweight icon controls.
- fix(ui): kept unchanged background status polling silent so periodic
  refreshes no longer disabled or replaced the visible refresh button.
- fix(ui): increased shared text and control breathing room and allowed compact
  action groups to wrap without clipping or horizontal overflow.
- fix(push): separated the preflight notice from the Remote selector so their
  surfaces and labels no longer overlap.
- fix(ui): restored the legible UI font and standardized filled, outlined,
  text, and icon button geometry without changing their action hierarchy.
- docs(roadmap): added cross-platform visual regression QA as Task 39.
- docs(roadmap): added Tasks 40–47 for contextual Git actions, direct
  cherry-pick discovery, workspace menus, and browse-assisted path selection.
- feat(windows): added a per-user gift setup executable with Start Menu and
  uninstall registration alongside the release bundle and portable launcher.
- fix(push): restored vertical breathing room between the Remote and Publish
  scope controls so their labels remain legible at compact widths.
- fix(windows): made gift-setup create Desktop and Start Menu shortcuts and
  clarified that portable only runs from temporary files without installation
  side effects.

## 2026-09-03
- fix(ui): grouped repository actions into a categorized menu and reduced
  crowded Changes and History toolbars.
- fix(ui): improved the welcome action hierarchy and gave recent repositories
  clearer card, status, and open affordances.
- fix(ui): standardized dialog action spacing and hardened compact hosting and
  repository-setup layouts against cramped windows.
- fix(ui): kept History's rollback, rebase, hosting, and refresh actions
  visible without requiring an extra menu step.
- fix(ui): prevented expandable revision and commit-option text from being
  clipped at compact widths and larger text scales.
- fix(ui): exposed primary Changes actions while retaining a categorized menu
  for less frequent repository tools.
- build(windows): added a self-extracting portable executable beside the
  standard Windows release bundle.
- fix(push): explained that review is a safe preflight, labeled the final
  remote-writing action, and separated destination, commits, and remote-tip
  details.
- fix(ui): added floating-label line height and input padding so dropdown
  labels remain fully visible at narrow widths and larger text scales.
- fix(build): hid the portable launcher's PowerShell console by routing the
  self-extracting entry point through the Windows Script Host.
- fix(ui): increased shared dropdown floating-label clearance and removed the
  dense attribute selector layout that could clip labels against field borders.



- feat(task31): added source-aware ignore status, scoped ignore rules, and
  bounded repository metadata inspection.
- feat(metadata): explained text, EOL, diff, and filter attributes without
  executing configured commands.
- feat(task32): added independent submodule status, lifecycle actions, and
  nested-root workspace mapping.
- feat(submodules): added explicit scoped init, sync, update, deinit, and
  compact manager controls for child repositories.
- feat(task33): added bounded reflog browsing and confirmation-bound recovery
  branch creation.
- feat(recovery): added a redacted process-local Git operation console that
  omitted stdin and bounded diagnostic output.
- feat(task34): added validated clone, initialize, shallow recovery, and
  bounded nested-root discovery flows.
- feat(setup): added responsive repository setup and reviewed publish controls
  from Welcome and repository actions.
- feat(task35): added GitHub and GitLab adapter contracts for safe hosted links
  and optional review handoff.
- feat(hosting): added responsive commit, file, blame, copy, and browser-open
  entry points with local-flow fallback for unsupported hosts.
- feat(task30): added typed worktree listing, isolated creation/opening, and
  preview-bound remove, lock, unlock, and prune actions.
- feat(workspace): opened linked worktrees as independent repository tabs and
  added a responsive Worktree manager with dirty-removal confirmation.
- feat(task29): added review-bound branch, selected-commit, explicit-tag, and
  force-with-lease push flows with protected-branch and rejection recovery.
- fix(remote): routed remote push actions through the review dialog instead of
  running an opaque push directly.
- fix(history): kept long diff text aligned with its fixed viewport background
  while horizontal scrolling.
- feat(remote): exposed a direct Push entry point from the Changes workspace.
- fix(ui): prevented compact History filters and details from overflowing, and
  kept diff backgrounds tied to the available viewport width.
- fix(ui): made File History and Advanced revision controls scrollable and
  ellipsis-safe in narrow windows.
- fix(history): made selected commit diff backgrounds fill the viewer width and
  added inline file-diff collapse toggles.
- feat(task28): added remote-branch browsing, tracking checkout, safe deletion,
  comparison entry points, and reviewed Update Project recovery flows.
- fix(ui): prevented interactive controls from clipping text and normalized
  compact button, checkbox, and input spacing across repository workflows.
- fix(history): unified diff row background widths across short and long lines.
- feat(task27): added immutable interactive-rebase plan and action validation
  contracts.
- feat(task27): added real-Git interactive-rebase previews with linear-range
  matching and unsafe-state blockers.
- feat(task27): added machine-owned interactive-rebase execution, recovery,
  rewritten-OID reporting, and History plan controls.
- fix(task27): classified conflict, hook, cancellation, and option-limit
  outcomes and added reviewed reword subjects.
- fix(ui): unified History detail scrolling, clarified repository action labels,
  and hardened compact menu layouts.
- fix(history): added a recent-commit target picker so reset no longer
  requires manually entering HEAD^ or HEAD~1 for common cases.
- fix(history): rendered the selected file diff directly below its file row
  instead of at the bottom of commit details.
- feat(task26): added preview-bound reset, undo, and revert safety with
  protected-state checks and explicit conflict recovery.
- fix(history): improved selected commit-file diffs with context, line numbers,
  change counts, copy, semantic colors, and independent scrolling.
- fix(ui): aligned diff checkboxes with code-line height and removed extra
  bottom spacing.
- fix(build): cleared generated Flutter desktop caches before release builds
  to prevent stale frontend errors after Windows source updates.
- docs(roadmap): expanded the JetBrains Git workflow backlog with Tasks 23–35.
- feat(task23): added a fingerprint-guarded revision and folder comparison
  workbench with lazy selected-file diffs and responsive entry points.
- feat(task23): added reviewed comparison Apply and Revert transfers with
  checked machine-generated patches and refreshed status.
- feat(task23): added bounded clipboard, external-text, three-way, and file
  navigation comparison flows with explicit content states.
- feat(task24): added persistent app-local changelists, reusable shelves, and
  bounded patch import/export without mutating Git stash.
- feat(task25): added bounded file history, rename-following blame, and
  fingerprint-guarded Get-from-Revision workflows.
- build(identity): replaced the desktop icon and README wordmark with a
  chubby Shiba Inu pixel mascot and gift-ribbon mark, and documented the
  Git-plus-Flutter name.
- feat(task22): added identity-bound stash, tag, remote, and upstream
  management workflows with responsive object controls.
- feat(task21): added fingerprint-guarded conflict inspection, resolution,
  and responsive three-pane recovery workflows.
- fix(task19): preserved merge topology and peeled annotated history refs for
  older repositories.
- fix(graph): rendered single-branch history as one connected lane of commit nodes.
- fix(graph): compacted closed history lanes so surviving commit ancestry no longer drifted into parallel columns.
- fix(graph): clarified branch topology with dotted lanes, stepped transitions, and pixel commit markers.
- feat(task20): added preview-bound advanced branch operations and explicit recovery states.
- feat(task19): added snapshot-bound history search and lazy commit inspection.

## 2026-09-02

- feat(task18): added guided commit options, identity preflight, templates, and history-change outcomes.
- breaking(branding): renamed the product identity and desktop metadata to gift and replaced the mascot with a 2D pixel-game logo.
- feat(task17): added safe hunk and line staging with stale selection guards.
- breaking(branding): renamed the product identity, package, assets, and desktop metadata to gift.
- feat(task16): added persisted multi-repository workspace tabs and isolated repository sessions.
- feat(ui): rebuilt the Git graph and added persistent light and dark pixel themes.
- fix(ui): replaced the low-legibility pixel font with Pixelify Sans and raised the type scale.
- fix(ui): replaced Pixelify Sans with the heavier Jersey 15 pixel font for clearer UI text.
- fix(ui): aligned light and dark semantic color roles and added contrast checks.
- fix(ui): refined the compact pixel type scale and prevented text and button overflow.
- fix(ui): corrected light-theme contrast, tightened button proportions, and aligned screen gutters.
- fix(ui): improved dual-font readability, theme contrast, and compact component alignment.
- fix(ui): enabled continuous multi-line selection across rendered diff rows.
- fix(build): changed desktop executable copyright metadata to kimmandoo.
- change(identity): changed desktop bundle identifiers to app.kimmandoo.gift.
- fix(ui): hardened compact layouts across core screens and operation dialogs.
- build(icon): generated desktop release icons from the gift icon asset.
- docs(roadmap): planned the ordered post-MVP work through signed public releases.
- fix(hardening): bounded Git processes, stabilized cancellation, preserved history lanes, and revoked discard previews.
- fix(settings): ignored stale async results and persisted canonical Git executable paths.
- breaking(branding): unified Dart packages and desktop product metadata under gift.
- fix(ci): limited automatic workflows to release tags and pinned third-party actions.
- docs(license): licensed gift under the MIT License.
- fix(ci): gated desktop checks to release commits and hardened platform setup.
- build(script): added one-command platform build wrappers and Windows launchers.
- fix(build): preserved launcher line endings across operating systems.
- docs(build): documented manual Linux, macOS, and Windows build steps.
- docs(setup): documented Flutter SDK, PATH, and desktop toolchain setup.
- feat(task5): added porcelain v2 status snapshots and grouped changes screen.
- feat(task6): added bounded staged and working-tree unified diff viewing.
- feat(task7): added serialized staging and un-staging actions.
- feat(task8): added expiring confirmation-based working-tree discard.
- feat(task9): added UTF-8 stdin commits and commit-hook feedback.
- feat(task10): added paginated history with deterministic graph lanes.
- feat(task11): added local branch management and switch feedback.
- feat(task12): added cancellable fetch, pull, push, and remote feedback.
- feat(task13): applied the responsive dark pixel workspace and keyboard
  shortcuts.
- build(task14): added cross-platform verification and desktop CI artifacts.
- docs(branding): updated the README logo with an original pixel-game Git mascot.
- docs(spec): defined the desktop Git behavior target and minimal pixel UI direction.
- breaking(architecture): migrated the Git backend from a native bridge to pure Dart.
- build(scaffold): removed native build plugins, generated bindings, and native toolchain files.
- test(backend): added Dart coverage for Git execution, discovery, redaction, and repository handles.
- feat(task4): added opaque repository handles, recent paths, and Git settings flow.
- fix(task3): drained stream output without reporting capture overflow.
- feat(task3): added the safe Git executor, discovery, redaction, and settings bridge.
- docs(task3): specified the safe Git executor and installation design.
- docs(repo): documented date-grouped changelog entries.
- fix(scaffold): resolved the bridge generator from PATH instead of a user-specific path.

## 2026-09-01

- docs(tasks): extracted and established centralized task tracking board.
- test(harness): verified bare remote repository support and finalized clean-room test harness.
- fix(harness): hardened test repository isolation from global Git signing and unsafe paths.
- fix(scaffold): excluded generated bridge bindings from native formatting.
- fix(scaffold): preserved canonical generated bridge output after formatting.
- build(scaffold): integrated desktop native bridge packaging.
- test(scaffold): asserted the exact Gift core version and documented the Windows build limitation.
- build(scaffold): scaffolded the Gift desktop bridge.
