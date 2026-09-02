import 'dart_git_backend.dart';
import 'commit.dart';
import 'domain.dart';
import 'discard.dart';
import 'diff.dart';
import 'git_gateway.dart';
import 'status.dart';

/// Adapts the UI-facing [GitGateway] contract to the Dart backend facade.
///
/// Keeping this class thin makes it obvious where the UI/backend boundary is.
class DartGitGateway implements GitGateway {
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
  Future<GitStatusSnapshot> discard(
    RepositoryId repositoryId,
    DiscardPreview preview,
  ) => backend.discard(repositoryId, preview);
}
