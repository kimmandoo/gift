import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gift/src/backend/dart_git_backend.dart';
import 'package:gift/src/backend/error.dart';
import 'package:gift/src/backend/worktree.dart';

void main() {
  test('lists linked worktrees with branch, head, and current state', () async {
    final fixture = await _createFixture('gift-worktree-');
    addTearDown(() => fixture.root.delete(recursive: true));
    await _git(fixture.repository.path, [
      'worktree',
      'add',
      '--quiet',
      '--detach',
      fixture.linked.path,
      'HEAD',
    ]);

    final backend = DartGitBackend();
    final opened = await backend.openRepository(fixture.repository.path);
    final snapshot = await backend.getWorktrees(opened.repositoryId);

    expect(snapshot.worktrees, hasLength(2));
    expect(snapshot.worktrees.first.isMain, isTrue);
    expect(snapshot.worktrees.first.isCurrent, isTrue);
    expect(snapshot.worktrees.first.branch, 'main');
    expect(snapshot.worktrees.last.path, fixture.linked.path);
    expect(snapshot.worktrees.last.isCurrent, isFalse);
    expect(snapshot.worktrees.last.branch, isNull);
    expect(snapshot.worktrees.last.head, hasLength(40));
  });

  test(
    'creates and opens an isolated worktree with independent status',
    () async {
      final fixture = await _createFixture('gift-worktree-add-');
      addTearDown(() => fixture.root.delete(recursive: true));
      final backend = DartGitBackend();
      final opened = await backend.openRepository(fixture.repository.path);
      final created = await backend.createWorktree(
        opened.repositoryId,
        GitWorktreeCreateRequest(path: fixture.linked.path, branch: 'feature'),
      );

      expect(created.worktree.branch, 'feature');
      final linked = await backend.openWorktree(
        opened.repositoryId,
        created.worktree,
      );
      await File('${fixture.linked.path}/linked.txt').writeAsString('linked\n');
      final mainStatus = await backend.getStatus(opened.repositoryId);
      final linkedStatus = await backend.getStatus(linked.repositoryId);

      expect(linkedStatus.branch.head, 'feature');
      expect(linkedStatus.untracked.map((change) => change.path), [
        'linked.txt',
      ]);
      expect(mainStatus.isClean, isTrue);

      GitError? occupied;
      try {
        await backend.createWorktree(
          opened.repositoryId,
          GitWorktreeCreateRequest(
            path: '${fixture.root.path}/occupied',
            branch: 'feature',
          ),
        );
      } on GitError catch (error) {
        occupied = error;
      }
      expect(occupied?.category, GitErrorCategory.worktreeBranchOccupied);

      final mainRemoval = await backend.previewWorktreeAction(
        opened.repositoryId,
        GitWorktreeActionRequest(
          action: GitWorktreeAction.remove,
          path: opened.root,
          confirmDirty: true,
        ),
      );
      expect(mainRemoval.canExecute, isFalse);
      expect(mainRemoval.blockingMessage, contains('main worktree'));

      final linkedRemoval = await backend.previewWorktreeAction(
        linked.repositoryId,
        GitWorktreeActionRequest(
          action: GitWorktreeAction.remove,
          path: linked.root,
          confirmDirty: true,
        ),
      );
      expect(linkedRemoval.canExecute, isFalse);
      expect(linkedRemoval.blockingMessage, contains('currently open'));
    },
  );

  test(
    'requires dirty confirmation and supports lock and unlock actions',
    () async {
      final fixture = await _createFixture('gift-worktree-actions-');
      addTearDown(() => fixture.root.delete(recursive: true));
      final backend = DartGitBackend();
      final opened = await backend.openRepository(fixture.repository.path);
      final created = await backend.createWorktree(
        opened.repositoryId,
        GitWorktreeCreateRequest(path: fixture.linked.path, branch: 'feature'),
      );
      await File('${fixture.linked.path}/dirty.txt').writeAsString('dirty\n');

      final blocked = await backend.previewWorktreeAction(
        opened.repositoryId,
        GitWorktreeActionRequest(
          action: GitWorktreeAction.remove,
          path: created.worktree.path,
        ),
      );
      expect(blocked.canExecute, isFalse);
      expect(blocked.requiresConfirmation, isTrue);
      expect(blocked.dirtyPaths, contains('dirty.txt'));

      final lockPreview = await backend.previewWorktreeAction(
        opened.repositoryId,
        GitWorktreeActionRequest(
          action: GitWorktreeAction.lock,
          path: created.worktree.path,
          lockReason: 'pause work',
        ),
      );
      await backend.executeWorktreeAction(
        opened.repositoryId,
        lockPreview.request,
      );
      final locked = (await backend.getWorktrees(opened.repositoryId)).worktrees
          .singleWhere((worktree) => worktree.path == created.worktree.path);
      expect(locked.isLocked, isTrue);
      expect(locked.lockReason, 'pause work');

      final removeLocked = await backend.previewWorktreeAction(
        opened.repositoryId,
        GitWorktreeActionRequest(
          action: GitWorktreeAction.remove,
          path: created.worktree.path,
          confirmDirty: true,
        ),
      );
      expect(removeLocked.canExecute, isFalse);
      expect(removeLocked.blockingMessage, contains('Unlock'));

      final unlockPreview = await backend.previewWorktreeAction(
        opened.repositoryId,
        GitWorktreeActionRequest(
          action: GitWorktreeAction.unlock,
          path: created.worktree.path,
        ),
      );
      await backend.executeWorktreeAction(
        opened.repositoryId,
        unlockPreview.request,
      );
      final removePreview = await backend.previewWorktreeAction(
        opened.repositoryId,
        GitWorktreeActionRequest(
          action: GitWorktreeAction.remove,
          path: created.worktree.path,
          confirmDirty: true,
        ),
      );
      expect(removePreview.canExecute, isTrue);
      await backend.executeWorktreeAction(
        opened.repositoryId,
        removePreview.request,
      );
      expect(Directory(fixture.linked.path).existsSync(), isFalse);
    },
  );

  test(
    'prunes a manually deleted worktree record without touching the main one',
    () async {
      final fixture = await _createFixture('gift-worktree-prune-');
      addTearDown(() => fixture.root.delete(recursive: true));
      final backend = DartGitBackend();
      final opened = await backend.openRepository(fixture.repository.path);
      final created = await backend.createWorktree(
        opened.repositoryId,
        GitWorktreeCreateRequest(path: fixture.linked.path, branch: 'feature'),
      );
      await Directory(created.worktree.path).delete(recursive: true);

      final snapshot = await backend.getWorktrees(opened.repositoryId);
      final stale = snapshot.worktrees.singleWhere(
        (worktree) => worktree.path == created.worktree.path,
      );
      expect(stale.isPrunable, isTrue);
      final preview = await backend.previewWorktreeAction(
        opened.repositoryId,
        GitWorktreeActionRequest(
          action: GitWorktreeAction.prune,
          path: stale.path,
        ),
      );
      expect(preview.canExecute, isTrue);
      final result = await backend.executeWorktreeAction(
        opened.repositoryId,
        preview.request,
      );

      expect(result.snapshot.worktrees, hasLength(1));
      expect(result.snapshot.worktrees.single.isMain, isTrue);
      expect(result.status.branch.head, 'main');
    },
  );
}

