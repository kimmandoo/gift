import 'domain.dart';
import 'error.dart';
import 'objects.dart';
import 'status.dart';

/// The destination selected by a push review.
enum GitPushTarget { currentBranch, selectedCommit, allTags }

/// A push request contains only structured values. The backend turns it into
/// an explicit refspec after validating the reviewed repository state.
class GitPushRequest {
  const GitPushRequest({
    required this.remote,
    this.target = GitPushTarget.currentBranch,
    this.branch,
    this.commitOid,
    this.tagNames = const [],
    this.forceWithLease = false,
    this.expectedRemoteOid,
    this.confirmationToken,
  });

  final String remote;
  final GitPushTarget target;
  final String? branch;
  final String? commitOid;
  final List<String> tagNames;
  final bool forceWithLease;
  final String? expectedRemoteOid;
  final String? confirmationToken;

  String get queryKey => [
    remote,
    target.name,
    branch ?? '',
    commitOid ?? '',
    ...tagNames,
    forceWithLease,
    expectedRemoteOid ?? '',
  ].join('|');

  GitPushRequest copyWith({String? confirmationToken}) => GitPushRequest(
    remote: remote,
    target: target,
    branch: branch,
    commitOid: commitOid,
    tagNames: tagNames,
    forceWithLease: forceWithLease,
    expectedRemoteOid: expectedRemoteOid,
    confirmationToken: confirmationToken ?? this.confirmationToken,
  );
}

class GitPushCommit {
  const GitPushCommit({
    required this.oid,
    required this.subject,
    this.changedPaths = const [],
  });

  final String oid;
  final String subject;
  final List<String> changedPaths;
}

class GitPushPreview {
  const GitPushPreview({
    required this.repositoryId,
    required this.request,
    required this.remote,
    required this.currentBranch,
    required this.targetBranch,
    required this.localHead,
    required this.targetOid,
    required this.remoteHead,
    required this.commits,
    required this.changedPaths,
    required this.tags,
    required this.dirtyWorktree,
    required this.protectedBranch,
    required this.requiresConfirmation,
    required this.fingerprint,
    this.blockingMessage,
    this.token,
    this.expiresAt,
  });

  final RepositoryId repositoryId;
  final GitPushRequest request;
  final String remote;
  final String currentBranch;
  final String targetBranch;
  final String localHead;
  final String targetOid;
  final String? remoteHead;
  final List<GitPushCommit> commits;
  final List<String> changedPaths;
  final List<GitTag> tags;
  final bool dirtyWorktree;
  final bool protectedBranch;
  final bool requiresConfirmation;
  final String fingerprint;
  final String? blockingMessage;
  final String? token;
  final DateTime? expiresAt;

  bool get canExecute =>
      token != null &&
      expiresAt != null &&
      expiresAt!.isAfter(DateTime.now()) &&
      blockingMessage == null;
}

enum GitPushState { completed, rejected, cancelled }

enum GitPushRecoveryAction { retry, merge, rebase }

class GitPushResult {
  const GitPushResult({
    required this.repositoryId,
    required this.request,
    required this.state,
    required this.status,
    required this.summary,
    this.failureCategory,
    this.recoveryActions = const [],
  });

  final RepositoryId repositoryId;
  final GitPushRequest request;
  final GitPushState state;
  final GitStatusSnapshot status;
  final String summary;
  final GitErrorCategory? failureCategory;
  final List<GitPushRecoveryAction> recoveryActions;

  bool get historyChanged => state == GitPushState.completed;
}
