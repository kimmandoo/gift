import 'dart_git_backend.dart';
import 'branch.dart';
import 'commit.dart';
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
  Future<GitHistoryPage> getHistory(
    RepositoryId repositoryId, {
    int limit = 50,
    int offset = 0,
  }) => backend.getHistory(repositoryId, limit: limit, offset: offset);

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
  Future<GitCommitResult> commit(RepositoryId repositoryId, String message) =>
      backend.commit(repositoryId, message);

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
