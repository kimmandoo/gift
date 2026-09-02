# Dart Safe Git Executor Design

## Goal

Provide a shell-free, credential-safe system-Git execution boundary for the
Flutter Desktop application using only Dart.

## Architecture

`GitInstallation` contains the selected executable path and validated semantic
version. `GitInvocation` is an immutable executable/argv/cwd/stdin request
with an explicit operation kind and output policy. `ProcessGitRunner` starts
the request with `Process.start(runInShell: false)`, reads stdout and stderr
concurrently, bounds retained output, and drains the remainder so a child
cannot deadlock on a full pipe.

The installation service checks an explicit executable before searching PATH
and replaces the cached installation only after `git --version` succeeds. The
backend facade exposes typed settings and repository operations; raw command
strings never cross the API boundary.

## Error and redaction contract

`GitErrorCategory` covers executable discovery, unsupported versions, process
startup, non-zero Git exits, output overflow, invalid repository state, and
invalid configuration. A `GitError` contains a short user message,
retryability, an optional exit code, and a diagnostic made after redacting
credential URLs and sensitive configuration values. Stdin is never included
in errors.

## Output policies

Capture requests retain at most the configured byte limit and report overflow.
Stream requests retain only a bounded prefix while continuously draining both
child pipes. Settings and discovery currently use capture; status, diffs, and
remote operations can use stream as their payloads grow.

## Verification

The Dart backend tests cover vendor-suffixed Git versions, the minimum version,
credential masking, exact execution in a path containing shell characters,
bounded process output, PATH discovery, explicit-path validation, repository
opening, bare repository rejection, and registry-local handles.
