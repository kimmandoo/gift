# Work Checkpoint

This file is the handoff record for continuing work across query sessions.

## Current checkpoint

- Date: 2026-09-04
- Active task: Task 36 Scale & resilience and Task 37 Accessibility &
  preferences are complete and verified. No implementation task is active.
- Branch: `main`; no new branch or worktree was created.
- Latest completed implementation commit before this session: `a5b3462`
  (`fix(windows): create desktop install shortcut`).
- This session added the Task 36 resilience foundation, Task 37 preference
  surface, and the requested remote-branch fetch affordance.
- Task 36 now watches repository metadata with a debounced coordinator and
  low-frequency fallback, coalesces refreshes, bounds diff caching/rendering,
  exposes deliberate diff paging, and records cancellation/timeout outcomes
  after bounded process-tree cleanup.
- Task 37 now persists validated version-1 preferences with legacy theme
  migration and corrupt-data recovery. UI scale, reduced motion, high
  contrast, color-safe graph colors, refresh policy, default branch/remote,
  English-first labels, semantic controls, and configurable shortcuts flow
  through the app and workspace boundaries.
- Branch browsing now shows a visible fetch affordance, fetches every
  configured remote, refreshes remote-tracking refs, and explains an empty
  remote cache instead of hiding the section.
- Changed files include `TASKS.md`, `CHANGELOG.md`,
  `docs/research/jetbrains-git-mvp-behavior.md`,
  `docs/superpowers/plans/2026-09-02-gift-dart-mvp.md`, this checkpoint,
  `lib/src/app/{app_preferences,app_strings,gift_app,pixel_theme,preferences_dialog}.dart`,
  `lib/src/backend/executor.dart`,
  `lib/src/features/repository/{repository_refresh_coordinator,changes_controller,changes_screen,history_screen,workspace_screen,branch_dialog,remote_dialog}.dart`,
  and their focused tests.
- Verification:
  `flutter test test/features/repository/repository_refresh_coordinator_test.dart
  test/features/repository/changes_screen_test.dart
  test/backend/dart_git_backend_test.dart` passed 43 tests;
  focused Task 37 and repository UI tests passed 49 tests;
  `PATH=/home/mgkim/.local/flutter/bin:$PATH dart run tool/verify.dart`
  passed formatting, analysis, and all 224 Flutter tests.
- Blockers: none.

## Previous checkpoint

- Date: 2026-09-02
- Milestone: Task 15 hardening, UI stabilization, and product identity are
  safe done under WSL; Task 16 multi-repository workspace is complete.
- Source of truth: `TASKS.md` and
  `docs/superpowers/plans/2026-09-02-gift-dart-mvp.md`.
- Completed scope: removed the native implementation, FFI bridge, generated
  bindings, native build plugin, and native build metadata; added a `dart:io`
  Git backend with direct argv execution, bounded output, redacted errors,
  Git discovery/version validation, repository root validation, and
  session-local opaque handles; rewired Flutter screens and tests; added
  `docs/ARCHITECTURE.md` and beginner-oriented source comments.
- Verification: restored the pinned Flutter 3.47.2 SDK with Dart 3.13.2 in
  `/home/mgkim/.local/flutter`; passed `flutter analyze`, the full Flutter test
  suite, and `PATH=/home/mgkim/.local/flutter/bin:$PATH dart run
  tool/verify.dart` (formatting, analysis, and all 81 tests).
- Commit identity cleanup: rewrote all reachable commits to
  `kimmandoo <mingyu5675@gmail.com>`, removed the temporary rewrite refs, and
  force-pushed `main` to GitHub. `git log --all` reports only that identity.
  The pre-rewrite history remains recoverable from
  `/tmp/gift-before-author-rewrite.bundle`.
- Final Task 13 changes added the shared dark pixel theme, square focusable
  surfaces, responsive Changes/History layouts and operation dialog sizing,
  keyboard shortcuts, bottom status feedback, responsive widget tests, and
  beginner-oriented architecture documentation.
