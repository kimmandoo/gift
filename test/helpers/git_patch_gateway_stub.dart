import 'package:gift/src/backend/commit.dart';
import 'package:gift/src/backend/diff.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/status.dart';

/// Existing feature fakes do not need partial-patch behavior unless a test is
/// specifically about it. This keeps those focused fakes small as the
/// GitGateway contract grows.
mixin GitPatchGatewayStub {
  Future<GitCommitPreflight> preflightCommit(
    RepositoryId repositoryId, {
    GitCommitOptions options = const GitCommitOptions(),
  }) => throw UnimplementedError();

  Future<GitCommitTemplate> loadCommitTemplate(RepositoryId repositoryId) =>
      throw UnimplementedError();

  Future<GitStatusSnapshot> stagePatch(
    RepositoryId repositoryId,
    GitPatchSelection selection,
  ) => throw UnimplementedError();

  Future<GitStatusSnapshot> unstagePatch(
    RepositoryId repositoryId,
    GitPatchSelection selection,
  ) => throw UnimplementedError();
}
