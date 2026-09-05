import 'package:gift/src/backend/commit.dart';
import 'package:gift/src/backend/conflict.dart';
import 'package:gift/src/backend/branch.dart';
import 'package:gift/src/backend/diff.dart';
import 'package:gift/src/backend/comparison.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/discard.dart';
import 'package:gift/src/backend/history.dart';
import 'package:gift/src/backend/interactive_rebase.dart';
import 'package:gift/src/backend/executor.dart';
import 'package:gift/src/backend/remote.dart';
import 'package:gift/src/backend/remote_branch.dart';
import 'package:gift/src/backend/status.dart';
import 'package:gift/src/backend/objects.dart';
import 'package:gift/src/backend/shelf.dart';
import 'package:gift/src/backend/file_history.dart';
import 'package:gift/src/backend/reset.dart';
import 'package:gift/src/backend/history_batch.dart';
import 'package:gift/src/backend/push.dart';
import 'package:gift/src/backend/worktree.dart';
import 'package:gift/src/backend/ignore.dart';
import 'package:gift/src/backend/submodule.dart';
import 'package:gift/src/backend/recovery.dart';
import 'package:gift/src/backend/setup.dart';
import 'package:gift/src/backend/hosting.dart';
import 'package:gift/src/backend/repository_paths.dart';

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

  Future<GitRepositoryPathSnapshot> getRepositoryPaths(
    RepositoryId repositoryId, {
    int maxEntries = 2000,
  }) => throw UnimplementedError();

  Future<GitHistoryPage> getHistory(
    RepositoryId repositoryId, {
    int limit = 50,
    int offset = 0,
    GitHistoryQuery? query,
  }) => throw UnimplementedError();

  Future<List<GitBranch>> getBranches(RepositoryId repositoryId) =>
      throw UnimplementedError();

  Future<GitRemoteBranchSnapshot> getRemoteBranchSnapshot(
    RepositoryId repositoryId,
  ) => throw UnimplementedError();

  Future<GitBranchActionResult> checkoutRemoteBranch(
    RepositoryId repositoryId,
    GitRemoteBranch branch, {
    String? localName,
  }) => throw UnimplementedError();

  Future<GitUpdateProjectPreview> previewUpdateProject(
    RepositoryId repositoryId,
    GitUpdateProjectRequest request,
  ) => throw UnimplementedError();

  Future<GitUpdateProjectResult> executeUpdateProject(
    RepositoryId repositoryId,
    GitUpdateProjectRequest request, {
    GitCancellationToken? cancellationToken,
  }) => throw UnimplementedError();

  Future<GitBranchActionResult> createBranch(
    RepositoryId repositoryId,
    String name,
  ) => throw UnimplementedError();

  Future<GitBranchActionResult> createBranchAtCommit(
    RepositoryId repositoryId,
    String name,
    String commitOid,
  ) => throw UnimplementedError();

  Future<GitBranchActionResult> switchBranch(
    RepositoryId repositoryId,
    String name,
  ) => throw UnimplementedError();

  Future<List<GitRemote>> getRemotes(RepositoryId repositoryId) =>
      throw UnimplementedError();

  Future<GitRemoteBranchDeletePreview> previewRemoteBranchDelete(
    RepositoryId repositoryId,
    GitRemoteBranch branch,
  ) => throw UnimplementedError();

  Future<GitRemoteBranchActionResult> deleteRemoteBranch(
    RepositoryId repositoryId,
    GitRemoteBranchDeletePreview preview,
  ) => throw UnimplementedError();

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

  Future<GitPushPreview> previewPush(
    RepositoryId repositoryId,
    GitPushRequest request,
  ) => throw UnimplementedError();

  Future<GitPushResult> executePush(
    RepositoryId repositoryId,
    GitPushRequest request, {
    GitCancellationToken? cancellationToken,
  }) => throw UnimplementedError();

  Future<GitWorktreeSnapshot> getWorktrees(RepositoryId repositoryId) =>
      throw UnimplementedError();

  Future<GitWorktreeCreateResult> createWorktree(
    RepositoryId repositoryId,
    GitWorktreeCreateRequest request,
  ) => throw UnimplementedError();

  Future<RepositoryOpened> openWorktree(
    RepositoryId repositoryId,
    GitWorktree worktree,
  ) => throw UnimplementedError();

  Future<GitWorktreeActionPreview> previewWorktreeAction(
    RepositoryId repositoryId,
    GitWorktreeActionRequest request,
  ) => throw UnimplementedError();

  Future<GitWorktreeActionResult> executeWorktreeAction(
    RepositoryId repositoryId,
    GitWorktreeActionRequest request, {
    GitCancellationToken? cancellationToken,
  }) => throw UnimplementedError();

  Future<GitIgnoreSnapshot> getIgnoreSnapshot(RepositoryId repositoryId) =>
      throw UnimplementedError();

  Future<GitIgnoreActionResult> addIgnorePattern(
    RepositoryId repositoryId,
    GitIgnoreRequest request,
  ) => throw UnimplementedError();

  Future<GitAttributesSnapshot> getAttributes(
    RepositoryId repositoryId, {
    List<String> paths = const [],
  }) => throw UnimplementedError();

  Future<GitSubmoduleSnapshot> getSubmodules(RepositoryId repositoryId) =>
      throw UnimplementedError();

  Future<GitSubmoduleActionResult> executeSubmoduleAction(
    RepositoryId repositoryId,
    GitSubmoduleActionRequest request, {
    GitCancellationToken? cancellationToken,
  }) => throw UnimplementedError();

  Future<GitNestedRootSnapshot> getNestedRoots(RepositoryId repositoryId) =>
      throw UnimplementedError();

  Future<GitReflogSnapshot> getReflog(
    RepositoryId repositoryId, {
    String ref = 'HEAD',
    int limit = 100,
  }) => throw UnimplementedError();

  Future<GitRecoveryBranchPreview> previewRecoveryBranch(
    RepositoryId repositoryId,
    GitRecoveryBranchRequest request,
  ) => throw UnimplementedError();

  Future<GitRecoveryBranchResult> createRecoveryBranch(
    RepositoryId repositoryId,
    GitRecoveryBranchPreview preview,
  ) => throw UnimplementedError();

  Future<List<GitOperationRecord>> getOperationRecords(
    RepositoryId repositoryId, {
    int limit = 100,
  }) => throw UnimplementedError();

  Future<GitRepositorySetupResult> cloneRepository(
    GitCloneRequest request, {
    GitCancellationToken? cancellationToken,
  }) => throw UnimplementedError();

  Future<GitRepositorySetupResult> initRepository(
    GitInitRequest request, {
    GitCancellationToken? cancellationToken,
  }) => throw UnimplementedError();

  Future<GitUnshallowResult> unshallowRepository(
    RepositoryId repositoryId, {
    GitCancellationToken? cancellationToken,
  }) => throw UnimplementedError();

  Future<GitRootDiscoverySnapshot> discoverRepositoryRoots(String path) =>
      throw UnimplementedError();

  Future<GitHostingSnapshot> getHostingRepository(
    RepositoryId repositoryId, {
    String remote = 'origin',
  }) => throw UnimplementedError();

  Future<GitHostingLinks> getHostingLinks(
    RepositoryId repositoryId,
    String commitOid, {
    String? remote,
    String? path,
    int? lineStart,
    int? lineEnd,
  }) => throw UnimplementedError();

  Future<GitHostingReviewCapability> getHostingReviewCapability(
    RepositoryId repositoryId, {
    String remote = 'origin',
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

  Future<GitHistoryRollbackPreview> previewHistoryRollback(
    RepositoryId repositoryId,
    GitHistoryRollbackRequest request,
  ) => throw UnimplementedError();

  Future<GitHistoryRollbackResult> executeHistoryRollback(
    RepositoryId repositoryId,
    GitHistoryRollbackPreview preview, {
    GitCancellationToken? cancellationToken,
  }) => throw UnimplementedError();

  Future<GitInteractiveRebasePreview> previewInteractiveRebase(
    RepositoryId repositoryId,
    GitInteractiveRebasePlan plan,
  ) => throw UnimplementedError();

  Future<GitHistoryBatchPreview> previewHistoryBatch(
    RepositoryId repositoryId,
    GitHistoryBatchRequest request,
  ) => throw UnimplementedError();

  Future<GitHistoryBatchResult> executeHistoryBatch(
    RepositoryId repositoryId,
    GitHistoryBatchPreview preview, {
    GitCancellationToken? cancellationToken,
  }) => throw UnimplementedError();

  Future<GitHistoryBatchResult> recoverHistoryBatch(
    RepositoryId repositoryId,
    GitHistoryBatchRecoveryRequest request, {
    GitCancellationToken? cancellationToken,
  }) => throw UnimplementedError();

  Future<GitInteractiveRebaseResult> executeInteractiveRebase(
    RepositoryId repositoryId,
    GitInteractiveRebasePreview preview, {
    GitCancellationToken? cancellationToken,
  }) => throw UnimplementedError();

  Future<GitInteractiveRebaseResult> recoverInteractiveRebase(
    RepositoryId repositoryId,
    GitInteractiveRebaseRecoveryRequest request, {
    GitCancellationToken? cancellationToken,
  }) => throw UnimplementedError();

  Future<GitHistoryRollbackPreview> previewReset(
    RepositoryId repositoryId,
    String targetRevision, {
    GitResetMode mode = GitResetMode.mixed,
  }) => throw UnimplementedError();

  Future<GitHistoryRollbackPreview> previewUndo(RepositoryId repositoryId) =>
      throw UnimplementedError();

  Future<GitHistoryRollbackPreview> previewRevert(
    RepositoryId repositoryId,
    Iterable<String> revisions,
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
