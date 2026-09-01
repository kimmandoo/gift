import 'package:branchline/src/rust/generated/domain.dart';
import 'package:branchline/src/rust/generated/domain/repository.dart';

abstract interface class GitGateway {
  Future<GitInstallation> getGitInstallation();

  Future<GitInstallation> configureGitPath(String path);

  Future<RepositoryOpened> openRepository(String path);
}
