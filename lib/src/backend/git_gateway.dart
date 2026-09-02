import 'domain.dart';

/// The small API that Flutter features depend on.
///
/// Screens and controllers use this interface instead of constructing
/// processes. Tests can provide a fake implementation without touching Git.
abstract interface class GitGateway {
  Future<GitInstallation> getGitInstallation();

  Future<GitInstallation> configureGitPath(String path);

  Future<RepositoryOpened> openRepository(String path);
}
