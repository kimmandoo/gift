import 'package:branchline/src/backend/domain.dart';
import 'package:branchline/src/backend/diff.dart';
import 'package:branchline/src/backend/git_gateway.dart';
import 'package:branchline/src/backend/status.dart';
import 'package:branchline/src/features/repository/changes_controller.dart';
import 'package:branchline/src/features/repository/changes_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

class FakeChangesGateway implements GitGateway {
  FakeChangesGateway({
    required this.snapshots,
    this.diffs = const {},
    this.stageSnapshot,
    this.unstageSnapshot,
  });

  final List<GitStatusSnapshot> snapshots;
  final Map<String, GitDiffSnapshot> diffs;
  final GitStatusSnapshot? stageSnapshot;
  final GitStatusSnapshot? unstageSnapshot;
  var diffCalls = 0;
  var stageCalls = 0;
  var unstageCalls = 0;
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
    final snapshot = snapshots[_index];
    if (_index < snapshots.length - 1) _index++;
    return snapshot;
  }

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
}
