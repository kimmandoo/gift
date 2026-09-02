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
| DISCARD-01 | approved design | A tracked file has an unstaged working-tree change. | Revert the selected working-tree change. | The UI removes the selected change from the changed-files view after confirmation. | The selected working-tree content matches the index/HEAD baseline; the discarded unstaged diff is absent. |
| COMMIT-01 | approved design | The index has staged changes and the user has supplied a commit message. | Create a local commit. | The UI reports the new commit and returns the staged changes to a clean state. | A new `HEAD` commit contains the staged tree and message; the index has no remaining staged changes. |
| LOG-01 | approved design | The repository has one or more commits. | Browse recent history. | The UI lists commits in a stable, readable order with summary metadata. | `git log` supplies the represented commit ordering and metadata. |
| BRANCH-01 | approved design | The repository has a current branch and may have additional local branches. | View, create, or switch a local branch. | The UI identifies the current branch and reflects branch creation or selection. | `HEAD` points to the selected branch; refs under `refs/heads/` reflect local branch creation. |
| REMOTE-01 | approved design | The repository has a configured remote and a local branch that can synchronize. | Fetch, pull, or push through the selected remote. | The UI reports synchronization progress and the resulting local/remote relationship. | The chosen Git network operation updates remote-tracking refs and/or remote refs according to the operation result. |

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
