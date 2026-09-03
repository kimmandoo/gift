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
    expect(tester.takeException(), isNull);
  });
}

class _ComparisonGateway with GitPatchGatewayStub implements GitGateway {
  _ComparisonGateway(this.repositoryId);

  final RepositoryId repositoryId;

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
    files: const [
      GitComparisonFile(
        path: 'src/notes.txt',
        status: GitComparisonFileStatus.modified,
      ),
    ],
    fingerprint: 'comparison',
  );

  @override
  Future<GitDiffSnapshot> getComparisonDiff(
    RepositoryId id,
    GitComparisonSnapshot comparison,
    String path,
  ) async => GitDiffSnapshot(
    repositoryId: id,
    path: path,
    scope: GitDiffScope.commit,
    contentHash: 'diff',
    lines: const [GitDiffLine(kind: GitDiffLineKind.addition, text: '+after')],
  );
}