- Final Task 14 changes added `tool/verify.dart`,
  `tool/build_desktop.dart`, `.github/workflows/ci.yml`, and
  `docs/RELEASING.md`; the task board, README, changelog, plan, and this
  checkpoint were updated for the completed 14-task MVP.
- Follow-up documentation changes added platform-specific manual Linux, macOS,
  and Windows build steps to `README.md` and linked each release output path.
- Follow-up setup documentation added common Flutter SDK verification plus
  Linux, macOS, and Windows PATH and desktop toolchain instructions to
  `README.md`.
- Follow-up CI changes gated Actions jobs to `release(scope):` commits, added
  Linux desktop dependencies and target activation, made the macOS build
  unsigned for CI, and removed Unix-only commands from cross-platform tests.
- CI repair verification passed `dart run tool/verify.dart`, the Linux release
  build helper, Dart analysis for the build helper, and workflow YAML parsing.
  macOS and Windows runners are configured in the matrix but are not available
  in this Linux workspace for local execution.
- Follow-up build ergonomics added one-command Linux/macOS/Windows shell
  wrappers plus native Windows PowerShell and batch launchers. The desktop
  helper now enables the requested Flutter target before building.
- Added `.gitattributes` so Git Bash shell wrappers keep LF endings and native
  Windows launchers keep Windows-friendly line endings after checkout.
- Task 15 added bounded non-interactive Git execution, deterministic
  cancellation outcomes, continuous paginated history lanes, stale settings
  request guards, canonical Git path persistence, discard-preview revocation,
  and expiry cleanup.
- Task 15 unified the Dart package, app shell, Linux binary/application ID,
  macOS product/bundle ID, Windows executable metadata, docs, tests, and build
  output paths under the lowercase `gift` product identity.
- Release automation now starts only for `release-*` tags whose commit uses a
  `release(scope): subject` message. Third-party Actions are pinned by commit.
- Added the MIT `LICENSE` and updated the public README license statement.
- Verification: `dart run tool/verify.dart` passed formatting, analysis, and
  all 66 tests. Workflow YAML parsing and release-subject matching passed.
- Local build note: `./tool/build_linux.sh` reached native compilation but the
  host lacks `libgtk-3-dev`; installing it requires a sudo password unavailable
  to this session. CI already installs this dependency before Linux builds.
- Added Tasks 16–38 as an ordered post-MVP backlog in
  `docs/POST_MVP_ROADMAP.md`. The roadmap covers multi-repository workspaces,
  partial staging, commit and history depth, advanced branches, conflicts,
  Git object management, scale, accessibility, and signed public releases.
- Task 15 was marked safe done under WSL. Its Linux GTK/native bundle check is
  delegated to CI because this host cannot provide the required desktop
  package. Task 16 was completed in this session.
- UI stabilization replaced one-line commit markers with graph-row segment
  models for incoming, continuation, fork, merge, and compressed wide-lane
  rendering. Pagination recomputes the complete visible graph.
- Replaced the first-pass Silkscreen font with the more legible OFL Pixelify
  Sans font, then replaced it with Jersey 15 for heavier, simpler glyphs, and
  kept the compact 12/13/15/16/18/22/24 px type scale with
  explicit line spacing, button sizing, and centralized heading tokens.
- Added persisted light/dark theme switching, compact 360x640 layout coverage,
  and responsive dialog bounds.
- `assets/images/gift_icon.png` is now the release icon source. Generated
  macOS AppIcon PNGs and the Windows multi-size ICO use that asset; Flutter
  also bundles it for Linux packaging.
- UI verification: `dart run tool/verify.dart` passed formatting, analysis,
  and all 71 tests. Added compact 320x480 welcome, compact 360x640 Changes and
  History, theme persistence, wide graph, merge/fork, and already-active
  parent lane coverage. Font and icon asset validation passed.
- Palette pass replaced generated/direct color mixing with explicit semantic
  light and dark roles, matching `on*` text colors for status containers, and
  a 4.5:1 contrast regression suite. Direct red error text was removed.
- Current UI refinement lowered the overall type scale, strengthened Jersey 15
  body weight and line spacing, moved screen headings to shared theme tokens,
  and added common button text/padding rules.
