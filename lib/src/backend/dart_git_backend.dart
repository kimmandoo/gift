import 'domain.dart';
import 'git_installation_service.dart';
import 'repository_service.dart';

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

  Future<RepositoryHandle> lookup(RepositoryId repositoryId) =>
      _state.lookup(repositoryId);
}
