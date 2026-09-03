# Changelog

## 2026-09-03

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