- Current font pass replaced Pixelify Sans with Jersey 15, darkened all light
  accent roles for raised-surface contrast, and bundled the matching OFL text.
- Current diff fix wrapped rendered lines in one `SelectionArea`, changed line
  bodies to selectable `Text`, and excluded line numbers from copied content so
  dragging across multiple rows stays continuous.
- Current packaging fix changed Windows and macOS executable copyright fields to
  `kimmandoo`, added matching Linux AppStream developer metadata, and unified
  desktop bundle identifiers under `app.kimmandoo.gift`.
- Current layout hardening made narrow summary/status rows wrap safely, added
  branch-input stacking below 300 px, and enabled dialog action overflow
  spacing so text and buttons do not collide.
- Current typography pass assigned OFL Atkinson Hyperlegible Next to body,
  button, list, input, and status text while retaining Jersey 15 for pixel-game
  headings. It tightened the shared type scale, explicitly mapped light/dark
  text colors, reduced control heights, and added a compact repository action
  menu plus responsive screen and dialog spacing.
- Current session verification passed `flutter analyze`, `flutter test`, and
  `PATH=/home/mgkim/.local/flutter/bin:$PATH dart run tool/verify.dart` with
  all 71 tests passing.
- Current typography verification passed the full `dart run tool/verify.dart`
  suite and compact 320–360 px widget coverage at 1.2x text scaling for the
  welcome, changes, history, branch, remote, and Git settings surfaces.
- Current identity verification found no remaining obsolete bundle-ID or
  native-language metadata references in the source tree, and the Linux
  AppStream metadata parsed as valid XML.
- Task 16 behavior-ledger scenarios were added for workspace restore, tab
  lifecycle, duplicate paths, unavailable folders, and cross-repository
  mutation isolation.
- First Task 16 RED test: `flutter test
  test/features/repository/workspace_store_test.dart` failed because
  `workspace_store.dart` and its persistence contract did not exist yet; the
  test then passed after the workspace store and controller were implemented.
- Task 16 implementation added `WorkspaceStore`, `WorkspaceController`, the
  responsive workspace tab shell, per-tab Changes/History controllers, and
  app-entry restoration wiring. Failed opens remain visible and recoverable;
  canonical duplicates are removed before persistence.
- Task 16 verification passed the workspace store/controller tests, including
  compact 360x640 tabs at 1.2x text scaling, keyboard navigation, controller
  isolation, and app-entry restoration.
- Changed implementation files this session: `lib/src/app/gift_app.dart`,
  `lib/src/features/repository/{changes_screen,repository_controller,welcome_screen,workspace_controller,workspace_screen,workspace_store}.dart`,
  plus the workspace behavior, architecture, plan, task, changelog, and test
  files.
- Concurrent work note: the README Windows registry command and `.serena/`
  project configuration were included in this session's requested commit.
- Blockers: no source blocker. The Linux release build still requires the host
  `libgtk-3-dev` package, whose installation requires a sudo password
  unavailable to this session.
- Task 33 activation recorded RECOVERY-02/03 in the behavior ledger. Its first
  RED command failed because the typed recovery and operation-console
  contracts did not exist; the real-Git and widget fixtures then passed.
- Task 33 added bounded reflog browsing, stale/fingerprint-bound recovery
  branch creation, and an operation history that stores redacted argv and
  diagnostics without stdin. The Changes actions expose the responsive
  Recovery diagnostics dialog.
- Changed Task 33 files: `TASKS.md`, `CHANGELOG.md`,
  `docs/research/jetbrains-git-mvp-behavior.md`,
  `docs/superpowers/plans/2026-09-02-gift-dart-mvp.md`, this checkpoint,
  `lib/src/backend/{executor,recovery,git_gateway,dart_git_backend,dart_git_gateway,repository_service}.dart`,
  `lib/src/features/repository/{recovery_dialog,changes_screen}.dart`, and
  the related backend/widget test and gateway-stub files.
- Verification: `PATH=/home/mgkim/.local/flutter/bin:$PATH dart run
  tool/verify.dart` passed formatting, analysis, and all 200 Flutter tests;
  `git diff --check` passed.
