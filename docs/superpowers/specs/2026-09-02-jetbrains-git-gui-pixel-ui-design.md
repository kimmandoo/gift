# JetBrains Git GUI Reverse-Engineering and Pixel UI Specification

## Goal

gitflu is a clean-room, black-box behavioral reverse engineering project for
the user-visible Git GUI system found in JetBrains IDEs. The target is the
workflow model and information hierarchy: how a user sees repository state,
chooses a change, opens a diff, stages or discards work, commits, navigates
history, changes branches, and synchronizes with a remote.

The implementation remains independent: Flutter owns the presentation and
Dart owns Git execution. We reproduce observable behavior and feedback, not
the original implementation.

## Clean-room boundary

- Observe only user-visible behavior, interaction results, and Git state that
  can be independently verified with the system Git CLI.
- Record observations as scenario inputs, user actions, visible state changes,
  and expected Git state in `docs/research/jetbrains-git-mvp-behavior.md`.
- Do not copy JetBrains source code, binaries, private protocols, proprietary
  assets, icons, screenshots, or exact implementation details.
- Use neutral gitflu names and original code/assets even when the behavior is
  intentionally equivalent.
- Label an unverified behavior as a hypothesis until a scenario test or a
  documented black-box observation confirms it.

## Behavioral target

The following JetBrains Git GUI concepts define the MVP target. The names in
the right column are gitflu's implementation concepts, not copied UI labels.

| JetBrains-observed concept | gitflu behavior target | Evidence required |
| --- | --- | --- |
| Project/repository navigation | A repository navigator with the active root and recent repositories | Open, switch, and missing-root scenarios |
| Local Changes / changelists | Separate staged, unstaged, untracked, and conflicted facets with stable grouping | Porcelain v2 fixtures and visible state snapshots |
| Diff viewer | A selected-file diff with explicit staged/unstaged scope and predictable selection | Matching `git diff` command and rendered state |
| Add/remove from index | Stage or unstage a path/hunk with immediate list and status feedback | Index before/after assertions |
| Rollback/discard | A confirmation-first discard flow with a clear result and recovery warning | Preview/confirm/cancel scenarios |
| Commit workflow | A focused commit editor, validation, hook/error feedback, and post-commit refresh | Commit tree/message/index assertions |
| Log/history | Stable commit rows, details, graph context, and pagination | `git log` fixtures and ordering assertions |
| Branch popup and branch actions | Current-branch identity, local branch actions, and switch feedback | Ref/HEAD assertions |
| Fetch, pull, and push feedback | Progress, completion, authentication, cancellation, and failure states | Remote-operation ledger scenarios |

Every row must be implemented as a vertical slice: backend contract, isolated
Git fixture, controller state, and a visible Flutter state. The behavior
ledger is the source of truth when implementation choices are ambiguous.

## Visual direction: minimal 2D pixel-game UI

The visual language must feel like a small, calm 2D pixel game while keeping
the information density expected from a desktop Git GUI.

- Use restrained light and dark canvases, crisp pixel-like borders, compact
  panels, and a small number of high-signal accent colors.
- Build spacing, borders, icon containers, and hit targets on a 4 px base grid;
  use 8 px for primary gaps and 16 px for panel padding.
- Prefer flat fills and hard edges. Do not use glassmorphism, soft gradients,
  large shadows, or generic dashboard cards.
- Use original 2D pixel motifs sparingly: repository folders, branches,
  commits, status markers, and action feedback may use small sprite-like
  shapes. A decoration must never replace a text label or semantic icon.
- Keep the UI minimal: one clear primary action per state, shallow navigation,
  and enough whitespace around the selected change.
- The pixel treatment is a visual system, not a game mechanic. Git operations
  remain explicit, reversible where possible, and understandable to a new
  user.

### Visual tokens and typography

These tokens are a starting contract; later visual tuning must preserve their
roles and contrast relationships.

| Token | Value | Use |
| --- | --- | --- |
| `pixelCanvas` | `#0D1117` | Dark app background |
| `pixelPanel` | `#151B23` | Dark navigation and content panels |
| `pixelPanelRaised` | `#202938` | Dark focused row and raised surface |
| `pixelInk` | `#F5F7E9` | Dark primary text |
| `pixelMuted` | `#9AA8A8` | Dark secondary text and outlines |
| `pixelMint` | `#63E6BE` | Dark safe/selected/ready state |
| `pixelAmber` | `#FFCC66` | Dark attention and pending state |
| `pixelCoral` | `#FF7B72` | Dark error and destructive state |
| `pixelSky` | `#79C0FF` | Dark links and informational state |
| `pixelLightCanvas` | `#F5F1E8` | Light app background |
| `pixelLightPanel` | `#FFFCF5` | Light navigation and content panels |
| `pixelLightInk` | `#17212B` | Light primary text |
| `pixelLightMuted` | `#526067` | Light secondary text and outlines |
| `pixelLightMint` | `#056B4A` | Light safe/selected/ready state |
| `pixelLightSky` | `#145A90` | Light links and informational state |

