import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/executor.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:gift/src/backend/recovery.dart';
import 'package:gift/src/backend/status.dart';
import 'package:gift/src/features/repository/recovery_dialog.dart';

import '../../helpers/git_patch_gateway_stub.dart';

void main() {
  testWidgets('reviews reflog recovery and shows redacted operation history', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final repository = const RepositoryOpened(
      repositoryId: RepositoryId(value: 'recovery-ui-repository'),
      root: '/workspace/project',
    );
    final gateway = _RecoveryGateway(repository);
    await tester.pumpWidget(
      MaterialApp(
        home: RecoveryDialog(gateway: gateway, repository: repository),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Recovery diagnostics'), findsOneWidget);
    expect(find.text('Reflog'), findsOneWidget);
    expect(find.text('Recent Git operations'), findsOneWidget);
    expect(find.text('remote-token=***'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('review-recovery-branch')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recovery-preview')), findsOneWidget);
    await tester.tap(find.byKey(const Key('create-recovery-branch')));
    await tester.pumpAndSettle();
    expect(gateway.created, isTrue);
    expect(find.byKey(const Key('recovery-message')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _RecoveryGateway with GitPatchGatewayStub implements GitGateway {
  _RecoveryGateway(this.repository);

  final RepositoryOpened repository;
  var created = false;

  final _entry = GitReflogEntry(
    oid: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    previousOid: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    selector: 'HEAD@{1}',
    actor: 'Recovery Tester',
    message: 'reset: moving to HEAD~1',
  );

  @override
  Future<GitReflogSnapshot> getReflog(
    RepositoryId repositoryId, {
    String ref = 'HEAD',
    int limit = 100,
  }) async => GitReflogSnapshot(
    repositoryId: repositoryId,
    ref: ref,
    fingerprint: 'reflog',
    entries: [_entry],
  );

  @override
  Future<List<GitOperationRecord>> getOperationRecords(
    RepositoryId repositoryId, {
    int limit = 100,
  }) async => [
    GitOperationRecord(
      startedAt: DateTime(2026),
      duration: const Duration(milliseconds: 18),
      program: 'git',
      args: const ['fetch', 'origin'],
      cwd: repository.root,
      kind: GitOperationKind.remote,
      succeeded: true,
      exitCode: 0,
      diagnostic: 'remote-token=***',
      stdinBytes: 0,
    ),
  ];

  @override
  Future<GitRecoveryBranchPreview> previewRecoveryBranch(
    RepositoryId repositoryId,
    GitRecoveryBranchRequest request,
  ) async => GitRecoveryBranchPreview(
    repositoryId: repositoryId,
    request: request,
    entry: _entry,
    fingerprint: 'reflog',
    token: 'recovery-token',
    expiresAt: DateTime.now().add(const Duration(minutes: 1)),
  );

  @override
  Future<GitRecoveryBranchResult> createRecoveryBranch(
    RepositoryId repositoryId,
    GitRecoveryBranchPreview preview,
  ) async {
    created = true;
    return GitRecoveryBranchResult(
      repositoryId: repositoryId,
      request: preview.request,
      branchName: preview.request.branchName,
      status: _status,
      reflog: GitReflogSnapshot(
        repositoryId: repositoryId,
        ref: 'HEAD',
        entries: [_entry],
        fingerprint: 'reflog',
      ),
      summary: 'Created recovery branch.',
    );
  }

  GitStatusSnapshot get _status => GitStatusSnapshot(
    repositoryId: repository.repositoryId,
    root: repository.root,
    branch: const GitBranchStatus(head: 'main'),
    changes: const [],
    contentHash: 'status',
    generation: 1,
  );
}