- Task 34 activation recorded SETUP-02/03 in the behavior ledger. The first
  RED command `/home/mgkim/.local/flutter/bin/flutter test
  test/backend/setup_test.dart` failed before implementation; the real-Git
  setup fixture then passed after the typed setup and root-discovery contracts
  were added.
- Task 34 is complete. It added validated clone/init/unshallow operations,
  bounded nested-root discovery, reviewed publish entry points, and responsive
  Welcome/repository setup controls.
- Changed Task 34 files: `TASKS.md`, `CHANGELOG.md`,
  `docs/research/jetbrains-git-mvp-behavior.md`,
  `docs/superpowers/plans/2026-09-02-gift-dart-mvp.md`, this checkpoint,
  `lib/src/backend/{setup,git_gateway,dart_git_backend,dart_git_gateway,repository_service}.dart`,
  `lib/src/features/repository/{repository_setup_dialog,changes_screen,welcome_screen}.dart`,
  and the related test/stub files.
- Verification: `PATH=/home/mgkim/.local/flutter/bin:$PATH dart run
  tool/verify.dart` passed formatting, analysis, and all 203 Flutter tests;
  `git diff --check` passed.
- Task 35 is complete. It added provider-neutral GitHub/GitLab URL adapters,
  credential-safe repository metadata, commit/file/blame link generation,
  copy/browser-open actions, optional review-handoff capability reporting,
  and responsive Changes/History entry points.
- Changed Task 35 files: `TASKS.md`, `CHANGELOG.md`,
  `docs/research/jetbrains-git-mvp-behavior.md`,
  `docs/superpowers/plans/2026-09-02-gift-dart-mvp.md`, this checkpoint,
  `lib/src/backend/{hosting,git_gateway,dart_git_backend,dart_git_gateway,repository_service}.dart`,
  `lib/src/features/repository/{hosting_dialog,changes_screen,history_screen}.dart`,
  and the related hosting backend/UI test and gateway-stub files.
- Verification: `PATH=/home/mgkim/.local/flutter/bin:$PATH dart run
  tool/verify.dart` passed formatting, analysis, and all 206 Flutter tests;
  `git diff --check` passed.
- Completed a post-Task-35 UI/UX audit focused on crowded navigation,
  dialog spacing/readability, and compact-window reachability.
- Replaced the Changes toolbar's long icon row with a categorized repository
  actions menu and applied the same compact action-menu treatment to History.
- Improved Welcome primary actions and recent-repository cards; added shared
  dialog action spacing and safer compact Hosting/Repository Setup sizing.
- Changed files: `CHANGELOG.md`, this checkpoint, the implementation plan,
  `lib/src/app/pixel_theme.dart`, the Changes, History, Hosting dialog,
  Repository Setup dialog, Welcome screen, and Changes widget test.
- Verification: `dart format` passed; `flutter analyze` passed; `flutter test
  test/features` passed with 69 tests; `git diff --check` passed. The
  repository-wide `dart run tool/verify.dart` completed format and analysis but
  retained 15 known Windows-only backend fixture failures involving
  newline/path normalization, rebase cleanup, and file locking. Desktop
  `flutter run -d windows` built and synced successfully.
- Continued the UI follow-up after user review: expandable revision and commit
  option tiles now preserve wrapped text, and compact reset spacing keeps the
  advanced control reachable without hidden content.
- History keeps rollback, rebase, hosting, and refresh actions visible in its
  app bar. Wider Changes toolbars expose Push, Update project, Branches, and
  History while compact windows retain the categorized actions menu.
- Additional changed files: `lib/src/features/repository/reset_dialog.dart`,
  plus the updated Changes and History toolbar widgets and UI records.
- Additional verification: focused Changes, History, and Reset widget tests
  passed after the follow-up edits.
- Implemented the portable Windows packaging follow-up: the Windows PowerShell
  and batch wrappers now build the normal Release directory and create
  `build/windows/x64/runner/gift-portable.exe`. The wrapper embeds the Release
  bundle as a ZIP in IExpress, extracts to a unique temporary directory,
  waits for `gift.exe`, and cleans up. Windows CI publishes both the Release
  directory and the portable EXE. Git remains a system dependency.
