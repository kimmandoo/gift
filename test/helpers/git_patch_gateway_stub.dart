import 'package:gift/src/backend/commit.dart';
import 'package:gift/src/backend/conflict.dart';
import 'package:gift/src/backend/branch.dart';
import 'package:gift/src/backend/diff.dart';
import 'package:gift/src/backend/comparison.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/discard.dart';
import 'package:gift/src/backend/history.dart';
import 'package:gift/src/backend/executor.dart';
import 'package:gift/src/backend/remote.dart';
import 'package:gift/src/backend/status.dart';
import 'package:gift/src/backend/objects.dart';
import 'package:gift/src/backend/shelf.dart';
import 'package:gift/src/backend/file_history.dart';

/// Existing feature fakes do not need partial-patch behavior unless a test is
/// specifically about it. This keeps those focused fakes small as the
/// GitGateway contract grows.
mixin GitPatchGatewayStub {
  Future<GitInstallation> getGitInstallation() => throw UnimplementedError();

  Future<GitInstallation> configureGitPath(String path) =>
      throw UnimplementedError();

  Future<RepositoryOpened> openRepository(String path) =>
      throw UnimplementedError();

  Future<GitStatusSnapshot> getStatus(RepositoryId repositoryId) =>
      throw UnimplementedError();

  Future<GitHistoryPage> getHistory(
    RepositoryId repositoryId, {
    int limit = 50,
    int offset = 0,
    GitHistoryQuery? query,
  }) => throw UnimplementedError();

  Future<List<GitBranch>> getBranches(RepositoryId repositoryId) =>
      throw UnimplementedError();

  Future<GitBranchActionResult> createBranch(
    RepositoryId repositoryId,
    String name,
  ) => throw UnimplementedError();

  Future<GitBranchActionResult> switchBranch(
    RepositoryId repositoryId,
    String name,
  ) => throw UnimplementedError();

  Future<List<GitRemote>> getRemotes(RepositoryId repositoryId) =>
      throw UnimplementedError();

  Future<GitRemoteOperationResult> fetch(
    RepositoryId repositoryId,
    String remote, {
    GitCancellationToken? cancellationToken,
  }) => throw UnimplementedError();

  Future<GitRemoteOperationResult> pull(
    RepositoryId repositoryId,
    String remote, {
    GitCancellationToken? cancellationToken,
  }) => throw UnimplementedError();

  Future<GitRemoteOperationResult> push(
    RepositoryId repositoryId,
    String remote, {
    GitCancellationToken? cancellationToken,
  }) => throw UnimplementedError();

  Future<GitStashSnapshot> getStashes(RepositoryId repositoryId) =>
      throw UnimplementedError();

  Future<GitStashActionResult> createStash(
    RepositoryId repositoryId, {
    String message = '',
    bool includeUntracked = false,
  }) => throw UnimplementedError();

  Future<GitStashActionResult> applyStash(
    RepositoryId repositoryId,
    String stashOid, {
    required String fingerprint,
  }) => throw UnimplementedError();

  Future<GitStashActionResult> popStash(
    RepositoryId repositoryId,
    String stashOid, {
    required String fingerprint,
  }) => throw UnimplementedError();

  Future<GitObjectPreview> previewStashDrop(
    RepositoryId repositoryId,
    String stashOid,
  ) => throw UnimplementedError();

  Future<GitStashActionResult> dropStash(
    RepositoryId repositoryId,
    GitObjectPreview preview,
  ) => throw UnimplementedError();

  Future<GitStashActionResult> branchFromStash(
    RepositoryId repositoryId,
    String branchName,
    String stashOid, {
    required String fingerprint,
  }) => throw UnimplementedError();

  Future<GitTagSnapshot> getTags(RepositoryId repositoryId) =>
      throw UnimplementedError();

  Future<GitTagActionResult> createTag(
    RepositoryId repositoryId,
    String name, {
    String? target,
    bool annotated = false,
    String message = '',
  }) => throw UnimplementedError();

  Future<GitTag> getTag(RepositoryId repositoryId, String name) =>
      throw UnimplementedError();

  Future<GitObjectPreview> previewTagDelete(
    RepositoryId repositoryId,
    String name,
  ) => throw UnimplementedError();

  Future<GitTagActionResult> deleteTag(
    RepositoryId repositoryId,
    GitObjectPreview preview,
  ) => throw UnimplementedError();

  Future<GitRemoteActionResult> addRemote(
    RepositoryId repositoryId,
    String name,
    String url,
  ) => throw UnimplementedError();

  Future<GitRemoteActionResult> renameRemote(
    RepositoryId repositoryId,
    String oldName,
    String newName,
  ) => throw UnimplementedError();

  Future<GitRemoteActionResult> setRemoteUrl(
    RepositoryId repositoryId,
    String name,
    String url, {
    bool push = false,
  }) => throw UnimplementedError();

  Future<GitObjectPreview> previewRemoteRemove(
    RepositoryId repositoryId,
    String name,
  ) => throw UnimplementedError();

  Future<GitRemoteActionResult> removeRemote(
    RepositoryId repositoryId,
    GitObjectPreview preview,
  ) => throw UnimplementedError();

  Future<GitObjectPreview> previewRemotePrune(
    RepositoryId repositoryId,
    String name,
  ) => throw UnimplementedError();

  Future<GitRemoteActionResult> pruneRemote(
    RepositoryId repositoryId,
    GitObjectPreview preview,
  ) => throw UnimplementedError();

  Future<GitRemoteOperationResult> pushTag(
    RepositoryId repositoryId,
    String remote,
    String tagName, {
    GitCancellationToken? cancellationToken,
  }) => throw UnimplementedError();

  Future<GitUpstreamSnapshot> getUpstream(RepositoryId repositoryId) =>
      throw UnimplementedError();

  Future<GitUpstreamActionResult> setUpstream(
    RepositoryId repositoryId,
    String remote, {
    String? branch,
    String? remoteBranch,
  }) => throw UnimplementedError();

  Future<GitUpstreamActionResult> unsetUpstream(
    RepositoryId repositoryId, {
    String? branch,
  }) => throw UnimplementedError();

  Future<GitUpstreamActionResult> publishBranch(
    RepositoryId repositoryId,
    String remote, {
    String? branch,
  }) => throw UnimplementedError();

  Future<GitDiffSnapshot> getDiff(
    RepositoryId repositoryId,
    String path, {
    GitDiffScope scope = GitDiffScope.workingTree,
    String? originalPath,
  }) => throw UnimplementedError();

  Future<GitComparisonSnapshot> compareRevisions(
    RepositoryId repositoryId,
    String left,
    String right, {
    String? path,
  }) => throw UnimplementedError();

  Future<GitComparisonSnapshot> compareSources(
    RepositoryId repositoryId,
    GitComparisonSource left,
    GitComparisonSource right, {
    String? path,
  }) => throw UnimplementedError();

  Future<GitThreeWayComparisonSnapshot> compareThreeWay(
    RepositoryId repositoryId,
    GitComparisonSource base,
    GitComparisonSource left,
    GitComparisonSource right, {
    required String path,
  }) => throw UnimplementedError();

  Future<GitDiffSnapshot> getComparisonDiff(
    RepositoryId repositoryId,
    GitComparisonSnapshot comparison,
    String path,
  ) => throw UnimplementedError();

  Future<GitComparisonTransferResult> applyComparison(
    RepositoryId repositoryId,
    GitComparisonSnapshot comparison,
    String path, {
    GitComparisonTransferAction action = GitComparisonTransferAction.apply,
  }) => throw UnimplementedError();

  Future<GitStatusSnapshot> stage(RepositoryId repositoryId, String path) =>
      throw UnimplementedError();

  Future<GitStatusSnapshot> unstage(RepositoryId repositoryId, String path) =>
      throw UnimplementedError();

  Future<GitCommitResult> commit(
    RepositoryId repositoryId,
    String message, {
    GitCommitOptions options = const GitCommitOptions(),
  }) => throw UnimplementedError();

  Future<DiscardPreview> createDiscardPreview(
    RepositoryId repositoryId,
    String path,
  ) => throw UnimplementedError();

  Future<GitChangelistSnapshot> getChangelists(RepositoryId repositoryId) =>
      throw UnimplementedError();

  Future<GitChangelistSnapshot> createChangelist(
    RepositoryId repositoryId,
    String name,
  ) => throw UnimplementedError();

  Future<GitChangelistSnapshot> renameChangelist(
    RepositoryId repositoryId,
    String changelistId,
    String name,
  ) => throw UnimplementedError();

  Future<GitChangelistSnapshot> activateChangelist(
    RepositoryId repositoryId,
    String changelistId,
  ) => throw UnimplementedError();

  Future<GitChangelistSnapshot> deleteChangelist(
    RepositoryId repositoryId,
    String changelistId,
  ) => throw UnimplementedError();

  Future<GitChangelistSnapshot> moveChangelistPaths(
    RepositoryId repositoryId,
    Iterable<String> paths,
    String changelistId,
  ) => throw UnimplementedError();

  Future<GitShelfSnapshot> getShelves(RepositoryId repositoryId) =>
      throw UnimplementedError();

  Future<GitShelfActionResult> shelve(
    RepositoryId repositoryId, {
    String name = '',
    Iterable<String> paths = const <String>[],
  }) => throw UnimplementedError();

  Future<GitShelfActionResult> unshelve(
    RepositoryId repositoryId,
    String shelfId,
  ) => throw UnimplementedError();

  Future<GitShelfActionResult> restoreShelf(
    RepositoryId repositoryId,
    String shelfId,
  ) => throw UnimplementedError();

  Future<GitShelfActionResult> deleteShelf(
    RepositoryId repositoryId,
    String shelfId,
  ) => throw UnimplementedError();

  Future<GitShelfActionResult> importShelf(
    RepositoryId repositoryId,
    String name,
    List<int> patchBytes, {
    String? baseRevision,
  }) => throw UnimplementedError();

  Future<List<int>> exportShelf(RepositoryId repositoryId, String shelfId) =>
      throw UnimplementedError();

  Future<GitFileHistorySnapshot> getFileHistory(
    RepositoryId repositoryId,
    GitFileHistoryQuery query,
  ) => throw UnimplementedError();

  Future<GitBlameSnapshot> getBlame(
    RepositoryId repositoryId,
    String path, {
    GitBlameOptions options = const GitBlameOptions(),
  }) => throw UnimplementedError();

  Future<GitRevisionGetResult> getFileFromRevision(
    RepositoryId repositoryId,
    GitFileHistorySnapshot history,
    String revision,
  ) => throw UnimplementedError();

  Future<GitStatusSnapshot> discard(
    RepositoryId repositoryId,
    DiscardPreview preview,
  ) => throw UnimplementedError();

  Future<GitConflictSnapshot> getConflicts(RepositoryId repositoryId) =>
      throw UnimplementedError();

  Future<GitConflictResolutionResult> acceptConflictOurs(
    RepositoryId repositoryId,
    String path, {
    required String fingerprint,
  }) => throw UnimplementedError();

  Future<GitConflictResolutionResult> acceptConflictTheirs(
    RepositoryId repositoryId,
    String path, {
    required String fingerprint,
  }) => throw UnimplementedError();

  Future<GitConflictResolutionResult> editConflictResult(
    RepositoryId repositoryId,
    String path,
    String content, {
    required String fingerprint,
  }) => throw UnimplementedError();

  Future<GitConflictResolutionResult> markConflictResolved(
    RepositoryId repositoryId,
    String path, {
    required String fingerprint,
    bool deleteResult = false,
  }) => throw UnimplementedError();

  Future<GitConflictOperationResult> continueConflict(
    RepositoryId repositoryId, {
    required String fingerprint,
    GitCancellationToken? cancellationToken,
  }) => throw UnimplementedError();

  Future<GitConflictOperationResult> abortConflict(
    RepositoryId repositoryId, {
    required String fingerprint,
    GitCancellationToken? cancellationToken,
  }) => throw UnimplementedError();

  Future<GitCommit> getCommit(RepositoryId repositoryId, String commitOid) =>
      throw UnimplementedError();

  Future<List<GitCommitFileChange>> getCommitFiles(
    RepositoryId repositoryId,
    String commitOid,
  ) => throw UnimplementedError();

  Future<GitCommitDiff> getCommitDiff(
    RepositoryId repositoryId,
    String commitOid,
    String path, {
    String? originalPath,
  }) => throw UnimplementedError();

  Future<GitCommitPreflight> preflightCommit(
    RepositoryId repositoryId, {
    GitCommitOptions options = const GitCommitOptions(),
  }) => throw UnimplementedError();

  Future<GitCommitTemplate> loadCommitTemplate(RepositoryId repositoryId) =>
      throw UnimplementedError();

  Future<GitStatusSnapshot> stagePatch(
    RepositoryId repositoryId,
    GitPatchSelection selection,
  ) => throw UnimplementedError();

  Future<GitStatusSnapshot> unstagePatch(
    RepositoryId repositoryId,
    GitPatchSelection selection,
  ) => throw UnimplementedError();

  Future<GitBranchOperationPreview> previewBranchOperation(
    RepositoryId repositoryId,
    GitBranchOperationRequest request,
  ) => throw UnimplementedError();

  Future<GitBranchOperationResult> executeBranchOperation(
    RepositoryId repositoryId,
    GitBranchOperationRequest request, {
    GitCancellationToken? cancellationToken,
  }) => throw UnimplementedError();
}
