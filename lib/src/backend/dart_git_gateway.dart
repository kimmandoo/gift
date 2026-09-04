import 'dart_git_backend.dart';
import 'branch.dart';
import 'commit.dart';
import 'conflict.dart';
import 'domain.dart';
import 'discard.dart';
import 'diff.dart';
import 'comparison.dart';
import 'git_gateway.dart';
import 'history.dart';
import 'interactive_rebase.dart';
import 'executor.dart';
import 'remote.dart';
import 'remote_branch.dart';
import 'status.dart';
import 'objects.dart';
import 'shelf.dart';
import 'file_history.dart';
import 'reset.dart';
import 'push.dart';
import 'worktree.dart';
import 'ignore.dart';
import 'submodule.dart';
import 'recovery.dart';
import 'setup.dart';
import 'hosting.dart';
import 'credentials.dart';

/// Adapts the UI-facing [GitGateway] contract to the Dart backend facade.
///
/// Keeping this class thin makes it obvious where the UI/backend boundary is.
class DartGitGateway
    implements
        GitGateway,
        DiscardPreviewCancellationGateway,
        GitCredentialTestGateway {
  DartGitGateway({
    DartGitBackend? backend,
    GitCredentialResolver? credentialResolver,
  }) : backend =
           backend ?? DartGitBackend(credentialResolver: credentialResolver);

  final DartGitBackend backend;

  @override
  Future<GitInstallation> getGitInstallation() => backend.getGitInstallation();

  @override
  Future<GitInstallation> configureGitPath(String path) =>
      backend.configureGitPath(path);

  @override
  Future<RepositoryOpened> openRepository(String path) =>
      backend.openRepository(path);

  @override
  Future<GitStatusSnapshot> getStatus(RepositoryId repositoryId) =>
      backend.getStatus(repositoryId);

  @override
  Future<GitConflictSnapshot> getConflicts(RepositoryId repositoryId) =>
      backend.getConflicts(repositoryId);

  @override
  Future<GitConflictResolutionResult> acceptConflictOurs(
    RepositoryId repositoryId,
    String path, {
    required String fingerprint,
  }) =>
      backend.acceptConflictOurs(repositoryId, path, fingerprint: fingerprint);

  @override
  Future<GitConflictResolutionResult> acceptConflictTheirs(
    RepositoryId repositoryId,
    String path, {
    required String fingerprint,
  }) => backend.acceptConflictTheirs(
    repositoryId,
    path,
    fingerprint: fingerprint,
  );

  @override
  Future<GitConflictResolutionResult> editConflictResult(
    RepositoryId repositoryId,
    String path,
    String content, {
    required String fingerprint,
  }) => backend.editConflictResult(
    repositoryId,
    path,
    content,
    fingerprint: fingerprint,
  );

  @override
  Future<GitConflictResolutionResult> markConflictResolved(
    RepositoryId repositoryId,
    String path, {
    required String fingerprint,
    bool deleteResult = false,
  }) => backend.markConflictResolved(
    repositoryId,
    path,
    fingerprint: fingerprint,
    deleteResult: deleteResult,
  );

  @override
  Future<GitConflictOperationResult> continueConflict(
    RepositoryId repositoryId, {
    required String fingerprint,
    GitCancellationToken? cancellationToken,
  }) => backend.continueConflict(
    repositoryId,
    fingerprint: fingerprint,
    cancellationToken: cancellationToken,
  );

  @override
  Future<GitConflictOperationResult> abortConflict(
    RepositoryId repositoryId, {
    required String fingerprint,
    GitCancellationToken? cancellationToken,
  }) => backend.abortConflict(
    repositoryId,
    fingerprint: fingerprint,
    cancellationToken: cancellationToken,
  );

  @override
  Future<GitHistoryPage> getHistory(
    RepositoryId repositoryId, {
    int limit = 50,
    int offset = 0,
    GitHistoryQuery? query,
  }) => backend.getHistory(
    repositoryId,
    limit: limit,
    offset: offset,
    query: query,
  );

  @override
  Future<GitCommit> getCommit(RepositoryId repositoryId, String commitOid) =>
      backend.getCommit(repositoryId, commitOid);

  @override
  Future<List<GitCommitFileChange>> getCommitFiles(
    RepositoryId repositoryId,
    String commitOid,
  ) => backend.getCommitFiles(repositoryId, commitOid);

  @override
  Future<GitCommitDiff> getCommitDiff(
    RepositoryId repositoryId,
    String commitOid,
    String path, {
    String? originalPath,
  }) => backend.getCommitDiff(
    repositoryId,
    commitOid,
    path,
    originalPath: originalPath,
  );

  @override
  Future<List<GitBranch>> getBranches(RepositoryId repositoryId) =>
      backend.getBranches(repositoryId);

  @override
  Future<GitRemoteBranchSnapshot> getRemoteBranchSnapshot(
    RepositoryId repositoryId,
  ) => backend.getRemoteBranchSnapshot(repositoryId);

  @override
  Future<GitBranchActionResult> checkoutRemoteBranch(
    RepositoryId repositoryId,
    GitRemoteBranch branch, {
    String? localName,
  }) =>
      backend.checkoutRemoteBranch(repositoryId, branch, localName: localName);

  @override
  Future<GitUpdateProjectPreview> previewUpdateProject(
    RepositoryId repositoryId,
    GitUpdateProjectRequest request,
  ) => backend.previewUpdateProject(repositoryId, request);

  @override
  Future<GitUpdateProjectResult> executeUpdateProject(
    RepositoryId repositoryId,
    GitUpdateProjectRequest request, {
    GitCancellationToken? cancellationToken,
  }) => backend.executeUpdateProject(
    repositoryId,
    request,
    cancellationToken: cancellationToken,
  );

  @override
  Future<GitRemoteBranchDeletePreview> previewRemoteBranchDelete(
    RepositoryId repositoryId,
    GitRemoteBranch branch,
  ) => backend.previewRemoteBranchDelete(repositoryId, branch);

  @override
  Future<GitRemoteBranchActionResult> deleteRemoteBranch(
    RepositoryId repositoryId,
    GitRemoteBranchDeletePreview preview,
  ) => backend.deleteRemoteBranch(repositoryId, preview);

  @override
  Future<GitBranchActionResult> createBranch(
    RepositoryId repositoryId,
    String name,
  ) => backend.createBranch(repositoryId, name);

  @override
  Future<GitBranchActionResult> createBranchAtCommit(
    RepositoryId repositoryId,
    String name,
    String commitOid,
  ) => backend.createBranchAtCommit(repositoryId, name, commitOid);

  @override
  Future<GitBranchActionResult> switchBranch(
    RepositoryId repositoryId,
    String name,
  ) => backend.switchBranch(repositoryId, name);

  @override
  Future<GitBranchOperationPreview> previewBranchOperation(
    RepositoryId repositoryId,
    GitBranchOperationRequest request,
  ) => backend.previewBranchOperation(repositoryId, request);

  @override
  Future<GitBranchOperationResult> executeBranchOperation(
    RepositoryId repositoryId,
    GitBranchOperationRequest request, {
    GitCancellationToken? cancellationToken,
  }) => backend.executeBranchOperation(
    repositoryId,
    request,
    cancellationToken: cancellationToken,
  );

  @override
  Future<List<GitRemote>> getRemotes(RepositoryId repositoryId) =>
      backend.getRemotes(repositoryId);

  @override
  Future<GitRemoteOperationResult> fetch(
    RepositoryId repositoryId,
    String remote, {
    GitCancellationToken? cancellationToken,
  }) =>
      backend.fetch(repositoryId, remote, cancellationToken: cancellationToken);

  @override
  Future<GitRemoteOperationResult> pull(
    RepositoryId repositoryId,
    String remote, {
    GitCancellationToken? cancellationToken,
  }) =>
      backend.pull(repositoryId, remote, cancellationToken: cancellationToken);

  @override
  Future<GitRemoteOperationResult> push(
    RepositoryId repositoryId,
    String remote, {
    GitCancellationToken? cancellationToken,
  }) =>
      backend.push(repositoryId, remote, cancellationToken: cancellationToken);

  @override
  Future<GitPushPreview> previewPush(
    RepositoryId repositoryId,
    GitPushRequest request,
  ) => backend.previewPush(repositoryId, request);

  @override
  Future<GitPushResult> executePush(
    RepositoryId repositoryId,
    GitPushRequest request, {
    GitCancellationToken? cancellationToken,
  }) => backend.executePush(
    repositoryId,
    request,
    cancellationToken: cancellationToken,
  );

  @override
  Future<GitWorktreeSnapshot> getWorktrees(RepositoryId repositoryId) =>
      backend.getWorktrees(repositoryId);

  @override
  Future<GitWorktreeCreateResult> createWorktree(
    RepositoryId repositoryId,
    GitWorktreeCreateRequest request,
  ) => backend.createWorktree(repositoryId, request);

  @override
  Future<RepositoryOpened> openWorktree(
    RepositoryId repositoryId,
    GitWorktree worktree,
  ) => backend.openWorktree(repositoryId, worktree);

  @override
  Future<GitWorktreeActionPreview> previewWorktreeAction(
    RepositoryId repositoryId,
    GitWorktreeActionRequest request,
  ) => backend.previewWorktreeAction(repositoryId, request);

  @override
  Future<GitWorktreeActionResult> executeWorktreeAction(
    RepositoryId repositoryId,
    GitWorktreeActionRequest request, {
    GitCancellationToken? cancellationToken,
  }) => backend.executeWorktreeAction(
    repositoryId,
    request,
    cancellationToken: cancellationToken,
  );

  @override
  Future<GitIgnoreSnapshot> getIgnoreSnapshot(RepositoryId repositoryId) =>
      backend.getIgnoreSnapshot(repositoryId);

  @override
  Future<GitIgnoreActionResult> addIgnorePattern(
    RepositoryId repositoryId,
    GitIgnoreRequest request,
  ) => backend.addIgnorePattern(repositoryId, request);

  @override
  Future<GitAttributesSnapshot> getAttributes(
    RepositoryId repositoryId, {
    List<String> paths = const [],
  }) => backend.getAttributes(repositoryId, paths: paths);

  @override
  Future<GitSubmoduleSnapshot> getSubmodules(RepositoryId repositoryId) =>
      backend.getSubmodules(repositoryId);

  @override
  Future<GitSubmoduleActionResult> executeSubmoduleAction(
    RepositoryId repositoryId,
    GitSubmoduleActionRequest request, {
    GitCancellationToken? cancellationToken,
  }) => backend.executeSubmoduleAction(
    repositoryId,
    request,
    cancellationToken: cancellationToken,
  );

  @override
  Future<GitNestedRootSnapshot> getNestedRoots(RepositoryId repositoryId) =>
      backend.getNestedRoots(repositoryId);

  @override
  Future<GitReflogSnapshot> getReflog(
    RepositoryId repositoryId, {
    String ref = 'HEAD',
    int limit = 100,
  }) => backend.getReflog(repositoryId, ref: ref, limit: limit);

  @override
  Future<GitRecoveryBranchPreview> previewRecoveryBranch(
    RepositoryId repositoryId,
    GitRecoveryBranchRequest request,
  ) => backend.previewRecoveryBranch(repositoryId, request);

  @override
  Future<GitRecoveryBranchResult> createRecoveryBranch(
    RepositoryId repositoryId,
    GitRecoveryBranchPreview preview,
  ) => backend.createRecoveryBranch(repositoryId, preview);

  @override
  Future<List<GitOperationRecord>> getOperationRecords(
    RepositoryId repositoryId, {
    int limit = 100,
  }) => backend.getOperationRecords(repositoryId, limit: limit);

  @override
  Future<GitRepositorySetupResult> cloneRepository(
    GitCloneRequest request, {
    GitCancellationToken? cancellationToken,
  }) => backend.cloneRepository(request, cancellationToken: cancellationToken);

  @override
  Future<GitCredentialTestResult> testCredential(
    String remoteUrl, {
    required String accountId,
  }) => backend.testCredential(remoteUrl, accountId: accountId);

  @override
  Future<GitRepositorySetupResult> initRepository(
    GitInitRequest request, {
    GitCancellationToken? cancellationToken,
  }) => backend.initRepository(request, cancellationToken: cancellationToken);

  @override
  Future<GitUnshallowResult> unshallowRepository(
    RepositoryId repositoryId, {
    GitCancellationToken? cancellationToken,
  }) => backend.unshallowRepository(
    repositoryId,
    cancellationToken: cancellationToken,
  );

  @override
  Future<GitRootDiscoverySnapshot> discoverRepositoryRoots(String path) =>
      backend.discoverRepositoryRoots(path);

  @override
  Future<GitHostingSnapshot> getHostingRepository(
    RepositoryId repositoryId, {
    String remote = 'origin',
  }) => backend.getHostingRepository(repositoryId, remote: remote);

  @override
  Future<GitHostingLinks> getHostingLinks(
    RepositoryId repositoryId,
    String commitOid, {
    String? remote,
    String? path,
    int? lineStart,
    int? lineEnd,
  }) => backend.getHostingLinks(
    repositoryId,
    commitOid,
    remote: remote,
    path: path,
    lineStart: lineStart,
    lineEnd: lineEnd,
  );

  @override
  Future<GitHostingReviewCapability> getHostingReviewCapability(
    RepositoryId repositoryId, {
    String remote = 'origin',
  }) => backend.getHostingReviewCapability(repositoryId, remote: remote);

  @override
  Future<GitStashSnapshot> getStashes(RepositoryId repositoryId) =>
      backend.getStashes(repositoryId);

  @override
  Future<GitStashActionResult> createStash(
    RepositoryId repositoryId, {
    String message = '',
    bool includeUntracked = false,
  }) => backend.createStash(
    repositoryId,
    message: message,
    includeUntracked: includeUntracked,
  );

  @override
  Future<GitStashActionResult> applyStash(
    RepositoryId repositoryId,
    String stashOid, {
    required String fingerprint,
  }) => backend.applyStash(repositoryId, stashOid, fingerprint: fingerprint);

  @override
  Future<GitStashActionResult> popStash(
    RepositoryId repositoryId,
    String stashOid, {
    required String fingerprint,
  }) => backend.popStash(repositoryId, stashOid, fingerprint: fingerprint);

  @override
  Future<GitObjectPreview> previewStashDrop(
    RepositoryId repositoryId,
    String stashOid,
  ) => backend.previewStashDrop(repositoryId, stashOid);

  @override
  Future<GitStashActionResult> dropStash(
    RepositoryId repositoryId,
    GitObjectPreview preview,
  ) => backend.dropStash(repositoryId, preview);

  @override
  Future<GitStashActionResult> branchFromStash(
    RepositoryId repositoryId,
    String branchName,
    String stashOid, {
    required String fingerprint,
  }) => backend.branchFromStash(
    repositoryId,
    branchName,
    stashOid,
    fingerprint: fingerprint,
  );

  @override
  Future<GitTagSnapshot> getTags(RepositoryId repositoryId) =>
      backend.getTags(repositoryId);

  @override
  Future<GitTagActionResult> createTag(
    RepositoryId repositoryId,
    String name, {
    String? target,
    bool annotated = false,
    String message = '',
  }) => backend.createTag(
    repositoryId,
    name,
    target: target,
    annotated: annotated,
    message: message,
  );

  @override
  Future<GitTag> getTag(RepositoryId repositoryId, String name) =>
      backend.getTag(repositoryId, name);

  @override
  Future<GitObjectPreview> previewTagDelete(
    RepositoryId repositoryId,
    String name,
  ) => backend.previewTagDelete(repositoryId, name);

  @override
  Future<GitTagActionResult> deleteTag(
    RepositoryId repositoryId,
    GitObjectPreview preview,
  ) => backend.deleteTag(repositoryId, preview);

  @override
  Future<GitRemoteActionResult> addRemote(
    RepositoryId repositoryId,
    String name,
    String url,
  ) => backend.addRemote(repositoryId, name, url);

  @override
  Future<GitRemoteActionResult> renameRemote(
    RepositoryId repositoryId,
    String oldName,
    String newName,
  ) => backend.renameRemote(repositoryId, oldName, newName);

  @override
  Future<GitRemoteActionResult> setRemoteUrl(
    RepositoryId repositoryId,
    String name,
    String url, {
    bool push = false,
  }) => backend.setRemoteUrl(repositoryId, name, url, push: push);

  @override
  Future<GitObjectPreview> previewRemoteRemove(
    RepositoryId repositoryId,
    String name,
  ) => backend.previewRemoteRemove(repositoryId, name);

  @override
  Future<GitRemoteActionResult> removeRemote(
    RepositoryId repositoryId,
    GitObjectPreview preview,
  ) => backend.removeRemote(repositoryId, preview);

  @override
  Future<GitObjectPreview> previewRemotePrune(
    RepositoryId repositoryId,
    String name,
  ) => backend.previewRemotePrune(repositoryId, name);

  @override
  Future<GitRemoteActionResult> pruneRemote(
    RepositoryId repositoryId,
    GitObjectPreview preview,
  ) => backend.pruneRemote(repositoryId, preview);

  @override
  Future<GitRemoteOperationResult> pushTag(
    RepositoryId repositoryId,
    String remote,
    String tagName, {
    GitCancellationToken? cancellationToken,
  }) => backend.pushTag(
    repositoryId,
    remote,
    tagName,
    cancellationToken: cancellationToken,
  );

  @override
  Future<GitUpstreamSnapshot> getUpstream(RepositoryId repositoryId) =>
      backend.getUpstream(repositoryId);

  @override
  Future<GitUpstreamActionResult> setUpstream(
    RepositoryId repositoryId,
    String remote, {
    String? branch,
    String? remoteBranch,
  }) => backend.setUpstream(
    repositoryId,
    remote,
    branch: branch,
    remoteBranch: remoteBranch,
  );

  @override
  Future<GitUpstreamActionResult> unsetUpstream(
    RepositoryId repositoryId, {
    String? branch,
  }) => backend.unsetUpstream(repositoryId, branch: branch);

  @override
  Future<GitUpstreamActionResult> publishBranch(
    RepositoryId repositoryId,
    String remote, {
    String? branch,
  }) => backend.publishBranch(repositoryId, remote, branch: branch);

  @override
  Future<GitDiffSnapshot> getDiff(
    RepositoryId repositoryId,
    String path, {
    GitDiffScope scope = GitDiffScope.workingTree,
    String? originalPath,
  }) => backend.getDiff(
    repositoryId,
    path,
    scope: scope,
    originalPath: originalPath,
  );

  @override
  Future<GitComparisonSnapshot> compareRevisions(
    RepositoryId repositoryId,
    String left,
    String right, {
    String? path,
  }) => backend.compareRevisions(repositoryId, left, right, path: path);

  @override
  Future<GitComparisonSnapshot> compareSources(
    RepositoryId repositoryId,
    GitComparisonSource left,
    GitComparisonSource right, {
    String? path,
  }) => backend.compareSources(repositoryId, left, right, path: path);

  @override
  Future<GitThreeWayComparisonSnapshot> compareThreeWay(
    RepositoryId repositoryId,
    GitComparisonSource base,
    GitComparisonSource left,
    GitComparisonSource right, {
    required String path,
  }) => backend.compareThreeWay(repositoryId, base, left, right, path: path);

  @override
  Future<GitDiffSnapshot> getComparisonDiff(
    RepositoryId repositoryId,
    GitComparisonSnapshot comparison,
    String path,
  ) => backend.getComparisonDiff(repositoryId, comparison, path);

  @override
  Future<GitComparisonTransferResult> applyComparison(
    RepositoryId repositoryId,
    GitComparisonSnapshot comparison,
    String path, {
    GitComparisonTransferAction action = GitComparisonTransferAction.apply,
  }) => backend.applyComparison(repositoryId, comparison, path, action: action);

  @override
  Future<GitChangelistSnapshot> getChangelists(RepositoryId repositoryId) =>
      backend.getChangelists(repositoryId);

  @override
  Future<GitChangelistSnapshot> createChangelist(
    RepositoryId repositoryId,
    String name,
  ) => backend.createChangelist(repositoryId, name);

  @override
  Future<GitChangelistSnapshot> renameChangelist(
    RepositoryId repositoryId,
    String changelistId,
    String name,
  ) => backend.renameChangelist(repositoryId, changelistId, name);

  @override
  Future<GitChangelistSnapshot> activateChangelist(
    RepositoryId repositoryId,
    String changelistId,
  ) => backend.activateChangelist(repositoryId, changelistId);

  @override
  Future<GitChangelistSnapshot> deleteChangelist(
    RepositoryId repositoryId,
    String changelistId,
  ) => backend.deleteChangelist(repositoryId, changelistId);

  @override
  Future<GitChangelistSnapshot> moveChangelistPaths(
    RepositoryId repositoryId,
    Iterable<String> paths,
    String changelistId,
  ) => backend.moveChangelistPaths(repositoryId, paths, changelistId);

  @override
  Future<GitShelfSnapshot> getShelves(RepositoryId repositoryId) =>
      backend.getShelves(repositoryId);

  @override
  Future<GitShelfActionResult> shelve(
    RepositoryId repositoryId, {
    String name = '',
    Iterable<String> paths = const <String>[],
  }) => backend.shelve(repositoryId, name: name, paths: paths);

  @override
  Future<GitShelfActionResult> unshelve(
    RepositoryId repositoryId,
    String shelfId,
  ) => backend.unshelve(repositoryId, shelfId);

  @override
  Future<GitShelfActionResult> restoreShelf(
    RepositoryId repositoryId,
    String shelfId,
  ) => backend.restoreShelf(repositoryId, shelfId);

  @override
  Future<GitShelfActionResult> deleteShelf(
    RepositoryId repositoryId,
    String shelfId,
  ) => backend.deleteShelf(repositoryId, shelfId);

  @override
  Future<GitShelfActionResult> importShelf(
    RepositoryId repositoryId,
    String name,
    List<int> patchBytes, {
    String? baseRevision,
  }) => backend.importShelf(
    repositoryId,
    name,
    patchBytes,
    baseRevision: baseRevision,
  );

  @override
  Future<List<int>> exportShelf(RepositoryId repositoryId, String shelfId) =>
      backend.exportShelf(repositoryId, shelfId);

  @override
  Future<GitFileHistorySnapshot> getFileHistory(
    RepositoryId repositoryId,
    GitFileHistoryQuery query,
  ) => backend.getFileHistory(repositoryId, query);

  @override
  Future<GitBlameSnapshot> getBlame(
    RepositoryId repositoryId,
    String path, {
    GitBlameOptions options = const GitBlameOptions(),
  }) => backend.getBlame(repositoryId, path, options: options);

  @override
  Future<GitRevisionGetResult> getFileFromRevision(
    RepositoryId repositoryId,
    GitFileHistorySnapshot history,
    String revision,
  ) => backend.getFileFromRevision(repositoryId, history, revision);

  @override
  Future<GitStatusSnapshot> stage(RepositoryId repositoryId, String path) =>
      backend.stage(repositoryId, path);

  @override
  Future<GitStatusSnapshot> unstage(RepositoryId repositoryId, String path) =>
      backend.unstage(repositoryId, path);

  @override
  Future<GitStatusSnapshot> stagePatch(
    RepositoryId repositoryId,
    GitPatchSelection selection,
  ) => backend.stagePatch(repositoryId, selection);

  @override
  Future<GitStatusSnapshot> unstagePatch(
    RepositoryId repositoryId,
    GitPatchSelection selection,
  ) => backend.unstagePatch(repositoryId, selection);

  @override
  Future<GitCommitPreflight> preflightCommit(
    RepositoryId repositoryId, {
    GitCommitOptions options = const GitCommitOptions(),
  }) => backend.preflightCommit(repositoryId, options: options);

  @override
  Future<GitCommitTemplate> loadCommitTemplate(RepositoryId repositoryId) =>
      backend.loadCommitTemplate(repositoryId);

  @override
  Future<GitCommitResult> commit(
    RepositoryId repositoryId,
    String message, {
    GitCommitOptions options = const GitCommitOptions(),
  }) => backend.commit(repositoryId, message, options: options);

  @override
  Future<GitHistoryRollbackPreview> previewHistoryRollback(
    RepositoryId repositoryId,
    GitHistoryRollbackRequest request,
  ) => backend.previewHistoryRollback(repositoryId, request);

  @override
  Future<GitHistoryRollbackResult> executeHistoryRollback(
    RepositoryId repositoryId,
    GitHistoryRollbackPreview preview, {
    GitCancellationToken? cancellationToken,
  }) => backend.executeHistoryRollback(
    repositoryId,
    preview,
    cancellationToken: cancellationToken,
  );

  @override
  Future<GitInteractiveRebasePreview> previewInteractiveRebase(
    RepositoryId repositoryId,
    GitInteractiveRebasePlan plan,
  ) => backend.previewInteractiveRebase(repositoryId, plan);

  @override
  Future<GitInteractiveRebaseResult> executeInteractiveRebase(
    RepositoryId repositoryId,
    GitInteractiveRebasePreview preview, {
    GitCancellationToken? cancellationToken,
  }) => backend.executeInteractiveRebase(
    repositoryId,
    preview,
    cancellationToken: cancellationToken,
  );

  @override
  Future<GitInteractiveRebaseResult> recoverInteractiveRebase(
    RepositoryId repositoryId,
    GitInteractiveRebaseRecoveryRequest request, {
    GitCancellationToken? cancellationToken,
  }) => backend.recoverInteractiveRebase(
    repositoryId,
    request,
    cancellationToken: cancellationToken,
  );

  @override
  Future<GitHistoryRollbackPreview> previewReset(
    RepositoryId repositoryId,
    String targetRevision, {
    GitResetMode mode = GitResetMode.mixed,
  }) => backend.previewReset(repositoryId, targetRevision, mode: mode);

  @override
  Future<GitHistoryRollbackPreview> previewUndo(RepositoryId repositoryId) =>
      backend.previewUndo(repositoryId);

  @override
  Future<GitHistoryRollbackPreview> previewRevert(
    RepositoryId repositoryId,
    Iterable<String> revisions,
  ) => backend.previewRevert(repositoryId, revisions);

  @override
  Future<DiscardPreview> createDiscardPreview(
    RepositoryId repositoryId,
    String path,
  ) => backend.createDiscardPreview(repositoryId, path);

  @override
  Future<void> cancelDiscardPreview(DiscardPreview preview) =>
      backend.cancelDiscardPreview(preview);

  @override
  Future<GitStatusSnapshot> discard(
    RepositoryId repositoryId,
    DiscardPreview preview,
  ) => backend.discard(repositoryId, preview);
}
