import 'domain.dart';
import 'status.dart';

/// The four Git reset modes exposed by the history rollback workflow.
enum GitResetMode { soft, mixed, hard, keep }

extension GitResetModeArgs on GitResetMode {
  String get gitValue => name;

  String get label => switch (this) {
    GitResetMode.soft => 'Soft',
    GitResetMode.mixed => 'Mixed',
    GitResetMode.hard => 'Hard',
    GitResetMode.keep => 'Keep',
  };
}

/// A history-changing action. Reset and undo move a ref; revert creates new
/// commit(s) and keeps the original history reachable.
enum GitHistoryRollbackAction { reset, undo, revert }

enum GitHistoryRollbackState { completed, conflicted, cancelled }

/// Describes what a reset will do to one tree-like part of the repository.
/// The values are intentionally typed so UI copy cannot accidentally present
/// a hard reset as if it preserved local content.
enum GitRollbackTreeEffect { preserved, resetToTarget, unchanged }

enum GitHistoryRollbackRecoveryAction { continueRevert, abortRevert }

/// The exact, bounded impact shown before a reset, undo, or revert runs.
class GitRollbackImpact {
  GitRollbackImpact({
    required this.headBefore,
    required this.headAfter,
    required this.indexEffect,
    required this.worktreeEffect,
    required List<String> stagedPathsBefore,
    required List<String> unstagedPathsBefore,
    required List<String> potentiallyDiscardedPaths,
    required List<String> preservedPaths,
    required this.commitsMoved,
  }) : stagedPathsBefore = List.unmodifiable(stagedPathsBefore),
       unstagedPathsBefore = List.unmodifiable(unstagedPathsBefore),
       potentiallyDiscardedPaths = List.unmodifiable(potentiallyDiscardedPaths),
       preservedPaths = List.unmodifiable(preservedPaths);

  final String headBefore;
  final String headAfter;
  final GitRollbackTreeEffect indexEffect;
  final GitRollbackTreeEffect worktreeEffect;
  final List<String> stagedPathsBefore;
  final List<String> unstagedPathsBefore;
  final List<String> potentiallyDiscardedPaths;
  final List<String> preservedPaths;
  final int commitsMoved;

  bool get discardsLocalContent => potentiallyDiscardedPaths.isNotEmpty;
}

/// A bounded request shared by the preview and execution calls.
class GitHistoryRollbackRequest {
  const GitHistoryRollbackRequest({
    required this.action,
    this.targetRevision,
    this.mode = GitResetMode.mixed,
    this.revisions = const <String>[],
  });

  final GitHistoryRollbackAction action;
  final String? targetRevision;
  final GitResetMode mode;
  final List<String> revisions;

  String get queryKey => [
    action.name,
    targetRevision ?? '',
    mode.name,
    ...revisions,
  ].join('\u0000');
}

/// Facts collected at preview time. A token is issued only when the
/// repository is safe for the requested action; execution rechecks every fact
/// before passing a command to Git.
class GitHistoryRollbackPreview {
  GitHistoryRollbackPreview({
    required this.repositoryId,
    required this.request,
    required this.currentBranch,
    required this.currentHead,
    required this.targetHead,
    required this.upstreamHead,
    required this.branchProtected,
    required this.pushedCommits,
    required this.detachedHead,
    required this.dirtyWorktree,
    required this.operationInProgress,
    required this.impact,
    required this.fingerprint,
    required this.requiresConfirmation,
    this.token,
    this.expiresAt,
    this.blockingMessage,
    List<String> revisions = const <String>[],
  }) : revisions = List.unmodifiable(revisions);

  final RepositoryId repositoryId;
  final GitHistoryRollbackRequest request;
  final String? currentBranch;
  final String currentHead;
  final String targetHead;
  final String? upstreamHead;
  final bool branchProtected;
  final bool pushedCommits;
  final bool detachedHead;
  final bool dirtyWorktree;
  final bool operationInProgress;
  final GitRollbackImpact impact;
  final String fingerprint;
  final bool requiresConfirmation;
  final String? token;
  final DateTime? expiresAt;
  final String? blockingMessage;
  final List<String> revisions;

  bool get canExecute =>
      blockingMessage == null &&
      token != null &&
      expiresAt != null &&
      expiresAt!.isAfter(DateTime.now());

  bool get isDestructive =>
      request.action != GitHistoryRollbackAction.revert ||
      request.mode == GitResetMode.hard;
}

class GitHistoryRollbackResult {
  GitHistoryRollbackResult({
    required this.repositoryId,
    required this.request,
    required this.state,
    required this.status,
    required this.previousHead,
    required this.resultingHead,
    required this.summary,
    List<String> revertedCommitOids = const <String>[],
    List<GitHistoryRollbackRecoveryAction> recoveryActions =
        const <GitHistoryRollbackRecoveryAction>[],
  }) : revertedCommitOids = List.unmodifiable(revertedCommitOids),
       recoveryActions = List.unmodifiable(recoveryActions);

  final RepositoryId repositoryId;
  final GitHistoryRollbackRequest request;
  final GitHistoryRollbackState state;
  final GitStatusSnapshot status;
  final String previousHead;
  final String resultingHead;
  final String summary;
  final List<String> revertedCommitOids;
  final List<GitHistoryRollbackRecoveryAction> recoveryActions;

  bool get historyChanged => state == GitHistoryRollbackState.completed;
}

// Short aliases keep the contract discoverable for callers that think in
// terms of one reset operation rather than the shared rollback workflow.
typedef GitResetPreview = GitHistoryRollbackPreview;
typedef GitResetResult = GitHistoryRollbackResult;
