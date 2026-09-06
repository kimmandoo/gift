/// A failed commit can still have changed history when a post-commit hook or
/// the follow-up status read failed after Git moved HEAD.
enum GitCommitOutcome { notCreated, createdButRefreshFailed }

/// Stable categories used to decide what message and recovery action Flutter
/// should show for a backend failure.
enum GitErrorCategory {
  gitNotFound,
  unsupportedGitVersion,
  notRepository,
  repositoryMoved,
  invalidRevision,
  detachedHead,
  unbornBranch,
  dirtyWorktree,
  mergeConflict,
  nonFastForward,
  authenticationRequired,
  permissionDenied,
  networkUnavailable,
  hookRejected,
  cancelled,
  timeout,
  staleConfirmation,
  stalePatch,
  staleComparison,
  comparisonFileNotFound,
  patchRejected,
  invalidOpaqueId,
  staleOpaqueId,
  parseFailure,
  unsupportedRepositoryState,
  internal,
  invalidGitPath,
  processSpawnFailed,
  processFailed,
  outputOverflow,
  missingIdentity,
  invalidCommitOptions,
  signingFailed,
  commitRefreshFailed,
  invalidGitConfig,
  invalidBranchName,
  operationInProgress,
  staleBranchPreview,
  branchOperationNotAllowed,
  staleRemoteRef,
  remoteBranchNotFound,
  staleUpdatePreview,
  stalePushPreview,
  staleWorktreePreview,
  worktreeBranchOccupied,
  worktreeOperationNotAllowed,
  updateNotAllowed,
  staleConflict,
  conflictResolutionNotAllowed,
  unresolvedConflicts,
  staleObject,
  staleRollbackPreview,
  protectedBranch,
  pushedHistory,
  historyRollbackNotAllowed,
  invalidObjectName,
  objectNotFound,
  objectOperationNotAllowed,
  lfsUnavailable,
  lfsObjectsMissing,
}

/// A backend error has a short user-facing message and a separately redacted
/// diagnostic for logs. Raw stdin is never stored here.
class GitError implements Exception {
  const GitError({
    required this.category,
    required this.userMessage,
    required this.diagnostic,
    required this.retryable,
    this.exitCode,
    this.commitOutcome,
  });

  final GitErrorCategory category;
  final String userMessage;
  final String diagnostic;
  final bool retryable;
  final int? exitCode;
  final GitCommitOutcome? commitOutcome;

  GitError copyWith({
    GitErrorCategory? category,
    String? userMessage,
    String? diagnostic,
    bool? retryable,
    int? exitCode,
    GitCommitOutcome? commitOutcome,
  }) {
    return GitError(
      category: category ?? this.category,
      userMessage: userMessage ?? this.userMessage,
      diagnostic: diagnostic ?? this.diagnostic,
      retryable: retryable ?? this.retryable,
      exitCode: exitCode ?? this.exitCode,
      commitOutcome: commitOutcome ?? this.commitOutcome,
    );
  }

  @override
  String toString() => '$category: $userMessage';
}