- Clarified Push review UX in `push_dialog.dart`: the dialog explains that
  review does not write remotely, the preview has ready/blocked states and
  explicit destination/commit/remote-tip labels, and actions are named
  `Review changes` and `Push to <remote>`.
- Increased shared floating-label line height and input vertical padding in
  `pixel_theme.dart`; added a narrow 360x640, 1.2x text-scale Push regression
  assertion for dropdown label bounds.
- Additional verification: the portable builder produced a 13,795,328-byte
  PE32+ GUI executable; launching it created the temporary extraction directory
  and exited cleanly when the supervised smoke process stopped. The Windows
  build wrapper completed `flutter build windows --release` and created the
  portable EXE. `flutter analyze`, formatting, `git diff --check`, the focused
  Push test, and the 69-test feature suite passed.
- Continued the packaging/UI follow-up: replaced the portable package's visible
  CMD entry point with a Windows Script Host launcher, so extraction and
  PowerShell execution stay hidden from the user.
- Increased shared dropdown floating-label height to 1.55 and input vertical
  padding to 14, and removed the dense attribute-path dropdown override.
- Changed files in this follow-up: `CHANGELOG.md`,
  `docs/superpowers/plans/2026-09-02-gift-dart-mvp.md`,
  `lib/src/app/pixel_theme.dart`,
  `lib/src/features/repository/ignore_dialog.dart`,
  `tool/package_windows.ps1`, deleted
  `tool/windows_portable_launcher.cmd`, and added
  `tool/windows_portable_launcher.vbs`.
- Verification: focused Push/Ignore/Reset/Update/Branch tests passed; the
  complete feature suite passed with 69 tests; `flutter analyze`, formatting,
  and `git diff --check` passed. The hidden portable package extracted and
  launched under supervision, and `tool/build_windows.ps1` rebuilt the
  Windows Release plus `gift-portable.exe` successfully.
- Next action: activate Task 36 after recording scale/resilience scenarios and
  adding its first failing performance or supervision fixture.

## Current session: UI controls and Windows setup packaging

- Date: 2026-09-04.
- Changed files: `CHANGELOG.md`, `README.md`, `docs/RELEASING.md`,
  `docs/superpowers/plans/2026-09-02-gift-dart-mvp.md`, this checkpoint,
  `.github/workflows/ci.yml`, `lib/src/app/pixel_theme.dart`,
  `lib/src/features/repository/{branch_dialog,changes_screen,ignore_dialog,interactive_rebase_dialog,object_dialog,push_dialog,update_project_dialog}.dart`,
  `test/{branding_test.dart,features/repository/push_dialog_test.dart}`,
  `tool/{build_windows.bat,package_windows.ps1,package_windows_installer.ps1,windows_setup_launcher.ps1,windows_setup_launcher.vbs,windows_uninstall.ps1,windows_uninstall.vbs}`.
- UI change: standardized bounded dropdown option labels, added square pixel
  button states, and made stage/unstage/discard actions visually distinct.
- Windows change: `package_windows.ps1` now emits
  `build/windows/x64/runner/gift-setup.exe`, a per-user installer that creates
  a Start Menu shortcut and HKCU uninstall registration.
- Verification: `flutter analyze` passed; focused branding, Push, and Changes
  widget tests passed after the dropdown regression test was corrected; the
  complete `flutter test` run passed all UI tests but retained 15 known
  Windows-only backend fixture failures involving newline/path normalization,
  interactive-rebase cleanup, and file locking.
- `tool/build_windows.ps1` completed a clean Windows release build and
  generated `gift-portable.exe` and `gift-setup.exe`; the rebuilt setup smoke
  installed and launched the app, registered the current-user uninstaller,
  exited, and the uninstaller removed the installed files and Start Menu entry.
- `git diff --check` passed. No blockers.
- Session changes were committed as `201c441`. Next action: Task 36.

## Current session: button redesign and silent polling

