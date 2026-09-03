import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gift/src/backend/conflict.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/error.dart';
import 'package:gift/src/backend/executor.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:gift/src/features/repository/conflict_controller.dart';
import 'package:gift/src/features/repository/conflict_workspace_screen.dart';
import 'package:gift/src/app/pixel_theme.dart';

import '../../helpers/git_patch_gateway_stub.dart';

void main() {
  test('keeps the selected conflict and reports a stale resolution', () async {
    final repository = _repository();
    final gateway = FakeConflictGateway(_snapshot(repository));
    final controller = ConflictController(
      gateway: gateway,
      repositoryId: repository.repositoryId,
    );
    await controller.refresh();
    gateway.stale = true;
    await controller.acceptOurs();

    expect(controller.state.error?.category, GitErrorCategory.staleConflict);
    expect(controller.state.selectedConflict?.path, 'notes.txt');
    expect(controller.state.isMutating, isFalse);
    controller.dispose();
  });

  testWidgets('shows three panes and conflict recovery actions', (
    tester,
  ) async {
    final repository = _repository();
    final controller = ConflictController(
      gateway: FakeConflictGateway(_snapshot(repository)),
      repositoryId: repository.repositoryId,
    );
    await controller.refresh();
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 1100,
          height: 760,
          child: ConflictWorkspaceScreen(
            gateway: controller.gateway,
            repository: repository,
            controller: controller,
            autoInitialize: false,
          ),
        ),
      ),
    );

    expect(find.text('Conflict workspace'), findsOneWidget);
    expect(find.byKey(const Key('conflict-base-pane')), findsOneWidget);
    expect(find.byKey(const Key('conflict-ours-pane')), findsOneWidget);
    expect(find.byKey(const Key('conflict-result-pane')), findsOneWidget);
    expect(find.byKey(const Key('conflict-theirs-pane')), findsOneWidget);
    expect(find.byKey(const Key('accept-conflict-ours')), findsOneWidget);
    expect(find.byKey(const Key('accept-conflict-theirs')), findsOneWidget);
    expect(find.byKey(const Key('mark-conflict-resolved')), findsOneWidget);
    expect(find.byKey(const Key('abort-conflict-operation')), findsOneWidget);
    expect(
      find.byKey(const Key('continue-conflict-operation')),
      findsOneWidget,
    );
    expect(find.textContaining('Available text'), findsWidgets);
    controller.dispose();
  });

  testWidgets('stacks the panes in a compact window with text labels', (
    tester,
  ) async {
    final repository = _repository();
    final controller = ConflictController(
      gateway: FakeConflictGateway(_snapshot(repository)),
      repositoryId: repository.repositoryId,
    );
    await controller.refresh();
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPixelTheme(),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(360, 640)),
          child: ConflictWorkspaceScreen(
            gateway: controller.gateway,
            repository: repository,
            controller: controller,
            autoInitialize: false,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('conflict-result-status')), findsOneWidget);
    expect(find.text('BASE · common ancestor'), findsOneWidget);
    expect(find.text('OURS · current branch'), findsOneWidget);
    expect(find.text('THEIRS · incoming change'), findsOneWidget);
    expect(tester.takeException(), isNull);
    controller.dispose();
  });
}

RepositoryOpened _repository() => const RepositoryOpened(
  repositoryId: RepositoryId(value: 'conflict-repository'),
  root: '/workspace/project',
);

GitConflictSnapshot _snapshot(RepositoryOpened repository) {
  const text = GitConflictContent(
    state: GitConflictContentState.available,
    text: 'line\n',
    byteLength: 5,
  );
  return GitConflictSnapshot(
    repositoryId: repository.repositoryId,
    fingerprint: 'fingerprint-1',
    operation: const GitConflictOperationMetadata(
      operation: GitConflictOperation.merge,
      mergeHeads: ['incoming'],
    ),
    conflicts: [
      const GitConflictEntry(
        path: 'notes.txt',
        base: GitConflictSide(stage: 1, oid: 'base', content: text),
        ours: GitConflictSide(stage: 2, oid: 'ours', content: text),
        theirs: GitConflictSide(stage: 3, oid: 'theirs', content: text),
        result: GitConflictSide(stage: 0, content: text),
      ),
    ],
  );
}

class FakeConflictGateway with GitPatchGatewayStub implements GitGateway {
  FakeConflictGateway(this.snapshot);

  GitConflictSnapshot snapshot;
  var stale = false;
  var editCalls = 0;

  @override
  Future<GitConflictSnapshot> getConflicts(RepositoryId repositoryId) async =>
      snapshot;

  @override
  Future<GitConflictResolutionResult> acceptConflictOurs(
    RepositoryId repositoryId,
    String path, {
    required String fingerprint,
  }) => _resolve(GitConflictResolutionAction.acceptOurs, path, fingerprint);

  @override
  Future<GitConflictResolutionResult> acceptConflictTheirs(
    RepositoryId repositoryId,
    String path, {
    required String fingerprint,
  }) => _resolve(GitConflictResolutionAction.acceptTheirs, path, fingerprint);

  @override
  Future<GitConflictResolutionResult> editConflictResult(
    RepositoryId repositoryId,
    String path,
    String content, {
    required String fingerprint,
  }) async {
    editCalls++;
    return _resolve(GitConflictResolutionAction.editResult, path, fingerprint);
  }

  @override
  Future<GitConflictResolutionResult> markConflictResolved(
    RepositoryId repositoryId,
    String path, {
    required String fingerprint,
    bool deleteResult = false,
  }) => _resolve(GitConflictResolutionAction.markResolved, path, fingerprint);

  @override
  Future<GitConflictOperationResult> continueConflict(
    RepositoryId repositoryId, {
    required String fingerprint,
    GitCancellationToken? cancellationToken,
  }) async => GitConflictOperationResult(
    repositoryId: repositoryId,
    operation: snapshot.operation!,
    action: GitConflictOperationAction.continueOperation,
    state: GitConflictOperationState.completed,
    snapshot: snapshot,
    summary: 'continued',
  );

  @override
  Future<GitConflictOperationResult> abortConflict(
    RepositoryId repositoryId, {
    required String fingerprint,
    GitCancellationToken? cancellationToken,
  }) async => GitConflictOperationResult(
    repositoryId: repositoryId,
    operation: snapshot.operation!,
    action: GitConflictOperationAction.abort,
    state: GitConflictOperationState.aborted,
    snapshot: snapshot,
    summary: 'aborted',
  );

  Future<GitConflictResolutionResult> _resolve(
    GitConflictResolutionAction action,
    String path,
    String fingerprint,
  ) async {
    if (stale) {
      throw const GitError(
        category: GitErrorCategory.staleConflict,
        userMessage: 'The conflict changed.',
        diagnostic: 'stale fixture',
        retryable: true,
      );
    }
    return GitConflictResolutionResult(
      repositoryId: snapshot.repositoryId,
      path: path,
      action: action,
      snapshot: snapshot,
      summary: 'resolved',
    );
  }
}
