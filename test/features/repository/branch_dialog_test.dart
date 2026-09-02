import 'package:branchline/src/backend/branch.dart';
import 'package:branchline/src/backend/commit.dart';
import 'package:branchline/src/backend/discard.dart';
import 'package:branchline/src/backend/diff.dart';
import 'package:branchline/src/backend/domain.dart';
import 'package:branchline/src/backend/git_gateway.dart';
import 'package:branchline/src/backend/history.dart';
import 'package:branchline/src/backend/status.dart';
import 'package:branchline/src/features/repository/branch_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('lists local branches and switches the selected branch', (
    tester,
  ) async {
    final repository = const RepositoryOpened(
      repositoryId: RepositoryId(value: 'branch-repository'),
      root: '/workspace/project',
    );
    final gateway = FakeBranchGateway(
      branches: const [
        GitBranch(name: 'feature/demo'),
        GitBranch(name: 'main', isCurrent: true),
      ],
      action: GitBranchActionResult(
        repositoryId: repository.repositoryId,
        branchName: 'feature/demo',
        status: GitStatusSnapshot(
          repositoryId: repository.repositoryId,
          root: repository.root,
          branch: GitBranchStatus(head: 'feature/demo'),
          changes: const [],
          contentHash: 'changed',
          generation: 2,
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BranchDialog(gateway: gateway, repository: repository),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('feature/demo'), findsOneWidget);
    expect(find.text('Current branch'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('branch:feature/demo')));
    await tester.pumpAndSettle();
    expect(gateway.switchedTo, 'feature/demo');
  });
}

class FakeBranchGateway implements GitGateway {
  FakeBranchGateway({required this.branches, required this.action});

  final List<GitBranch> branches;
  final GitBranchActionResult action;
  String? switchedTo;

  @override
  Future<List<GitBranch>> getBranches(RepositoryId repositoryId) async =>
      branches;

  @override
  Future<GitBranchActionResult> switchBranch(
    RepositoryId repositoryId,
    String name,
  ) async {
    switchedTo = name;
    return action;
  }

  @override
  Future<GitInstallation> configureGitPath(String path) =>
      throw UnimplementedError();

  @override
  Future<GitInstallation> getGitInstallation() => throw UnimplementedError();

  @override
  Future<RepositoryOpened> openRepository(String path) =>
      throw UnimplementedError();

  @override
  Future<GitStatusSnapshot> getStatus(RepositoryId repositoryId) =>
      throw UnimplementedError();

  @override
  Future<GitHistoryPage> getHistory(
    RepositoryId repositoryId, {
    int limit = 50,
    int offset = 0,
  }) => throw UnimplementedError();

  @override
  Future<GitDiffSnapshot> getDiff(
    RepositoryId repositoryId,
    String path, {
    GitDiffScope scope = GitDiffScope.workingTree,
    String? originalPath,
  }) => throw UnimplementedError();

  @override
  Future<GitStatusSnapshot> stage(RepositoryId repositoryId, String path) =>
      throw UnimplementedError();

  @override
  Future<GitStatusSnapshot> unstage(RepositoryId repositoryId, String path) =>
      throw UnimplementedError();

  @override
  Future<GitCommitResult> commit(RepositoryId repositoryId, String message) =>
      throw UnimplementedError();

  @override
  Future<GitBranchActionResult> createBranch(
    RepositoryId repositoryId,
    String name,
  ) => throw UnimplementedError();

  @override
  Future<DiscardPreview> createDiscardPreview(
    RepositoryId repositoryId,
    String path,
  ) => throw UnimplementedError();

  @override
  Future<GitStatusSnapshot> discard(
    RepositoryId repositoryId,
    DiscardPreview preview,
  ) => throw UnimplementedError();
}
