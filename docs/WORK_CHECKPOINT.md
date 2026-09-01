# Work Checkpoint

This file is the handoff record for continuing work across query sessions. It
keeps the next action and verification evidence in the repository instead of
depending on conversation history.

## Current checkpoint

- Date: 2026-09-02
- Milestone: Task 4 is complete; Task 5 is the next active task.
- Source of truth: `TASKS.md` for milestone status and
  `docs/superpowers/plans/2026-09-01-branchline-mvp.md` for implementation steps.
- Completed scope: opaque repository IDs, canonical repository opening, bare
  repository rejection, registry-local ID validation, persisted recent paths,
  Git executable settings, retry flow, and fake-gateway Flutter tests.
- Verification: Rust tests, repository-open tests, Flutter tests, Flutter
  analyze, Rust clippy, Rust format check, and FRB generation completed
  successfully for this milestone.
- Next action: read this checkpoint and the Task 5 plan section before writing
  code; begin with the first failing status-parser test.

## Resume procedure

1. Read this file, `AGENTS.md`, `TASKS.md`, and the active section of the
   implementation plan.
2. Run `git status --short --branch` and inspect the latest commit before
   touching files.
3. If the checkpoint says a task is in progress, continue that task at its
   recorded step. Do not start the next task based only on the latest commit
   title.
4. Re-run the recorded failing or verification command before changing the
   implementation when the checkpoint describes an unresolved failure.
5. Update this file before ending the session with the exact files changed,
   tests run, observed results, blockers, and next action.

## Handoff format for an incomplete task

When pausing before a task is complete, record:

- the active task and exact plan step;
- the behavior already implemented and the behavior still missing;
- the current working-tree state and changed files;
- the last RED/GREEN or verification command and its output summary;
- any environmental blocker and the safe next diagnostic;
- the single next action for the next session.

An incomplete task must remain marked active in `TASKS.md`. Mark it complete
only after the plan's required verification commands pass and the same-session
commit has been created.
