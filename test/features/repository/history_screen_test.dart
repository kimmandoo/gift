import 'dart:async';

import 'package:gift/src/backend/commit.dart';
import 'package:gift/src/backend/branch.dart';
import 'package:gift/src/backend/discard.dart';
import 'package:gift/src/backend/diff.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/executor.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:gift/src/backend/history.dart';
import 'package:gift/src/backend/status.dart';
import 'package:gift/src/backend/remote.dart';
import 'package:gift/src/features/repository/history_controller.dart';
import 'package:gift/src/features/repository/history_screen.dart';
import 'package:gift/src/app/pixel_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/git_patch_gateway_stub.dart';

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
          nextCursor: GitHistoryCursor(
            snapshotTips: const [],
            position: 1,
            queryKey: const GitHistoryFilters().queryKey,
          ),
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
  testWidgets('separates changed file rows with visible breathing room', (
    tester,
  ) async {
    final repository = const RepositoryOpened(
      repositoryId: RepositoryId(value: 'history-file-spacing-repository'),
      root: '/workspace/project',
    );
    final commit = makeCommit('j' * 40, 'File spacing');
    final firstFile = const GitCommitFileChange(
      status: GitCommitFileStatus.modified,
      path: 'lib/first.dart',
    );
    final secondFile = const GitCommitFileChange(
      status: GitCommitFileStatus.modified,
      path: 'lib/second.dart',
    );
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
      filesByCommit: {
        commit.oid: [firstFile, secondFile],
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
    await tester.tap(find.byKey(ValueKey('commit:${commit.oid}')));
    await tester.pump();

    final firstTile = find.byKey(const Key('commit-file:lib/first.dart'));
    final secondTile = find.byKey(const Key('commit-file:lib/second.dart'));
    expect(firstTile, findsOneWidget);
    expect(secondTile, findsOneWidget);
    expect(
      tester.getTopLeft(secondTile).dy - tester.getBottomLeft(firstTile).dy,
      greaterThanOrEqualTo(8),
    );
    controller.dispose();
  });

  testWidgets('exposes OID-bound actions from each History commit row', (
    tester,
  ) async {
    final repository = const RepositoryOpened(
      repositoryId: RepositoryId(value: 'history-actions-repository'),
      root: '/workspace/project',
    );
    final commit = makeCommit('d' * 40, 'Context actions');
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
        home: HistoryScreen(
          gateway: gateway,
          repository: repository,
          controller: controller,
          autoInitialize: false,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(ValueKey('commit-actions:${commit.oid}')));
    await tester.pumpAndSettle();

    expect(find.text('Cherry-pick onto current branch'), findsOneWidget);
    expect(find.text('Revert commit'), findsOneWidget);
    expect(find.text('Create branch here'), findsOneWidget);
    expect(find.text('Create tag here'), findsOneWidget);
    expect(find.text('Compare with HEAD'), findsOneWidget);
    expect(find.text('Reset current branch here'), findsOneWidget);
    expect(find.text('Copy full hash'), findsOneWidget);
    expect(find.text('Copy short hash'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('prefills cherry-pick with the full OID and current branch', (
    tester,
  ) async {
    final repository = const RepositoryOpened(
      repositoryId: RepositoryId(value: 'history-cherry-pick-repository'),
      root: '/workspace/project',
    );
    final commit = makeCommit('e' * 40, 'Cherry-pick source');
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
      branches: const [GitBranch(name: 'main', isCurrent: true)],
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
    await tester.pump();
    await tester.tap(find.byKey(ValueKey('commit-actions:${commit.oid}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cherry-pick onto current branch'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('advanced-branch-source')))
          .controller
          ?.text,
      commit.oid,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('advanced-branch-target')))
          .controller
          ?.text,
      'main',
    );
    await tester.tap(find.text('Close').last);
    await tester.pumpAndSettle();
    controller.dispose();
  });

  testWidgets('copy actions use the full OID from the refreshed row', (
    tester,
  ) async {
    final repository = const RepositoryOpened(
      repositoryId: RepositoryId(value: 'history-copy-repository'),
      root: '/workspace/project',
    );
    final first = makeCommit('f' * 40, 'First selected commit');
    final second = makeCommit('a' * 40, 'Refreshed selected commit');
    final copiedValues = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        final arguments = Map<Object?, Object?>.from(call.arguments as Map);
        copiedValues.add(arguments['text'] as String);
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final gateway = FakeHistoryGateway(
      pages: {
        0: GitHistoryPage(
          repositoryId: repository.repositoryId,
          commits: [first],
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
        home: HistoryScreen(
          gateway: gateway,
          repository: repository,
          controller: controller,
          autoInitialize: false,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(ValueKey('commit-actions:${first.oid}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy full hash'));
    await tester.pumpAndSettle();
    expect(copiedValues, [first.oid]);

    gateway.pages[0] = GitHistoryPage(
      repositoryId: repository.repositoryId,
      commits: [second],
      offset: 0,
      limit: 1,
      hasMore: false,
    );
    await controller.refresh();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('commit-actions:${second.oid}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy short hash'));
    await tester.pumpAndSettle();
    expect(copiedValues, [first.oid, second.oid.substring(0, 7)]);
    controller.dispose();
  });
  testWidgets('supports keyboard-accessible non-contiguous selection', (
    tester,
  ) async {
    final repository = const RepositoryOpened(
      repositoryId: RepositoryId(value: 'history-batch-selection-repository'),
      root: '/workspace/project',
    );
    final first = makeCommit('1' * 40, 'First batch commit');
    final second = makeCommit('2' * 40, 'Second batch commit');
    final third = makeCommit('3' * 40, 'Third batch commit');
    final gateway = FakeHistoryGateway(
      pages: {
        0: GitHistoryPage(
          repositoryId: repository.repositoryId,
          commits: [first, second, third],
          offset: 0,
          limit: 3,
          hasMore: false,
        ),
      },
    );
    final controller = HistoryController(
      gateway: gateway,
      repositoryId: repository.repositoryId,
      pageSize: 3,
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
    await tester.pump();

    expect(find.byKey(const Key('history-selection-summary')), findsOneWidget);
    expect(find.byKey(const Key('history-select-mode')), findsOneWidget);
    expect(find.byKey(ValueKey('commit-select:${first.oid}')), findsNothing);
    await tester.tap(find.byKey(const Key('history-select-mode')));
    await tester.pump();
    expect(find.byKey(ValueKey('commit-select:${first.oid}')), findsOneWidget);
    expect(find.text('Select commits for batch actions'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('commit-select:${first.oid}')));
    await tester.tap(find.byKey(ValueKey('commit-select:${third.oid}')));
    await tester.pump();
    expect(find.text('2 commits selected'), findsOneWidget);
    expect(find.byKey(const Key('history-clear-selection')), findsOneWidget);
    await tester.tap(find.byKey(const Key('history-clear-selection')));
    await tester.pump();
    expect(find.text('0 commits selected'), findsOneWidget);
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
    expect(
      tester.getTopLeft(find.byKey(const Key('history-apply-filters'))).dy,
      greaterThan(
        tester.getTopLeft(find.byKey(const Key('history-search'))).dy,
      ),
    );
    controller.dispose();
  });

  testWidgets('filters history and lazily displays a selected commit diff', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final repository = const RepositoryOpened(
      repositoryId: RepositoryId(value: 'inspect-history-repository'),
      root: '/workspace/project',
    );
    final oid = 'g' * 40;
    final commit = GitCommit(
      oid: oid,
      parents: ['p' * 40],
      authorName: 'Kimmandoo',
      authorEmail: 'kimmandoo@example.test',
      authoredAt: DateTime(2026, 9, 2, 12),
      subject: 'Inspect this change',
      body: 'Details',
      refs: [GitCommitRef(name: 'refs/heads/main', targetOid: oid)],
    );
    final file = const GitCommitFileChange(
      status: GitCommitFileStatus.modified,
      path: 'notes.txt',
    );
    final diff = GitCommitDiff(
      commitOid: oid,
      snapshot: GitDiffSnapshot(
        path: 'notes.txt',
        scope: GitDiffScope.commit,
        lines: [
          const GitDiffLine(kind: GitDiffLineKind.addition, text: '+new'),
          GitDiffLine(kind: GitDiffLineKind.context, text: ' ${'x' * 120}'),
        ],
        contentHash: 'commit-diff',
      ),
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
      filesByCommit: {
        oid: [file],
      },
      diffsByPath: {'$oid:notes.txt': diff},
    );
    final controller = HistoryController(
      gateway: gateway,
      repositoryId: repository.repositoryId,
      pageSize: 30,
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
    await tester.tap(find.byKey(ValueKey('commit:$oid')));
    await tester.pump();
    expect(find.byKey(ValueKey('commit-file:notes.txt')), findsOneWidget);
    expect(find.text('branch: main'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('commit-file:notes.txt')));
    tester
        .widget<ListTile>(find.byKey(const Key('commit-file:notes.txt')))
        .onTap!
        .call();
    await tester.pumpAndSettle();
    await tester.pump();
    expect(find.byKey(const Key('commit-diff')), findsOneWidget);
    expect(
      find.byKey(const Key('commit-file-section:notes.txt')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('history-details-scroll')), findsOneWidget);
    expect(
      tester
          .widget<SingleChildScrollView>(
            find.byKey(const Key('commit-diff-scroll')),
          )
          .scrollDirection,
      Axis.horizontal,
    );
    expect(find.byKey(const Key('commit-diff-scroll')), findsOneWidget);
    expect(find.byKey(const Key('commit-diff-line:0')), findsOneWidget);
    expect(find.byKey(const Key('commit-diff-line:1')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('commit-diff-background:0'))).width,
      tester.getSize(find.byKey(const Key('commit-diff-background:1'))).width,
    );
    final diffBackgroundWidth = tester
        .getSize(find.byKey(const Key('commit-diff-background:0')))
        .width;
    final diffViewportWidth = tester
        .getSize(find.byKey(const Key('commit-diff-scroll')))
        .width;
    expect(diffBackgroundWidth, closeTo(diffViewportWidth, 0.01));
    expect(find.text('+1'), findsOneWidget);
    expect(find.text('-0'), findsOneWidget);
    expect(find.byKey(const Key('copy-commit-diff')), findsOneWidget);
    expect(find.text('+new'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('commit-diff'))).dy,
      greaterThan(
        tester.getTopLeft(find.byKey(const Key('commit-file:notes.txt'))).dy,
      ),
    );

    tester
        .widget<ListTile>(find.byKey(const Key('commit-file:notes.txt')))
        .onTap!
        .call();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('commit-diff')), findsNothing);

    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('history-author-filter')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.enterText(find.byKey(const Key('history-search')), 'Inspect');
    await tester.tap(find.byKey(const Key('history-apply-filters')));
    await tester.pumpAndSettle();
    expect(controller.state.filters.text, 'Inspect');
    expect(tester.takeException(), isNull);
    controller.dispose();
  });

  test('drops an older history response when filters change', () async {
    final oldResponse = Completer<GitHistoryPage>();
    final newResponse = Completer<GitHistoryPage>();
    var requestCount = 0;
    final oldCommit = makeCommit('e' * 40, 'old result');
    final newCommit = makeCommit('f' * 40, 'new result');
    final gateway = FakeHistoryGateway(
      response: (_) {
        requestCount++;
        return requestCount == 1 ? oldResponse.future : newResponse.future;
      },
    );
    final controller = HistoryController(
      gateway: gateway,
      repositoryId: const RepositoryId(value: 'race-repository'),
      pageSize: 1,
    );

    final initial = controller.refresh();
    final filtered = controller.applyFilters(
      const GitHistoryFilters(text: 'new'),
    );
    oldResponse.complete(
      GitHistoryPage(
        repositoryId: const RepositoryId(value: 'race-repository'),
        commits: [oldCommit],
        offset: 0,
        limit: 1,
        hasMore: false,
      ),
    );
    newResponse.complete(
      GitHistoryPage(
        repositoryId: const RepositoryId(value: 'race-repository'),
        commits: [newCommit],
        offset: 0,
        limit: 1,
        hasMore: false,
      ),
    );
    await Future.wait([initial, filtered]);

    expect(controller.state.page?.commits.single.subject, 'new result');
    expect(controller.state.filters.text, 'new');
    controller.dispose();
  });

  test('does not publish commit files from an older selection', () async {
    final oldFiles = Completer<List<GitCommitFileChange>>();
    final newFiles = Completer<List<GitCommitFileChange>>();
    final first = makeCommit('h' * 40, 'first selection');
    final second = makeCommit('i' * 40, 'second selection');
    final gateway = FakeHistoryGateway(
      pages: {
        0: GitHistoryPage(
          repositoryId: const RepositoryId(value: 'detail-race-repository'),
          commits: [first, second],
          offset: 0,
          limit: 30,
          hasMore: false,
        ),
      },
      filesResponse: (oid) =>
          oid == first.oid ? oldFiles.future : newFiles.future,
    );
    final controller = HistoryController(
      gateway: gateway,
      repositoryId: const RepositoryId(value: 'detail-race-repository'),
    );
    await controller.refresh();
    controller.selectCommit(first);
    controller.selectCommit(second);

    oldFiles.complete([
      const GitCommitFileChange(
        status: GitCommitFileStatus.modified,
        path: 'old.txt',
      ),
    ]);
    newFiles.complete([
      const GitCommitFileChange(
        status: GitCommitFileStatus.modified,
        path: 'new.txt',
      ),
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.selectedOid, second.oid);
    expect(controller.state.commitFiles?.single.path, 'new.txt');
    controller.dispose();
  });

  testWidgets('allocates graph width for many active lanes', (tester) async {
    final repository = const RepositoryOpened(
      repositoryId: RepositoryId(value: 'wide-graph-repository'),
      root: '/workspace/project',
    );
    final commit = GitCommit(
      oid: 'd' * 40,
      parents: ['e' * 40, 'f' * 40],
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
      120,
    );
    expect(
      find.bySemanticsLabel('Commit graph · lane 6 of 6 · merge commit'),
      findsOneWidget,
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

class FakeHistoryGateway with GitPatchGatewayStub implements GitGateway {
  FakeHistoryGateway({
    this.pages = const {},
    this.response,
    this.filesByCommit = const {},
    this.diffsByPath = const {},
    this.filesResponse,
    this.branches = const [],
  });

  final Map<int, GitHistoryPage> pages;
  final Future<GitHistoryPage> Function(GitHistoryQuery query)? response;
  final Map<String, List<GitCommitFileChange>> filesByCommit;
  final Map<String, GitCommitDiff> diffsByPath;
  final Future<List<GitCommitFileChange>> Function(String commitOid)?
  filesResponse;
  final List<GitBranch> branches;
  final historyCalls = <int>[];

  @override
  Future<GitHistoryPage> getHistory(
    RepositoryId repositoryId, {
    int limit = 50,
    int offset = 0,
    GitHistoryQuery? query,
  }) async {
    final position = query?.cursor?.position ?? offset;
    historyCalls.add(position);
    final response = this.response;
    if (response != null) {
      return response(query ?? GitHistoryQuery(limit: limit));
    }
    return pages[position]!;
  }

  @override
  Future<GitInstallation> configureGitPath(String path) =>
      throw UnimplementedError();

  @override
  Future<GitInstallation> getGitInstallation() => throw UnimplementedError();

  @override
  Future<GitCommit> getCommit(RepositoryId repositoryId, String commitOid) =>
      throw UnimplementedError();

  @override
  Future<List<GitCommitFileChange>> getCommitFiles(
    RepositoryId repositoryId,
    String commitOid,
  ) async {
    final response = filesResponse;
    if (response != null) return response(commitOid);
    return filesByCommit[commitOid] ?? const [];
  }

  @override
  Future<GitCommitDiff> getCommitDiff(
    RepositoryId repositoryId,
    String commitOid,
    String path, {
    String? originalPath,
  }) => Future.value(diffsByPath['$commitOid:$path']!);

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
  Future<GitCommitResult> commit(
    RepositoryId repositoryId,
    String message, {
    GitCommitOptions options = const GitCommitOptions(),
  }) => throw UnimplementedError();
  @override
  Future<List<GitBranch>> getBranches(RepositoryId repositoryId) async =>
      branches;

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
