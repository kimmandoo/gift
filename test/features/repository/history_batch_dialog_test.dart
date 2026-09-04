import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/executor.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:gift/src/backend/history_batch.dart';
import 'package:gift/src/backend/status.dart';
import 'package:gift/src/features/repository/history_batch_dialog.dart';

import '../../helpers/git_patch_gateway_stub.dart';

void main() {
  testWidgets('previews exact order and renders completed progress', (
    tester,
  ) async {
    final repository = const RepositoryOpened(
      repositoryId: RepositoryId(value: 'batch-dialog-repository'),
      root: '/workspace/project',
    );
    final newest = 'b' * 40;
    final oldest = 'a' * 40;
    final request = GitHistoryBatchRequest(
      action: GitHistoryBatchAction.cherryPick,
      revisions: [newest, oldest],
      targetBranch: 'main',
    );
    final preview = GitHistoryBatchPreview(
      repositoryId: repository.repositoryId,
      request: request,
      currentBranch: 'main',
      currentHead: 'c' * 40,
      targetBranch: 'main',
      displayedOids: [newest, oldest],
      executionOids: [oldest, newest],
      executionDirection: GitHistoryBatchExecutionDirection.oldestToNewest,
      dirtyWorktree: false,
      detachedHead: false,
      operationInProgress: null,
      duplicateOids: const [],
      containedOids: const [],
      mergeCommitOids: const [],
      mergeMainlineRequired: const [],
      impactedPaths: const ['one.txt', 'two.txt'],
      fingerprint: 'fingerprint',
      requiresConfirmation: true,
      token: 'preview-token',
      expiresAt: DateTime.now().add(const Duration(minutes: 1)),
    );
    final gateway = _BatchDialogGateway(
      repository: repository,
      preview: preview,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HistoryBatchDialog(
          gateway: gateway,
          repository: repository,
          action: GitHistoryBatchAction.cherryPick,
          revisions: [newest, oldest],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('batch-execution-direction')), findsOneWidget);
    expect(find.text('Execution: oldest → newest'), findsOneWidget);
    expect(find.byKey(ValueKey('batch-preview-oid:$oldest')), findsOneWidget);
    expect(find.byKey(ValueKey('batch-preview-oid:$newest')), findsOneWidget);
    await tester.tap(find.byKey(const Key('batch-execute')));
    await tester.pumpAndSettle();

    expect(gateway.requested?.revisions, [newest, oldest]);
    expect(find.textContaining('Progress: 2 completed'), findsOneWidget);
    expect(find.textContaining('Completed · $oldest'), findsOneWidget);
    expect(find.textContaining('Completed · $newest'), findsOneWidget);
  });
}

class _BatchDialogGateway with GitPatchGatewayStub implements GitGateway {
  _BatchDialogGateway({required this.repository, required this.preview});

  final RepositoryOpened repository;
  final GitHistoryBatchPreview preview;
  GitHistoryBatchRequest? requested;

  @override
  Future<GitHistoryBatchPreview> previewHistoryBatch(
    RepositoryId repositoryId,
    GitHistoryBatchRequest request,
  ) async {
    requested = request;
    return preview;
  }

  @override
  Future<GitHistoryBatchResult> executeHistoryBatch(
    RepositoryId repositoryId,
    GitHistoryBatchPreview preview, {
    GitCancellationToken? cancellationToken,
  }) async {
    return GitHistoryBatchResult(
      repositoryId: repositoryId,
      request: preview.request,
      state: GitHistoryBatchState.completed,
      status: _status(repositoryId),
      previousHead: preview.currentHead,
      resultingHead: 'd' * 40,
      completedOids: preview.executionOids,
      skippedOids: const [],
      currentOid: null,
      remainingOids: const [],
      summary: 'Cherry-pick completed.',
      recoveryActions: const [],
    );
  }

  GitStatusSnapshot _status(RepositoryId repositoryId) => GitStatusSnapshot(
    repositoryId: repositoryId,
    root: repository.root,
    branch: GitBranchStatus(head: 'main', oid: 'd' * 40),
    changes: const [],
    contentHash: 'status',
    generation: 1,
  );
}
