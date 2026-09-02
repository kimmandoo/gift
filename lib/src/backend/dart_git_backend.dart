import 'domain.dart';
import 'branch.dart';
import 'commit.dart';
import 'discard.dart';
import 'diff.dart';
import 'git_installation_service.dart';
import 'history.dart';
import 'repository_service.dart';
import 'executor.dart';
import 'remote.dart';
import 'status.dart';

/// Application-facing entry point for backend operations.
///
/// This class coordinates services. It intentionally does not contain the
/// details of process I/O or repository parsing.
class DartGitBackend {
  DartGitBackend({
    GitInstallationService? installationService,
    AppState? state,
    ProcessGitRunner? runner,
  }) : _installationService = installationService ?? GitInstallationService(),
       _state = state ?? AppState(),
       _runner = runner ?? const ProcessGitRunner();

  static const version = '1.0.0';

  final GitInstallationService _installationService;
  final AppState _state;
  final ProcessGitRunner _runner;

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
    ).openRepository(path);
  }

  Future<GitStatusSnapshot> getStatus(RepositoryId repositoryId) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
      runner: _runner,
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

  Future<List<GitBranch>> getBranches(RepositoryId repositoryId) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
    ).getBranches(repositoryId);
  }

  Future<GitBranchActionResult> createBranch(
    RepositoryId repositoryId,
    String name,
  ) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
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
    ).switchBranch(repositoryId, name);
  }

  Future<List<GitRemote>> getRemotes(RepositoryId repositoryId) async {
    final installation = await getGitInstallation();
    return RepositoryService(
      gitPath: installation.executablePath,
      state: _state,
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
    ).push(repositoryId, remote, cancellationToken: cancellationToken);
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
