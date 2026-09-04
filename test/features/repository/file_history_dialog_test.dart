import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gift/src/app/pixel_theme.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/file_history.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:gift/src/backend/history.dart';
import 'package:gift/src/backend/status.dart';
import 'package:gift/src/features/repository/file_history_dialog.dart';

import '../../helpers/git_patch_gateway_stub.dart';

void main() {
  testWidgets('switches between compact file history and blame views', (
    tester,
  ) async {
    final repository = const RepositoryOpened(
      repositoryId: RepositoryId(value: 'file-history-ui-repository'),
      root: '/workspace/project',
    );
    final gateway = _FileHistoryGateway(repository.repositoryId);
    await tester.binding.setSurfaceSize(const Size(420, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPixelTheme(),
        home: FileHistoryDialog(
          gateway: gateway,
          repository: repository,
          initialPath: 'notes.txt',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('load-file-history')));
    await tester.pumpAndSettle();
    expect(find.text('Load history'), findsOneWidget);
    expect(find.text('Load blame'), findsOneWidget);
    expect(find.byKey(const Key('file-history-list')), findsOneWidget);
    final blameButtonRect = tester.getRect(
      find.byKey(const Key('load-file-blame')),
    );
    final followRect = tester.getRect(
      find.byKey(const Key('file-history-follow')),
    );
    expect(followRect.top - blameButtonRect.bottom, greaterThanOrEqualTo(8));
    expect(
      find.byKey(const Key('file-history-entry:1234567890abcdef')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('get-from-revision:1234567890abcdef')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Restore'), findsOneWidget);
    expect(find.byKey(const Key('file-history-message')), findsOneWidget);

    await tester.tap(find.byKey(const Key('load-file-blame')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('blame-list')), findsOneWidget);
    expect(find.byKey(const Key('blame-line:1')), findsOneWidget);
    expect(gateway.blameCalls, 1);
  });

  testWidgets(
    'keeps file history controls usable in a narrow large-text window',
    (tester) async {
      final repository = const RepositoryOpened(
        repositoryId: RepositoryId(value: 'file-history-narrow-repository'),
        root: '/workspace/project',
      );
      final gateway = _FileHistoryGateway(repository.repositoryId);
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildPixelTheme(),
          home: FileHistoryDialog(
            gateway: gateway,
            repository: repository,
            initialPath: 'notes.txt',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('load-file-history')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('file-history-lines-toggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('file-history-line-start')), findsOneWidget);
      expect(find.byKey(const Key('file-history-line-end')), findsOneWidget);
      final lineStartRect = tester.getRect(
        find.byKey(const Key('file-history-line-start')),
      );
      final followAfterRangeRect = tester.getRect(
        find.byKey(const Key('file-history-follow')),
      );
      expect(
        lineStartRect.top - followAfterRangeRect.bottom,
        greaterThanOrEqualTo(8),
      );
      expect(tester.takeException(), isNull);
    },
  );
}

class _FileHistoryGateway with GitPatchGatewayStub implements GitGateway {
  _FileHistoryGateway(this.repositoryId);

  final RepositoryId repositoryId;
  var blameCalls = 0;
  var getCalls = 0;

  @override
  Future<GitFileHistorySnapshot> getFileHistory(
    RepositoryId id,
    GitFileHistoryQuery query,
  ) async => GitFileHistorySnapshot(
    repositoryId: id,
    query: query,
    entries: [
      GitFileHistoryEntry(
        commit: GitCommit(
          oid: '1234567890abcdef',
          parents: const [],
          authorName: 'History Tester',
          authorEmail: 'history@test',
          authoredAt: DateTime.utc(2026, 1, 1),
          subject: 'Add notes',
          body: '',
        ),
        path: query.path,
      ),
    ],
    fingerprint: 'history',
    workingTreeFingerprint: 'worktree',
    hasMore: false,
  );

  @override
  Future<GitBlameSnapshot> getBlame(
    RepositoryId id,
    String path, {
    GitBlameOptions options = const GitBlameOptions(),
  }) async {
    blameCalls++;
    return GitBlameSnapshot(
      repositoryId: id,
      path: path,
      options: options,
      fingerprint: 'blame',
      lines: [
        GitBlameLine(
          lineNumber: 1,
          text: 'first',
          commitOid: '1234567890abcdef',
          authorName: 'History Tester',
          authoredAt: DateTime.utc(2026, 1, 1),
          originalLineNumber: 1,
          originalPath: path,
        ),
      ],
    );
  }

  @override
  Future<GitRevisionGetResult> getFileFromRevision(
    RepositoryId id,
    GitFileHistorySnapshot history,
    String revision,
  ) async {
    getCalls++;
    return GitRevisionGetResult(
      repositoryId: id,
      path: history.query.path,
      revision: revision,
      outcome: GitRevisionGetOutcome.restored,
      status: GitStatusSnapshot(
        repositoryId: id,
        root: '/workspace/project',
        branch: const GitBranchStatus(head: 'main'),
        changes: const [],
        contentHash: 'status',
        generation: 1,
      ),
      summary: 'Restored from $revision.',
    );
  }
}
