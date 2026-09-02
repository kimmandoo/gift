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
  invalidOpaqueId,
  staleOpaqueId,
  parseFailure,
  unsupportedRepositoryState,
  internal,
  invalidGitPath,
  processSpawnFailed,
  processFailed,
  outputOverflow,
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
  });

  final GitErrorCategory category;
  final String userMessage;
  final String diagnostic;
  final bool retryable;
  final int? exitCode;

  GitError copyWith({
    GitErrorCategory? category,
    String? userMessage,
    String? diagnostic,
    bool? retryable,
    int? exitCode,
  }) {
    return GitError(
      category: category ?? this.category,
      userMessage: userMessage ?? this.userMessage,
      diagnostic: diagnostic ?? this.diagnostic,
      retryable: retryable ?? this.retryable,
      exitCode: exitCode ?? this.exitCode,
    );
  }

  @override
  String toString() => '$category: $userMessage';
}
