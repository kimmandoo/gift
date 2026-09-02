import 'package:gift/src/backend/commit.dart';
import 'package:gift/src/backend/branch.dart';
import 'package:gift/src/backend/diff.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/history.dart';
import 'package:gift/src/backend/executor.dart';
import 'package:gift/src/backend/status.dart';

/// Existing feature fakes do not need partial-patch behavior unless a test is
/// specifically about it. This keeps those focused fakes small as the
/// GitGateway contract grows.
mixin GitPatchGatewayStub {
  Future<GitCommit> getCommit(RepositoryId repositoryId, String commitOid) =>
      throw UnimplementedError();

  Future<List<GitCommitFileChange>> getCommitFiles(
    RepositoryId repositoryId,
    String commitOid,
  ) => throw UnimplementedError();

  Future<GitCommitDiff> getCommitDiff(
    RepositoryId repositoryId,
    String commitOid,
    String path, {
    String? originalPath,
  }) => throw UnimplementedError();

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

  Future<GitBranchOperationPreview> previewBranchOperation(
    RepositoryId repositoryId,
    GitBranchOperationRequest request,
  ) => throw UnimplementedError();

  Future<GitBranchOperationResult> executeBranchOperation(
    RepositoryId repositoryId,
    GitBranchOperationRequest request, {
    GitCancellationToken? cancellationToken,
  }) => throw UnimplementedError();
}