The light palette mirrors each semantic role with warm paper-like surfaces and
dark ink. Theme switching is available from every top-level workflow and is
persisted locally. Text uses the bundled Jersey 15 family under the SIL Open
Font License. Jersey 15 was chosen for its heavier, simpler pixel glyphs;
source and diff content may retain a denser monospace treatment where exact
character alignment matters. The compact desktop type scale is 12 px for
small metadata, 13 px for labels and diff text, 15 px for normal body text, 16 px for
prominent body text, 18 px for screen titles, 22 px for detail headings, and
24 px for the welcome heading, with line-height preserved for scanning.

Text must remain readable without relying on color alone. Both palettes and
the pixel font must be tested at compact desktop sizes and normal text scale.
All foreground/background pairs use the matching `ColorScheme` on-color role;
the test suite keeps primary text and interactive/status surfaces at a minimum
4.5:1 contrast ratio.

### Git graph contract

- A commit row renders every active lane crossing that row, not only the
  selected commit's vertical marker.
- Forks connect one commit node to every parent lane; merges and lane shifts
  remain visually connected above and below the node.
- Lane assignment is recomputed over all loaded rows after pagination so a
  page boundary cannot reset or jump a branch line.
- Graph width grows for ordinary branch counts and compresses lane spacing for
  unusually wide histories instead of clipping the rightmost lane.
- At least four distinguishable semantic palette colors repeat by lane, while
  node shape and line geometry keep the graph understandable without color.

## Desktop shell

The first repository screen should follow this stable hierarchy:

```text
┌─────────────────────────────────────────────────────────────┐
│ repo identity · branch selector                 action menu │
├───────────────┬───────────────────────────────┬─────────────┤
│ repository     │ changes / history / branches  │ file detail │
│ navigator      │ selected workflow             │ or diff     │
├───────────────┴───────────────────────────────┴─────────────┤
│ operation status · sync state · keyboard hint               │
└─────────────────────────────────────────────────────────────┘
```

- The left rail identifies the repository and keeps navigation shallow.
- The center pane is the current JetBrains-equivalent workflow surface:
  changes first, then history, branches, and remote actions.
- The right pane shows details for the selected file, commit, or operation.
- The bottom status strip reports Git discovery, branch, sync, progress, and
  errors without hiding the main content.
- On a narrow window, the right pane becomes a push route or bottom sheet; no
  information may become unreachable.
- At 360 px width and 640 px height, core screens and operation dialogs must
  remain reachable without RenderFlex overflow.

## Interaction and state rules

- Keyboard focus is visible as a pixel-outline treatment. Common actions have
  stable shortcuts, while every shortcut also has a discoverable menu/action
  label.
- Selected rows, staged rows, disabled actions, loading, empty, success,
  warning, and error states must each have a distinct visual treatment and a
  text or semantic explanation.
- Destructive actions require a confirmation surface that names the affected
  path or operation. The UI must never imply that a local discard is a remote
  delete.
- Git output is translated into user-facing status copy; raw commands and
  credential-bearing diagnostics stay out of the UI.
- Polling and mutation refreshes preserve the selected repository and file
  whenever the corresponding item still exists.

## Accessibility and acceptance criteria

- All pixel-styled controls expose normal Flutter semantics, labels, focus,
  and keyboard activation.
- Text and important status indicators meet accessible contrast targets in the
  dark palette; status color always has a text, shape, or icon companion.
- A first-time user can identify the repository, current branch, changed-file
  groups, selected file, and next safe action without reading documentation.
- Each JetBrains behavior-ledger scenario has a testable Flutter state and a
  matching Dart/Git assertion before the feature is marked complete.
- Visual review checks the 4 px/8 px grid, flat pixel surfaces, restrained
  palette, focus visibility, narrow-window behavior, and absence of copied
  proprietary assets.

## Beginner reading order

1. Read the behavior scenarios in `docs/research/jetbrains-git-mvp-behavior.md`.
2. Read `docs/ARCHITECTURE.md` to follow the Flutter-to-Dart call flow.
3. Read the active task in `TASKS.md` and its backend contract.
4. Read the matching controller and screen only after the behavior and state
   names are clear.
