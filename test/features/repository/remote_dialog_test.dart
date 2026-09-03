import 'dart:async';

import 'package:gift/src/backend/branch.dart';
import 'package:gift/src/backend/commit.dart';
import 'package:gift/src/backend/discard.dart';
import 'package:gift/src/backend/diff.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/error.dart';
import 'package:gift/src/backend/executor.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:gift/src/backend/history.dart';
import 'package:gift/src/backend/remote.dart';
import 'package:gift/src/backend/status.dart';
import 'package:gift/src/features/repository/remote_dialog.dart';
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

  testWidgets('exposes a push-only remote entry point', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(420, 760);
    tester.view.devicePixelRatio = 1;
    final repository = const RepositoryOpened(
      repositoryId: RepositoryId(value: 'push-entry-repository'),
      root: '/workspace/project',
    );
    final gateway = FakeRemoteGateway(repository);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => RemoteDialog(
                gateway: gateway,
                repository: repository,
                initialOperation: GitRemoteOperation.push,
              ),
            ),
            child: const Text('Open push'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open push'));
    await tester.pumpAndSettle();

    expect(find.text('Push to remote'), findsOneWidget);
    expect(find.byKey(const ValueKey('fetch:origin')), findsNothing);
    expect(find.byKey(const ValueKey('pull:origin')), findsNothing);
    expect(find.byKey(const ValueKey('push:origin')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('push:origin')));
    await tester.pumpAndSettle();
    expect(gateway.pushCalls, 1);
  });
}

class FakeRemoteGateway with GitPatchGatewayStub implements GitGateway {
  FakeRemoteGateway(this.repository);

  final RepositoryOpened repository;
  final pending = Completer<GitRemoteOperationResult>();
  GitCancellationToken? token;
  var pushCalls = 0;

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
    GitHistoryQuery? query,
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
  Future<GitCommitResult> commit(
    RepositoryId repositoryId,
    String message, {
    GitCommitOptions options = const GitCommitOptions(),
  }) => throw UnimplementedError();

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
  }) async {
    pushCalls++;
    return GitRemoteOperationResult(
      repositoryId: repositoryId,
      remote: remote,
      operation: GitRemoteOperation.push,
      status: GitStatusSnapshot(
        repositoryId: repositoryId,
        root: repository.root,
        branch: GitBranchStatus(head: 'main', oid: 'a' * 40),
        changes: const [],
        contentHash: 'clean',
        generation: 1,
      ),
      summary: 'pushed',
    );
  }

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
