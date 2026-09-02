import 'package:gitshiba/src/backend/commit.dart';
import 'package:gitshiba/src/backend/branch.dart';
import 'package:gitshiba/src/backend/discard.dart';
import 'package:gitshiba/src/backend/diff.dart';
import 'package:gitshiba/src/backend/domain.dart';
import 'package:gitshiba/src/backend/executor.dart';
import 'package:gitshiba/src/backend/git_gateway.dart';
import 'package:gitshiba/src/backend/history.dart';
import 'package:gitshiba/src/backend/status.dart';
import 'package:gitshiba/src/backend/remote.dart';
import 'package:gitshiba/src/features/repository/history_controller.dart';
import 'package:gitshiba/src/features/repository/history_screen.dart';
import 'package:gitshiba/src/app/pixel_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows commit details and loads the next history page', (
    tester,
  ) async {
    final repository = const RepositoryOpened(
      repositoryId: RepositoryId(value: 'history-repository'),
      root: '/workspace/project',
    );
    final first = makeCommit('a' * 40, 'Add history');
    final second = makeCommit('b' * 40, 'Add branches');
    final gateway = FakeHistoryGateway(
      pages: {
        0: GitHistoryPage(
          repositoryId: repository.repositoryId,
          commits: [first],
          offset: 0,
          limit: 1,
          hasMore: true,
        ),
        1: GitHistoryPage(
          repositoryId: repository.repositoryId,
          commits: [second],
          offset: 1,
          limit: 1,
          hasMore: false,
        ),
      },
    );
    final controller = HistoryController(
      gateway: gateway,
      repositoryId: repository.repositoryId,
      pageSize: 1,
    );
    await controller.refresh();

    await tester.pumpWidget(
      MaterialApp(
        home: HistoryScreen(
          gateway: gateway,
          repository: repository,
          controller: controller,
          autoInitialize: false,
        ),
      ),
    );

    expect(find.text('Add history'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('commit:${first.oid}')));
    await tester.pump();
    expect(find.text(first.oid), findsOneWidget);
    expect(find.text('First body'), findsOneWidget);

    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(find.text('Add branches'), findsOneWidget);
    expect(gateway.historyCalls, [0, 1]);
    controller.dispose();
  });

  testWidgets('stacks the history workspace at a narrow window width', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final repository = const RepositoryOpened(
      repositoryId: RepositoryId(value: 'narrow-history-repository'),
      root: '/workspace/project',
    );
    final commit = makeCommit('c' * 40, 'Narrow history');
    final gateway = FakeHistoryGateway(
      pages: {
        0: GitHistoryPage(
          repositoryId: repository.repositoryId,
          commits: [commit],
          offset: 0,
          limit: 1,
          hasMore: false,
        ),
      },
    );
    final controller = HistoryController(
      gateway: gateway,
      repositoryId: repository.repositoryId,
      pageSize: 1,
    );
    await controller.refresh();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPixelTheme(brightness: Brightness.light),
        home: HistoryScreen(
          gateway: gateway,
          repository: repository,
          controller: controller,
          autoInitialize: false,
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Narrow history'), findsOneWidget);
    expect(find.byKey(const Key('history-status-strip')), findsOneWidget);
    controller.dispose();
  });

  testWidgets('allocates graph width for many active lanes', (tester) async {
    final repository = const RepositoryOpened(
      repositoryId: RepositoryId(value: 'wide-graph-repository'),
      root: '/workspace/project',
    );
    final commit = GitCommit(
      oid: 'd' * 40,
      parents: const [],
      authorName: 'Kimmandoo',
      authorEmail: 'kimmandoo@example.test',
      authoredAt: DateTime(2026, 9, 2, 12),
      subject: 'Wide graph',
      body: '',
      lane: 5,
      laneCount: 6,
      graphHasIncoming: true,
      graphSegments: const [GitGraphSegment(fromLane: 0, toLane: 0)],
    );
    final gateway = FakeHistoryGateway(
      pages: {
        0: GitHistoryPage(
          repositoryId: repository.repositoryId,
          commits: [commit],
          offset: 0,
          limit: 30,
          hasMore: false,
        ),
      },
    );
    final controller = HistoryController(
      gateway: gateway,
      repositoryId: repository.repositoryId,
    );
    await controller.refresh();

    await tester.pumpWidget(
      MaterialApp(
        home: HistoryScreen(
          gateway: gateway,
          repository: repository,
          controller: controller,
          autoInitialize: false,
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(ValueKey('graph:${commit.oid}'))).width,
      104,
    );
    expect(tester.takeException(), isNull);
    controller.dispose();
  });
}

