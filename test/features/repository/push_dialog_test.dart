import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/executor.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:gift/src/backend/history.dart';
import 'package:gift/src/backend/push.dart';
import 'package:gift/src/backend/remote.dart';
import 'package:gift/src/backend/credentials.dart';
import 'package:gift/src/backend/status.dart';
import 'package:gift/src/app/pixel_theme.dart';
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
        theme: buildPixelTheme(),
        home: PushDialog(gateway: gateway, repository: repository),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('push-guidance')), findsOneWidget);
    expect(find.text('Publish and link main'), findsOneWidget);
    final guidance = tester.getRect(find.byKey(const Key('push-guidance')));
    final remote = tester.getRect(find.byKey(const Key('push-remote')));
    final destination = tester.getRect(
      find.byKey(const Key('push-destination')),
    );
    expect(remote.top, greaterThanOrEqualTo(guidance.bottom + 8));
    expect(destination.top, greaterThanOrEqualTo(remote.bottom + 8));
    expect(remote.bottom, lessThanOrEqualTo(640));
    expect(find.byKey(const Key('execute-push')), findsNothing);
    expect(
      tester
          .widget<CheckboxListTile>(find.byKey(const Key('push-set-upstream')))
          .value,
      isTrue,
    );
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
    expect(gateway.executedRequest?.setUpstream, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('separates the push account field from the remote field', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    final repository = const RepositoryOpened(
      repositoryId: RepositoryId(value: 'push-account-spacing-repository'),
      root: '/workspace/project',
    );
    final store = InMemoryGitCredentialStore(
      records: [
        GitCredentialRecord(
          account: const GitCredentialAccount(
            id: 'github-account',
            provider: GitCredentialProvider.github,
            host: 'github.com',
            accountName: 'GitHub work',
            kind: GitCredentialKind.httpsToken,
          ),
          secret: 'test-secret',
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPixelTheme(),
        home: PushDialog(
          gateway: _PushGateway(
            repository,
            remotes: const [
              GitRemote(
                name: 'origin',
                fetchUrl: 'https://github.com/acme/project.git',
                pushUrl: 'https://github.com/acme/project.git',
              ),
            ],
          ),
          repository: repository,
          credentialStore: store,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final remote = tester.getRect(find.byKey(const Key('push-remote')));
    final account = tester.getRect(find.byKey(const Key('push-credential')));
    expect(account.top, greaterThanOrEqualTo(remote.bottom + 8));
    expect(find.text('Push account'), findsOneWidget);
    expect(find.text('github.com · default account'), findsOneWidget);
  });

  testWidgets('keeps push progress visible until the remote operation ends', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    final repository = const RepositoryOpened(
      repositoryId: RepositoryId(value: 'push-progress-repository'),
      root: '/workspace/project',
    );
    final gateway = _PushGateway(repository)..executionGate = Completer<void>();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPixelTheme(),
        home: PushDialog(gateway: gateway, repository: repository),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('preview-push')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('execute-push')));
    await tester.pump();

    expect(find.byKey(const Key('push-progress')), findsOneWidget);
    expect(find.text('Pushing to origin/main…'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Cancel push'), findsOneWidget);
    expect(gateway.executedRequest, isNotNull);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel push'));
    expect(gateway.executionCancellationToken?.isCancelled, isTrue);
    gateway.executionGate!.complete();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('push-progress')), findsNothing);
    expect(find.byKey(const Key('push-result')), findsOneWidget);
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
        theme: buildPixelTheme(),
        home: PushDialog(
          gateway: _PushGateway(repository),
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('push-advanced-options')));
    await tester.tap(find.byKey(const Key('push-advanced-options')));
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
  testWidgets('uses the configured upstream before a preferred remote', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(420, 700);
    tester.view.devicePixelRatio = 1;
    final repository = const RepositoryOpened(
      repositoryId: RepositoryId(value: 'tracked-push-repository'),
      root: '/workspace/project',
    );
    final gateway = _PushGateway(
      repository,
      remotes: const [
        GitRemote(name: 'backup'),
        GitRemote(name: 'origin'),
      ],
      branchStatus: GitBranchStatus(
        head: 'feature',
        oid: 'a' * 40,
        upstream: 'origin/review/feature',
        ahead: 2,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPixelTheme(),
        home: PushDialog(
          gateway: gateway,
          repository: repository,
          preferredRemote: 'backup',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Push feature to origin/review/feature'), findsOneWidget);
    expect(find.text('feature → origin/review/feature'), findsOneWidget);
    expect(find.text('Linked upstream: origin/review/feature'), findsOneWidget);
    expect(find.byKey(const Key('push-set-upstream')), findsNothing);

    await tester.tap(find.byKey(const Key('preview-push')));
    await tester.pumpAndSettle();
    expect(gateway.previewedRequest?.remote, 'origin');
    expect(gateway.previewedRequest?.branch, 'review/feature');
    expect(gateway.previewedRequest?.setUpstream, isFalse);
  });
}

class _PushGateway with GitPatchGatewayStub implements GitGateway {
  _PushGateway(
    this.repository, {
    this.remotes = const [GitRemote(name: 'origin')],
    GitBranchStatus? branchStatus,
  }) : branchStatus =
           branchStatus ?? GitBranchStatus(head: 'main', oid: 'a' * 40);

  final RepositoryOpened repository;
  final List<GitRemote> remotes;
  final GitBranchStatus branchStatus;
  GitPushRequest? previewedRequest;
  GitPushRequest? executedRequest;
  Completer<void>? executionGate;
  GitCancellationToken? executionCancellationToken;

  @override
  Future<List<GitRemote>> getRemotes(RepositoryId repositoryId) async =>
      remotes;

  @override
  Future<GitStatusSnapshot> getStatus(RepositoryId repositoryId) async =>
      GitStatusSnapshot(
        repositoryId: repositoryId,
        root: repository.root,
        branch: branchStatus,
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
  ) async {
    previewedRequest = request;
    return GitPushPreview(
      repositoryId: repositoryId,
      request: request,
      remote: request.remote,
      currentBranch: branchStatus.head ?? '',
      targetBranch: request.branch ?? branchStatus.head ?? '',
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
  }

  @override
  Future<GitPushResult> executePush(
    RepositoryId repositoryId,
    GitPushRequest request, {
    GitCancellationToken? cancellationToken,
  }) async {
    executedRequest = request;
    executionCancellationToken = cancellationToken;
    await executionGate?.future;
    final cancelled = cancellationToken?.isCancelled ?? false;
    return GitPushResult(
      repositoryId: repositoryId,
      request: request,
      state: cancelled ? GitPushState.cancelled : GitPushState.completed,
      status: await getStatus(repositoryId),
      summary: cancelled ? 'The push was cancelled.' : 'Pushed',
      recoveryActions: cancelled
          ? const [GitPushRecoveryAction.retry]
          : const [],
    );
  }
}
