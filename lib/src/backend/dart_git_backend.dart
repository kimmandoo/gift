import 'domain.dart';
import 'branch.dart';
import 'commit.dart';
import 'conflict.dart';
import 'discard.dart';
import 'diff.dart';
import 'comparison.dart';
import 'git_installation_service.dart';
import 'history.dart';
import 'interactive_rebase.dart';
import 'repository_service.dart';
import 'executor.dart';
import 'remote.dart';
import 'remote_branch.dart';
import 'status.dart';
import 'objects.dart';
import 'shelf.dart';
import 'file_history.dart';
import 'reset.dart';

/// Application-facing entry point for backend operations.
///
/// This class coordinates services. It intentionally does not contain the
/// details of process I/O or repository parsing.
class DartGitBackend {
  DartGitBackend({
    GitInstallationService? installationService,
    AppState? state,
    ProcessGitRunner? runner,
    GitShelfStore? shelfStore,
  }) : _installationService = installationService ?? GitInstallationService(),
       _state = state ?? AppState(),
       _runner = runner ?? const ProcessGitRunner(),
       _shelfStore = shelfStore ?? const FileGitShelfStore();

  static const version = '1.0.0';

  final GitInstallationService _installationService;
  final AppState _state;
  final ProcessGitRunner _runner;
  final GitShelfStore _shelfStore;

  Health health() => const Health(product: 'gift', coreVersion: version);

  Future<GitInstallation> getGitInstallation() =>
      _installationService.getOrDiscover();

  Future<GitInstallation> configureGitPath(String path) =>
      _installationService.configureGitPath(path);

