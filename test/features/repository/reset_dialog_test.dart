import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gift/src/app/pixel_theme.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/executor.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:gift/src/backend/reset.dart';
import 'package:gift/src/backend/status.dart';
import 'package:gift/src/features/repository/reset_dialog.dart';

import '../../helpers/git_patch_gateway_stub.dart';

void main() {
  testWidgets(
    'requires a hard-reset acknowledgement after showing its preview',
    (tester) async {
      addTearDown(tester.view.reset);
      tester.view.physicalSize = const Size(900, 1200);
      tester.view.devicePixelRatio = 1;
      final repository = const RepositoryOpened(
        repositoryId: RepositoryId(value: 'rollback-ui-repository'),
        root: '/workspace/project',
      );
      final gateway = _RollbackGateway(repository.repositoryId);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildPixelTheme(),
          home: Scaffold(
            body: ResetDialog(gateway: gateway, repository: repository),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('rollback-reset-mode')));
      await tester.tap(find.byKey(const Key('rollback-reset-mode')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hard — reset index and files').last);
      await tester.ensureVisible(find.byKey(const Key('preview-rollback')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('preview-rollback')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('rollback-preview')), findsOneWidget);
      expect(find.byKey(const Key('confirm-hard-reset')), findsOneWidget);
      final executeBefore = tester.widget<FilledButton>(
        find.byKey(const Key('execute-rollback')),
      );
      expect(executeBefore.onPressed, isNull);

      await tester.ensureVisible(find.byKey(const Key('confirm-hard-reset')));
      await tester.tap(find.byKey(const Key('confirm-hard-reset')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('execute-rollback')));
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('execute-rollback')))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const Key('execute-rollback')));
      await tester.pumpAndSettle();

      expect(gateway.executed, isTrue);
      expect(find.byKey(const Key('rollback-result')), findsOneWidget);
    },
  );
}

class _RollbackGateway with GitPatchGatewayStub implements GitGateway {
  _RollbackGateway(this.repositoryId);

  final RepositoryId repositoryId;
  var executed = false;

  @override
  Future<GitHistoryRollbackPreview> previewHistoryRollback(
    RepositoryId id,
    GitHistoryRollbackRequest request,
  ) async {
    return GitHistoryRollbackPreview(
      repositoryId: repositoryId,
      request: request,
      currentBranch: 'topic',
      currentHead: 'a' * 40,
      targetHead: 'b' * 40,
      upstreamHead: null,
      branchProtected: false,
      pushedCommits: false,
      detachedHead: false,
      dirtyWorktree: false,
      operationInProgress: false,
      impact: GitRollbackImpact(
        headBefore: 'a' * 40,
        headAfter: 'b' * 40,
        indexEffect: GitRollbackTreeEffect.resetToTarget,
        worktreeEffect: GitRollbackTreeEffect.resetToTarget,
        stagedPathsBefore: const [],
        unstagedPathsBefore: const [],
        potentiallyDiscardedPaths: const ['file.txt'],
        preservedPaths: const [],
        commitsMoved: 1,
      ),
      fingerprint: 'fingerprint',
      requiresConfirmation: true,
      token: 'token',
      expiresAt: DateTime(2030),
    );
  }

  @override
  Future<GitHistoryRollbackResult> executeHistoryRollback(
    RepositoryId id,
    GitHistoryRollbackPreview preview, {
    GitCancellationToken? cancellationToken,
  }) async {
    executed = true;
    return GitHistoryRollbackResult(
      repositoryId: repositoryId,
      request: preview.request,
      state: GitHistoryRollbackState.completed,
      status: GitStatusSnapshot(
        repositoryId: repositoryId,
        root: '/workspace/project',
        branch: GitBranchStatus(head: 'topic', oid: 'b' * 40),
        changes: const [],
        contentHash: 'clean',
        generation: 2,
      ),
      previousHead: 'a' * 40,
      resultingHead: 'b' * 40,
      summary: 'Hard reset completed.',
    );
  }
}
