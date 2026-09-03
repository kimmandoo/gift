import 'domain.dart';
import 'branch.dart';
import 'commit.dart';
import 'conflict.dart';
import 'discard.dart';
import 'diff.dart';
import 'comparison.dart';
import 'status.dart';
import 'history.dart';
import 'executor.dart';
import 'remote.dart';
import 'objects.dart';
import 'shelf.dart';

/// The small API that Flutter features depend on.
///
/// Screens and controllers use this interface instead of constructing
/// processes. Tests can provide a fake implementation without touching Git.
abstract interface class GitGateway {
  Future<GitInstallation> getGitInstallation();

  Future<GitInstallation> configureGitPath(String path);

  Future<RepositoryOpened> openRepository(String path);

  Future<GitStatusSnapshot> getStatus(RepositoryId repositoryId);

  Future<GitConflictSnapshot> getConflicts(RepositoryId repositoryId);

  Future<GitConflictResolutionResult> acceptConflictOurs(
    RepositoryId repositoryId,
    String path, {
    required String fingerprint,
  });

  Future<GitConflictResolutionResult> acceptConflictTheirs(
    RepositoryId repositoryId,
    String path, {
    required String fingerprint,
  });

  Future<GitConflictResolutionResult> editConflictResult(
    RepositoryId repositoryId,
    String path,
    String content, {
    required String fingerprint,
  });

  Future<GitConflictResolutionResult> markConflictResolved(
    RepositoryId repositoryId,
    String path, {
    required String fingerprint,
    bool deleteResult = false,
  });

  Future<GitConflictOperationResult> continueConflict(
    RepositoryId repositoryId, {
    required String fingerprint,
    GitCancellationToken? cancellationToken,
  });

  Future<GitConflictOperationResult> abortConflict(
    RepositoryId repositoryId, {
    required String fingerprint,
    GitCancellationToken? cancellationToken,
  });

  Future<GitHistoryPage> getHistory(
    RepositoryId repositoryId, {
    int limit = 50,
    int offset = 0,
    GitHistoryQuery? query,
  });

  Future<GitCommit> getCommit(RepositoryId repositoryId, String commitOid);

  Future<List<GitCommitFileChange>> getCommitFiles(
    RepositoryId repositoryId,
    String commitOid,
  );

  Future<GitCommitDiff> getCommitDiff(
    RepositoryId repositoryId,
    String commitOid,
    String path, {
    String? originalPath,
  });

  Future<List<GitBranch>> getBranches(RepositoryId repositoryId);

  Future<GitBranchActionResult> createBranch(
    RepositoryId repositoryId,
    String name,
  );

  Future<GitBranchActionResult> switchBranch(
    RepositoryId repositoryId,
    String name,
  );

  Future<GitBranchOperationPreview> previewBranchOperation(
    RepositoryId repositoryId,
    GitBranchOperationRequest request,
  );

  Future<GitBranchOperationResult> executeBranchOperation(
    RepositoryId repositoryId,
    GitBranchOperationRequest request, {
    GitCancellationToken? cancellationToken,
  });

  Future<List<GitRemote>> getRemotes(RepositoryId repositoryId);

  Future<GitRemoteOperationResult> fetch(
    RepositoryId repositoryId,
    String remote, {
    GitCancellationToken? cancellationToken,
  });

  Future<GitRemoteOperationResult> pull(
    RepositoryId repositoryId,
    String remote, {
    GitCancellationToken? cancellationToken,
  });

  Future<GitRemoteOperationResult> push(
    RepositoryId repositoryId,
    String remote, {
    GitCancellationToken? cancellationToken,
  });

  Future<GitStashSnapshot> getStashes(RepositoryId repositoryId);

  Future<GitStashActionResult> createStash(
    RepositoryId repositoryId, {
    String message = '',
    bool includeUntracked = false,
  });

  Future<GitStashActionResult> applyStash(
    RepositoryId repositoryId,
    String stashOid, {
    required String fingerprint,
  });

  Future<GitStashActionResult> popStash(
    RepositoryId repositoryId,
    String stashOid, {
    required String fingerprint,
  });

  Future<GitObjectPreview> previewStashDrop(
    RepositoryId repositoryId,
    String stashOid,
  );

  Future<GitStashActionResult> dropStash(
    RepositoryId repositoryId,
    GitObjectPreview preview,
  );

  Future<GitStashActionResult> branchFromStash(
    RepositoryId repositoryId,
    String branchName,
    String stashOid, {
    required String fingerprint,
  });

  Future<GitTagSnapshot> getTags(RepositoryId repositoryId);

  Future<GitTagActionResult> createTag(
    RepositoryId repositoryId,
    String name, {
    String? target,
    bool annotated = false,
    String message = '',
  });

  Future<GitTag> getTag(RepositoryId repositoryId, String name);

  Future<GitObjectPreview> previewTagDelete(
    RepositoryId repositoryId,
    String name,
  );

  Future<GitTagActionResult> deleteTag(
    RepositoryId repositoryId,
    GitObjectPreview preview,
  );

  Future<GitRemoteActionResult> addRemote(
    RepositoryId repositoryId,
    String name,
    String url,
  );

  Future<GitRemoteActionResult> renameRemote(
    RepositoryId repositoryId,
    String oldName,
    String newName,
  );

