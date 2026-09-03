import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/executor.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:gift/src/backend/history.dart';
import 'package:gift/src/backend/push.dart';
import 'package:gift/src/backend/remote.dart';
import 'package:gift/src/backend/status.dart';
import 'package:gift/src/features/repository/push_dialog.dart';

import '../../helpers/git_patch_gateway_stub.dart';

void main() {
  testWidgets('reviews the push scope before enabling publication', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final repository = const RepositoryOpened(
      repositoryId: RepositoryId(value: 'push-ui-repository'),
      root: '/workspace/project',
    );
    final gateway = _PushGateway(repository);

    await tester.pumpWidget(
      MaterialApp(
        home: PushDialog(gateway: gateway, repository: repository),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('push-guidance')), findsOneWidget);
    expect(find.text('Nothing is pushed yet'), findsOneWidget);
    final remoteLabel = tester.getRect(find.text('Remote'));
    expect(remoteLabel.top, greaterThanOrEqualTo(0));
    expect(remoteLabel.bottom, lessThanOrEqualTo(640));
    expect(find.byKey(const Key('execute-push')), findsNothing);
    await tester.tap(find.byKey(const Key('preview-push')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('push-preview')), findsOneWidget);
    expect(find.text('Ready to push'), findsOneWidget);
    expect(find.textContaining('1 commit(s), 1 file(s)'), findsOneWidget);
    expect(find.text('Push to origin'), findsOneWidget);
    expect(find.byKey(const Key('execute-push')), findsOneWidget);
    await tester.tap(find.byKey(const Key('execute-push')));
    await tester.pumpAndSettle();

    expect(gateway.executedRequest?.confirmationToken, 'push-token');
    expect(tester.takeException(), isNull);
  });

  testWidgets('bounds every push dropdown option to one line', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    final repository = const RepositoryOpened(
      repositoryId: RepositoryId(value: 'push-dropdown-repository'),
      root: '/workspace/project',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PushDialog(
          gateway: _PushGateway(repository),
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('push-target')));
    await tester.tap(find.byKey(const Key('push-target')));
    await tester.pumpAndSettle();
    final longTargetLabel = tester.widget<Text>(
      find.text('All local tags (explicit refs)'),
    );
    expect(longTargetLabel.maxLines, 1);
    expect(longTargetLabel.overflow, TextOverflow.ellipsis);

    await tester.tap(find.text('Up to selected commit'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('push-selected-commit')));
    await tester.tap(find.byKey(const Key('push-selected-commit')));
    await tester.pumpAndSettle();
    final commitLabel = tester.widget<Text>(
      find.textContaining('Publish this'),
    );
    expect(commitLabel.maxLines, 1);
    expect(commitLabel.overflow, TextOverflow.ellipsis);
  });
}

class _PushGateway with GitPatchGatewayStub implements GitGateway {
  _PushGateway(this.repository);

  final RepositoryOpened repository;
  GitPushRequest? executedRequest;

  @override
  Future<List<GitRemote>> getRemotes(RepositoryId repositoryId) async => const [
    GitRemote(name: 'origin'),
  ];

  @override
  Future<GitStatusSnapshot> getStatus(RepositoryId repositoryId) async =>
      GitStatusSnapshot(
        repositoryId: repositoryId,
        root: repository.root,
        branch: GitBranchStatus(head: 'main', oid: 'a' * 40),
        changes: const [],
        contentHash: 'status',
        generation: 1,
      );

  @override
  Future<GitHistoryPage> getHistory(
    RepositoryId repositoryId, {
    int limit = 50,
    int offset = 0,
    GitHistoryQuery? query,
  }) async => GitHistoryPage(
    repositoryId: repositoryId,
    commits: [
      GitCommit(
        oid: 'a' * 40,
        parents: const [],
        authorName: 'Tester',
        authorEmail: 'test@example.com',
        authoredAt: DateTime(2026),
        subject: 'Publish this',
        body: '',
      ),
    ],
    offset: 0,
    limit: limit,
    hasMore: false,
  );

  @override
  Future<GitPushPreview> previewPush(
    RepositoryId repositoryId,
    GitPushRequest request,
  ) async => GitPushPreview(
    repositoryId: repositoryId,
    request: request,
    remote: 'origin',
    currentBranch: 'main',
    targetBranch: 'main',
    localHead: 'a' * 40,
    targetOid: 'a' * 40,
    remoteHead: 'b' * 40,
    commits: [GitPushCommit(oid: 'a' * 40, subject: 'Publish this')],
    changedPaths: const ['README.md'],
    tags: const [],
    dirtyWorktree: false,
    protectedBranch: false,
    requiresConfirmation: false,
    fingerprint: 'fingerprint',
    token: 'push-token',
    expiresAt: DateTime.now().add(const Duration(minutes: 1)),
  );

  @override
  Future<GitPushResult> executePush(
    RepositoryId repositoryId,
    GitPushRequest request, {
    GitCancellationToken? cancellationToken,
  }) async {
    executedRequest = request;
    return GitPushResult(
      repositoryId: repositoryId,
      request: request,
      state: GitPushState.completed,
      status: await getStatus(repositoryId),
      summary: 'Pushed',
    );
  }
}
