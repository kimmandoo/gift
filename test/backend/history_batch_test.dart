import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gift/src/backend/dart_git_backend.dart';
import 'package:gift/src/backend/error.dart';
import 'package:gift/src/backend/executor.dart';
import 'package:gift/src/backend/history_batch.dart';

void main() {
  test('previews and executes cherry-pick in oldest-first order', () async {
    await _withTempDirectory((directory) async {
      await _createRepository(directory.path);
      await _runGit(directory.path, ['switch', '--create', 'feature']);
      await File('${directory.path}/one.txt').writeAsString('one\n');
      await _runGit(directory.path, ['add', '--', 'one.txt']);
      await _runGit(directory.path, ['commit', '-m', 'one']);
      final one = await _runGit(directory.path, ['rev-parse', 'HEAD']);
      await File('${directory.path}/two.txt').writeAsString('two\n');
      await _runGit(directory.path, ['add', '--', 'two.txt']);
      await _runGit(directory.path, ['commit', '-m', 'two']);
      final two = await _runGit(directory.path, ['rev-parse', 'HEAD']);
      await _runGit(directory.path, ['switch', 'main']);

      final backend = DartGitBackend();
      final repository = await backend.openRepository(directory.path);
      final preview = await backend.previewHistoryBatch(
        repository.repositoryId,
        GitHistoryBatchRequest(
          action: GitHistoryBatchAction.cherryPick,
          revisions: [two, one],
          targetBranch: 'main',
        ),
      );

      expect(preview.displayedOids, [two, one]);
      expect(preview.executionOids, [one, two]);
      expect(
        preview.executionDirection,
        GitHistoryBatchExecutionDirection.oldestToNewest,
      );
      expect(preview.impactedPaths, ['one.txt', 'two.txt']);
      expect(preview.canExecute, isTrue);

      final result = await backend.executeHistoryBatch(
        repository.repositoryId,
        preview,
      );
      expect(result.state, GitHistoryBatchState.completed);
      expect(result.completedOids, [one, two]);
      expect(result.currentOid, isNull);
      expect(result.remainingOids, isEmpty);
      expect(await _runGit(directory.path, ['rev-parse', 'HEAD']), isNot(two));
    });
  });

  test(
    'reports duplicates, contained commits, and dirty state before mutation',
    () async {
      await _withTempDirectory((directory) async {
        await _createRepository(directory.path);
        final base = await _runGit(directory.path, ['rev-parse', 'HEAD']);
        final backend = DartGitBackend();
        final repository = await backend.openRepository(directory.path);

        final duplicate = await backend.previewHistoryBatch(
          repository.repositoryId,
          GitHistoryBatchRequest(
            action: GitHistoryBatchAction.cherryPick,
            revisions: [base, base],
            targetBranch: 'main',
          ),
        );
        expect(duplicate.duplicateOids, [base]);
        expect(duplicate.token, isNull);
        expect(duplicate.blockingMessage, contains('duplicate'));

        final contained = await backend.previewHistoryBatch(
          repository.repositoryId,
          GitHistoryBatchRequest(
            action: GitHistoryBatchAction.cherryPick,
            revisions: [base],
            targetBranch: 'main',
          ),
        );
        expect(contained.containedOids, [base]);
        expect(contained.token, isNull);
        expect(contained.blockingMessage, contains('already contained'));

        await File('${directory.path}/dirty.txt').writeAsString('dirty\n');
        final dirty = await backend.previewHistoryBatch(
          repository.repositoryId,
          GitHistoryBatchRequest(
            action: GitHistoryBatchAction.revert,
            revisions: [base],
            targetBranch: 'main',
          ),
        );
        expect(dirty.dirtyWorktree, isTrue);
        expect(dirty.token, isNull);
        expect(dirty.blockingMessage, contains('Commit or stash'));
      });
    },
  );

  test('previews and executes revert in newest-first order', () async {
    await _withTempDirectory((directory) async {
      await _createRepository(directory.path);
      await File('${directory.path}/one.txt').writeAsString('one\n');
      await _runGit(directory.path, ['add', '--', 'one.txt']);
      await _runGit(directory.path, ['commit', '-m', 'one']);
      final one = await _runGit(directory.path, ['rev-parse', 'HEAD']);
      await File('${directory.path}/two.txt').writeAsString('two\n');
      await _runGit(directory.path, ['add', '--', 'two.txt']);
      await _runGit(directory.path, ['commit', '-m', 'two']);
      final two = await _runGit(directory.path, ['rev-parse', 'HEAD']);

      final backend = DartGitBackend();
      final repository = await backend.openRepository(directory.path);
      final preview = await backend.previewHistoryBatch(
        repository.repositoryId,
        GitHistoryBatchRequest(
          action: GitHistoryBatchAction.revert,
          revisions: [two, one],
          targetBranch: 'main',
        ),
      );
      expect(
        preview.executionDirection,
        GitHistoryBatchExecutionDirection.newestToOldest,
      );
      expect(preview.executionOids, [two, one]);
      expect(preview.canExecute, isTrue);

      final result = await backend.executeHistoryBatch(
        repository.repositoryId,
        preview,
      );
      expect(result.state, GitHistoryBatchState.completed);
      expect(result.completedOids, [two, one]);
      expect(File('${directory.path}/one.txt').existsSync(), isFalse);
      expect(File('${directory.path}/two.txt').existsSync(), isFalse);
    });
  });

  test(
    'rejects a batch preview after the selected repository state changes',
    () async {
      await _withTempDirectory((directory) async {
        await _createRepository(directory.path);
        await _runGit(directory.path, ['switch', '--create', 'feature']);
        await File('${directory.path}/feature.txt').writeAsString('feature\n');
        await _runGit(directory.path, ['add', '--', 'feature.txt']);
        await _runGit(directory.path, ['commit', '-m', 'feature']);
        final feature = await _runGit(directory.path, ['rev-parse', 'HEAD']);
        await _runGit(directory.path, ['switch', 'main']);

        final backend = DartGitBackend();
        final repository = await backend.openRepository(directory.path);
        final preview = await backend.previewHistoryBatch(
          repository.repositoryId,
          GitHistoryBatchRequest(
            action: GitHistoryBatchAction.cherryPick,
            revisions: [feature],
            targetBranch: 'main',
          ),
        );
        await File('${directory.path}/other.txt').writeAsString('other\n');
        await _runGit(directory.path, ['add', '--', 'other.txt']);
        await _runGit(directory.path, ['commit', '-m', 'other']);

        await expectLater(
          backend.executeHistoryBatch(repository.repositoryId, preview),
          throwsA(
            isA<GitError>().having(
              (error) => error.category,
              'category',
              GitErrorCategory.staleRollbackPreview,
            ),
          ),
        );
      });
    },
  );

  test(
    'reports merge mainline requirements before allowing execution',
    () async {
      await _withTempDirectory((directory) async {
        await _createRepository(directory.path);
        await _runGit(directory.path, ['switch', '--create', 'feature']);
        await File('${directory.path}/feature.txt').writeAsString('feature\n');
        await _runGit(directory.path, ['add', '--', 'feature.txt']);
        await _runGit(directory.path, ['commit', '-m', 'feature']);
        await _runGit(directory.path, ['switch', 'main']);
        await File('${directory.path}/main.txt').writeAsString('main\n');
        await _runGit(directory.path, ['add', '--', 'main.txt']);
        await _runGit(directory.path, ['commit', '-m', 'main change']);
        await _runGit(directory.path, [
          'merge',
          '--no-ff',
          'feature',
          '-m',
          'merge',
        ]);
        final merge = await _runGit(directory.path, ['rev-parse', 'HEAD']);
        final parent = await _runGit(directory.path, ['rev-parse', 'HEAD^1']);
        await _runGit(directory.path, ['branch', 'target', parent]);
        await _runGit(directory.path, ['switch', 'target']);

        final backend = DartGitBackend();
        final repository = await backend.openRepository(directory.path);
        final blocked = await backend.previewHistoryBatch(
          repository.repositoryId,
          GitHistoryBatchRequest(
            action: GitHistoryBatchAction.cherryPick,
            revisions: [merge],
            targetBranch: 'target',
          ),
        );
        expect(blocked.mergeCommitOids, [merge]);
        expect(blocked.mergeMainlineRequired, [merge]);
        expect(blocked.token, isNull);

        final reviewed = await backend.previewHistoryBatch(
          repository.repositoryId,
          GitHistoryBatchRequest(
            action: GitHistoryBatchAction.cherryPick,
            revisions: [merge],
            targetBranch: 'target',
            mainlines: {merge: 1},
          ),
        );
        expect(reviewed.mergeMainlineRequired, isEmpty);
        expect(reviewed.canExecute, isTrue);
        final result = await backend.executeHistoryBatch(
          repository.repositoryId,
          reviewed,
        );
        expect(result.state, GitHistoryBatchState.completed);
        expect(result.completedOids, [merge]);
      });
    },
  );

  test('stops before the next commit when cancelled', () async {
    await _withTempDirectory((directory) async {
      await _createRepository(directory.path);
      await _runGit(directory.path, ['switch', '--create', 'feature']);
      await File('${directory.path}/feature.txt').writeAsString('feature\n');
      await _runGit(directory.path, ['add', '--', 'feature.txt']);
      await _runGit(directory.path, ['commit', '-m', 'feature']);
      final feature = await _runGit(directory.path, ['rev-parse', 'HEAD']);
      await _runGit(directory.path, ['switch', 'main']);

      final backend = DartGitBackend();
      final repository = await backend.openRepository(directory.path);
      final preview = await backend.previewHistoryBatch(
        repository.repositoryId,
        GitHistoryBatchRequest(
          action: GitHistoryBatchAction.cherryPick,
          revisions: [feature],
          targetBranch: 'main',
        ),
      );
      final cancellation = GitCancellationToken()..cancel();
      final result = await backend.executeHistoryBatch(
        repository.repositoryId,
        preview,
        cancellationToken: cancellation,
      );

      expect(result.state, GitHistoryBatchState.cancelled);
      expect(result.completedOids, isEmpty);
      expect(result.remainingOids, [feature]);
      expect(
        await _runGit(directory.path, ['rev-parse', 'HEAD']),
        isNot(feature),
      );
    });
  });
  test(
    'recovers one conflict before explicitly continuing the remainder',
    () async {
      await _withTempDirectory((directory) async {
        await _createRepository(directory.path);
        await _runGit(directory.path, ['switch', '--create', 'feature']);
        await File('${directory.path}/base.txt').writeAsString('feature\n');
        await _runGit(directory.path, ['add', '--', 'base.txt']);
        await _runGit(directory.path, ['commit', '-m', 'feature']);
        final feature = await _runGit(directory.path, ['rev-parse', 'HEAD']);
        await _runGit(directory.path, ['switch', 'main']);
        await File('${directory.path}/base.txt').writeAsString('main\n');
        await _runGit(directory.path, ['add', '--', 'base.txt']);
        await _runGit(directory.path, ['commit', '-m', 'main change']);

        final backend = DartGitBackend();
        final repository = await backend.openRepository(directory.path);
        final preview = await backend.previewHistoryBatch(
          repository.repositoryId,
          GitHistoryBatchRequest(
            action: GitHistoryBatchAction.cherryPick,
            revisions: [feature],
            targetBranch: 'main',
          ),
        );
        final conflicted = await backend.executeHistoryBatch(
          repository.repositoryId,
          preview,
        );
        expect(conflicted.state, GitHistoryBatchState.conflicted);
        expect(conflicted.currentOid, feature);
        expect(conflicted.continuationToken, isNotNull);
        expect(
          conflicted.recoveryActions,
          contains(GitHistoryBatchRecoveryAction.continueCurrent),
        );

        await File('${directory.path}/base.txt').writeAsString('resolved\n');
        await _runGit(directory.path, ['add', '--', 'base.txt']);
        final current = conflicted.currentOid!;
        final recovered = await backend.recoverHistoryBatch(
          repository.repositoryId,
          GitHistoryBatchRecoveryRequest(
            action: GitHistoryBatchAction.cherryPick,
            revisions: [feature],
            executionOids: preview.executionOids,
            completedOids: conflicted.completedOids,
            skippedOids: conflicted.skippedOids,
            currentOid: current,
            remainingOids: const [],
            targetBranch: 'main',
            mainlines: const {},
            selectionFingerprint: conflicted.selectionFingerprint,
            recoveryAction: GitHistoryBatchRecoveryAction.continueCurrent,
            continuationToken: conflicted.continuationToken!,
          ),
        );
        expect(recovered.state, GitHistoryBatchState.readyToContinue);
        expect(recovered.completedOids, [feature]);
        expect(recovered.remainingOids, isEmpty);
        expect(
          recovered.recoveryActions,
          contains(GitHistoryBatchRecoveryAction.continueRemaining),
        );

        final completed = await backend.recoverHistoryBatch(
          repository.repositoryId,
          GitHistoryBatchRecoveryRequest(
            action: GitHistoryBatchAction.cherryPick,
            revisions: [feature],
            executionOids: preview.executionOids,
            completedOids: recovered.completedOids,
            skippedOids: recovered.skippedOids,
            currentOid: current,
            remainingOids: const [],
            targetBranch: 'main',
            mainlines: const {},
            selectionFingerprint: recovered.selectionFingerprint,
            recoveryAction: GitHistoryBatchRecoveryAction.continueRemaining,
            continuationToken: recovered.continuationToken!,
          ),
        );
        expect(completed.state, GitHistoryBatchState.completed);
        expect(
          await _runGit(directory.path, ['rev-parse', 'HEAD']),
          isNot(feature),
        );
      });
    },
  );
  test('recovers a conflicted revert sequencer explicitly', () async {
    await _withTempDirectory((directory) async {
      await _createRepository(directory.path);
      await File('${directory.path}/base.txt').writeAsString('selected\n');
      await _runGit(directory.path, ['add', '--', 'base.txt']);
      await _runGit(directory.path, ['commit', '-m', 'selected']);
      final selected = await _runGit(directory.path, ['rev-parse', 'HEAD']);
      await File('${directory.path}/base.txt').writeAsString('later\n');
      await _runGit(directory.path, ['add', '--', 'base.txt']);
      await _runGit(directory.path, ['commit', '-m', 'later']);

      final backend = DartGitBackend();
      final repository = await backend.openRepository(directory.path);
      final preview = await backend.previewHistoryBatch(
        repository.repositoryId,
        GitHistoryBatchRequest(
          action: GitHistoryBatchAction.revert,
          revisions: [selected],
          targetBranch: 'main',
        ),
      );
      final conflicted = await backend.executeHistoryBatch(
        repository.repositoryId,
        preview,
      );
      expect(conflicted.state, GitHistoryBatchState.conflicted);
      expect(conflicted.currentOid, selected);

      await File('${directory.path}/base.txt').writeAsString('resolved\n');
      await _runGit(directory.path, ['add', '--', 'base.txt']);
      final recovered = await backend.recoverHistoryBatch(
        repository.repositoryId,
        GitHistoryBatchRecoveryRequest(
          action: GitHistoryBatchAction.revert,
          revisions: [selected],
          executionOids: preview.executionOids,
          completedOids: conflicted.completedOids,
          skippedOids: conflicted.skippedOids,
          currentOid: selected,
          remainingOids: const [],
          targetBranch: 'main',
          mainlines: const {},
          selectionFingerprint: conflicted.selectionFingerprint,
          recoveryAction: GitHistoryBatchRecoveryAction.continueCurrent,
          continuationToken: conflicted.continuationToken!,
        ),
      );
      expect(recovered.state, GitHistoryBatchState.readyToContinue);

      final completed = await backend.recoverHistoryBatch(
        repository.repositoryId,
        GitHistoryBatchRecoveryRequest(
          action: GitHistoryBatchAction.revert,
          revisions: [selected],
          executionOids: preview.executionOids,
          completedOids: recovered.completedOids,
          skippedOids: recovered.skippedOids,
          currentOid: selected,
          remainingOids: const [],
          targetBranch: 'main',
          mainlines: const {},
          selectionFingerprint: recovered.selectionFingerprint,
          recoveryAction: GitHistoryBatchRecoveryAction.continueRemaining,
          continuationToken: recovered.continuationToken!,
        ),
      );
      expect(completed.state, GitHistoryBatchState.completed);
    });
  });
}

Future<void> _createRepository(String path) async {
  await _runGit(path, ['init', '--initial-branch=main']);
  await _runGit(path, ['config', 'user.name', 'Gift Test']);
  await _runGit(path, ['config', 'user.email', 'gift@example.test']);
  await File('$path/base.txt').writeAsString('base\n');
  await _runGit(path, ['add', '--', 'base.txt']);
  await _runGit(path, ['commit', '-m', 'base']);
}

Future<String> _runGit(String path, List<String> args) async {
  final result = await Process.run('git', args, workingDirectory: path);
  if (result.exitCode != 0) {
    throw StateError('git ${args.join(' ')} failed: ${result.stderr}');
  }
  return '${result.stdout}'.trim();
}

Future<void> _withTempDirectory(
  Future<void> Function(Directory directory) action,
) async {
  final directory = await Directory.systemTemp.createTemp('gift-batch-');
  try {
    await action(directory);
  } finally {
    if (directory.existsSync()) await directory.delete(recursive: true);
  }
}