- Date: 2026-09-04.
- Changed files: `CHANGELOG.md`,
  `docs/superpowers/plans/2026-09-02-gift-dart-mvp.md`, this checkpoint,
  `lib/src/app/pixel_theme.dart`,
  `lib/src/features/repository/{changes_controller,changes_screen,conflict_workspace_screen,hosting_dialog,object_dialog}.dart`,
  and `test/{app_boot_test.dart,branding_test.dart,features/repository/changes_screen_test.dart,features/repository/conflict_workspace_screen_test.dart,features/repository/hosting_dialog_test.dart}`.
- UI change: replaced persistent primary-colored outlines and boxed icon
  buttons with a restrained solid/outlined/text hierarchy, four-pixel corners,
  borderless icon controls, and immediate interaction states. Stage is the
  primary action, Unstage is secondary, and Discard is a lightweight
  destructive action.
- Refresh change: the five-second background poll no longer toggles the
  visible refresh state and does not notify/rebuild the screen when the status
  content hash is unchanged. Explicit refreshes still show progress.
- Spacing change: increased shared label line heights and primary/secondary
  button hit areas, wrapped constrained dialog action groups, bounded long
  conflict labels, and added missing action run spacing.
- Verification: formatting and `flutter analyze` passed; expanded button,
  spacing, app boot, Changes behavior, and silent-polling tests passed with 25
  tests; the final complete feature UI suite passed with 71 tests, including
  the existing narrow File History and Reset contracts.
- `flutter build windows --release` rebuilt `gift.exe` after the final spacing
  changes; the process stayed running and reported `Responding=True`.
- Blockers: none.
- Next action after this session commit: activate Task 36 after recording its
  scale/resilience scenarios and first failing fixture.

## Current session: Push spacing, primary typography, and Task 39

- Date: 2026-09-04.
- Changed files: `CHANGELOG.md`, `TASKS.md`,
  `docs/{POST_MVP_ROADMAP.md,WORK_CHECKPOINT.md}`,
  `docs/superpowers/plans/2026-09-02-gift-dart-mvp.md`,
  `lib/src/app/pixel_theme.dart`,
  `lib/src/features/repository/{changes_screen,comparison_dialog,hosting_dialog,push_dialog,repository_setup_dialog,reset_dialog,update_project_dialog,welcome_screen}.dart`,
  and `test/{branding_test.dart,features/repository/push_dialog_test.dart}`.
- Push change: inserted a fixed 14-pixel gap between the `Nothing is pushed
  yet` guidance card and Remote selector; the narrow-window test now asserts
  their geometry cannot overlap.
- Button change: selected large workflow-defining primary actions use the
  `Jersey 15` display title face, 19-pixel labels, wider horizontal padding,
  and a 42-pixel minimum height. Compact filled buttons plus secondary, text,
  and icon controls retain the legible UI face and compact geometry.
- Roadmap change: added Task 39 for cross-platform visual-regression fixtures,
  golden matrices, clipping/hit-area assertions, platform font baselines, and
  reviewed baseline updates. Task 36 remains the next task by dependency order.
- Verification so far: formatting and `flutter analyze` passed; focused
  branding, app boot, and Push tests passed with 9 tests; the final complete
  feature UI suite passed with 71 tests.
- `flutter build windows --release` rebuilt `gift.exe`; the resulting desktop
  process stayed running and reported `Responding=True`.
- Blockers: none.
- Next action after this session commit: activate Task 36 after recording its
  scale/resilience scenarios and first failing fixture.

## Current session: unified button geometry

- Date: 2026-09-04.
- Changed files: `CHANGELOG.md`,
  `docs/superpowers/plans/2026-09-02-gift-dart-mvp.md`, this checkpoint,
  `lib/src/app/pixel_theme.dart`,
  `lib/src/features/repository/{changes_screen,comparison_dialog,hosting_dialog,push_dialog,repository_setup_dialog,reset_dialog,update_project_dialog,welcome_screen}.dart`,
  and `test/{app_boot_test.dart,branding_test.dart}`.
