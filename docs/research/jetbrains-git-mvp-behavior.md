# JetBrains Git MVP behavior ledger

This is the product's primary behavior ledger for black-box reverse engineering
of the user-visible Git GUI system in JetBrains IDEs. It records the workflow
and information hierarchy that gift intends to reproduce, using neutral
implementation names and independently verifiable Git state.

This clean-room ledger contains no proprietary captures, source, binaries,
assets, or implementation details. An observation describes only the starting
state, user action, visible result, and corresponding system-Git result. Later
authorized observations append versioned notes to the relevant scenario; an
uncertain observation stays marked as a hypothesis until verified.

The matching visual target is defined in
`docs/superpowers/specs/2026-09-02-jetbrains-git-gui-pixel-ui-design.md`: a
minimal 2D pixel-game interface with desktop Git GUI information density.

| Scenario | Source type | Input state | User intent | Expected visible state | Expected Git state |
| --- | --- | --- | --- | --- | --- |
| STATUS-01 | approved design | A repository contains tracked and/or changed files. | See the repository's current working state. | The UI identifies changed, staged, untracked, and conflicted files and their relevant state. | `git status --porcelain=v2 -z --branch` produces the represented branch and file facets. |
| DIFF-01 | approved design | A selected file has staged or unstaged content changes. | Inspect the selected change. | The UI lazily shows a readable, line-numbered unified diff for the selected file; staged and working-tree scopes can be switched, while binary and empty output have explicit states. | `git diff --find-renames --unified=3` or `git diff --cached --find-renames --unified=3`, with the selected path after `--`, produces the represented change. |
| STAGE-01 | approved design | A working-tree change is available and not yet staged. | Add the selected change to the next commit. | The UI disables the action while the mutation runs, then moves or marks the selected change as staged and keeps it selected. | `git add -- <path>` adds the selected path to the index; the returned `git status --porcelain=v2 -z --branch` snapshot shows its staged facet. |
| DISCARD-01 | approved design | A tracked file has an unstaged working-tree change. | Revert the selected working-tree change. | The UI requests a fresh confirmation, disables the destructive action while running, preserves staged content, and removes the selected change from the changed-files view when no facet remains. | `git restore --worktree -- <path>` runs only after the repository/path/status/diff preview remains fresh; the returned `git status --porcelain=v2 -z --branch` snapshot has no discarded unstaged facet. |
| COMMIT-01 | approved design | The index has staged changes and the user has supplied a non-empty commit message. | Create a local commit. | The commit editor accepts Unicode text, disables itself while Git runs, reports the new commit ID on success, returns the staged changes to a clean state, and explains when a commit hook rejects the operation. | The backend sends the message as UTF-8 stdin to `git commit --file=-`; a new `HEAD` commit contains the staged tree and message, and the returned status has no remaining staged changes. |
| LOG-01 | approved design | The repository has one or more commits. | Browse recent history. | The UI lists commits in stable topological order with author/date/subject metadata, shows merge context, and loads the next bounded page on request. | `git log --all --topo-order --format=... --max-count=<page+1> --skip=<offset>` supplies the represented commit ordering, parents, metadata, and page boundary. |
| BRANCH-01 | approved design | The repository has a current branch and may have additional local branches. | View, create, or switch a local branch. | The popup identifies the current branch, validates a new name, reports dirty-worktree failures, and reflects a successful branch creation or selection. | `git for-each-ref` supplies local refs; `git switch --create <name>` or `git switch <name>` updates `HEAD`, and the returned status identifies the selected branch. |
| REMOTE-01 | approved design | The repository has a configured remote and a local branch that can synchronize. | Fetch, pull, or push through the selected remote. | The UI shows the selected remote, indeterminate progress, cancellation, authentication/network/non-fast-forward/conflict feedback, and the resulting local/remote relationship. | `git remote --verbose` supplies the configured remote; `git fetch --prune <remote>`, `git pull --ff-only <remote> <branch>`, or `git push <remote> <branch>` updates refs according to the operation result, unless the cancellation token stops the process. |
| WORKSPACE-01 | approved design | The app has previously opened several canonical repository roots. | Resume work after restarting gift. | The workspace restores the saved tab order and last active tab; an unavailable path stays visible with a recoverable explanation. | Each saved path is independently validated by the backend and receives a new session-local opaque repository ID; persisted data never contains those IDs. |
| WORKSPACE-02 | approved design | One or more repository tabs are open. | Open, close, reorder, or switch repository tabs. | The active tab is visibly selected, tab operations preserve the remaining order, duplicate canonical roots are not added, and the last active path is persisted. | Each tab's Git requests use only its own validated root and opaque repository ID. |
| WORKSPACE-03 | approved design | A repository mutation is running while another repository tab is selected. | Continue inspecting another repository without cross-talk. | The selected tab remains responsive; progress, errors, selection, and refresh results remain attached to the originating tab. | The mutation queue and status snapshot are scoped to the originating repository ID and cannot update another repository. |
| PARTIAL-01 | approved design | A text file has two or more independent hunks in the working-tree diff. | Stage only the selected hunk. | The selected hunk is staged, unselected hunks remain unstaged, and the diff labels the operation as working-tree staging. | A machine-generated patch is sent to `git apply --cached`; the patch contains the selected hunk and enough context to apply safely. |
| PARTIAL-02 | approved design | A hunk contains additions, deletions, and possibly a no-newline marker. | Stage or unstage selected lines. | Line checkboxes support a selected range; only selected additions/deletions move to the target facet, while unselected lines remain in their original facet. | The backend derives a bounded patch from parsed diff lines; UI text is never accepted as arbitrary patch input. |
| PARTIAL-03 | approved design | A diff was selected and the file changed before the mutation. | Apply the previous selection. | The operation is rejected with a stale-diff explanation and no index change. | The selection's repository ID, path, scope, and content hash must match a fresh diff before `git apply` runs. |
| PARTIAL-04 | approved design | The selected path is binary, rename-only, or the generated patch no longer applies. | Attempt partial staging. | The UI explains that partial staging is unavailable or failed and keeps the current selection recoverable. | Binary/rename-only patches are not treated as text hunks; Git patch failure is typed and the mutation queue remains consistent. |

## Observation protocol

For every new JetBrains behavior, record the following in order:

1. Define the repository state and the selected user intent.
2. Observe the visible controls, grouping, selection, feedback, and recovery
   path without inspecting proprietary implementation artifacts.
3. Reproduce the starting state in an isolated Git fixture.
4. Express the result as a Dart backend contract, controller state, and Flutter
   acceptance test.
5. Add a versioned note when the behavior is confirmed, changed, or still
   uncertain.

## MVP equivalence boundary

“Equivalent” means that a user can complete the same Git workflow, understand
the same important state transitions, and recover from the same failure class.
It does not mean copying source code, private protocols, exact assets, or
unnecessary visual details. gift's UI must keep its own minimal 2D pixel-game
visual language while preserving the observed workflow semantics.
