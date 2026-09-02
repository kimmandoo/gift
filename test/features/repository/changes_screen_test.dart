import 'package:branchline/src/backend/domain.dart';
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
    await tester.pump();
    expect(find.text('This path is not tracked by Git yet.'), findsOneWidget);
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

class FakeChangesGateway implements GitGateway {
  FakeChangesGateway({required this.snapshots});

  final List<GitStatusSnapshot> snapshots;
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
}
