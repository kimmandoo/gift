# JetBrains Git MVP behavior ledger

This clean-room ledger records approved, neutral Git behavior scenarios for
the MVP. It contains no proprietary captures, source, or implementation
details. Later authorized observations append versioned notes to the relevant
scenario without storing proprietary captures.

| Scenario | Source type | Input state | User intent | Expected visible state | Expected Git state |
| --- | --- | --- | --- | --- | --- |
| STATUS-01 | approved design | A repository contains tracked and/or changed files. | See the repository's current working state. | The UI identifies changed, staged, and untracked files and their relevant state. | `git status --porcelain` reflects the same working-tree and index categories. |
| DIFF-01 | approved design | A selected file has staged or unstaged content changes. | Inspect the selected change. | The UI shows a readable before/after representation for the selected file and change scope. | `git diff` or `git diff --cached`, matching the selected scope, produces the represented change. |
| STAGE-01 | approved design | A working-tree change is available and not yet staged. | Add the selected change to the next commit. | The UI moves or marks the selected change as staged. | The selected path or hunk is added to the index; `git diff --cached` contains it. |
| DISCARD-01 | approved design | A tracked file has an unstaged working-tree change. | Revert the selected working-tree change. | The UI removes the selected change from the changed-files view after confirmation. | The selected working-tree content matches the index/HEAD baseline; the discarded unstaged diff is absent. |
| COMMIT-01 | approved design | The index has staged changes and the user has supplied a commit message. | Create a local commit. | The UI reports the new commit and returns the staged changes to a clean state. | A new `HEAD` commit contains the staged tree and message; the index has no remaining staged changes. |
| LOG-01 | approved design | The repository has one or more commits. | Browse recent history. | The UI lists commits in a stable, readable order with summary metadata. | `git log` supplies the represented commit ordering and metadata. |
| BRANCH-01 | approved design | The repository has a current branch and may have additional local branches. | View, create, or switch a local branch. | The UI identifies the current branch and reflects branch creation or selection. | `HEAD` points to the selected branch; refs under `refs/heads/` reflect local branch creation. |
| REMOTE-01 | approved design | The repository has a configured remote and a local branch that can synchronize. | Fetch, pull, or push through the selected remote. | The UI reports synchronization progress and the resulting local/remote relationship. | The chosen Git network operation updates remote-tracking refs and/or remote refs according to the operation result. |