  Future<GitRemoteActionResult> setRemoteUrl(
    RepositoryId repositoryId,
    String name,
    String url, {
    bool push = false,
  });

  Future<GitObjectPreview> previewRemoteRemove(
    RepositoryId repositoryId,
    String name,
  );

  Future<GitRemoteActionResult> removeRemote(
    RepositoryId repositoryId,
    GitObjectPreview preview,
  );

  Future<GitObjectPreview> previewRemotePrune(
    RepositoryId repositoryId,
    String name,
  );

  Future<GitRemoteActionResult> pruneRemote(
    RepositoryId repositoryId,
    GitObjectPreview preview,
  );

  Future<GitRemoteOperationResult> pushTag(
    RepositoryId repositoryId,
    String remote,
    String tagName, {
    GitCancellationToken? cancellationToken,
  });

  Future<GitUpstreamSnapshot> getUpstream(RepositoryId repositoryId);

  Future<GitUpstreamActionResult> setUpstream(
    RepositoryId repositoryId,
    String remote, {
    String? branch,
    String? remoteBranch,
  });

  Future<GitUpstreamActionResult> unsetUpstream(
    RepositoryId repositoryId, {
    String? branch,
  });

  Future<GitUpstreamActionResult> publishBranch(
    RepositoryId repositoryId,
    String remote, {
    String? branch,
  });

  Future<GitDiffSnapshot> getDiff(
    RepositoryId repositoryId,
    String path, {
    GitDiffScope scope = GitDiffScope.workingTree,
    String? originalPath,
  });

  Future<GitComparisonSnapshot> compareRevisions(
    RepositoryId repositoryId,
    String left,
    String right, {
    String? path,
  });

  Future<GitComparisonSnapshot> compareSources(
    RepositoryId repositoryId,
    GitComparisonSource left,
    GitComparisonSource right, {
    String? path,
  });

  Future<GitThreeWayComparisonSnapshot> compareThreeWay(
    RepositoryId repositoryId,
    GitComparisonSource base,
    GitComparisonSource left,
    GitComparisonSource right, {
    required String path,
  });

  Future<GitDiffSnapshot> getComparisonDiff(
    RepositoryId repositoryId,
    GitComparisonSnapshot comparison,
    String path,
  );

  Future<GitComparisonTransferResult> applyComparison(
    RepositoryId repositoryId,
    GitComparisonSnapshot comparison,
    String path, {
    GitComparisonTransferAction action = GitComparisonTransferAction.apply,
  });

  Future<GitChangelistSnapshot> getChangelists(RepositoryId repositoryId);

  Future<GitChangelistSnapshot> createChangelist(
    RepositoryId repositoryId,
    String name,
  );

  Future<GitChangelistSnapshot> renameChangelist(
    RepositoryId repositoryId,
    String changelistId,
    String name,
  );

  Future<GitChangelistSnapshot> activateChangelist(
    RepositoryId repositoryId,
    String changelistId,
  );

  Future<GitChangelistSnapshot> deleteChangelist(
    RepositoryId repositoryId,
    String changelistId,
  );

  Future<GitChangelistSnapshot> moveChangelistPaths(
    RepositoryId repositoryId,
    Iterable<String> paths,
    String changelistId,
  );

  Future<GitShelfSnapshot> getShelves(RepositoryId repositoryId);

  Future<GitShelfActionResult> shelve(
    RepositoryId repositoryId, {
    String name = '',
    Iterable<String> paths = const <String>[],
  });

  Future<GitShelfActionResult> unshelve(
    RepositoryId repositoryId,
    String shelfId,
  );

  Future<GitShelfActionResult> restoreShelf(
    RepositoryId repositoryId,
    String shelfId,
  );

  Future<GitShelfActionResult> deleteShelf(
    RepositoryId repositoryId,
    String shelfId,
  );

  Future<GitShelfActionResult> importShelf(
    RepositoryId repositoryId,
    String name,
    List<int> patchBytes, {
    String? baseRevision,
  });

  Future<List<int>> exportShelf(RepositoryId repositoryId, String shelfId);

  Future<GitStatusSnapshot> stage(RepositoryId repositoryId, String path);

  Future<GitStatusSnapshot> unstage(RepositoryId repositoryId, String path);

  Future<GitStatusSnapshot> stagePatch(
    RepositoryId repositoryId,
    GitPatchSelection selection,
  );

  Future<GitStatusSnapshot> unstagePatch(
    RepositoryId repositoryId,
    GitPatchSelection selection,
  );

  Future<GitCommitPreflight> preflightCommit(
    RepositoryId repositoryId, {
    GitCommitOptions options = const GitCommitOptions(),
  });

  Future<GitCommitTemplate> loadCommitTemplate(RepositoryId repositoryId);

  Future<GitCommitResult> commit(
    RepositoryId repositoryId,
    String message, {
    GitCommitOptions options = const GitCommitOptions(),
  });

  Future<DiscardPreview> createDiscardPreview(
    RepositoryId repositoryId,
    String path,
  );

  Future<GitStatusSnapshot> discard(
    RepositoryId repositoryId,
    DiscardPreview preview,
  );
}

/// Optional capability for gateways that can revoke an unused destructive
/// confirmation immediately instead of waiting for its short expiry.
abstract interface class DiscardPreviewCancellationGateway {
  Future<void> cancelDiscardPreview(DiscardPreview preview);
}
