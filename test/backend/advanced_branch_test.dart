import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gift/src/backend/branch.dart';
import 'package:gift/src/backend/dart_git_backend.dart';
import 'package:gift/src/backend/error.dart';
import 'package:gift/src/backend/executor.dart';
import 'package:gift/src/backend/repository_service.dart';

void main() {
  test(
    'previews and applies a fast-forward merge with a fresh token',
    () async {
      await withTempDirectory((directory) async {
        await createRepository(directory.path);
        await runGit(directory.path, ['switch', '--create', 'feature']);
        await File('${directory.path}/feature.txt').writeAsString('feature\n');
        await runGit(directory.path, ['add', '--', 'feature.txt']);
        await runGit(directory.path, ['commit', '-m', 'feature']);
        await runGit(directory.path, ['switch', 'main']);

        final backend = DartGitBackend();
        final opened = await backend.openRepository(directory.path);
        final preview = await backend.previewBranchOperation(
          opened.repositoryId,
          const GitBranchOperationRequest(
            operation: GitBranchOperation.merge,
            source: 'feature',
            target: 'main',
          ),
        );

        expect(preview.canExecute, isTrue);
        expect(preview.ahead, 1);
        expect(preview.behind, 0);
        expect(preview.mergeBase, isNotEmpty);
        final result = await backend.executeBranchOperation(
          opened.repositoryId,
          GitBranchOperationRequest(
            operation: GitBranchOperation.merge,
            source: 'feature',
            target: 'main',
            confirmationToken: preview.token,
          ),
        );

        expect(result.state, GitBranchOperationState.completed);
        expect(
          (await backend.getStatus(opened.repositoryId)).branch.head,
          'main',
        );
        expect(
          await runGit(directory.path, [
            'merge-base',
            '--is-ancestor',
            'feature',
            'main',
          ]),
          isEmpty,
        );
      });
    },
  );

  test('rejects a stale preview before deleting an unmerged branch', () async {
    await withTempDirectory((directory) async {
      await createRepository(directory.path);
      await runGit(directory.path, ['switch', '--create', 'unmerged']);
      await File('${directory.path}/unmerged.txt').writeAsString('keep\n');
      await runGit(directory.path, ['add', '--', 'unmerged.txt']);
      await runGit(directory.path, ['commit', '-m', 'unmerged']);
      await runGit(directory.path, ['switch', 'main']);

      final backend = DartGitBackend();
      final opened = await backend.openRepository(directory.path);
      final preview = await backend.previewBranchOperation(
        opened.repositoryId,
        const GitBranchOperationRequest(
          operation: GitBranchOperation.delete,
          source: 'unmerged',
          force: true,
        ),
      );
      await runGit(directory.path, ['switch', '--create', 'other']);
      await runGit(directory.path, ['switch', 'main']);

      await expectLater(
        backend.executeBranchOperation(
          opened.repositoryId,
          GitBranchOperationRequest(
            operation: GitBranchOperation.delete,
            source: 'unmerged',
            force: true,
            confirmationToken: preview.token,
          ),
        ),
        throwsA(
          isA<GitError>().having(
            (error) => error.category,
            'category',
            GitErrorCategory.staleBranchPreview,
          ),
        ),
      );
      expect(
        await runGit(directory.path, ['rev-parse', '--verify', 'unmerged']),
        isNotEmpty,
      );
    });
  });

  test(
    'renames and force-deletes a branch only through reviewed previews',
    () async {
      await withTempDirectory((directory) async {
        await createRepository(directory.path);
        await runGit(directory.path, ['switch', '--create', 'topic']);
        await runGit(directory.path, ['switch', 'main']);
        final backend = DartGitBackend();
        final opened = await backend.openRepository(directory.path);

        final rename = await backend.previewBranchOperation(
          opened.repositoryId,
          const GitBranchOperationRequest(
            operation: GitBranchOperation.rename,
            source: 'topic',
            target: 'renamed',
          ),
        );
        expect(rename.canExecute, isTrue);
        await backend.executeBranchOperation(
          opened.repositoryId,
          GitBranchOperationRequest(
            operation: GitBranchOperation.rename,
            source: 'topic',
            target: 'renamed',
            confirmationToken: rename.token,
          ),
        );

        final deletion = await backend.previewBranchOperation(
          opened.repositoryId,
          const GitBranchOperationRequest(
            operation: GitBranchOperation.delete,
            source: 'renamed',
            force: true,
          ),
        );
        final deleted = await backend.executeBranchOperation(
          opened.repositoryId,
          GitBranchOperationRequest(
            operation: GitBranchOperation.delete,
            source: 'renamed',
            force: true,
            confirmationToken: deletion.token,
          ),
        );
        expect(deleted.historyChanged, isTrue);
        expect(
          await runGit(directory.path, ['branch', '--list', 'renamed']),
          isEmpty,
        );

        await expectLater(
          backend.previewBranchOperation(
            opened.repositoryId,
            const GitBranchOperationRequest(
              operation: GitBranchOperation.rename,
              source: 'main',
              target: 'invalid name',
            ),
          ),
          throwsA(
            isA<GitError>().having(
              (error) => error.category,
              'category',
              GitErrorCategory.invalidBranchName,
            ),
          ),
        );
      });
    },
  );

  test('expires a force-delete preview before it can remove a ref', () async {
    await withTempDirectory((directory) async {
      await createRepository(directory.path);
      await runGit(directory.path, ['switch', '--create', 'topic']);
      await runGit(directory.path, ['switch', 'main']);
      var now = DateTime(2026, 1, 1);
      final backend = DartGitBackend(state: AppState(now: () => now));
      final opened = await backend.openRepository(directory.path);
      final preview = await backend.previewBranchOperation(
        opened.repositoryId,
        const GitBranchOperationRequest(
          operation: GitBranchOperation.delete,
          source: 'topic',
          force: true,
        ),
      );
      now = now.add(const Duration(minutes: 3));

      await expectLater(
        backend.executeBranchOperation(
          opened.repositoryId,
          GitBranchOperationRequest(
            operation: GitBranchOperation.delete,
            source: 'topic',
            force: true,
            confirmationToken: preview.token,
          ),
        ),
        throwsA(
          isA<GitError>().having(
            (error) => error.category,
            'category',
            GitErrorCategory.staleBranchPreview,
          ),
        ),
      );
      expect(
        await runGit(directory.path, ['branch', '--list', 'topic']),
        isNotEmpty,
      );
    });
  });

  test(
    'returns conflict recovery actions and abort preserves reachable commits',
    () async {
      await withTempDirectory((directory) async {
        await createRepository(directory.path);
        await runGit(directory.path, ['switch', '--create', 'conflict']);
        await File('${directory.path}/base.txt').writeAsString('feature\n');
        await runGit(directory.path, ['add', '--', 'base.txt']);
        await runGit(directory.path, ['commit', '-m', 'feature change']);
        await runGit(directory.path, ['switch', 'main']);
        await File('${directory.path}/base.txt').writeAsString('main\n');
        await runGit(directory.path, ['add', '--', 'base.txt']);
        await runGit(directory.path, ['commit', '-m', 'main change']);

        final backend = DartGitBackend();
        final opened = await backend.openRepository(directory.path);
        final preview = await backend.previewBranchOperation(
          opened.repositoryId,
          const GitBranchOperationRequest(
            operation: GitBranchOperation.merge,
            source: 'conflict',
            target: 'main',
          ),
        );
        final conflicted = await backend.executeBranchOperation(
          opened.repositoryId,
          GitBranchOperationRequest(
            operation: GitBranchOperation.merge,
            source: 'conflict',
            target: 'main',
            confirmationToken: preview.token,
          ),
        );
        expect(conflicted.state, GitBranchOperationState.conflicted);
        expect(
          conflicted.recoveryActions,
          containsAll(<GitBranchOperationPhase>[
            GitBranchOperationPhase.continueOperation,
            GitBranchOperationPhase.abort,
          ]),
        );
        final aborted = await backend.executeBranchOperation(
          opened.repositoryId,
          const GitBranchOperationRequest(
            operation: GitBranchOperation.merge,
            phase: GitBranchOperationPhase.abort,
          ),
        );
        expect(aborted.state, GitBranchOperationState.aborted);
        expect(
          await runGit(directory.path, ['rev-parse', 'conflict']),
          isNotEmpty,
        );
        expect((await backend.getStatus(opened.repositoryId)).isClean, isTrue);
      });
    },
  );

  test(
    'supports reviewed cherry-pick, rebase, and pre-cancelled operations',
    () async {
      await withTempDirectory((directory) async {
        await createRepository(directory.path);
        await runGit(directory.path, ['switch', '--create', 'picked']);
        await File('${directory.path}/picked.txt').writeAsString('picked\n');
        await runGit(directory.path, ['add', '--', 'picked.txt']);
        await runGit(directory.path, ['commit', '-m', 'picked']);
        final pickedOid = await runGit(directory.path, ['rev-parse', 'HEAD']);
        await runGit(directory.path, ['switch', 'main']);

        final backend = DartGitBackend();
        final opened = await backend.openRepository(directory.path);
        final cherryPreview = await backend.previewBranchOperation(
          opened.repositoryId,
          GitBranchOperationRequest(
            operation: GitBranchOperation.cherryPick,
            source: pickedOid,
            target: 'main',
          ),
        );
        final cherry = await backend.executeBranchOperation(
          opened.repositoryId,
          GitBranchOperationRequest(
            operation: GitBranchOperation.cherryPick,
            source: pickedOid,
            target: 'main',
            confirmationToken: cherryPreview.token,
          ),
        );
        expect(cherry.state, GitBranchOperationState.completed);

        await runGit(directory.path, ['switch', 'picked']);
        final rebasePreview = await backend.previewBranchOperation(
          opened.repositoryId,
          const GitBranchOperationRequest(
            operation: GitBranchOperation.rebase,
            source: 'picked',
            target: 'main',
          ),
        );
        final rebase = await backend.executeBranchOperation(
          opened.repositoryId,
          GitBranchOperationRequest(
            operation: GitBranchOperation.rebase,
            source: 'picked',
            target: 'main',
            confirmationToken: rebasePreview.token,
          ),
        );
        expect(rebase.state, GitBranchOperationState.completed);

        await runGit(directory.path, ['switch', 'main']);
        final cancelPreview = await backend.previewBranchOperation(
          opened.repositoryId,
          const GitBranchOperationRequest(
            operation: GitBranchOperation.merge,
            source: 'picked',
            target: 'main',
          ),
        );
        final cancellation = GitCancellationToken()..cancel();
        final cancelled = await backend.executeBranchOperation(
          opened.repositoryId,
          GitBranchOperationRequest(
            operation: GitBranchOperation.merge,
            source: 'picked',
            target: 'main',
            confirmationToken: cancelPreview.token,
          ),
          cancellationToken: cancellation,
        );
        expect(cancelled.state, GitBranchOperationState.cancelled);
        expect(
          await runGit(directory.path, ['rev-parse', '--abbrev-ref', 'HEAD']),
          'main',
        );
      });
    },
  );

  test(
    'reports dirty-worktree and detached-head preflight without a token',
    () async {
      await withTempDirectory((directory) async {
        await createRepository(directory.path);
        await runGit(directory.path, ['switch', '--create', 'feature']);
        await runGit(directory.path, ['switch', 'main']);
        await File('${directory.path}/local.txt')
            .writeAsString('uncommitted\n');

        final backend = DartGitBackend();
        final opened = await backend.openRepository(directory.path);
        final dirty = await backend.previewBranchOperation(
          opened.repositoryId,
          const GitBranchOperationRequest(
            operation: GitBranchOperation.merge,
            source: 'feature',
            target: 'main',
          ),
        );
        expect(dirty.dirtyWorktree, isTrue);
        expect(dirty.canExecute, isFalse);
        expect(dirty.token, isNull);

        await File('${directory.path}/local.txt').delete();
        await runGit(directory.path, ['switch', '--detach', 'main']);
        final detached = await backend.previewBranchOperation(
          opened.repositoryId,
          const GitBranchOperationRequest(
            operation: GitBranchOperation.merge,
            source: 'feature',
            target: 'main',
          ),
        );
        expect(detached.detachedHead, isTrue);
        expect(detached.canExecute, isFalse);
        expect(detached.blockingMessage, contains('Switch to a branch'));
      });
    },
  );
}

Future<void> createRepository(String path) async {
  await runGit(path, ['init', '--initial-branch=main']);
  await runGit(path, ['config', 'user.name', 'Gift Test']);
  await runGit(path, ['config', 'user.email', 'gift@example.test']);
  await File('$path/base.txt').writeAsString('base\n');
  await runGit(path, ['add', '--', 'base.txt']);
  await runGit(path, ['commit', '-m', 'base']);
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
  final directory = await Directory.systemTemp.createTemp('gift-advanced-');
  try {
    await action(directory);
  } finally {
    if (directory.existsSync()) await directory.delete(recursive: true);
  }
}