- UI change: removed the selective `Jersey 15` primary-action style and its
  per-screen overrides. Filled, outlined, and text buttons now share the
  `Atkinson Hyperlegible Next` UI face, 12-pixel horizontal padding, 18-pixel
  icon size, and 38-pixel height. Icon-only controls also use a 38-pixel square.
  Fill, outline, text, and destructive color hierarchy remains intact.
- Verification: formatting and `flutter analyze` passed; focused theme, app
  boot, Push, File History, Shelf, and Changes tests passed with 25 tests; the
  complete responsive feature UI suite passed with 71 tests.
- `flutter build windows --release` rebuilt `gift.exe`; the resulting desktop
  process stayed running and reported `Responding=True`.
- Blockers: none.
- Next action after this session commit: activate Task 36 after recording its
  scale/resilience scenarios and first failing fixture.

## Current session: contextual actions and path-selection roadmap

- Date: 2026-09-04.
- Changed files: `CHANGELOG.md`, `TASKS.md`, `docs/POST_MVP_ROADMAP.md`,
  `docs/superpowers/plans/2026-09-02-gift-dart-mvp.md`, and this checkpoint.
- Audit result: cherry-pick already exists in the typed backend, Advanced
  branch dialog, real-Git tests, and conflict recovery flow. Its only primary
  UI entry is the generic Advanced branch form, so discoverability—not the
  single-commit engine—is the immediate gap.
- Roadmap change: added Tasks 40–47 for a shared right-click/keyboard action
  contract; direct commit cherry-pick and other History actions; ordered
  multi-commit operations; change/file, branch/remote, and workspace/root
  context menus; editable native absolute-folder fields; and searchable
  repository-relative path navigation.
- Safety decision: context menus route to existing previews and confirmations;
  secondary click never executes Git. Actions bind to stable OIDs, refs, paths,
  canonical roots, repository IDs, and freshness fingerprints rather than
  visible list indices.
- UX decision: absolute destinations retain direct text entry plus a native
  Browse flow and purpose-specific recent directory. Repository-relative
  fields retain direct typing plus bounded tracked-path search and explicit
  file/directory modes.
- Verification: documentation structure, task dependencies, cross-references,
  acceptance criteria, and diff integrity were reviewed. No implementation or
  runtime behavior changed, so no Flutter test or backtest was required.
- Blockers: none.
- Next action: activate Task 40, add the context-action behavior-ledger
  scenarios, and record the first failing shared menu-contract widget test.

## Current session: visible push progress

- Date: 2026-09-04.
- Changed files: `CHANGELOG.md`, this checkpoint,
  `docs/superpowers/plans/2026-09-02-gift-dart-mvp.md`,
  `lib/src/features/repository/push_dialog.dart`, and
  `test/features/repository/push_dialog_test.dart`.
- UX change: when the reviewed Push action starts, the dialog keeps its
  familiar pixel-card language and shows a cloud-upload icon, destination
  (`remote/branch` or all tags), an indeterminate progress bar, an explanation,
  and an explicit `Cancel push` action. Controls remain disabled while Git is
  running; successful pushes still close the dialog and rejected/cancelled
  pushes still render their result/recovery state.
- Design constraint: the gateway exposes cooperative cancellation but no
  byte-level transfer events, so an indeterminate indicator is used instead of
  inventing a percentage.
- Verification: `flutter analyze` passed; the focused Push dialog suite passed
  with 3 tests; the complete responsive feature suite passed with 72 tests;
  `flutter build windows --release` rebuilt `gift.exe`; and the rebuilt
  executable stayed running with `Responding=True` during the Windows smoke
  check.
- Blockers: none.
- Next action after this session commit: activate Task 40 or another
  dependency-ready roadmap task.

## Current session: push field spacing correction

- Date: 2026-09-04.
- Changed files: `CHANGELOG.md`, this checkpoint,
  `lib/src/features/repository/push_dialog.dart`, and
  `test/features/repository/push_dialog_test.dart`.
- Bug: the Remote field and Publish scope field had no vertical spacer after
  the progress-card edit, allowing their outlined labels to visually collide.
