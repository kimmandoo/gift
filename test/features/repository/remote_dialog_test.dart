import 'dart:async';

import 'package:gitshiba/src/backend/branch.dart';
import 'package:gitshiba/src/backend/commit.dart';
import 'package:gitshiba/src/backend/discard.dart';
import 'package:gitshiba/src/backend/diff.dart';
import 'package:gitshiba/src/backend/domain.dart';
import 'package:gitshiba/src/backend/error.dart';
import 'package:gitshiba/src/backend/executor.dart';
import 'package:gitshiba/src/backend/git_gateway.dart';
import 'package:gitshiba/src/backend/history.dart';
import 'package:gitshiba/src/backend/remote.dart';
import 'package:gitshiba/src/backend/status.dart';
import 'package:gitshiba/src/features/repository/remote_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/git_patch_gateway_stub.dart';

void main() {
  testWidgets('shows remote progress and cancels the running operation', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final repository = const RepositoryOpened(
      repositoryId: RepositoryId(value: 'remote-repository'),
      root: '/workspace/project',
    );
    final gateway = FakeRemoteGateway(repository);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) =>
                  RemoteDialog(gateway: gateway, repository: repository),
            ),
            child: const Text('Open remotes'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open remotes'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('fetch:origin')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('fetch:origin')));
    await tester.pump();
    expect(find.byKey(const Key('remote-progress')), findsOneWidget);
    expect(find.byKey(const Key('cancel-remote')), findsOneWidget);

    await tester.tap(find.byKey(const Key('cancel-remote')));
    expect(gateway.token?.isCancelled, isTrue);
    gateway.pending.completeError(
      const GitError(
        category: GitErrorCategory.cancelled,
        userMessage: 'The Git operation was cancelled.',
        diagnostic: 'test cancellation',
        retryable: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('The Git operation was cancelled.'), findsOneWidget);
  });
}

class FakeRemoteGateway with GitPatchGatewayStub implements GitGateway {
  FakeRemoteGateway(this.repository);

  final RepositoryOpened repository;
  final pending = Completer<GitRemoteOperationResult>();
  GitCancellationToken? token;

  @override
  Future<List<GitRemote>> getRemotes(RepositoryId repositoryId) async => const [
    GitRemote(name: 'origin', fetchUrl: 'https://example.test/repo'),
  ];

  @override
  Future<GitRemoteOperationResult> fetch(
    RepositoryId repositoryId,
    String remote, {
    GitCancellationToken? cancellationToken,
  }) {
    token = cancellationToken;
    return pending.future;
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
  Future<List<GitBranch>> getBranches(RepositoryId repositoryId) =>
      throw UnimplementedError();

  @override
  Future<GitBranchActionResult> createBranch(
    RepositoryId repositoryId,
    String name,
  ) => throw UnimplementedError();

  @override
  Future<GitBranchActionResult> switchBranch(
    RepositoryId repositoryId,
    String name,
  ) => throw UnimplementedError();

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
  Future<GitRemoteOperationResult> pull(
    RepositoryId repositoryId,
    String remote, {
    GitCancellationToken? cancellationToken,
  }) => throw UnimplementedError();

  @override
  Future<GitRemoteOperationResult> push(
    RepositoryId repositoryId,
    String remote, {
    GitCancellationToken? cancellationToken,
  }) => throw UnimplementedError();

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
