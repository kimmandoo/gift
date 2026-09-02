import 'domain.dart';
import 'branch.dart';
import 'commit.dart';
import 'discard.dart';
import 'diff.dart';
import 'status.dart';
import 'history.dart';
import 'executor.dart';
import 'remote.dart';

/// The small API that Flutter features depend on.
///
/// Screens and controllers use this interface instead of constructing
/// processes. Tests can provide a fake implementation without touching Git.
abstract interface class GitGateway {
  Future<GitInstallation> getGitInstallation();

  Future<GitInstallation> configureGitPath(String path);

  Future<RepositoryOpened> openRepository(String path);

  Future<GitStatusSnapshot> getStatus(RepositoryId repositoryId);

  Future<GitHistoryPage> getHistory(
    RepositoryId repositoryId, {
    int limit = 50,
    int offset = 0,
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
