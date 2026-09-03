import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/executor.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:gift/src/backend/history.dart';
import 'package:gift/src/backend/interactive_rebase.dart';
import 'package:gift/src/backend/status.dart';
import 'package:gift/src/features/repository/interactive_rebase_dialog.dart';

import '../../helpers/git_patch_gateway_stub.dart';

void main() {
  testWidgets('builds and previews the selected History range', (tester) async {
    final gateway = _InteractiveRebaseGateway();
    final repository = RepositoryOpened(
      repositoryId: const RepositoryId(value: 'repo-1'),
      root: '/tmp/rebase-repository',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: InteractiveRebaseDialog(gateway: gateway, repository: repository),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('interactive-rebase-dialog')), findsOneWidget);
    expect(find.byKey(const Key('rebase-upstream')), findsOneWidget);
    expect(
      find.byKey(
        const Key('rebase-entry:3333333333333333333333333333333333333333'),
      ),
      findsOneWidget,
    );
    expect(find.text('Plan (1 commit)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('preview-interactive-rebase')));
    await tester.pumpAndSettle();

    expect(gateway.previewedPlan, isNotNull);
    expect(find.byKey(const Key('interactive-rebase-preview')), findsOneWidget);
    expect(find.byKey(const Key('execute-interactive-rebase')), findsOneWidget);
    expect(find.textContaining('Option notes:'), findsOneWidget);
  });

  testWidgets('starts the reviewed rebase from the dialog', (tester) async {
    final gateway = _InteractiveRebaseGateway();
    final repository = RepositoryOpened(
      repositoryId: const RepositoryId(value: 'repo-1'),
      root: '/tmp/rebase-repository',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: InteractiveRebaseDialog(gateway: gateway, repository: repository),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('preview-interactive-rebase')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('execute-interactive-rebase')));
    await tester.pumpAndSettle();

    expect(gateway.executeCount, 1);
  });

  testWidgets('offers cancellation while rebase execution is in flight', (
    tester,
  ) async {
    final gateway = _InteractiveRebaseGateway()..holdExecution = true;
    final repository = RepositoryOpened(
      repositoryId: const RepositoryId(value: 'repo-1'),
      root: '/tmp/rebase-repository',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: InteractiveRebaseDialog(gateway: gateway, repository: repository),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('preview-interactive-rebase')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('execute-interactive-rebase')));
    await tester.pump();

    expect(find.byKey(const Key('cancel-interactive-rebase')), findsOneWidget);
    await tester.tap(find.byKey(const Key('cancel-interactive-rebase')));
    expect(gateway.executeToken?.isCancelled, isTrue);

    gateway.completeExecution();
    await tester.pumpAndSettle();
  });
}

class _InteractiveRebaseGateway with GitPatchGatewayStub implements GitGateway {
  final repositoryId = const RepositoryId(value: 'repo-1');
  GitInteractiveRebasePlan? previewedPlan;
  var executeCount = 0;
  var holdExecution = false;
  GitCancellationToken? executeToken;
  Completer<GitInteractiveRebaseResult>? executionCompleter;

  @override
  Future<GitHistoryPage> getHistory(
    RepositoryId repositoryId, {
    int limit = 50,
    int offset = 0,
    GitHistoryQuery? query,
  }) async => GitHistoryPage(
    repositoryId: this.repositoryId,
    commits: [_commit('3', 'three'), _commit('2', 'two'), _commit('1', 'one')],
    offset: 0,
    limit: limit,
    hasMore: false,
  );

  @override
  Future<GitStatusSnapshot> getStatus(RepositoryId repositoryId) async =>
      GitStatusSnapshot(
        repositoryId: this.repositoryId,
        root: '/tmp/rebase-repository',
        branch: const GitBranchStatus(head: 'topic', oid: _headOid),
        changes: const [],
        contentHash: 'clean',
        generation: 1,
      );

  @override
  Future<GitInteractiveRebasePreview> previewInteractiveRebase(
    RepositoryId repositoryId,
    GitInteractiveRebasePlan plan,
  ) async {
    previewedPlan = plan;
    return GitInteractiveRebasePreview(
      repositoryId: repositoryId,
      plan: plan,
      currentBranch: 'topic',
      currentHead: _headOid,
      upstreamHead: plan.upstreamRevision,
      selectedCommitCount: plan.entries.length,
      mergeCommitCount: 0,
      branchProtected: false,
      pushedCommits: false,
      detachedHead: false,
      dirtyWorktree: false,
      operationInProgress: null,
      fingerprint: 'preview-fingerprint',
      requiresConfirmation: true,
      token: 'preview-token',
      expiresAt: DateTime.now().add(const Duration(minutes: 1)),
      optionLimitations: const [
        'Root mode rewrites every reachable commit.',
        'Update refs may move local branches.',
      ],
    );
  }

  @override
  Future<GitInteractiveRebaseResult> executeInteractiveRebase(
    RepositoryId repositoryId,
    GitInteractiveRebasePreview preview, {
    GitCancellationToken? cancellationToken,
  }) async {
    executeCount++;
    executeToken = cancellationToken;
    if (holdExecution) {
      executionCompleter = Completer<GitInteractiveRebaseResult>();
      return executionCompleter!.future;
    }
    return GitInteractiveRebaseResult(
      repositoryId: repositoryId,
      phase: GitInteractiveRebasePhase.start,
      state: GitInteractiveRebaseExecutionState.completed,
      status: await getStatus(repositoryId),
      previousHead: _headOid,
      resultingHead: _headOid,
      summary: 'The interactive rebase completed.',
      originalCommitOids: preview.plan.entries.map(
        (entry) => entry.originalOid,
      ),
    );
  }

  void completeExecution() {
    executionCompleter?.complete(
      GitInteractiveRebaseResult(
        repositoryId: repositoryId,
        phase: GitInteractiveRebasePhase.start,
        state: GitInteractiveRebaseExecutionState.cancelled,
        status: GitStatusSnapshot(
          repositoryId: repositoryId,
          root: '/tmp/rebase-repository',
          branch: const GitBranchStatus(head: 'topic', oid: _headOid),
          changes: const [],
          contentHash: 'clean',
          generation: 1,
        ),
        previousHead: _headOid,
        resultingHead: _headOid,
        summary: 'The rebase was cancelled.',
      ),
    );
  }
}

GitCommit _commit(String first, String subject) => GitCommit(
  oid: first * 40,
  parents: const [],
  authorName: 'Gift Test',
  authorEmail: 'gift@example.test',
  authoredAt: DateTime(2026, 1, 1),
  subject: subject,
  body: '',
);

const _headOid = '3333333333333333333333333333333333333333';
