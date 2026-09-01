import 'package:branchline/src/rust/generated/api/repository_api.dart'
    as repository_api;
import 'package:branchline/src/rust/generated/api/settings_api.dart'
    as settings_api;
import 'package:branchline/src/rust/generated/domain.dart';
import 'package:branchline/src/rust/generated/domain/repository.dart';
import 'package:branchline/src/rust/git_gateway.dart';

class FrbGitGateway implements GitGateway {
  const FrbGitGateway();

  @override
  Future<GitInstallation> getGitInstallation() =>
      settings_api.getGitInstallation();

  @override
  Future<GitInstallation> configureGitPath(String path) =>
      settings_api.configureGitPath(path: path);

  @override
  Future<RepositoryOpened> openRepository(String path) =>
      repository_api.openRepository(path: path);
}
