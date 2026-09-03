import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/executor.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:gift/src/backend/status.dart';
import 'package:gift/src/backend/worktree.dart';
import 'package:gift/src/features/repository/worktree_dialog.dart';

import '../../helpers/git_patch_gateway_stub.dart';

void main() {
  testWidgets('shows worktree states and confirms dirty removal', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final repository = const RepositoryOpened(
      repositoryId: RepositoryId(value: 'worktree-ui-repository'),
      root: '/workspace/project',
    );
    final gateway = _WorktreeGateway(repository);

    await tester.pumpWidget(
      MaterialApp(
        home: WorktreeDialog(gateway: gateway, repository: repository),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Worktrees'), findsOneWidget);
    expect(find.text('main'), findsOneWidget);
    expect(find.text('feature/ui'), findsOneWidget);
    expect(find.text('Dirty (1)'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final removeButton = find.byKey(
      const ValueKey('remove-worktree:/workspace/feature'),
    );
    await tester.drag(
      find.byKey(const Key('worktree-list')),
      const Offset(0, -240),
    );
    await tester.pump();
    await tester.tap(removeButton);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Remove dirty worktree?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('confirm-remove-dirty-worktree')));
    await tester.pumpAndSettle();
    expect(gateway.executedRequest?.confirmDirty, isTrue);
    expect(find.byKey(const Key('worktree-message')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _WorktreeGateway with GitPatchGatewayStub implements GitGateway {
  _WorktreeGateway(this.repository)
    : _snapshot = GitWorktreeSnapshot(
        repositoryId: repository.repositoryId,
        fingerprint: 'worktrees',
        worktrees: [
          GitWorktree(
            path: '/workspace/project',
            branch: 'main',
            head: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            isMain: true,
            isCurrent: true,
          ),
          GitWorktree(
            path: '/workspace/feature',
            branch: 'feature/ui',
            head: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            isDirty: true,
            dirtyPaths: ['lib/screen.dart'],
          ),
        ],
      );

  final RepositoryOpened repository;
  GitWorktreeSnapshot _snapshot;
  GitWorktreeActionRequest? executedRequest;

  @override
  Future<GitWorktreeSnapshot> getWorktrees(RepositoryId repositoryId) async =>
      _snapshot;

  @override
  Future<GitWorktreeActionPreview> previewWorktreeAction(
    RepositoryId repositoryId,
    GitWorktreeActionRequest request,
  ) async {
    final worktree = _snapshot.worktrees.singleWhere(
      (candidate) => candidate.path == request.path,
    );
    final blocked =
        request.action == GitWorktreeAction.remove &&
        worktree.isDirty &&
        !request.confirmDirty;
    final previewRequest = request.confirmationToken == null
        ? GitWorktreeActionRequest(
            action: request.action,
            path: request.path,
            confirmDirty: request.confirmDirty,
            lockReason: request.lockReason,
            confirmationToken: blocked ? null : 'worktree-token',
          )
        : request;
    return GitWorktreeActionPreview(
      repositoryId: repositoryId,
      request: previewRequest,
      worktree: worktree,
      dirtyPaths: worktree.dirtyPaths,
      requiresConfirmation:
          request.action == GitWorktreeAction.remove && worktree.isDirty,
      fingerprint: 'fingerprint',
      blockingMessage: blocked ? 'Confirm dirty removal.' : null,
      token: blocked ? null : 'worktree-token',
      expiresAt: DateTime.now().add(const Duration(minutes: 1)),
    );
  }

  @override
  Future<GitWorktreeActionResult> executeWorktreeAction(
    RepositoryId repositoryId,
    GitWorktreeActionRequest request, {
    GitCancellationToken? cancellationToken,
  }) async {
    executedRequest = request;
    final removed = request.action == GitWorktreeAction.remove;
    final worktrees = removed
        ? _snapshot.worktrees
              .where((worktree) => worktree.path != request.path)
              .toList()
        : _snapshot.worktrees;
    _snapshot = GitWorktreeSnapshot(
      repositoryId: repositoryId,
      worktrees: worktrees,
      fingerprint: 'after-action',
    );
    return GitWorktreeActionResult(
      repositoryId: repositoryId,
      request: request,
      action: request.action,
      status: _status,
      snapshot: _snapshot,
      summary: 'Worktree action complete.',
    );
  }

  GitStatusSnapshot get _status => GitStatusSnapshot(
    repositoryId: repository.repositoryId,
    root: repository.root,
    branch: const GitBranchStatus(
      head: 'main',
      oid: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    ),
    changes: const [],
    contentHash: 'status',
    generation: 1,
  );
}
