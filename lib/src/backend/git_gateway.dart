import 'domain.dart';
import 'commit.dart';
import 'discard.dart';
import 'diff.dart';
import 'status.dart';

/// The small API that Flutter features depend on.
///
/// Screens and controllers use this interface instead of constructing
/// processes. Tests can provide a fake implementation without touching Git.
abstract interface class GitGateway {
  Future<GitInstallation> getGitInstallation();

  Future<GitInstallation> configureGitPath(String path);

  Future<RepositoryOpened> openRepository(String path);

  Future<GitStatusSnapshot> getStatus(RepositoryId repositoryId);

  Future<GitDiffSnapshot> getDiff(
    RepositoryId repositoryId,
    String path, {
    GitDiffScope scope = GitDiffScope.workingTree,
    String? originalPath,
  });

  Future<GitStatusSnapshot> stage(RepositoryId repositoryId, String path);

  Future<GitStatusSnapshot> unstage(RepositoryId repositoryId, String path);

  Future<GitCommitResult> commit(RepositoryId repositoryId, String message);

  Future<DiscardPreview> createDiscardPreview(
    RepositoryId repositoryId,
    String path,
  );

  Future<GitStatusSnapshot> discard(
    RepositoryId repositoryId,
    DiscardPreview preview,
  );
}
