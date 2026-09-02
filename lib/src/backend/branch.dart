import 'dart:convert';

import 'domain.dart';
import 'status.dart';

/// A local branch and the upstream information Git reports for it.
class GitBranch {
  const GitBranch({
    required this.name,
    this.oid,
    this.upstream,
    this.isCurrent = false,
    this.ahead = 0,
    this.behind = 0,
  });

  final String name;
  final String? oid;
  final String? upstream;
  final bool isCurrent;
  final int ahead;
  final int behind;

  bool get hasUpstream => upstream != null && upstream!.isNotEmpty;
}

/// The refreshed repository state after creating or switching a branch.
class GitBranchActionResult {
  const GitBranchActionResult({
    required this.repositoryId,
    required this.branchName,
    required this.status,
  });

  final RepositoryId repositoryId;
  final String branchName;
  final GitStatusSnapshot status;
}

/// History-changing operations exposed by the branch workflow.
enum GitBranchOperation { rename, delete, merge, rebase, cherryPick }

/// Git's recovery commands are intentionally represented as separate phases.
/// A caller must choose the exact recovery action instead of asking the
/// backend to guess whether a failed operation should continue or abort.
enum GitBranchOperationPhase { start, continueOperation, skip, abort }

enum GitBranchOperationState { completed, conflicted, aborted, cancelled }

/// A request for a branch operation. `source` and `target` have operation-
/// specific meanings documented by [GitBranchOperationPreview].
class GitBranchOperationRequest {
  const GitBranchOperationRequest({
    required this.operation,
    this.source,
    this.target,
    this.phase = GitBranchOperationPhase.start,
    this.force = false,
    this.confirmationToken,
  });

  final GitBranchOperation operation;
  final String? source;
  final String? target;
  final GitBranchOperationPhase phase;
  final bool force;
  final String? confirmationToken;
}

/// The bounded facts shown to a user before a history-changing operation.
///
/// For rename/delete, source and target are branch names. For merge, source is
/// the branch being merged into the current target. For rebase, source is the
/// current branch and target is its new base. For cherry-pick, source is a
/// commit/ref and target is the current branch.
class GitBranchOperationPreview {
  const GitBranchOperationPreview({
    required this.repositoryId,
    required this.request,
    required this.currentBranch,
    required this.ahead,
    required this.behind,
    required this.expectedCommits,
    required this.mergeBase,
    required this.dirtyWorktree,
    required this.detachedHead,
    required this.operationInProgress,
    required this.requiresConfirmation,
    required this.token,
    required this.expiresAt,
    this.blockingMessage,
  });

  final RepositoryId repositoryId;
  final GitBranchOperationRequest request;
  final String? currentBranch;
  final int ahead;
  final int behind;
  final int expectedCommits;
  final String? mergeBase;
  final bool dirtyWorktree;
  final bool detachedHead;
  final GitBranchOperation? operationInProgress;
  final bool requiresConfirmation;
  final String? token;
  final DateTime? expiresAt;
  final String? blockingMessage;

  bool get canExecute =>
      token != null &&
      expiresAt != null &&
      expiresAt!.isAfter(DateTime.now()) &&
      blockingMessage == null;
}

class GitBranchOperationResult {
  const GitBranchOperationResult({
    required this.repositoryId,
    required this.request,
    required this.state,
    required this.status,
    required this.summary,
    required this.recoveryActions,
  });

  final RepositoryId repositoryId;
  final GitBranchOperationRequest request;
  final GitBranchOperationState state;
  final GitStatusSnapshot status;
  final String summary;
  final List<GitBranchOperationPhase> recoveryActions;

  bool get historyChanged => state == GitBranchOperationState.completed;
}

/// The token returned by AppState for a short-lived operation preview.
class GitBranchPreviewToken {
  const GitBranchPreviewToken({required this.value, required this.expiresAt});

  final String value;
  final DateTime expiresAt;
}

/// Parses `git for-each-ref` rows without depending on localized output.
List<GitBranch> parseGitBranches(List<int> output) {
  final branches = <GitBranch>[];
  final text = utf8.decode(output, allowMalformed: true);
  for (final rawLine in text.split('\n')) {
    final line = rawLine.trimRight();
    if (line.isEmpty) continue;
    final fields = line.split('\u0000');
    if (fields.length != 4 || fields[0].isEmpty) {
      throw FormatException('Invalid Git branch record: $line');
    }
    branches.add(
      GitBranch(
        name: fields[0],
        oid: fields[1].isEmpty ? null : fields[1],
        upstream: fields[2].isEmpty ? null : fields[2],
        isCurrent: fields[3].trim() == '*',
      ),
    );
  }
  return List.unmodifiable(branches);
}
