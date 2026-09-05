import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gift/src/backend/comparison.dart';
import 'package:gift/src/backend/diff.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:gift/src/features/repository/comparison_dialog.dart';

import '../../helpers/git_patch_gateway_stub.dart';

void main() {
  testWidgets('shows revision inputs, changed files, and a selected diff', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(380, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    const repository = RepositoryOpened(
      repositoryId: RepositoryId(value: 'comparison-repository'),
      root: '/workspace/project',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ComparisonDialog(
          gateway: _ComparisonGateway(repository.repositoryId),
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Compare revisions'), findsOneWidget);
    expect(find.byKey(const Key('comparison-left')), findsOneWidget);
    expect(find.byKey(const Key('comparison-right')), findsOneWidget);
    expect(find.text('src/notes.txt'), findsOneWidget);
    expect(find.text('+after'), findsOneWidget);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    await tester.pump();
    expect(tester.takeException(), isNull);
    final titleRect = tester.getRect(find.text('Compare revisions'));
    final modeRect = tester.getRect(
      find.byKey(const Key('comparison-source-mode')),
    );
    expect(titleRect.overlaps(modeRect), isFalse);
  });

  testWidgets('compares a revision with pasted external text', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(520, 640);
    tester.view.devicePixelRatio = 1;
    const repository = RepositoryOpened(
      repositoryId: RepositoryId(value: 'external-comparison-repository'),
      root: '/workspace/project',
    );
    final gateway = _ComparisonGateway(repository.repositoryId);

    await tester.pumpWidget(
      MaterialApp(
        home: ComparisonDialog(gateway: gateway, repository: repository),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('comparison-source-mode')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('comparison-external-text')),
      'from external text\n',
    );
    await tester.enterText(
      find.byKey(const Key('comparison-path')),
      'src/notes.txt',
    );
    await tester.tap(find.byKey(const Key('compare-revisions')));
    await tester.pumpAndSettle();

    expect(gateway.lastSourceRequest?.right.kind, GitComparisonSourceKind.text);
    expect(gateway.lastSourceRequest?.path, 'src/notes.txt');
    expect(find.text('+after'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('navigates between changed files from the diff pane', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(700, 640);
    tester.view.devicePixelRatio = 1;
    const repository = RepositoryOpened(
      repositoryId: RepositoryId(value: 'navigation-comparison-repository'),
      root: '/workspace/project',
    );
    final gateway = _ComparisonGateway(
      repository.repositoryId,
      multipleFiles: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ComparisonDialog(gateway: gateway, repository: repository),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('comparison-next-file')));
    await tester.pumpAndSettle();

    expect(gateway.lastDiffPath, 'src/other.txt');
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders a compact three-way comparison with conflict state', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(520, 640);
    tester.view.devicePixelRatio = 1;
    const repository = RepositoryOpened(
      repositoryId: RepositoryId(value: 'three-way-repository'),
      root: '/workspace/project',
    );
    final gateway = _ComparisonGateway(repository.repositoryId);

    await tester.pumpWidget(
      MaterialApp(
        home: ThreeWayComparisonDialog(
          gateway: gateway,
          repository: repository,
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('three-way-path')),
      'src/notes.txt',
    );
    await tester.tap(find.byKey(const Key('compare-three-way')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('three-way-pane-base')), findsOneWidget);
    expect(find.byKey(const Key('three-way-pane-left')), findsOneWidget);
    expect(find.byKey(const Key('three-way-pane-right')), findsOneWidget);
    expect(find.byKey(const Key('three-way-conflict')), findsOneWidget);
    expect(gateway.threeWayCalls, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('exposes actions for each comparison file', (tester) async {
    const repository = RepositoryOpened(
      repositoryId: RepositoryId(value: 'comparison-file-actions-repository'),
      root: '/workspace/project',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ComparisonDialog(
          gateway: _ComparisonGateway(repository.repositoryId),
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('comparison-file-actions:src/notes.txt')),
    );
    await tester.pumpAndSettle();

    expect(find.text('File history'), findsOneWidget);
    expect(find.text('Blame'), findsOneWidget);
    expect(find.text('Compare revisions'), findsNWidgets(2));
    expect(find.text('Copy path'), findsOneWidget);
    expect(find.text('Copy absolute path'), findsOneWidget);
    expect(find.text('Reveal in file manager'), findsOneWidget);
  });
}

class _ComparisonGateway with GitPatchGatewayStub implements GitGateway {
  _ComparisonGateway(this.repositoryId, {this.multipleFiles = false});

  final RepositoryId repositoryId;
  final bool multipleFiles;
  GitComparisonRequest? lastSourceRequest;
  String? lastDiffPath;
  var threeWayCalls = 0;

  @override
  Future<GitComparisonSnapshot> compareRevisions(
    RepositoryId id,
    String left,
    String right, {
    String? path,
  }) async => GitComparisonSnapshot(
    request: GitComparisonRequest(
      repositoryId: id,
      left: GitComparisonSource(
        kind: GitComparisonSourceKind.revision,
        value: left,
      ),
      right: GitComparisonSource(
        kind: GitComparisonSourceKind.revision,
        value: right,
      ),
      path: path,
    ),
    files: [
      const GitComparisonFile(
        path: 'src/notes.txt',
        status: GitComparisonFileStatus.modified,
      ),
      if (multipleFiles)
        const GitComparisonFile(
          path: 'src/other.txt',
          status: GitComparisonFileStatus.added,
        ),
    ],
    fingerprint: 'comparison',
  );

  @override
  Future<GitComparisonSnapshot> compareSources(
    RepositoryId id,
    GitComparisonSource left,
    GitComparisonSource right, {
    String? path,
  }) async {
    lastSourceRequest = GitComparisonRequest(
      repositoryId: id,
      left: left,
      right: right,
      path: path,
    );
    return GitComparisonSnapshot(
      request: lastSourceRequest!,
      files: [
        const GitComparisonFile(
          path: 'src/notes.txt',
          status: GitComparisonFileStatus.modified,
        ),
        if (multipleFiles)
          const GitComparisonFile(
            path: 'src/other.txt',
            status: GitComparisonFileStatus.added,
          ),
      ],
      fingerprint: 'external-comparison',
    );
  }

  @override
  Future<GitThreeWayComparisonSnapshot> compareThreeWay(
    RepositoryId id,
    GitComparisonSource base,
    GitComparisonSource left,
    GitComparisonSource right, {
    required String path,
  }) async {
    threeWayCalls++;
    return GitThreeWayComparisonSnapshot(
      request: GitThreeWayComparisonRequest(
        repositoryId: id,
        base: base,
        left: left,
        right: right,
        path: path,
      ),
      base: const GitComparisonContent.available('base\n'),
      left: const GitComparisonContent.available('ours\n'),
      right: const GitComparisonContent.available('theirs\n'),
      fingerprint: 'three-way',
    );
  }

  @override
  Future<GitDiffSnapshot> getComparisonDiff(
    RepositoryId id,
    GitComparisonSnapshot comparison,
    String path,
  ) async {
    lastDiffPath = path;
    return GitDiffSnapshot(
      repositoryId: id,
      path: path,
      scope: GitDiffScope.commit,
      contentHash: 'diff',
      lines: const [
        GitDiffLine(kind: GitDiffLineKind.addition, text: '+after'),
      ],
    );
  }
}