class _WorktreeFixture {
  const _WorktreeFixture({
    required this.root,
    required this.repository,
    required this.linked,
  });

  final Directory root;
  final Directory repository;
  final Directory linked;
}

Future<_WorktreeFixture> _createFixture(String prefix) async {
  final root = await Directory.systemTemp.createTemp(prefix);
  final repository = Directory('${root.path}/repository');
  final linked = Directory('${root.path}/feature');
  await repository.create();
  await _git(repository.path, ['init', '--quiet']);
  await _git(repository.path, ['config', 'user.name', 'Worktree Tester']);
  await _git(repository.path, ['config', 'user.email', 'worktree@test']);
  await File('${repository.path}/README.md').writeAsString('main\n');
  await _git(repository.path, ['add', '--', 'README.md']);
  await _git(repository.path, ['commit', '--quiet', '-m', 'main']);
  await _git(repository.path, ['branch', '-M', 'main']);
  return _WorktreeFixture(root: root, repository: repository, linked: linked);
}

Future<void> _git(String cwd, List<String> args) async {
  final result = await Process.run('git', args, workingDirectory: cwd);
  if (result.exitCode != 0) {
    throw ProcessException(
      'git',
      args,
      '${result.stdout}\n${result.stderr}',
      result.exitCode,
    );
  }
}
