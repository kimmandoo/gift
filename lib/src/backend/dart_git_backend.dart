import 'domain.dart';
import 'commit.dart';
import 'discard.dart';
import 'diff.dart';
import 'git_installation_service.dart';
import 'history.dart';
import 'repository_service.dart';
import 'status.dart';

/// Application-facing entry point for backend operations.
///
/// This class coordinates services. It intentionally does not contain the
/// details of process I/O or repository parsing.
class DartGitBackend {
  DartGitBackend({GitInstallationService? installationService, AppState? state})
    : _installationService = installationService ?? GitInstallationService(),
      _state = state ?? AppState();

  static const version = '1.0.0';

  final GitInstallationService _installationService;
  final AppState _state;

  Health health() => const Health(product: 'Branchline', coreVersion: version);

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
    ).openRepository(path);
  }

  Future<GitStatusSnapshot> getStatus(RepositoryId repositoryId) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
    ).getStatus(repositoryId);
  }

  Future<GitHistoryPage> getHistory(
    RepositoryId repositoryId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
    ).getHistory(repositoryId, limit: limit, offset: offset);
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

  Future<GitCommitResult> commit(
    RepositoryId repositoryId,
    String message,
  ) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
    ).commit(repositoryId, message);
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

  Future<RepositoryHandle> lookup(RepositoryId repositoryId) =>
      _state.lookup(repositoryId);
}