  Future<RepositoryOpened> openRepository(String path) async {
    // A repository operation always uses the validated Git installation.
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
      shelfStore: _shelfStore,
    ).openRepository(path);
  }

  Future<GitStatusSnapshot> getStatus(RepositoryId repositoryId) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
      shelfStore: _shelfStore,
    ).getStatus(repositoryId);
  }

  Future<GitConflictSnapshot> getConflicts(RepositoryId repositoryId) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).getConflicts(repositoryId);
  }

  Future<GitConflictResolutionResult> acceptConflictOurs(
    RepositoryId repositoryId,
    String path, {
    required String fingerprint,
  }) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).acceptConflictOurs(repositoryId, path, fingerprint: fingerprint);
  }

  Future<GitConflictResolutionResult> acceptConflictTheirs(
    RepositoryId repositoryId,
    String path, {
    required String fingerprint,
  }) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).acceptConflictTheirs(repositoryId, path, fingerprint: fingerprint);
  }

  Future<GitConflictResolutionResult> editConflictResult(
    RepositoryId repositoryId,
    String path,
    String content, {
    required String fingerprint,
  }) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).editConflictResult(repositoryId, path, content, fingerprint: fingerprint);
  }

  Future<GitConflictResolutionResult> markConflictResolved(
    RepositoryId repositoryId,
    String path, {
    required String fingerprint,
    bool deleteResult = false,
  }) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).markConflictResolved(
      repositoryId,
      path,
      fingerprint: fingerprint,
      deleteResult: deleteResult,
    );
  }

  Future<GitConflictOperationResult> continueConflict(
    RepositoryId repositoryId, {
    required String fingerprint,
    GitCancellationToken? cancellationToken,
  }) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).continueConflict(
      repositoryId,
      fingerprint: fingerprint,
      cancellationToken: cancellationToken,
    );
  }

  Future<GitConflictOperationResult> abortConflict(
    RepositoryId repositoryId, {
    required String fingerprint,
    GitCancellationToken? cancellationToken,
  }) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).abortConflict(
      repositoryId,
      fingerprint: fingerprint,
      cancellationToken: cancellationToken,
    );
  }

  Future<GitHistoryPage> getHistory(
    RepositoryId repositoryId, {
    int limit = 50,
    int offset = 0,
    GitHistoryQuery? query,
  }) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).getHistory(repositoryId, limit: limit, offset: offset, query: query);
  }

  Future<GitCommit> getCommit(
    RepositoryId repositoryId,
    String commitOid,
  ) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).getCommit(repositoryId, commitOid);
  }

  Future<List<GitCommitFileChange>> getCommitFiles(
    RepositoryId repositoryId,
    String commitOid,
  ) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).getCommitFiles(repositoryId, commitOid);
  }

  Future<GitCommitDiff> getCommitDiff(
    RepositoryId repositoryId,
    String commitOid,
    String path, {
    String? originalPath,
  }) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).getCommitDiff(repositoryId, commitOid, path, originalPath: originalPath);
  }

  Future<List<GitBranch>> getBranches(RepositoryId repositoryId) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).getBranches(repositoryId);
  }

  Future<GitRemoteBranchSnapshot> getRemoteBranchSnapshot(
    RepositoryId repositoryId,
  ) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).getRemoteBranchSnapshot(repositoryId);
  }

  Future<GitBranchActionResult> checkoutRemoteBranch(
    RepositoryId repositoryId,
    GitRemoteBranch branch, {
    String? localName,
  }) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).checkoutRemoteBranch(repositoryId, branch, localName: localName);
  }

  Future<GitRemoteBranchDeletePreview> previewRemoteBranchDelete(
    RepositoryId repositoryId,
    GitRemoteBranch branch,
  ) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).previewRemoteBranchDelete(repositoryId, branch);
  }

  Future<GitRemoteBranchActionResult> deleteRemoteBranch(
    RepositoryId repositoryId,
    GitRemoteBranchDeletePreview preview,
  ) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).deleteRemoteBranch(repositoryId, preview);
  }

  Future<GitUpdateProjectPreview> previewUpdateProject(
    RepositoryId repositoryId,
    GitUpdateProjectRequest request,
  ) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).previewUpdateProject(repositoryId, request);
  }

  Future<GitUpdateProjectResult> executeUpdateProject(
    RepositoryId repositoryId,
    GitUpdateProjectRequest request, {
    GitCancellationToken? cancellationToken,
  }) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).executeUpdateProject(
      repositoryId,
      request,
      cancellationToken: cancellationToken,
    );
  }

  Future<GitBranchActionResult> createBranch(
    RepositoryId repositoryId,
    String name,
  ) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).createBranch(repositoryId, name);
  }

  Future<GitBranchActionResult> switchBranch(
    RepositoryId repositoryId,
    String name,
  ) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).switchBranch(repositoryId, name);
  }

  Future<GitBranchOperationPreview> previewBranchOperation(
    RepositoryId repositoryId,
    GitBranchOperationRequest request,
  ) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).previewBranchOperation(repositoryId, request);
  }

  Future<GitBranchOperationResult> executeBranchOperation(
    RepositoryId repositoryId,
    GitBranchOperationRequest request, {
    GitCancellationToken? cancellationToken,
  }) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).executeBranchOperation(
      repositoryId,
      request,
      cancellationToken: cancellationToken,
    );
  }

  Future<List<GitRemote>> getRemotes(RepositoryId repositoryId) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).getRemotes(repositoryId);
  }

  Future<GitRemoteOperationResult> fetch(
    RepositoryId repositoryId,
    String remote, {
    GitCancellationToken? cancellationToken,
  }) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).fetch(repositoryId, remote, cancellationToken: cancellationToken);
  }

  Future<GitRemoteOperationResult> pull(
    RepositoryId repositoryId,
    String remote, {
    GitCancellationToken? cancellationToken,
  }) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).pull(repositoryId, remote, cancellationToken: cancellationToken);
  }

  Future<GitRemoteOperationResult> push(
    RepositoryId repositoryId,
    String remote, {
    GitCancellationToken? cancellationToken,
  }) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).push(repositoryId, remote, cancellationToken: cancellationToken);
  }

  Future<GitStashSnapshot> getStashes(RepositoryId repositoryId) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).getStashes(repositoryId);
  }

  Future<GitStashActionResult> createStash(
    RepositoryId repositoryId, {
    String message = '',
    bool includeUntracked = false,
  }) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).createStash(
      repositoryId,
      message: message,
      includeUntracked: includeUntracked,
    );
  }

  Future<GitStashActionResult> applyStash(
    RepositoryId repositoryId,
    String stashOid, {
    required String fingerprint,
  }) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).applyStash(repositoryId, stashOid, fingerprint: fingerprint);
  }

  Future<GitStashActionResult> popStash(
    RepositoryId repositoryId,
    String stashOid, {
    required String fingerprint,
  }) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).popStash(repositoryId, stashOid, fingerprint: fingerprint);
  }

  Future<GitObjectPreview> previewStashDrop(
    RepositoryId repositoryId,
    String stashOid,
  ) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).previewStashDrop(repositoryId, stashOid);
  }

  Future<GitStashActionResult> dropStash(
    RepositoryId repositoryId,
    GitObjectPreview preview,
  ) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).dropStash(repositoryId, preview);
  }

  Future<GitStashActionResult> branchFromStash(
    RepositoryId repositoryId,
    String branchName,
    String stashOid, {
    required String fingerprint,
  }) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).branchFromStash(
      repositoryId,
      branchName,
      stashOid,
      fingerprint: fingerprint,
    );
  }

  Future<GitTagSnapshot> getTags(RepositoryId repositoryId) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).getTags(repositoryId);
  }

  Future<GitTagActionResult> createTag(
    RepositoryId repositoryId,
    String name, {
    String? target,
    bool annotated = false,
    String message = '',
  }) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).createTag(
      repositoryId,
      name,
      target: target,
      annotated: annotated,
      message: message,
    );
  }

  Future<GitTag> getTag(RepositoryId repositoryId, String name) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).getTag(repositoryId, name);
  }

  Future<GitObjectPreview> previewTagDelete(
    RepositoryId repositoryId,
    String name,
  ) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).previewTagDelete(repositoryId, name);
  }

  Future<GitTagActionResult> deleteTag(
    RepositoryId repositoryId,
    GitObjectPreview preview,
  ) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).deleteTag(repositoryId, preview);
  }

  Future<GitRemoteActionResult> addRemote(
    RepositoryId repositoryId,
    String name,
    String url,
  ) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).addRemote(repositoryId, name, url);
  }

  Future<GitRemoteActionResult> renameRemote(
    RepositoryId repositoryId,
    String oldName,
    String newName,
  ) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).renameRemote(repositoryId, oldName, newName);
  }

  Future<GitRemoteActionResult> setRemoteUrl(
    RepositoryId repositoryId,
    String name,
    String url, {
    bool push = false,
  }) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).setRemoteUrl(repositoryId, name, url, push: push);
  }

  Future<GitObjectPreview> previewRemoteRemove(
    RepositoryId repositoryId,
    String name,
  ) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).previewRemoteRemove(repositoryId, name);
  }

  Future<GitRemoteActionResult> removeRemote(
    RepositoryId repositoryId,
    GitObjectPreview preview,
  ) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).removeRemote(repositoryId, preview);
  }

  Future<GitObjectPreview> previewRemotePrune(
    RepositoryId repositoryId,
    String name,
  ) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).previewRemotePrune(repositoryId, name);
  }

  Future<GitRemoteActionResult> pruneRemote(
    RepositoryId repositoryId,
    GitObjectPreview preview,
  ) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).pruneRemote(repositoryId, preview);
  }

  Future<GitRemoteOperationResult> pushTag(
    RepositoryId repositoryId,
    String remote,
    String tagName, {
    GitCancellationToken? cancellationToken,
  }) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).pushTag(
      repositoryId,
      remote,
      tagName,
      cancellationToken: cancellationToken,
    );
  }

  Future<GitUpstreamSnapshot> getUpstream(RepositoryId repositoryId) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).getUpstream(repositoryId);
  }

  Future<GitUpstreamActionResult> setUpstream(
    RepositoryId repositoryId,
    String remote, {
    String? branch,
    String? remoteBranch,
  }) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).setUpstream(
      repositoryId,
      remote,
      branch: branch,
      remoteBranch: remoteBranch,
    );
  }

  Future<GitUpstreamActionResult> unsetUpstream(
    RepositoryId repositoryId, {
    String? branch,
  }) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).unsetUpstream(repositoryId, branch: branch);
  }

  Future<GitUpstreamActionResult> publishBranch(
    RepositoryId repositoryId,
    String remote, {
    String? branch,
  }) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).publishBranch(repositoryId, remote, branch: branch);
  }

  Future<GitDiffSnapshot> getDiff(
    RepositoryId repositoryId,
    String path, {
    GitDiffScope scope = GitDiffScope.workingTree,
    String? originalPath,
  }) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
    ).getDiff(repositoryId, path, scope: scope, originalPath: originalPath);
  }

  Future<GitComparisonSnapshot> compareRevisions(
    RepositoryId repositoryId,
    String left,
    String right, {
    String? path,
  }) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).compareRevisions(repositoryId, left, right, path: path);
  }

  Future<GitComparisonSnapshot> compareSources(
    RepositoryId repositoryId,
    GitComparisonSource left,
    GitComparisonSource right, {
    String? path,
  }) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).compareSources(repositoryId, left, right, path: path);
  }

  Future<GitThreeWayComparisonSnapshot> compareThreeWay(
    RepositoryId repositoryId,
    GitComparisonSource base,
    GitComparisonSource left,
    GitComparisonSource right, {
    required String path,
  }) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).compareThreeWay(repositoryId, base, left, right, path: path);
  }

  Future<GitDiffSnapshot> getComparisonDiff(
    RepositoryId repositoryId,
    GitComparisonSnapshot comparison,
    String path,
  ) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).getComparisonDiff(repositoryId, comparison, path);
  }

  Future<GitComparisonTransferResult> applyComparison(
    RepositoryId repositoryId,
    GitComparisonSnapshot comparison,
    String path, {
    GitComparisonTransferAction action = GitComparisonTransferAction.apply,
  }) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).applyComparison(repositoryId, comparison, path, action: action);
  }

  Future<GitChangelistSnapshot> getChangelists(
    RepositoryId repositoryId,
  ) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
      shelfStore: _shelfStore,
    ).getChangelists(repositoryId);
  }

  Future<GitChangelistSnapshot> createChangelist(
    RepositoryId repositoryId,
    String name,
  ) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
      shelfStore: _shelfStore,
    ).createChangelist(repositoryId, name);
  }

  Future<GitChangelistSnapshot> renameChangelist(
    RepositoryId repositoryId,
    String changelistId,
    String name,
  ) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
      shelfStore: _shelfStore,
    ).renameChangelist(repositoryId, changelistId, name);
  }

  Future<GitChangelistSnapshot> activateChangelist(
    RepositoryId repositoryId,
    String changelistId,
  ) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
      shelfStore: _shelfStore,
    ).activateChangelist(repositoryId, changelistId);
  }

  Future<GitChangelistSnapshot> deleteChangelist(
    RepositoryId repositoryId,
    String changelistId,
  ) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
      shelfStore: _shelfStore,
    ).deleteChangelist(repositoryId, changelistId);
  }

  Future<GitChangelistSnapshot> moveChangelistPaths(
    RepositoryId repositoryId,
    Iterable<String> paths,
    String changelistId,
  ) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
      shelfStore: _shelfStore,
    ).moveChangelistPaths(repositoryId, paths, changelistId);
  }

  Future<GitShelfSnapshot> getShelves(RepositoryId repositoryId) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
      shelfStore: _shelfStore,
    ).getShelves(repositoryId);
  }

  Future<GitShelfActionResult> shelve(
    RepositoryId repositoryId, {
    String name = '',
    Iterable<String> paths = const <String>[],
  }) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
      shelfStore: _shelfStore,
    ).shelve(repositoryId, name: name, paths: paths);
  }

  Future<GitShelfActionResult> unshelve(
    RepositoryId repositoryId,
    String shelfId,
  ) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
      shelfStore: _shelfStore,
    ).unshelve(repositoryId, shelfId);
  }

  Future<GitShelfActionResult> restoreShelf(
    RepositoryId repositoryId,
    String shelfId,
  ) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
      shelfStore: _shelfStore,
    ).restoreShelf(repositoryId, shelfId);
  }

  Future<GitShelfActionResult> deleteShelf(
    RepositoryId repositoryId,
    String shelfId,
  ) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
      shelfStore: _shelfStore,
    ).deleteShelf(repositoryId, shelfId);
  }

  Future<GitShelfActionResult> importShelf(
    RepositoryId repositoryId,
    String name,
    List<int> patchBytes, {
    String? baseRevision,
  }) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
      shelfStore: _shelfStore,
    ).importShelf(repositoryId, name, patchBytes, baseRevision: baseRevision);
  }

  Future<List<int>> exportShelf(
    RepositoryId repositoryId,
    String shelfId,
  ) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
      shelfStore: _shelfStore,
    ).exportShelf(repositoryId, shelfId);
  }

  Future<GitFileHistorySnapshot> getFileHistory(
    RepositoryId repositoryId,
    GitFileHistoryQuery query,
  ) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
      shelfStore: _shelfStore,
    ).getFileHistory(repositoryId, query);
  }

  Future<GitBlameSnapshot> getBlame(
    RepositoryId repositoryId,
    String path, {
    GitBlameOptions options = const GitBlameOptions(),
  }) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
      shelfStore: _shelfStore,
    ).getBlame(repositoryId, path, options: options);
  }

  Future<GitRevisionGetResult> getFileFromRevision(
    RepositoryId repositoryId,
    GitFileHistorySnapshot history,
    String revision,
  ) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
      shelfStore: _shelfStore,
    ).getFileFromRevision(repositoryId, history, revision);
  }

  Future<GitStatusSnapshot> stage(
    RepositoryId repositoryId,
    String path,
  ) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
    ).stage(repositoryId, path);
  }

  Future<GitStatusSnapshot> unstage(
    RepositoryId repositoryId,
    String path,
  ) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
    ).unstage(repositoryId, path);
  }

  Future<GitStatusSnapshot> stagePatch(
    RepositoryId repositoryId,
    GitPatchSelection selection,
  ) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
    ).stagePatch(repositoryId, selection);
  }

  Future<GitStatusSnapshot> unstagePatch(
    RepositoryId repositoryId,
    GitPatchSelection selection,
  ) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
    ).unstagePatch(repositoryId, selection);
  }

  Future<GitCommitPreflight> preflightCommit(
    RepositoryId repositoryId, {
    GitCommitOptions options = const GitCommitOptions(),
  }) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).preflightCommit(repositoryId, options: options);
  }

  Future<GitCommitTemplate> loadCommitTemplate(
    RepositoryId repositoryId,
  ) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).loadCommitTemplate(repositoryId);
  }

  Future<GitCommitResult> commit(
    RepositoryId repositoryId,
    String message, {
    GitCommitOptions options = const GitCommitOptions(),
  }) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).commit(repositoryId, message, options: options);
  }

  Future<GitHistoryRollbackPreview> previewHistoryRollback(
    RepositoryId repositoryId,
    GitHistoryRollbackRequest request,
  ) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).previewHistoryRollback(repositoryId, request);
  }

  Future<GitHistoryRollbackResult> executeHistoryRollback(
    RepositoryId repositoryId,
    GitHistoryRollbackPreview preview, {
    GitCancellationToken? cancellationToken,
  }) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).executeHistoryRollback(
      repositoryId,
      preview,
      cancellationToken: cancellationToken,
    );
  }

  Future<GitInteractiveRebasePreview> previewInteractiveRebase(
    RepositoryId repositoryId,
    GitInteractiveRebasePlan plan,
  ) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).previewInteractiveRebase(repositoryId, plan);
  }

  Future<GitInteractiveRebaseResult> executeInteractiveRebase(
    RepositoryId repositoryId,
    GitInteractiveRebasePreview preview, {
    GitCancellationToken? cancellationToken,
  }) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).executeInteractiveRebase(
      repositoryId,
      preview,
      cancellationToken: cancellationToken,
    );
  }

  Future<GitInteractiveRebaseResult> recoverInteractiveRebase(
    RepositoryId repositoryId,
    GitInteractiveRebaseRecoveryRequest request, {
    GitCancellationToken? cancellationToken,
  }) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).recoverInteractiveRebase(
      repositoryId,
      request,
      cancellationToken: cancellationToken,
    );
  }

  Future<GitHistoryRollbackPreview> previewReset(
    RepositoryId repositoryId,
    String targetRevision, {
    GitResetMode mode = GitResetMode.mixed,
  }) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).previewReset(repositoryId, targetRevision, mode: mode);
  }

  Future<GitHistoryRollbackPreview> previewUndo(
    RepositoryId repositoryId,
  ) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).previewUndo(repositoryId);
  }

  Future<GitHistoryRollbackPreview> previewRevert(
    RepositoryId repositoryId,
    Iterable<String> revisions,
  ) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
    ).previewRevert(repositoryId, revisions);
  }

  Future<DiscardPreview> createDiscardPreview(
    RepositoryId repositoryId,
    String path,
  ) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
    ).createDiscardPreview(repositoryId, path);
  }

  Future<GitStatusSnapshot> discard(
    RepositoryId repositoryId,
    DiscardPreview preview,
  ) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
    ).discard(repositoryId, preview);
  }

  Future<void> cancelDiscardPreview(DiscardPreview preview) async {
    final installation = await getGitInstallation();
    RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
    ).cancelDiscardPreview(preview);
  }

  Future<RepositoryHandle> lookup(RepositoryId repositoryId) =>
      _state.lookup(repositoryId);
}