- Fix: restored the shared 8-pixel field gap and added a compact 360×640
  regression assertion that checks Remote-to-scope separation without requiring
  the scrollable scope field to remain fully inside the viewport.
- Verification so far: `flutter analyze` passed; the focused Push dialog suite
  passed with 3 tests; and the complete responsive feature suite passed with
  72 tests.
- Blockers: none.
- Next action after this session commit: activate Task 40 or another
  dependency-ready roadmap task.

## Current session: Windows installer shortcut correction

- Date: 2026-09-04.
- Changed files: `CHANGELOG.md`, `README.md`, `docs/RELEASING.md`, this
  checkpoint, `docs/superpowers/plans/2026-09-02-gift-dart-mvp.md`,
  `tool/windows_setup_launcher.ps1`, and `tool/windows_uninstall.ps1`.
- Diagnosis: `gift-setup.exe` already installed a persistent per-user copy and
  registered an uninstaller, but it created only a Start Menu shortcut. Its
  post-install app launch made the visible result feel like the portable
  launcher.
- Fix: setup now creates both Desktop and Start Menu shortcuts, sets the
  installed executable as the shortcut icon, and the uninstaller removes both.
  Release documentation now explicitly distinguishes persistent setup from
  temporary portable execution.
- Verification: all four Windows PowerShell packaging scripts parsed without
  syntax errors; `tool/build_windows.ps1` rebuilt the release bundle,
  `gift-portable.exe`, and `gift-setup.exe`; installer smoke confirmed the
  persistent install directory, Desktop shortcut, Start Menu shortcut,
  shortcut target, and uninstall registration; uninstaller smoke removed all
  of them. The generated setup package also passed the requested install
  flow.
- Blockers: none.
- Next action after this session commit: activate Task 40 or another
  dependency-ready roadmap task.


## Current session: Task 40 contextual actions and UI spacing follow-up

- Date: 2026-09-04.
- Changed files: `CHANGELOG.md`, `TASKS.md`,
  `docs/research/jetbrains-git-mvp-behavior.md`,
  `docs/superpowers/plans/2026-09-02-gift-dart-mvp.md`, this checkpoint,
  `lib/src/features/repository/{context_actions,changes_screen,file_history_dialog,interactive_rebase_dialog,object_dialog,remote_dialog}.dart`,
  and `test/features/repository/{context_action_menu_test,changes_screen_test,file_history_dialog_test}.dart`.
- Task 40 activation recorded ACTION-01/02/03/04. The first RED command
  `PATH=/home/mgkim/.local/flutter/bin:$PATH flutter test
  test/features/repository/context_action_menu_test.dart` failed before
  implementation because `context_actions.dart` and the typed presenter
  contract did not exist.
- Implemented immutable repository/object snapshots, typed targets,
  availability results, route descriptors, and a shared semantic presenter
  with secondary-click placement, Shift+F10/Menu invocation, arrow/Escape
  navigation, edge clamping, stale-snapshot rejection, focus restoration,
  disabled reasons, and per-change overflow routing.
- Changes row actions route Inspect/Stage/Unstage through the existing
  controller and Discard through the existing preview/confirmation dialog;
  opening or dismissing a menu has no Git side effect.
- Restored vertical spacing between File History's path controls and Follow
  renames, line-range, and blame controls. Added the same missing breathing
  room around interactive-rebase, object-management, and remote action groups.
- Verification: focused context and Changes tests passed; focused
  File History, interactive rebase, object, and remote tests passed; `dart
  run tool/verify.dart` passed formatting, analysis, and all 213 Flutter
  tests; `git diff --check` passed.
- Next action: Task 41, direct commit context actions and History
  cherry-pick discovery.

## Resume procedure

1. Read this file, `AGENTS.md`, `TASKS.md`, and the active section of the
   implementation plan.
2. Run `git status --short --branch` and inspect the latest commit before
   touching files.
3. Continue the exact active task and recorded next action. Do not infer
   completion from a clean tree or a commit title.
4. Re-run the recorded verification command before changing implementation if
   this checkpoint describes an unresolved failure.
5. Update this file before ending the session with exact files changed, tests
   run, observed results, blockers, and the next action.