GitCommit makeCommit(String oid, String subject) {
  return GitCommit(
    oid: oid,
    parents: const [],
    authorName: 'Kimmandoo',
    authorEmail: 'kimmandoo@example.test',
    authoredAt: DateTime(2026, 9, 2, 12),
    subject: subject,
    body: 'First body',
  );
}

class FakeHistoryGateway implements GitGateway {
  FakeHistoryGateway({required this.pages});

  final Map<int, GitHistoryPage> pages;
  final historyCalls = <int>[];

  @override
  Future<GitHistoryPage> getHistory(
    RepositoryId repositoryId, {
    int limit = 50,
    int offset = 0,
  }) async {
    historyCalls.add(offset);
    return pages[offset]!;
  }

  @override
  Future<GitInstallation> configureGitPath(String path) =>
      throw UnimplementedError();

  @override
  Future<GitInstallation> getGitInstallation() => throw UnimplementedError();

  @override
  Future<RepositoryOpened> openRepository(String path) =>
      throw UnimplementedError();

  @override
  Future<GitStatusSnapshot> getStatus(RepositoryId repositoryId) =>
      throw UnimplementedError();

  @override
  Future<GitDiffSnapshot> getDiff(
    RepositoryId repositoryId,
    String path, {
    GitDiffScope scope = GitDiffScope.workingTree,
    String? originalPath,
  }) => throw UnimplementedError();

  @override
  Future<GitStatusSnapshot> stage(RepositoryId repositoryId, String path) =>
      throw UnimplementedError();

  @override
  Future<GitStatusSnapshot> unstage(RepositoryId repositoryId, String path) =>
      throw UnimplementedError();

  @override
  Future<GitCommitResult> commit(RepositoryId repositoryId, String message) =>
      throw UnimplementedError();

  @override
  Future<List<GitBranch>> getBranches(RepositoryId repositoryId) =>
      throw UnimplementedError();

  @override
  Future<GitBranchActionResult> createBranch(
    RepositoryId repositoryId,
    String name,
  ) => throw UnimplementedError();

  @override
  Future<GitBranchActionResult> switchBranch(
    RepositoryId repositoryId,
    String name,
  ) => throw UnimplementedError();

  @override
  Future<List<GitRemote>> getRemotes(RepositoryId repositoryId) =>
      throw UnimplementedError();

  @override
  Future<GitRemoteOperationResult> fetch(
    RepositoryId repositoryId,
    String remote, {
    GitCancellationToken? cancellationToken,
  }) => throw UnimplementedError();

  @override
  Future<GitRemoteOperationResult> pull(
    RepositoryId repositoryId,
    String remote, {
    GitCancellationToken? cancellationToken,
  }) => throw UnimplementedError();

  @override
  Future<GitRemoteOperationResult> push(
    RepositoryId repositoryId,
    String remote, {
    GitCancellationToken? cancellationToken,
  }) => throw UnimplementedError();

  @override
  Future<DiscardPreview> createDiscardPreview(
    RepositoryId repositoryId,
    String path,
  ) => throw UnimplementedError();

  @override
  Future<GitStatusSnapshot> discard(
    RepositoryId repositoryId,
    DiscardPreview preview,
  ) => throw UnimplementedError();
}
