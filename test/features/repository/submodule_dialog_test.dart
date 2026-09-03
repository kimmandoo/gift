import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/executor.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:gift/src/backend/status.dart';
import 'package:gift/src/backend/submodule.dart';
import 'package:gift/src/features/repository/submodule_dialog.dart';

import '../../helpers/git_patch_gateway_stub.dart';

void main() {
  testWidgets('shows nested roots and keeps submodule actions explicit', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final repository = const RepositoryOpened(
      repositoryId: RepositoryId(value: 'submodule-ui-repository'),
      root: '/workspace/project',
    );
    final gateway = _SubmoduleGateway(repository);
    await tester.pumpWidget(
      MaterialApp(
        home: SubmoduleDialog(gateway: gateway, repository: repository),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Submodules & nested roots'), findsOneWidget);
    expect(find.text('Nested roots'), findsOneWidget);
    expect(find.text('Uninitialized'), findsOneWidget);
    expect(find.text('Update all recursively'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final initialize = find.byKey(
      const ValueKey('init-submodule:modules/widget'),
    );
    await tester.drag(
      find.byKey(const Key('submodule-list')),
      const Offset(0, -220),
    );
    await tester.pump();
    await tester.ensureVisible(initialize);
    await tester.tap(initialize);
    await tester.pumpAndSettle();
    expect(gateway.lastRequest?.action, GitSubmoduleAction.init);
    expect(gateway.lastRequest?.paths, ['modules/widget']);
    expect(find.text('Initialized'), findsOneWidget);
    expect(find.byKey(const Key('submodule-message')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _SubmoduleGateway with GitPatchGatewayStub implements GitGateway {
  _SubmoduleGateway(this.repository);

  final RepositoryOpened repository;
  GitSubmoduleActionRequest? lastRequest;
  var _initialized = false;

  GitSubmoduleSnapshot get _snapshot => GitSubmoduleSnapshot(
    repositoryId: repository.repositoryId,
    root: repository.root,
    fingerprint: _initialized ? 'initialized' : 'uninitialized',
    modules: [
      GitSubmodule(
        name: 'widget',
        path: 'modules/widget',
        url: 'https://example.test/widget.git',
        expectedOid: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        currentOid: _initialized
            ? 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
            : null,
        states: [
          if (_initialized)
            GitSubmoduleState.initialized
          else
            GitSubmoduleState.uninitialized,
        ],
      ),
    ],
  );

  @override
  Future<GitSubmoduleSnapshot> getSubmodules(RepositoryId repositoryId) async =>
      _snapshot;

  @override
  Future<GitNestedRootSnapshot> getNestedRoots(
    RepositoryId repositoryId,
  ) async => GitNestedRootSnapshot(
    repositoryId: repositoryId,
    fingerprint: 'roots',
    roots: [
      GitNestedRoot(
        path: repository.root,
        relativePath: '',
        kind: GitNestedRootKind.superproject,
      ),
      if (_initialized)
        const GitNestedRoot(
          path: '/workspace/project/modules/widget',
          relativePath: 'modules/widget',
          kind: GitNestedRootKind.submodule,
          submodulePath: 'modules/widget',
        ),
    ],
  );

  @override
  Future<GitSubmoduleActionResult> executeSubmoduleAction(
    RepositoryId repositoryId,
    GitSubmoduleActionRequest request, {
    GitCancellationToken? cancellationToken,
  }) async {
    lastRequest = request;
    _initialized = request.action != GitSubmoduleAction.deinit;
    return GitSubmoduleActionResult(
      repositoryId: repositoryId,
      request: request,
      status: _status,
      snapshot: _snapshot,
      summary: 'Submodule action complete.',
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
