import 'dart_git_backend.dart';
import 'branch.dart';
import 'commit.dart';
import 'conflict.dart';
import 'domain.dart';
import 'discard.dart';
import 'diff.dart';
import 'git_gateway.dart';
import 'history.dart';
import 'executor.dart';
import 'remote.dart';
import 'status.dart';

/// Adapts the UI-facing [GitGateway] contract to the Dart backend facade.
///
/// Keeping this class thin makes it obvious where the UI/backend boundary is.
class DartGitGateway implements GitGateway, DiscardPreviewCancellationGateway {
  DartGitGateway({DartGitBackend? backend})
    : backend = backend ?? DartGitBackend();

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
  Future<GitBranchActionResult> createBranch(
    RepositoryId repositoryId,
    String name,
  ) => backend.createBranch(repositoryId, name);

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
