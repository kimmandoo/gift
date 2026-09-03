import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:gift/src/backend/ignore.dart';
import 'package:gift/src/backend/status.dart';
import 'package:gift/src/features/repository/ignore_dialog.dart';

import '../../helpers/git_patch_gateway_stub.dart';

void main() {
  testWidgets(
    'shows metadata states and updates after a scoped ignore action',
    (tester) async {
      addTearDown(tester.view.reset);
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final repository = const RepositoryOpened(
        repositoryId: RepositoryId(value: 'ignore-ui-repository'),
        root: '/workspace/project',
      );
      final gateway = _IgnoreGateway(repository);

      await tester.pumpWidget(
        MaterialApp(
          home: IgnoreDialog(gateway: gateway, repository: repository),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ignore & metadata'), findsOneWidget);
      expect(find.text('Ignored'), findsOneWidget);
      expect(find.text('Untracked'), findsOneWidget);
      expect(tester.takeException(), isNull);

      final ignoreButton = find.byKey(
        const ValueKey('ignore-repository:notes.txt'),
      );
      await tester.drag(
        find.byKey(const Key('ignore-path-list')),
        const Offset(0, -260),
      );
      await tester.pump();
      expect(find.text('Tracked modified'), findsOneWidget);
      await tester.tap(ignoreButton);
      await tester.pump(const Duration(milliseconds: 300));

      expect(gateway.lastRequest?.scope, GitIgnoreScope.repository);
      expect(find.byKey(const Key('ignore-message')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

class _IgnoreGateway with GitPatchGatewayStub implements GitGateway {
  _IgnoreGateway(this.repository)
    : _snapshot = GitIgnoreSnapshot(
        repositoryId: repository.repositoryId,
        fingerprint: 'ignore',
        entries: const [
          GitIgnoreEntry(
            path: 'build/generated.txt',
            kind: GitPathMetadataKind.ignored,
            source: GitIgnoreSource.gitignore,
            sourcePath: '.gitignore',
            line: 1,
            pattern: 'build/',
          ),
          GitIgnoreEntry(
            path: 'notes.txt',
            kind: GitPathMetadataKind.untracked,
          ),
          GitIgnoreEntry(
            path: 'tracked.txt',
            kind: GitPathMetadataKind.trackedModified,
          ),
        ],
      );

  final RepositoryOpened repository;
  GitIgnoreSnapshot _snapshot;
  GitIgnoreRequest? lastRequest;

  @override
  Future<GitIgnoreSnapshot> getIgnoreSnapshot(
    RepositoryId repositoryId,
  ) async => _snapshot;

  @override
  Future<GitIgnoreActionResult> addIgnorePattern(
    RepositoryId repositoryId,
    GitIgnoreRequest request,
  ) async {
    lastRequest = request;
    _snapshot = GitIgnoreSnapshot(
      repositoryId: repositoryId,
      fingerprint: 'after-ignore',
      entries: [
        ..._snapshot.entries.where((entry) => entry.path != request.path),
        GitIgnoreEntry(
          path: request.path,
          kind: GitPathMetadataKind.ignored,
          source: request.scope == GitIgnoreScope.repository
              ? GitIgnoreSource.gitignore
              : GitIgnoreSource.infoExclude,
        ),
      ],
    );
    return GitIgnoreActionResult(
      repositoryId: repositoryId,
      request: request,
      snapshot: _snapshot,
      status: _status,
      pattern: '/${request.path}',
      changed: true,
      summary: 'Ignore rule added.',
    );
  }

  @override
  Future<GitAttributesSnapshot> getAttributes(
    RepositoryId repositoryId, {
    List<String> paths = const [],
  }) async => GitAttributesSnapshot(
    repositoryId: repositoryId,
    fingerprint: 'attributes',
    entries: [
      GitAttributeEntry(
        path: paths.single,
        values: const {'text': 'set', 'eol': 'lf'},
      ),
    ],
  );

  GitStatusSnapshot get _status => GitStatusSnapshot(
    repositoryId: repository.repositoryId,
    root: repository.root,
    branch: const GitBranchStatus(head: 'main'),
    changes: const [],
    contentHash: 'status',
    generation: 1,
  );
}
