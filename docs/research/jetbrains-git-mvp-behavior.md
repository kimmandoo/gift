# JetBrains Git MVP behavior ledger

This is the product's primary behavior ledger for black-box reverse engineering
of the user-visible Git GUI system in JetBrains IDEs. It records the workflow
and information hierarchy that gitflu intends to reproduce, using neutral
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
unnecessary visual details. gitflu's UI must keep its own minimal 2D pixel-game
visual language while preserving the observed workflow semantics.
