import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/branch.dart';
import 'package:gift/src/backend/commit.dart';
import 'package:gift/src/backend/discard.dart';
import 'package:gift/src/backend/diff.dart';
import 'package:gift/src/backend/error.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:gift/src/backend/history.dart';
import 'package:gift/src/backend/executor.dart';
import 'package:gift/src/backend/remote.dart';
import 'package:gift/src/backend/status.dart';
import 'package:gift/src/features/repository/changes_controller.dart';
import 'package:gift/src/features/repository/changes_screen.dart';
import 'package:gift/src/app/pixel_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/git_patch_gateway_stub.dart';

void main() {
  test('refreshes status and clears a selection that disappeared', () async {
    final repository = const RepositoryOpened(
      repositoryId: RepositoryId(value: 'repository-id'),
      root: '/workspace/project',
    );
    final gateway = FakeChangesGateway(
      snapshots: [
        snapshot(repository, changes: [change('lib/app.dart')]),
        snapshot(repository, changes: const <GitChange>[]),
      ],
    );
    final controller = ChangesController(
      gateway: gateway,
      repositoryId: repository.repositoryId,
      pollInterval: const Duration(hours: 1),
    );

    await controller.refresh();
    controller.selectPath('lib/app.dart');
    expect(controller.state.selectedPath, 'lib/app.dart');

    await controller.refresh();
    expect(controller.state.snapshot?.isClean, isTrue);
    expect(controller.state.selectedPath, isNull);
    controller.dispose();
  });

  test('reuses a diff until the status snapshot changes', () async {
    final repository = const RepositoryOpened(
      repositoryId: RepositoryId(value: 'diff-cache-repository'),
      root: '/workspace/project',
    );
    final gateway = FakeChangesGateway(
      snapshots: [
        snapshot(repository, changes: [change('notes.txt')]),
        snapshot(
          repository,
          changes: [change('notes.txt'), change('lib/app.dart')],
        ),
      ],
      diffs: {
        'notes.txt:workingTree': diff(
          repository,
          path: 'notes.txt',
          scope: GitDiffScope.workingTree,
          lines: const [],
        ),
      },
    );
    final controller = ChangesController(
      gateway: gateway,
      repositoryId: repository.repositoryId,
      pollInterval: const Duration(hours: 1),
    );

    await controller.refresh();
    controller.selectPath('notes.txt');
    await controller.loadDiff('notes.txt');
    await controller.loadDiff('notes.txt');
    expect(gateway.diffCalls, 1);

    await controller.refresh();
    await controller.loadDiff('notes.txt');
    expect(gateway.diffCalls, 2);
    controller.dispose();
  });
  test('keeps unchanged background polling visually silent', () async {
    final repository = const RepositoryOpened(
      repositoryId: RepositoryId(value: 'polling-repository'),
      root: '/workspace/project',
    );
    final unchanged = snapshot(repository, changes: const <GitChange>[]);
    final gateway = FakeChangesGateway(snapshots: [unchanged]);
    final controller = ChangesController(
      gateway: gateway,
      repositoryId: repository.repositoryId,
      pollInterval: const Duration(milliseconds: 20),
    );
    final refreshingStates = <bool>[];
    controller.addListener(() {
      refreshingStates.add(controller.state.isRefreshing);
    });

    controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 75));

    expect(gateway.statusCalls, greaterThanOrEqualTo(2));
    expect(refreshingStates, [true, false]);
    controller.dispose();
  });
  test('caps large diffs and deliberately loads the next page', () async {
    final repository = const RepositoryOpened(
      repositoryId: RepositoryId(value: 'large-diff-repository'),
      root: '/workspace/project',
    );
    final lines = List<GitDiffLine>.generate(
      maxRenderedDiffLines + 1,
      (index) =>
          GitDiffLine(kind: GitDiffLineKind.context, text: ' line $index'),
    );
    final gateway = FakeChangesGateway(
      snapshots: [
        snapshot(repository, changes: [change('large.txt')]),
      ],
      diffs: {
        'large.txt:workingTree': GitDiffSnapshot(
          repositoryId: repository.repositoryId,
          path: 'large.txt',
          scope: GitDiffScope.workingTree,
          lines: lines,
          contentHash: 'large-diff',
        ),
      },
    );
    final controller = ChangesController(
      gateway: gateway,
      repositoryId: repository.repositoryId,
      pollInterval: const Duration(hours: 1),
    );

    await controller.refresh();
    controller.selectPath('large.txt');
    await controller.loadDiff('large.txt');
    expect(controller.state.visibleDiffLineCount, maxRenderedDiffLines);
    expect(controller.state.hasMoreDiffLines, isTrue);

    controller.loadMoreDiffLines();
    expect(controller.state.visibleDiffLineCount, maxRenderedDiffLines + 1);
    expect(controller.state.hasMoreDiffLines, isFalse);
    controller.dispose();
  });

  test('keeps a partial selection recoverable after patch rejection', () async {
    final repository = const RepositoryOpened(
      repositoryId: RepositoryId(value: 'rejected-patch-repository'),
      root: '/workspace/project',
    );
    final gateway = FakeChangesGateway(
      snapshots: [
        snapshot(repository, changes: [change('notes.txt')]),
      ],
      diffs: {
        'notes.txt:workingTree': selectableDiff(
          repository,
          path: 'notes.txt',
          scope: GitDiffScope.workingTree,
        ),
      },
      stagePatchError: const GitError(
        category: GitErrorCategory.patchRejected,
        userMessage: 'Git could not apply the selected changes.',
        diagnostic: 'fixture rejected the generated patch',
        retryable: false,
      ),
    );
    final controller = ChangesController(
      gateway: gateway,
      repositoryId: repository.repositoryId,
      pollInterval: const Duration(hours: 1),
    );

    await controller.refresh();
    controller.selectPath('notes.txt');
    await controller.loadDiff('notes.txt');
    controller.toggleDiffHunk(0, true);
    await controller.stageSelectedPatch();

    expect(
      controller.state.mutationError?.category,
      GitErrorCategory.patchRejected,
    );
    expect(controller.state.diff, isNotNull);
    expect(controller.state.selectedDiffHunks, contains(0));
    expect(controller.state.isMutating, isFalse);
    expect(gateway.stagePatchCalls, 1);
    controller.dispose();
  });

  testWidgets('shows changes in independent grouped sections', (tester) async {
    final repository = const RepositoryOpened(
      repositoryId: RepositoryId(value: 'repository-id'),
      root: '/workspace/project',
    );
    final controller = ChangesController(
      gateway: FakeChangesGateway(
        snapshots: [
          snapshot(
            repository,
            changes: [
              change('lib/app.dart'),
              GitChange(
                type: GitChangeType.untracked,
                path: 'notes/todo.txt',
                indexStatus: '?',
                worktreeStatus: '?',
                submoduleStatus: 'N...',
              ),
            ],
          ),
        ],
      ),
      repositoryId: repository.repositoryId,
      pollInterval: const Duration(hours: 1),
    );
    await controller.refresh();

    await tester.pumpWidget(
      MaterialApp(
        home: ChangesScreen(
          gateway: controller.gateway,
          repository: repository,
          controller: controller,
          autoInitialize: false,
        ),
      ),
    );

    expect(find.text('Changes'), findsOneWidget);
    expect(find.text('Unstaged (1)'), findsOneWidget);
    expect(find.text('Untracked (1)'), findsOneWidget);
    expect(find.text('lib/app.dart'), findsOneWidget);
    expect(find.text('notes/todo.txt'), findsOneWidget);

    await tester.tap(find.text('notes/todo.txt'));
    await tester.pumpAndSettle();
    expect(find.text('This path is not tracked by Git yet.'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('loads a selected file diff and switches its scope lazily', (
    tester,
  ) async {
    final repository = const RepositoryOpened(
      repositoryId: RepositoryId(value: 'repository-id'),
      root: '/workspace/project',
    );
    final gateway = FakeChangesGateway(
      snapshots: [
        snapshot(
          repository,
          changes: [
            GitChange(
              type: GitChangeType.tracked,
              path: 'lib/app.dart',
              indexStatus: 'M',
              worktreeStatus: 'M',
              submoduleStatus: 'N...',
            ),
          ],
        ),
      ],
      diffs: {
        'lib/app.dart:workingTree': diff(
          repository,
          path: 'lib/app.dart',
          scope: GitDiffScope.workingTree,
          lines: const [
            GitDiffLine(
              kind: GitDiffLineKind.addition,
              text: '+working change',
              newLineNumber: 2,
            ),
            GitDiffLine(
              kind: GitDiffLineKind.context,
              text: 'context line',
              oldLineNumber: 3,
              newLineNumber: 3,
            ),
          ],
        ),
        'lib/app.dart:staged': diff(
          repository,
          path: 'lib/app.dart',
          scope: GitDiffScope.staged,
          lines: const [
            GitDiffLine(
              kind: GitDiffLineKind.addition,
              text: '+staged change',
              newLineNumber: 2,
            ),
          ],
        ),
      },
    );
    final controller = ChangesController(
      gateway: gateway,
      repositoryId: repository.repositoryId,
      pollInterval: const Duration(hours: 1),
    );
    await controller.refresh();

    await tester.pumpWidget(
      MaterialApp(
        home: ChangesScreen(
          gateway: gateway,
          repository: repository,
          controller: controller,
          autoInitialize: false,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('unstaged:lib/app.dart')));
    await tester.pumpAndSettle();
    expect(find.text('+working change'), findsOneWidget);
    expect(find.byKey(const Key('diff-selection-area')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('diff-line-1')),
      40,
      scrollable: find.descendant(
        of: find.byKey(const Key('diff-lines')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('context line'), findsOneWidget);
    expect(find.byType(SelectableText), findsNothing);
    expect(gateway.diffCalls, 1);

    await tester.tap(find.text('Staged'));
    await tester.pumpAndSettle();
    expect(find.text('+staged change'), findsOneWidget);
    expect(gateway.diffCalls, 2);
    controller.dispose();
  });

  testWidgets('stages the selected path and refreshes its status facet', (
    tester,
  ) async {
    final repository = const RepositoryOpened(
      repositoryId: RepositoryId(value: 'repository-id'),
      root: '/workspace/project',
    );
    final gateway = FakeChangesGateway(
      snapshots: [
        snapshot(repository, changes: [change('lib/app.dart')]),
      ],
      stageSnapshot: snapshot(
        repository,
        changes: [
          GitChange(
            type: GitChangeType.tracked,
            path: 'lib/app.dart',
            indexStatus: 'M',
            worktreeStatus: '.',
            submoduleStatus: 'N...',
          ),
        ],
      ),
    );
    final controller = ChangesController(
      gateway: gateway,
      repositoryId: repository.repositoryId,
      pollInterval: const Duration(hours: 1),
    );
    await controller.refresh();

    await tester.pumpWidget(
      MaterialApp(
        home: ChangesScreen(
          gateway: gateway,
          repository: repository,
          controller: controller,
          autoInitialize: false,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('unstaged:lib/app.dart')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('stage-selected')), findsOneWidget);

    await tester.tap(find.byKey(const Key('stage-selected')));
    await tester.pumpAndSettle();
    expect(gateway.stageCalls, 1);
    expect(find.text('Staged (1)'), findsOneWidget);
    expect(find.byKey(const Key('unstage-selected')), findsOneWidget);

    await tester.tap(find.byKey(const Key('unstage-selected')));
    await tester.pumpAndSettle();
    expect(gateway.unstageCalls, 1);
    expect(find.text('Unstaged (1)'), findsOneWidget);
    expect(find.byKey(const Key('stage-selected')), findsOneWidget);
    controller.dispose();
  });

  testWidgets('confirms discard and removes the selected working-tree change', (
    tester,
  ) async {
    final repository = const RepositoryOpened(
      repositoryId: RepositoryId(value: 'repository-id'),
      root: '/workspace/project',
    );
    final gateway = FakeChangesGateway(
      snapshots: [
        snapshot(repository, changes: [change('lib/app.dart')]),
      ],
      discardPreview: DiscardPreview(
        repositoryId: repository.repositoryId,
        token: 'discard-token',
        path: 'lib/app.dart',
        expiresAt: DateTime(2026, 9, 2, 13),
      ),
      discardSnapshot: snapshot(repository, changes: const <GitChange>[]),
    );
    final controller = ChangesController(
      gateway: gateway,
      repositoryId: repository.repositoryId,
      pollInterval: const Duration(hours: 1),
    );
    await controller.refresh();

    await tester.pumpWidget(
      MaterialApp(
        home: ChangesScreen(
          gateway: gateway,
          repository: repository,
          controller: controller,
          autoInitialize: false,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('unstaged:lib/app.dart')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('discard-selected')));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    expect(find.textContaining('lib/app.dart'), findsWidgets);

    await tester.tap(find.byKey(const Key('confirm-discard')));
    await tester.pumpAndSettle();
    expect(gateway.discardCalls, 1);
    expect(find.text('Working tree is clean.'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('commits staged changes from the editor and refreshes the list', (
    tester,
  ) async {
    final repository = const RepositoryOpened(
      repositoryId: RepositoryId(value: 'repository-id'),
      root: '/workspace/project',
    );
    final gateway = FakeChangesGateway(
      snapshots: [
        snapshot(
          repository,
          changes: [
            GitChange(
              type: GitChangeType.tracked,
              path: 'lib/app.dart',
              indexStatus: 'M',
              worktreeStatus: '.',
              submoduleStatus: 'N...',
            ),
          ],
        ),
      ],
      commitResult: GitCommitResult(
        repositoryId: repository.repositoryId,
        commitOid: '0123456789abcdef0123456789abcdef01234567',
        status: snapshot(repository, changes: const <GitChange>[]),
      ),
    );
    final controller = ChangesController(
      gateway: gateway,
      repositoryId: repository.repositoryId,
      pollInterval: const Duration(hours: 1),
    );
    await controller.refresh();

    await tester.pumpWidget(
      MaterialApp(
        home: ChangesScreen(
          gateway: gateway,
          repository: repository,
          controller: controller,
          autoInitialize: false,
        ),
      ),
    );

    expect(find.text('Commit staged changes'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('commit-message')),
      '수정: café 🚀',
    );
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('commit-staged')))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const Key('commit-staged')));
    await tester.pumpAndSettle();

    expect(gateway.commitCalls, 1);
    expect(gateway.lastCommitMessage, '수정: café 🚀');
    expect(find.byKey(const Key('commit-success')), findsOneWidget);
    expect(find.text('Working tree is clean.'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('shows guided commit options, template controls, and identity', (
    tester,
  ) async {
    final repository = const RepositoryOpened(
      repositoryId: RepositoryId(value: 'repository-id'),
      root: '/workspace/project',
    );
    final stagedSnapshot = snapshot(
      repository,
      changes: [
        GitChange(
          type: GitChangeType.tracked,
          path: 'lib/app.dart',
          indexStatus: 'M',
          worktreeStatus: '.',
          submoduleStatus: 'N...',
        ),
      ],
    );
    final gateway = FakeChangesGateway(
      snapshots: [stagedSnapshot],
      commitResult: GitCommitResult(
        repositoryId: repository.repositoryId,
        commitOid: '0123456789abcdef0123456789abcdef01234567',
        status: snapshot(repository, changes: const <GitChange>[]),
      ),
      commitPreflight: GitCommitPreflight(
        status: stagedSnapshot,
        identity: const GitCommitIdentity(
          localName: 'Gift Test',
          localEmail: 'gift@example.test',
        ),
        hasHead: true,
        options: const GitCommitOptions(),
      ),
      commitTemplate: const GitCommitTemplate(
        path: '/workspace/project/.gitmessage',
        contents: 'Template subject\n\nDetails\n',
      ),
    );
    final controller = ChangesController(
      gateway: gateway,
      repositoryId: repository.repositoryId,
      pollInterval: const Duration(hours: 1),
    );
    await controller.refresh();

    await tester.pumpWidget(
      MaterialApp(
        home: ChangesScreen(
          gateway: gateway,
          repository: repository,
          controller: controller,
          autoInitialize: false,
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('commit-options-toggle')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('commit-amend')), findsOneWidget);
    expect(find.byKey(const Key('commit-signoff')), findsOneWidget);
    expect(find.byKey(const Key('commit-cleanup')), findsOneWidget);
    expect(
      find.textContaining('Replaces the current HEAD commit'),
      findsOneWidget,
    );
    expect(find.textContaining('Identity: Gift Test'), findsOneWidget);

    await tester.drag(
      find.byKey(const Key('commit-options-scroll')),
      const Offset(0, -300),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('commit-load-template')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('commit-message')))
          .controller!
          .text,
      'Template subject\n\nDetails\n',
    );
    await tester.tap(find.byKey(const Key('commit-reset-template')));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('commit-message')))
          .controller!
          .text,
      'Template subject\n\nDetails\n',
    );

    await tester.drag(
      find.byKey(const Key('commit-options-scroll')),
      const Offset(0, 300),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('commit-amend')));
    await tester.tap(find.byKey(const Key('commit-signoff')));
    await tester.enterText(
      find.byKey(const Key('commit-author-name')),
      'Override Author',
    );
    await tester.enterText(
      find.byKey(const Key('commit-author-email')),
      'override@example.test',
    );
    await tester.tap(find.byKey(const Key('commit-staged')));
    await tester.pumpAndSettle();

    expect(gateway.lastCommitOptions?.amend, isTrue);
    expect(gateway.lastCommitOptions?.signOff, isTrue);
    expect(gateway.lastCommitOptions?.author?.email, 'override@example.test');
    controller.dispose();
  });

  testWidgets('refreshes from the visible Ctrl+R shortcut and status strip', (
    tester,
  ) async {
    final repository = const RepositoryOpened(
      repositoryId: RepositoryId(value: 'repository-id'),
      root: '/workspace/project',
    );
    final gateway = FakeChangesGateway(
      snapshots: [snapshot(repository, changes: const <GitChange>[])],
    );
    final controller = ChangesController(
      gateway: gateway,
      repositoryId: repository.repositoryId,
      pollInterval: const Duration(hours: 1),
    );
    await controller.refresh();

    await tester.pumpWidget(
      MaterialApp(
        home: ChangesScreen(
          gateway: gateway,
          repository: repository,
          controller: controller,
          autoInitialize: false,
        ),
      ),
    );
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(gateway.statusCalls, 2);
    expect(find.byKey(const Key('status-strip')), findsOneWidget);
    expect(find.text('Ctrl+R refresh · Ctrl+H history'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('stacks the changes workspace at a narrow window width', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final repository = const RepositoryOpened(
      repositoryId: RepositoryId(value: 'narrow-repository'),
      root: '/workspace/project',
    );
    final gateway = FakeChangesGateway(
      snapshots: [snapshot(repository, changes: const <GitChange>[])],
    );
    final controller = ChangesController(
      gateway: gateway,
      repositoryId: repository.repositoryId,
      pollInterval: const Duration(hours: 1),
    );
    await controller.refresh();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPixelTheme(brightness: Brightness.light),
        home: ChangesScreen(
          gateway: gateway,
          repository: repository,
          controller: controller,
          autoInitialize: false,
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Working tree is clean.'), findsOneWidget);
    expect(find.text('Ctrl+R refresh · Ctrl+H history'), findsNothing);
    expect(find.byKey(const Key('repository-actions-menu')), findsOneWidget);
    await tester.tap(find.byKey(const Key('repository-actions-menu')));
    await tester.pumpAndSettle();
    expect(find.text('SYNC & NAVIGATION'), findsOneWidget);
    expect(find.text('REVIEW & HISTORY'), findsOneWidget);
    expect(find.text('REPOSITORY TOOLS'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    controller.dispose();
  });

  test('selects a line range and sends a bound patch selection', () async {
    final repository = const RepositoryOpened(
      repositoryId: RepositoryId(value: 'partial-repository'),
      root: '/workspace/project',
    );
    final gateway = FakeChangesGateway(
      snapshots: [
        snapshot(repository, changes: [change('notes.txt')]),
      ],
      diffs: {
        'notes.txt:workingTree': selectableDiff(
          repository,
          path: 'notes.txt',
          scope: GitDiffScope.workingTree,
        ),
      },
      stagePatchSnapshot: snapshot(
        repository,
        changes: [
          GitChange(
            type: GitChangeType.tracked,
            path: 'notes.txt',
            indexStatus: 'M',
            worktreeStatus: 'M',
            submoduleStatus: 'N...',
          ),
        ],
      ),
    );
    final controller = ChangesController(
      gateway: gateway,
      repositoryId: repository.repositoryId,
      pollInterval: const Duration(hours: 1),
    );

    await controller.refresh();
    controller.selectPath('notes.txt');
    await controller.loadDiff('notes.txt');
    controller.toggleDiffLine(1, true);
    controller.toggleDiffLine(2, true, extend: true);

    expect(controller.canStagePatch, isTrue);
    expect(controller.state.selectedDiffLines, containsAll([1, 2]));
    await controller.stageSelectedPatch();

    expect(gateway.stagePatchCalls, 1);
    expect(
      gateway.lastStagePatchSelection?.repositoryId,
      repository.repositoryId,
    );
    expect(gateway.lastStagePatchSelection?.path, 'notes.txt');
    expect(gateway.lastStagePatchSelection?.scope, GitDiffScope.workingTree);
    expect(
      gateway.lastStagePatchSelection?.contentHash,
      'partial-diff-workingTree',
    );
    expect(gateway.lastStagePatchSelection?.lineIndexes, containsAll([1, 2]));
    expect(controller.state.mutationError, isNull);
    expect(controller.state.isMutating, isFalse);
    controller.dispose();
  });

  testWidgets('keeps partial staging controls usable in a compact window', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final repository = const RepositoryOpened(
      repositoryId: RepositoryId(value: 'compact-partial-repository'),
      root: '/workspace/project',
    );
    final gateway = FakeChangesGateway(
      snapshots: [
        snapshot(repository, changes: [change('notes.txt')]),
      ],
      diffs: {
        'notes.txt:workingTree': selectableDiff(
          repository,
          path: 'notes.txt',
          scope: GitDiffScope.workingTree,
        ),
      },
      stagePatchSnapshot: snapshot(repository, changes: [change('notes.txt')]),
    );
    final controller = ChangesController(
      gateway: gateway,
      repositoryId: repository.repositoryId,
      pollInterval: const Duration(hours: 1),
    );
    await controller.refresh();

    await tester.pumpWidget(
      MaterialApp(
        home: ChangesScreen(
          gateway: gateway,
          repository: repository,
          controller: controller,
          autoInitialize: false,
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('unstaged:notes.txt')));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('compact-details-scroll')),
      const Offset(0, -320),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('diff-hunk-select-0')));
    await tester.pump();

    expect(
      tester.getSize(find.byKey(const ValueKey('diff-hunk-select-0'))).height,
      lessThanOrEqualTo(24),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('diff-line-select-1'))).height,
      lessThanOrEqualTo(24),
    );
    expect(find.byKey(const Key('stage-selected-patch')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('stage-selected-patch')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('stage-selected-patch')));
    await tester.pumpAndSettle();
    expect(gateway.stagePatchCalls, 1);
    expect(tester.takeException(), isNull);
    controller.dispose();
  });
  testWidgets(
    'opens stable change actions and routes Stage through controller',
    (tester) async {
      final repository = const RepositoryOpened(
        repositoryId: RepositoryId(value: 'context-change-repository'),
        root: '/workspace/project',
      );
      final gateway = FakeChangesGateway(
        snapshots: [
          snapshot(repository, changes: [change('lib/app.dart')]),
        ],
      );
      final controller = ChangesController(
        gateway: gateway,
        repositoryId: repository.repositoryId,
        pollInterval: const Duration(hours: 1),
      );
      await controller.refresh();

      await tester.pumpWidget(
        MaterialApp(
          home: ChangesScreen(
            gateway: gateway,
            repository: repository,
            controller: controller,
            autoInitialize: false,
          ),
        ),
      );
      final row = find.byKey(const ValueKey('unstaged:lib/app.dart'));
      expect(
        find.byKey(const ValueKey('change-actions:lib/app.dart')),
        findsOneWidget,
      );
      final gesture = await tester.startGesture(
        tester.getCenter(row),
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('Stage'), findsOneWidget);
      expect(find.text('Discard'), findsOneWidget);
      await tester.tap(find.text('Stage'));
      await tester.pumpAndSettle();

      expect(gateway.stageCalls, 1);
      controller.dispose();
    },
  );
}

GitChange change(String path) {
  return GitChange(
    type: GitChangeType.tracked,
    path: path,
    indexStatus: '.',
    worktreeStatus: 'M',
    submoduleStatus: 'N...',
  );
}

GitStatusSnapshot snapshot(
  RepositoryOpened repository, {
  required List<GitChange> changes,
}) {
  return GitStatusSnapshot(
    repositoryId: repository.repositoryId,
    root: repository.root,
    branch: const GitBranchStatus(head: 'main'),
    changes: changes,
    contentHash: 'hash-${changes.length}',
    generation: 1,
  );
}

GitDiffSnapshot diff(
  RepositoryOpened repository, {
  required String path,
  required GitDiffScope scope,
  required List<GitDiffLine> lines,
}) {
  return GitDiffSnapshot(
    repositoryId: repository.repositoryId,
    path: path,
    scope: scope,
    lines: lines,
    contentHash: 'diff-${scope.name}',
  );
}

GitDiffSnapshot selectableDiff(
  RepositoryOpened repository, {
  required String path,
  required GitDiffScope scope,
}) {
  final lines = <GitDiffLine>[
    const GitDiffLine(
      kind: GitDiffLineKind.hunkHeader,
      text: '@@ -1,2 +1,3 @@',
      hunkIndex: 0,
    ),
    const GitDiffLine(
      kind: GitDiffLineKind.addition,
      text: '+first selected',
      newLineNumber: 1,
      hunkIndex: 0,
    ),
    const GitDiffLine(
      kind: GitDiffLineKind.deletion,
      text: '-second selected',
      oldLineNumber: 2,
      hunkIndex: 0,
    ),
    const GitDiffLine(
      kind: GitDiffLineKind.context,
      text: 'context',
      oldLineNumber: 3,
      newLineNumber: 2,
      hunkIndex: 0,
    ),
  ];
  return GitDiffSnapshot(
    repositoryId: repository.repositoryId,
    path: path,
    scope: scope,
    lines: lines,
    contentHash: 'partial-diff-${scope.name}',
    hunks: [
      GitDiffHunk(
        index: 0,
        oldStart: 1,
        oldCount: 2,
        newStart: 1,
        newCount: 2,
        section: '',
        lines: lines.skip(1).toList(),
      ),
    ],
  );
}

class FakeChangesGateway with GitPatchGatewayStub implements GitGateway {
  FakeChangesGateway({
    required this.snapshots,
    this.diffs = const {},
    this.stageSnapshot,
    this.unstageSnapshot,
    this.stagePatchSnapshot,
    this.unstagePatchSnapshot,
    this.stagePatchError,
    this.unstagePatchError,
    this.commitResult,
    this.commitPreflight,
    this.commitTemplate,
    this.discardPreview,
    this.discardSnapshot,
  });

  final List<GitStatusSnapshot> snapshots;
  final Map<String, GitDiffSnapshot> diffs;
  final GitStatusSnapshot? stageSnapshot;
  final GitStatusSnapshot? unstageSnapshot;
  final GitStatusSnapshot? stagePatchSnapshot;
  final GitStatusSnapshot? unstagePatchSnapshot;
  final GitError? stagePatchError;
  final GitError? unstagePatchError;
  final GitCommitResult? commitResult;
  final GitCommitPreflight? commitPreflight;
  final GitCommitTemplate? commitTemplate;
  final DiscardPreview? discardPreview;
  final GitStatusSnapshot? discardSnapshot;
  var diffCalls = 0;
  var statusCalls = 0;
  var stageCalls = 0;
  var unstageCalls = 0;
  var stagePatchCalls = 0;
  var unstagePatchCalls = 0;
  GitPatchSelection? lastStagePatchSelection;
  GitPatchSelection? lastUnstagePatchSelection;
  var commitCalls = 0;
  String? lastCommitMessage;
  GitCommitOptions? lastCommitOptions;
  var discardCalls = 0;
  var _index = 0;

  @override
  Future<GitInstallation> configureGitPath(String path) {
    throw UnimplementedError();
  }

  @override
  Future<GitInstallation> getGitInstallation() {
    throw UnimplementedError();
  }

  @override
  Future<RepositoryOpened> openRepository(String path) {
    throw UnimplementedError();
  }

  @override
  Future<GitStatusSnapshot> getStatus(RepositoryId repositoryId) async {
    statusCalls++;
    final snapshot = snapshots[_index];
    if (_index < snapshots.length - 1) _index++;
    return snapshot;
  }

  @override
  Future<GitHistoryPage> getHistory(
    RepositoryId repositoryId, {
    int limit = 50,
    int offset = 0,
    GitHistoryQuery? query,
  }) {
    throw UnimplementedError();
  }

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
  Future<GitDiffSnapshot> getDiff(
    RepositoryId repositoryId,
    String path, {
    GitDiffScope scope = GitDiffScope.workingTree,
    String? originalPath,
  }) async {
    diffCalls++;
    return diffs['$path:${scope.name}'] ??
        GitDiffSnapshot(
          repositoryId: repositoryId,
          path: path,
          scope: scope,
          lines: const [],
          contentHash: 'empty',
        );
  }

  @override
  Future<GitStatusSnapshot> stage(
    RepositoryId repositoryId,
    String path,
  ) async {
    stageCalls++;
    return stageSnapshot ?? snapshots.last;
  }

  @override
  Future<GitStatusSnapshot> unstage(
    RepositoryId repositoryId,
    String path,
  ) async {
    unstageCalls++;
    return unstageSnapshot ?? snapshots.last;
  }

  @override
  Future<GitStatusSnapshot> stagePatch(
    RepositoryId repositoryId,
    GitPatchSelection selection,
  ) async {
    stagePatchCalls++;
    lastStagePatchSelection = selection;
    if (stagePatchError case final error?) throw error;
    return stagePatchSnapshot ?? snapshots.last;
  }

  @override
  Future<GitStatusSnapshot> unstagePatch(
    RepositoryId repositoryId,
    GitPatchSelection selection,
  ) async {
    unstagePatchCalls++;
    lastUnstagePatchSelection = selection;
    if (unstagePatchError case final error?) throw error;
    return unstagePatchSnapshot ?? snapshots.last;
  }

  @override
  Future<GitCommitResult> commit(
    RepositoryId repositoryId,
    String message, {
    GitCommitOptions options = const GitCommitOptions(),
  }) async {
    commitCalls++;
    lastCommitMessage = message;
    lastCommitOptions = options;
    return commitResult!;
  }

  @override
  Future<GitCommitPreflight> preflightCommit(
    RepositoryId repositoryId, {
    GitCommitOptions options = const GitCommitOptions(),
  }) async {
    return commitPreflight!;
  }

  @override
  Future<GitCommitTemplate> loadCommitTemplate(
    RepositoryId repositoryId,
  ) async {
    return commitTemplate ?? const GitCommitTemplate();
  }

  @override
  Future<DiscardPreview> createDiscardPreview(
    RepositoryId repositoryId,
    String path,
  ) async {
    return discardPreview!;
  }

  @override
  Future<GitStatusSnapshot> discard(
    RepositoryId repositoryId,
    DiscardPreview preview,
  ) async {
    discardCalls++;
    return discardSnapshot ?? snapshots.last;
  }
}
