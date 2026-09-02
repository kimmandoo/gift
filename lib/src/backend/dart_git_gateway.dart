import 'dart_git_backend.dart';
import 'domain.dart';
import 'git_gateway.dart';

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
}
