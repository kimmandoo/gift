import 'domain.dart';
import 'branch.dart';
import 'executor.dart';
import 'status.dart';

/// A deliberate batch operation over an ordered set of history commits.
enum GitHistoryBatchAction { cherryPick, revert }

extension GitHistoryBatchActionLabel on GitHistoryBatchAction {
  String get label => switch (this) {
    GitHistoryBatchAction.cherryPick => 'Cherry-pick',
    GitHistoryBatchAction.revert => 'Revert',
  };
}

enum GitHistoryBatchExecutionDirection { oldestToNewest, newestToOldest }

enum GitHistoryBatchState {
  completed,
  conflicted,
  cancelled,
  failed,
  readyToContinue,
  aborted,
}

enum GitHistoryBatchRecoveryAction {
  continueCurrent,
  skipCurrent,
  abortCurrent,
  continueRemaining,
  abortRemaining,
}

/// Full object IDs are retained in the request so refreshes cannot retarget a
/// batch to another visible row.
class GitHistoryBatchRequest {
  const GitHistoryBatchRequest({
    required this.action,
    required this.revisions,
    this.targetBranch,
    this.mainlines = const <String, int>{},
    this.confirmationToken,
    this.continuationToken,
    this.completedOids = const <String>[],
    this.skippedOids = const <String>[],
  });

  final GitHistoryBatchAction action;
  final List<String> revisions;
  final String? targetBranch;
  final Map<String, int> mainlines;
  final String? confirmationToken;
  final String? continuationToken;
  final List<String> completedOids;
  final List<String> skippedOids;

  String get queryKey => [
    action.name,
    targetBranch ?? '',
    ...revisions,
    for (final entry
        in mainlines.entries.toList()
          ..sort((left, right) => left.key.compareTo(right.key)))
      '${entry.key}:${entry.value}',
  ].join('\u0000');
}

/// State facts and impact for a batch before any Git mutation runs.
class GitHistoryBatchPreview {
  GitHistoryBatchPreview({
    required this.repositoryId,
    required this.request,
    required this.currentBranch,
    required this.currentHead,
    required this.targetBranch,
    required List<String> displayedOids,
    required List<String> executionOids,
    required this.executionDirection,
    required this.dirtyWorktree,
    required this.detachedHead,
    required this.operationInProgress,
    required List<String> duplicateOids,
    required List<String> containedOids,
    required List<String> mergeCommitOids,
    required List<String> mergeMainlineRequired,
    required List<String> impactedPaths,
    required this.fingerprint,
    required this.requiresConfirmation,
    this.token,
    this.expiresAt,
    this.blockingMessage,
  }) : displayedOids = List.unmodifiable(displayedOids),
       executionOids = List.unmodifiable(executionOids),
       duplicateOids = List.unmodifiable(duplicateOids),
       containedOids = List.unmodifiable(containedOids),
       mergeCommitOids = List.unmodifiable(mergeCommitOids),
       mergeMainlineRequired = List.unmodifiable(mergeMainlineRequired),
       impactedPaths = List.unmodifiable(impactedPaths);

  final RepositoryId repositoryId;
  final GitHistoryBatchRequest request;
  final String? currentBranch;
  final String currentHead;
  final String? targetBranch;
  final List<String> displayedOids;
  final List<String> executionOids;
  final GitHistoryBatchExecutionDirection executionDirection;
  final bool dirtyWorktree;
  final bool detachedHead;
  final GitBranchOperation? operationInProgress;
  final List<String> duplicateOids;
  final List<String> containedOids;
  final List<String> mergeCommitOids;
  final List<String> mergeMainlineRequired;
  final List<String> impactedPaths;
  final String fingerprint;
  final bool requiresConfirmation;
  final String? token;
  final DateTime? expiresAt;
  final String? blockingMessage;

  bool get canExecute =>
      blockingMessage == null &&
      token != null &&
      expiresAt != null &&
      expiresAt!.isAfter(DateTime.now());
}

/// Progress is explicit even when the operation stops at a conflict or is
/// cancelled between commits.
class GitHistoryBatchResult {
  GitHistoryBatchResult({
    required this.repositoryId,
    required this.request,
    required this.state,
    required this.status,
    required this.previousHead,
    required this.resultingHead,
    required List<String> completedOids,
    required List<String> skippedOids,
    required this.currentOid,
    required List<String> remainingOids,
    required this.summary,
    required List<GitHistoryBatchRecoveryAction> recoveryActions,
    this.continuationToken,
    this.selectionFingerprint = '',
  }) : completedOids = List.unmodifiable(completedOids),
       skippedOids = List.unmodifiable(skippedOids),
       remainingOids = List.unmodifiable(remainingOids),
       recoveryActions = List.unmodifiable(recoveryActions);

  final RepositoryId repositoryId;
  final GitHistoryBatchRequest request;
  final GitHistoryBatchState state;
  final GitStatusSnapshot status;
  final String previousHead;
  final String resultingHead;
  final List<String> completedOids;
  final List<String> skippedOids;
  final String? currentOid;
  final List<String> remainingOids;
  final String summary;
  final List<GitHistoryBatchRecoveryAction> recoveryActions;

  final String selectionFingerprint;
  final String? continuationToken;

  bool get historyChanged => completedOids.isNotEmpty || skippedOids.isNotEmpty;
}

/// Explicit recovery of the current sequencer operation or continuation of
/// the reviewed remainder.
class GitHistoryBatchRecoveryRequest {
  const GitHistoryBatchRecoveryRequest({
    required this.action,
    required this.revisions,
    required this.executionOids,
    required this.completedOids,
    required this.skippedOids,
    required this.currentOid,
    required this.remainingOids,
    required this.targetBranch,
    required this.mainlines,
    required this.selectionFingerprint,
    required this.recoveryAction,
    required this.continuationToken,
  });

  final GitHistoryBatchAction action;
  final List<String> revisions;
  final List<String> executionOids;
  final List<String> completedOids;
  final List<String> skippedOids;
  final String currentOid;
  final List<String> remainingOids;
  final String targetBranch;
  final Map<String, int> mainlines;
  final String selectionFingerprint;
  final GitHistoryBatchRecoveryAction recoveryAction;
  final String continuationToken;

  String get queryKey => [
    action.name,
    targetBranch,
    ...revisions,
    ...executionOids,
    ...completedOids,
    ...skippedOids,
    currentOid,
    ...remainingOids,
    selectionFingerprint,
  ].join('\u0000');

  GitHistoryBatchRequest get request => GitHistoryBatchRequest(
    action: action,
    revisions: revisions,
    targetBranch: targetBranch,
    mainlines: mainlines,
    completedOids: completedOids,
    skippedOids: skippedOids,
    continuationToken: continuationToken,
  );
}

/// A compact progress projection for widgets that do not need the full result.
class GitHistoryBatchProgress {
  const GitHistoryBatchProgress({
    required this.completedOids,
    required this.currentOid,
    required this.remainingOids,
  });

  final List<String> completedOids;
  final String? currentOid;
  final List<String> remainingOids;

  factory GitHistoryBatchProgress.fromResult(GitHistoryBatchResult result) =>
      GitHistoryBatchProgress(
        completedOids: result.completedOids,
        currentOid: result.currentOid,
        remainingOids: result.remainingOids,
      );
}

/// Keeps cancellation in the public contract without leaking process objects.
typedef GitHistoryBatchCancellation = GitCancellationToken;
