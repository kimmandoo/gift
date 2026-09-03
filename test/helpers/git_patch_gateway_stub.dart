import 'package:gift/src/backend/commit.dart';
import 'package:gift/src/backend/conflict.dart';
import 'package:gift/src/backend/branch.dart';
import 'package:gift/src/backend/diff.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/discard.dart';
import 'package:gift/src/backend/history.dart';
import 'package:gift/src/backend/executor.dart';
import 'package:gift/src/backend/remote.dart';
import 'package:gift/src/backend/status.dart';

/// Existing feature fakes do not need partial-patch behavior unless a test is
/// specifically about it. This keeps those focused fakes small as the
/// GitGateway contract grows.
mixin GitPatchGatewayStub {
  Future<GitInstallation> getGitInstallation() => throw UnimplementedError();

  Future<GitInstallation> configureGitPath(String path) =>
      throw UnimplementedError();

  Future<RepositoryOpened> openRepository(String path) =>
      throw UnimplementedError();

  Future<GitStatusSnapshot> getStatus(RepositoryId repositoryId) =>
      throw UnimplementedError();

  Future<GitHistoryPage> getHistory(
    RepositoryId repositoryId, {
    int limit = 50,
    int offset = 0,
    GitHistoryQuery? query,
  }) => throw UnimplementedError();

  Future<List<GitBranch>> getBranches(RepositoryId repositoryId) =>
      throw UnimplementedError();

  Future<GitBranchActionResult> createBranch(
    RepositoryId repositoryId,
    String name,
  ) => throw UnimplementedError();

  Future<GitBranchActionResult> switchBranch(
    RepositoryId repositoryId,
    String name,
  ) => throw UnimplementedError();

  Future<List<GitRemote>> getRemotes(RepositoryId repositoryId) =>
      throw UnimplementedError();

  Future<GitRemoteOperationResult> fetch(
    RepositoryId repositoryId,
    String remote, {
    GitCancellationToken? cancellationToken,
  }) => throw UnimplementedError();

  Future<GitRemoteOperationResult> pull(
    RepositoryId repositoryId,
    String remote, {
    GitCancellationToken? cancellationToken,
  }) => throw UnimplementedError();

  Future<GitRemoteOperationResult> push(
    RepositoryId repositoryId,
    String remote, {
    GitCancellationToken? cancellationToken,
  }) => throw UnimplementedError();

  Future<GitDiffSnapshot> getDiff(
    RepositoryId repositoryId,
    String path, {
    GitDiffScope scope = GitDiffScope.workingTree,
    String? originalPath,
  }) => throw UnimplementedError();

  Future<GitStatusSnapshot> stage(RepositoryId repositoryId, String path) =>
      throw UnimplementedError();

  Future<GitStatusSnapshot> unstage(RepositoryId repositoryId, String path) =>
      throw UnimplementedError();

  Future<GitCommitResult> commit(
    RepositoryId repositoryId,
    String message, {
    GitCommitOptions options = const GitCommitOptions(),
  }) => throw UnimplementedError();

  Future<DiscardPreview> createDiscardPreview(
    RepositoryId repositoryId,
    String path,
  ) => throw UnimplementedError();

  Future<GitStatusSnapshot> discard(
    RepositoryId repositoryId,
    DiscardPreview preview,
  ) => throw UnimplementedError();

  Future<GitConflictSnapshot> getConflicts(RepositoryId repositoryId) =>
      throw UnimplementedError();

  Future<GitConflictResolutionResult> acceptConflictOurs(
    RepositoryId repositoryId,
    String path, {
    required String fingerprint,
  }) => throw UnimplementedError();

  Future<GitConflictResolutionResult> acceptConflictTheirs(
    RepositoryId repositoryId,
    String path, {
    required String fingerprint,
  }) => throw UnimplementedError();

  Future<GitConflictResolutionResult> editConflictResult(
    RepositoryId repositoryId,
    String path,
    String content, {
    required String fingerprint,
  }) => throw UnimplementedError();

  Future<GitConflictResolutionResult> markConflictResolved(
    RepositoryId repositoryId,
    String path, {
    required String fingerprint,
    bool deleteResult = false,
  }) => throw UnimplementedError();

  Future<GitConflictOperationResult> continueConflict(
    RepositoryId repositoryId, {
    required String fingerprint,
    GitCancellationToken? cancellationToken,
  }) => throw UnimplementedError();

  Future<GitConflictOperationResult> abortConflict(
    RepositoryId repositoryId, {
    required String fingerprint,
    GitCancellationToken? cancellationToken,
  }) => throw UnimplementedError();

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
