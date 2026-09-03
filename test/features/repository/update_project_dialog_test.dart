import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/executor.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:gift/src/backend/remote_branch.dart';
import 'package:gift/src/backend/status.dart';
import 'package:gift/src/features/repository/update_project_dialog.dart';

import '../../helpers/git_patch_gateway_stub.dart';

void main() {
  testWidgets('previews and applies the selected update strategy', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final repository = const RepositoryOpened(
      repositoryId: RepositoryId(value: 'update-ui-repository'),
      root: '/workspace/project',
    );
    final gateway = _UpdateGateway(repository.repositoryId);
    await tester.pumpWidget(
      MaterialApp(
        home: UpdateProjectDialog(gateway: gateway, repository: repository),
      ),
    );

    await tester.tap(find.byKey(const Key('preview-update-project')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('update-project-preview')), findsOneWidget);
    expect(find.textContaining('Incoming 2'), findsOneWidget);
    await tester.tap(find.byKey(const Key('execute-update-project')));
    await tester.pumpAndSettle();
    expect(gateway.executed, isTrue);
    expect(tester.takeException(), isNull);
  });
}

class _UpdateGateway with GitPatchGatewayStub implements GitGateway {
  _UpdateGateway(this.repositoryId);

  final RepositoryId repositoryId;
  var executed = false;

  @override
  Future<GitUpdateProjectPreview> previewUpdateProject(
    RepositoryId repositoryId,
    GitUpdateProjectRequest request,
  ) async => GitUpdateProjectPreview(
    repositoryId: repositoryId,
    request: request,
    branch: 'main',
    upstream: 'origin/main',
    currentOid: 'a' * 40,
    upstreamOid: 'b' * 40,
    incoming: 2,
    outgoing: 1,
    dirtyWorktree: false,
    requiresConfirmation: false,
    fingerprint: 'preview',
    token: 'token',
    expiresAt: DateTime.now().add(const Duration(minutes: 1)),
  );

  @override
  Future<GitUpdateProjectResult> executeUpdateProject(
    RepositoryId repositoryId,
    GitUpdateProjectRequest request, {
    GitCancellationToken? cancellationToken,
  }) async {
    executed = true;
    return GitUpdateProjectResult(
      repositoryId: repositoryId,
      request: request,
      state: GitUpdateState.completed,
      status: GitStatusSnapshot(
        repositoryId: repositoryId,
        root: '/workspace/project',
        branch: const GitBranchStatus(head: 'main'),
        changes: const [],
        contentHash: 'updated',
        generation: 2,
      ),
      summary: 'Updated',
    );
  }
}
