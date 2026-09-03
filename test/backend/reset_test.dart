import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gift/src/backend/conflict.dart';
import 'package:gift/src/backend/dart_git_backend.dart';
import 'package:gift/src/backend/error.dart';
import 'package:gift/src/backend/reset.dart';

void main() {
  test(
    'previews and applies a soft reset while preserving the index',
    () async {
      await withTempDirectory((directory) async {
        await createRepository(directory.path);
        final backend = DartGitBackend();
        final opened = await backend.openRepository(directory.path);

        final preview = await backend.previewHistoryRollback(
          opened.repositoryId,
          const GitHistoryRollbackRequest(
            action: GitHistoryRollbackAction.reset,
            targetRevision: 'HEAD^',
            mode: GitResetMode.soft,
          ),
        );

        expect(preview.canExecute, isTrue);
        expect(preview.impact.indexEffect, GitRollbackTreeEffect.preserved);
        expect(preview.impact.worktreeEffect, GitRollbackTreeEffect.preserved);
        final result = await backend.executeHistoryRollback(
          opened.repositoryId,
          preview,
        );

        expect(result.state, GitHistoryRollbackState.completed);
        expect(result.status.staged, isNotEmpty);
        expect(
          await runGit(directory.path, ['rev-parse', 'HEAD']),
          preview.targetHead,
        );
      });
    },
  );

  test(
    'previews and applies every reset mode with an exact tree impact',
    () async {
      for (final mode in GitResetMode.values) {
        await withTempDirectory((directory) async {
          await createRepository(directory.path);
          final backend = DartGitBackend();
          final opened = await backend.openRepository(directory.path);
          final preview = await backend.previewReset(
            opened.repositoryId,
            'HEAD^',
            mode: mode,
          );

          expect(preview.canExecute, isTrue, reason: mode.name);
          expect(preview.targetHead, isNot(preview.currentHead));
          if (mode == GitResetMode.soft) {
            expect(preview.impact.indexEffect, GitRollbackTreeEffect.preserved);
            expect(
              preview.impact.worktreeEffect,
              GitRollbackTreeEffect.preserved,
            );
          } else {
            expect(
              preview.impact.indexEffect,
              GitRollbackTreeEffect.resetToTarget,
            );
            expect(
              preview.impact.worktreeEffect,
              mode == GitResetMode.hard || mode == GitResetMode.keep
                  ? GitRollbackTreeEffect.resetToTarget
                  : GitRollbackTreeEffect.preserved,
            );
          }
          if (mode == GitResetMode.hard) {
            expect(
              preview.impact.potentiallyDiscardedPaths,
              contains('file.txt'),
            );
          }

          final result = await backend.executeHistoryRollback(
            opened.repositoryId,
            preview,
          );
          expect(
            result.state,
            GitHistoryRollbackState.completed,
            reason: mode.name,
          );
          expect(
            await runGit(directory.path, ['rev-parse', 'HEAD']),
            preview.targetHead,
          );
          expect(
            await File('${directory.path}/file.txt').readAsString(),
            mode == GitResetMode.hard || mode == GitResetMode.keep
                ? 'base\n'
                : 'second\n',
            reason: mode.name,
          );
          if (mode == GitResetMode.soft) {
            expect(result.status.staged, isNotEmpty);
          } else if (mode == GitResetMode.mixed) {
            expect(result.status.unstaged, isNotEmpty);
          } else {
            expect(result.status.isClean, isTrue);
          }
        });
      }
    },
  );

  test(
    'undo preserves the latest unpushed commit as worktree changes',
    () async {
      await withTempDirectory((directory) async {
        await createRepository(directory.path);
        final backend = DartGitBackend();
        final opened = await backend.openRepository(directory.path);

        final preview = await backend.previewUndo(opened.repositoryId);
        expect(preview.canExecute, isTrue);
        expect(preview.impact.commitsMoved, 1);
        final result = await backend.executeHistoryRollback(
          opened.repositoryId,
          preview,
        );

        expect(result.state, GitHistoryRollbackState.completed);
        expect(result.status.unstaged, isNotEmpty);
        expect(
          await File('${directory.path}/file.txt').readAsString(),
          'second\n',
        );
        expect(
          await runGit(directory.path, ['rev-parse', 'HEAD']),
          preview.targetHead,
        );
      });
    },
  );

  test('blocks protected, pushed, and dirty history rewrites', () async {
    await withTempDirectory((directory) async {
      await createRepository(directory.path);
      await runGit(directory.path, ['switch', 'main']);
      final backend = DartGitBackend();
      final opened = await backend.openRepository(directory.path);
      final protectedPreview = await backend.previewReset(
        opened.repositoryId,
        'HEAD^',
        mode: GitResetMode.hard,
      );
      expect(protectedPreview.canExecute, isFalse);
      expect(protectedPreview.blockingMessage, contains('protected'));
      await expectLater(
        backend.executeHistoryRollback(opened.repositoryId, protectedPreview),
        throwsA(
          isA<GitError>().having(
            (error) => error.category,
            'category',
            GitErrorCategory.protectedBranch,
          ),
        ),
      );
    });

    await withTempDirectory((directory) async {
      await createRepository(directory.path);
      final remote = await Directory.systemTemp.createTemp('gift-remote-');
      try {
        await runGit(remote.path, ['init', '--bare']);
        await runGit(directory.path, ['remote', 'add', 'origin', remote.path]);
        await runGit(directory.path, [
          'push',
          '--set-upstream',
          'origin',
          'topic',
        ]);
        final backend = DartGitBackend();
        final opened = await backend.openRepository(directory.path);
        final pushedPreview = await backend.previewReset(
          opened.repositoryId,
          'HEAD^',
          mode: GitResetMode.soft,
        );
        expect(pushedPreview.canExecute, isFalse);
        await expectLater(
          backend.executeHistoryRollback(opened.repositoryId, pushedPreview),
          throwsA(
            isA<GitError>().having(
              (error) => error.category,
              'category',
              GitErrorCategory.pushedHistory,
            ),
          ),
        );
      } finally {
        if (remote.existsSync()) await remote.delete(recursive: true);
      }
    });

    await withTempDirectory((directory) async {
      await createRepository(directory.path);
      await File('${directory.path}/file.txt').writeAsString('local\n');
      final backend = DartGitBackend();
      final opened = await backend.openRepository(directory.path);
      final dirtyPreview = await backend.previewReset(
        opened.repositoryId,
        'HEAD^',
        mode: GitResetMode.hard,
      );
      expect(dirtyPreview.canExecute, isFalse);
      expect(dirtyPreview.blockingMessage, contains('local changes'));
      await expectLater(
        backend.executeHistoryRollback(opened.repositoryId, dirtyPreview),
        throwsA(
          isA<GitError>().having(
            (error) => error.category,
            'category',
            GitErrorCategory.dirtyWorktree,
          ),
        ),
      );
    });
  });

  test(
    'rejects a rollback after the preview fingerprint becomes stale',
    () async {
      await withTempDirectory((directory) async {
        await createRepository(directory.path);
        final backend = DartGitBackend();
        final opened = await backend.openRepository(directory.path);
        final preview = await backend.previewReset(
          opened.repositoryId,
          'HEAD^',
          mode: GitResetMode.soft,
        );
        await File('${directory.path}/file.txt').writeAsString('changed\n');

        await expectLater(
          backend.executeHistoryRollback(opened.repositoryId, preview),
          throwsA(
            isA<GitError>().having(
              (error) => error.category,
              'category',
              GitErrorCategory.staleRollbackPreview,
            ),
          ),
        );
        expect(
          await runGit(directory.path, ['rev-parse', 'HEAD']),
          preview.currentHead,
        );
      });
    },
  );

  test(
    'reverts multiple commits into new history without moving HEAD backward',
    () async {
      await withTempDirectory((directory) async {
        await createRepository(directory.path);
        await File('${directory.path}/second.txt').writeAsString('second\n');
        await runGit(directory.path, ['add', '--', 'second.txt']);
        await runGit(directory.path, ['commit', '-m', 'add second file']);
        final secondOid = await runGit(directory.path, ['rev-parse', 'HEAD']);
        await File('${directory.path}/third.txt').writeAsString('third\n');
        await runGit(directory.path, ['add', '--', 'third.txt']);
        await runGit(directory.path, ['commit', '-m', 'add third file']);
        final thirdOid = await runGit(directory.path, ['rev-parse', 'HEAD']);
        final before = await runGit(directory.path, ['rev-parse', 'HEAD']);

        final backend = DartGitBackend();
        final opened = await backend.openRepository(directory.path);
        final preview = await backend.previewRevert(opened.repositoryId, [
          secondOid,
          thirdOid,
        ]);
        expect(preview.canExecute, isTrue);
        final result = await backend.executeHistoryRollback(
          opened.repositoryId,
          preview,
        );

        expect(result.state, GitHistoryRollbackState.completed);
        expect(result.revertedCommitOids, [secondOid, thirdOid]);
        expect(
          await runGit(directory.path, ['rev-parse', 'HEAD']),
          isNot(before),
        );
        expect(await File('${directory.path}/second.txt').exists(), isFalse);
        expect(await File('${directory.path}/third.txt').exists(), isFalse);
        expect(result.status.isClean, isTrue);
      });
    },
  );

  test('returns a recoverable conflicted state for revert', () async {
    await withTempDirectory((directory) async {
      await createRepository(directory.path);
      await runGit(directory.path, ['switch', '--create', 'feature']);
      await File('${directory.path}/file.txt').writeAsString('feature\n');
      await runGit(directory.path, ['add', '--', 'file.txt']);
      await runGit(directory.path, ['commit', '-m', 'feature change']);
      final featureOid = await runGit(directory.path, ['rev-parse', 'HEAD']);
      await runGit(directory.path, ['switch', 'main']);
      await File('${directory.path}/file.txt').writeAsString('main\n');
      await runGit(directory.path, ['add', '--', 'file.txt']);
      await runGit(directory.path, ['commit', '-m', 'main change']);

      final backend = DartGitBackend();
      final opened = await backend.openRepository(directory.path);
      final preview = await backend.previewRevert(opened.repositoryId, [
        featureOid,
      ]);
      expect(preview.canExecute, isTrue);
      final result = await backend.executeHistoryRollback(
        opened.repositoryId,
        preview,
      );
      expect(result.state, GitHistoryRollbackState.conflicted);
      expect(
        result.recoveryActions,
        contains(GitHistoryRollbackRecoveryAction.abortRevert),
      );

      final conflicts = await backend.getConflicts(opened.repositoryId);
      expect(conflicts.operation?.operation, GitConflictOperation.revert);
      final aborted = await backend.abortConflict(
        opened.repositoryId,
        fingerprint: conflicts.fingerprint,
      );
      expect(aborted.state, GitConflictOperationState.aborted);
    });
  });
}

Future<void> createRepository(String path) async {
  await runGit(path, ['init', '--initial-branch=main']);
  await runGit(path, ['config', 'user.name', 'Gift Test']);
  await runGit(path, ['config', 'user.email', 'gift@example.test']);
  await File('$path/file.txt').writeAsString('base\n');
  await runGit(path, ['add', '--', 'file.txt']);
  await runGit(path, ['commit', '-m', 'base']);
  await File('$path/file.txt').writeAsString('second\n');
  await runGit(path, ['add', '--', 'file.txt']);
  await runGit(path, ['commit', '-m', 'second']);
  await runGit(path, ['switch', '--create', 'topic']);
}

Future<String> runGit(String path, List<String> args) async {
  final result = await Process.run('git', args, workingDirectory: path);
  if (result.exitCode != 0) {
    throw StateError('git ${args.join(' ')} failed: ${result.stderr}');
  }
  return '${result.stdout}'.trim();
}

Future<void> withTempDirectory(
  Future<void> Function(Directory directory) action,
) async {
  final directory = await Directory.systemTemp.createTemp('gift-reset-');
  try {
    await action(directory);
  } finally {
    if (directory.existsSync()) await directory.delete(recursive: true);
  }
}
