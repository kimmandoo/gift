import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gift/src/backend/dart_git_backend.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/error.dart';
import 'package:gift/src/backend/interactive_rebase.dart';

void main() {
  test(
    'executes a machine-owned reorder and keeps recovery evidence',
    () async {
      await withTempDirectory((directory) async {
        await createRepository(directory.path);
        await runGit(directory.path, ['switch', '--create', 'topic']);
        await commitFile(directory.path, 'one.txt', 'one\n', 'one');
        await commitFile(directory.path, 'two.txt', 'two\n', 'two');
        await commitFile(directory.path, 'three.txt', 'three\n', 'three');

        final backend = DartGitBackend();
        final opened = await backend.openRepository(directory.path);
        final upstream = await runGit(directory.path, ['rev-parse', 'main']);
        final plan = await readPlan(
          directory.path,
          upstream,
          opened.repositoryId,
        );
        final reordered = plan.reorder(2, 1);
        final preview = await backend.previewInteractiveRebase(
          opened.repositoryId,
          reordered,
        );
        final result = await backend.executeInteractiveRebase(
          opened.repositoryId,
          preview,
        );

        expect(result.state, GitInteractiveRebaseExecutionState.completed);
        expect(result.status.isClean, isTrue);
        expect(
          result.originalCommitOids,
          reordered.entries.map((entry) => entry.originalOid),
        );
        expect(result.rewrittenCommitOids, hasLength(3));
        expect(result.recoveryRefs, isNotEmpty);
        expect(result.recoveryRefs.first, startsWith('refs/gift/rebase/'));
        expect(
          await runGit(directory.path, ['log', '--format=%s', '--reverse']),
          'base\none\nthree\ntwo',
        );
      });
    },
  );

  test(
    'pauses on edit and exposes explicit continue and abort recovery',
    () async {
      await withTempDirectory((directory) async {
        await createRepository(directory.path);
        await runGit(directory.path, ['switch', '--create', 'topic']);
        await commitFile(directory.path, 'one.txt', 'one\n', 'one');
        await commitFile(directory.path, 'two.txt', 'two\n', 'two');

        final backend = DartGitBackend();
        final opened = await backend.openRepository(directory.path);
        final upstream = await runGit(directory.path, ['rev-parse', 'main']);
        final plan = await readPlan(
          directory.path,
          upstream,
          opened.repositoryId,
        );
        final editPlan = plan.withAction(1, GitInteractiveRebaseAction.edit);
        final preview = await backend.previewInteractiveRebase(
          opened.repositoryId,
          editPlan,
        );
        final paused = await backend.executeInteractiveRebase(
          opened.repositoryId,
          preview,
        );

        expect(paused.state, GitInteractiveRebaseExecutionState.paused);
        expect(
          paused.recoveryActions,
          containsAll(<GitInteractiveRebaseRecoveryAction>[
            GitInteractiveRebaseRecoveryAction.continueOperation,
            GitInteractiveRebaseRecoveryAction.skip,
            GitInteractiveRebaseRecoveryAction.abort,
          ]),
        );
        expect(paused.recoveryFingerprint, isNotNull);

        final completed = await backend.recoverInteractiveRebase(
          opened.repositoryId,
          GitInteractiveRebaseRecoveryRequest(
            action: GitInteractiveRebaseRecoveryAction.continueOperation,
            fingerprint: paused.recoveryFingerprint!,
          ),
        );
        expect(completed.state, GitInteractiveRebaseExecutionState.completed);
        expect(completed.recoveryActions, isEmpty);
        expect(completed.status.isClean, isTrue);
      });
    },
  );

  test('applies reword, squash, fixup, and drop todo actions', () async {
    await withTempDirectory((directory) async {
      await createRepository(directory.path);
      await runGit(directory.path, ['switch', '--create', 'topic']);
      await commitFile(directory.path, 'one.txt', 'one\n', 'one');
      await commitFile(directory.path, 'two.txt', 'two\n', 'two');
      await commitFile(directory.path, 'three.txt', 'three\n', 'three');
      await commitFile(directory.path, 'four.txt', 'four\n', 'four');

      final backend = DartGitBackend();
      final opened = await backend.openRepository(directory.path);
      final upstream = await runGit(directory.path, ['rev-parse', 'main']);
      final plan = await readPlan(
        directory.path,
        upstream,
        opened.repositoryId,
      );
      final editedPlan = plan
          .withAction(1, GitInteractiveRebaseAction.reword)
          .withAction(2, GitInteractiveRebaseAction.squash)
          .withAction(3, GitInteractiveRebaseAction.drop);
      final preview = await backend.previewInteractiveRebase(
        opened.repositoryId,
        editedPlan,
      );
      final result = await backend.executeInteractiveRebase(
        opened.repositoryId,
        preview,
      );

      expect(result.state, GitInteractiveRebaseExecutionState.completed);
      expect(result.originalCommitOids, hasLength(4));
      expect(result.rewrittenCommitOids, hasLength(3));
      expect(
        await runGit(directory.path, ['rev-list', '--count', 'HEAD']),
        '3',
      );
      expect(await File('${directory.path}/four.txt').exists(), isFalse);
      expect(result.status.isClean, isTrue);
    });
  });

  test(
    'aborts a paused rebase and leaves the original head reachable',
    () async {
      await withTempDirectory((directory) async {
        await createRepository(directory.path);
        await runGit(directory.path, ['switch', '--create', 'topic']);
        await commitFile(directory.path, 'one.txt', 'one\n', 'one');

        final backend = DartGitBackend();
        final opened = await backend.openRepository(directory.path);
        final upstream = await runGit(directory.path, ['rev-parse', 'main']);
        final plan = await readPlan(
          directory.path,
          upstream,
          opened.repositoryId,
        );
        final editPlan = plan.withAction(0, GitInteractiveRebaseAction.edit);
        final preview = await backend.previewInteractiveRebase(
          opened.repositoryId,
          editPlan,
        );
        final paused = await backend.executeInteractiveRebase(
          opened.repositoryId,
          preview,
        );
        final aborted = await backend.recoverInteractiveRebase(
          opened.repositoryId,
          GitInteractiveRebaseRecoveryRequest(
            action: GitInteractiveRebaseRecoveryAction.abort,
            fingerprint: paused.recoveryFingerprint!,
          ),
        );

        expect(aborted.state, GitInteractiveRebaseExecutionState.aborted);
        expect(aborted.recoveryActions, isEmpty);
        expect(
          await runGit(directory.path, ['rev-parse', 'HEAD']),
          paused.previousHead,
        );
        expect(aborted.status.isClean, isTrue);
      });
    },
  );

  test('rejects a preview after the reviewed commit range changes', () async {
    await withTempDirectory((directory) async {
      await createRepository(directory.path);
      await runGit(directory.path, ['switch', '--create', 'topic']);
      await commitFile(directory.path, 'one.txt', 'one\n', 'one');

      final backend = DartGitBackend();
      final opened = await backend.openRepository(directory.path);
      final upstream = await runGit(directory.path, ['rev-parse', 'main']);
      final plan = await readPlan(
        directory.path,
        upstream,
        opened.repositoryId,
      );
      final preview = await backend.previewInteractiveRebase(
        opened.repositoryId,
        plan,
      );
      await commitFile(directory.path, 'two.txt', 'two\n', 'two');

      await expectLater(
        backend.executeInteractiveRebase(opened.repositoryId, preview),
        throwsA(
          isA<GitError>().having(
            (error) => error.category,
            'category',
            GitErrorCategory.staleRollbackPreview,
          ),
        ),
      );
    });
  });
}

Future<GitInteractiveRebasePlan> readPlan(
  String path,
  String upstream,
  RepositoryId repositoryId,
) async {
  final oids = (await runGit(path, [
    'rev-list',
    '--reverse',
    '$upstream..HEAD',
  ])).split('\n').where((oid) => oid.isNotEmpty).toList(growable: false);
  return GitInteractiveRebasePlan(
    repositoryId: repositoryId,
    upstreamRevision: upstream,
    entries: [
      for (var index = 0; index < oids.length; index++)
        GitInteractiveRebaseEntry(
          originalOid: oids[index],
          subject: 'commit ${index + 1}',
          action: GitInteractiveRebaseAction.pick,
          originalIndex: index,
        ),
    ],
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

Future<void> commitFile(
  String path,
  String file,
  String contents,
  String message,
) async {
  await File('$path/$file').writeAsString(contents);
  await runGit(path, ['add', '--', file]);
  await runGit(path, ['commit', '-m', message]);
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
  final directory = await Directory.systemTemp.createTemp('gift-rebase-');
  try {
    await action(directory);
  } finally {
    if (directory.existsSync()) await directory.delete(recursive: true);
  }
}
