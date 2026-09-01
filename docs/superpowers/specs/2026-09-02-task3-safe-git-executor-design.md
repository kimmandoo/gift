# Task 3 Safe Git Executor Design

**Date:** 2026-09-02

## Goal

Provide a shell-free, credential-safe Rust Git execution boundary that can
discover a supported system Git installation and expose its configuration
through the Flutter Rust Bridge.

## Architecture

`GitInstallation` owns the selected executable path and validated semantic
version. `GitInvocation` is an immutable argv/cwd/stdin request with an
explicit operation kind and output policy. `ProcessGitRunner` executes that
request with Tokio, pipes stdout and stderr concurrently, bounds captured
output, and drains streamed output so a child cannot deadlock on a full pipe.

The settings service checks an explicitly configured executable before PATH,
and only replaces the in-memory installation after `git --version` succeeds.
The bridge exposes typed settings operations; no raw command string crosses
the API boundary.

## Error and redaction contract

`GitErrorCategory` covers executable discovery, unsupported versions, process
startup, non-zero Git exits, output overflow, and invalid configuration. A
`GitError` contains a short user message, retryability, optional exit code, and
a diagnostic made from lossy UTF-8 conversion only after redacting credential
URLs and sensitive configuration values. Stdin is never included in errors.

## Output policies

Capture requests have a caller-supplied limit and reject output beyond that
limit without retaining the complete payload. Stream requests deliver bounded
chunks to a consumer while continuously draining both child pipes. The
initial settings and discovery calls use Capture; future parser and remote
operations will use Stream.

## Verification

Rust integration tests cover vendor-suffixed Git versions, the 2.35 minimum,
credential URL masking, exact execution in a temporary path containing spaces
and `&`, output overflow, PATH fallback, explicit-path precedence, and
preserving the previous valid installation after invalid reconfiguration.
Generated FRB bindings are regenerated after the public API changes and the
two-pass drift check is run when the pinned code generator is available.

