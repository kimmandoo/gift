import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gift/src/backend/conflict.dart';
import 'package:gift/src/backend/dart_git_backend.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/interactive_rebase.dart';

void main() {
  test('previews a linear plan and blocks unsafe repository states', () async {
    await withTempDirectory((directory) async {
      await createRepository(directory.path);
      await runGit(directory.path, ['switch', '--create', 'topic']);
      await commitFile(directory.path, 'one.txt', 'one\n', 'one');
      await commitFile(directory.path, 'two.txt', 'two\n', 'two');
      final upstream = await runGit(directory.path, ['rev-parse', 'main']);

      final backend = DartGitBackend();
      final opened = await backend.openRepository(directory.path);
      final plan = await readPlan(
        directory.path,
        upstream,
        opened.repositoryId,
      );
      final clean = await backend.previewInteractiveRebase(
        opened.repositoryId,
        plan,
      );

      expect(clean.canExecute, isTrue);
      expect(clean.currentBranch, 'topic');
      expect(
        clean.currentHead,
        await runGit(directory.path, ['rev-parse', 'HEAD']),
      );
      expect(clean.upstreamHead, upstream);
      expect(clean.selectedCommitCount, 2);
      expect(clean.mergeCommitCount, 0);
      expect(clean.dirtyWorktree, isFalse);
      expect(clean.detachedHead, isFalse);
      expect(clean.branchProtected, isFalse);
      expect(clean.pushedCommits, isFalse);
      expect(clean.operationInProgress, isNull);
      expect(clean.token, isNotNull);

      await File('${directory.path}/local.txt').writeAsString('dirty\n');
      final dirty = await backend.previewInteractiveRebase(
        opened.repositoryId,
        plan,
      );
      expect(dirty.dirtyWorktree, isTrue);
      expect(dirty.canExecute, isFalse);
      expect(dirty.token, isNull);
      expect(dirty.blockingMessage, contains('Commit or stash'));

      await File('${directory.path}/local.txt').delete();
      await runGit(directory.path, ['switch', '--detach', 'topic']);
      final detached = await backend.previewInteractiveRebase(
        opened.repositoryId,
        plan,
      );
      expect(detached.detachedHead, isTrue);
      expect(detached.canExecute, isFalse);
      expect(detached.blockingMessage, contains('Switch to a branch'));

      await runGit(directory.path, ['switch', 'main']);
      final rootPlan = GitInteractiveRebasePlan(
        repositoryId: opened.repositoryId,
        entries: [
          GitInteractiveRebaseEntry(
            originalOid: await runGit(directory.path, ['rev-parse', 'HEAD']),
            subject: 'base',
            action: GitInteractiveRebaseAction.pick,
            originalIndex: 0,
          ),
        ],
        options: const GitInteractiveRebaseOptions(root: true),
      );
      final protectedPreview = await backend.previewInteractiveRebase(
        opened.repositoryId,
        rootPlan,
      );
      expect(protectedPreview.branchProtected, isTrue);
      expect(protectedPreview.canExecute, isFalse);
      expect(protectedPreview.blockingMessage, contains('protected'));

      final remote = Directory('${directory.path}-remote');
      await remote.create();
      try {
        await runGit(remote.path, ['init', '--bare', '--quiet']);
        await runGit(directory.path, ['switch', 'topic']);
        await runGit(directory.path, ['remote', 'add', 'origin', remote.path]);
        await runGit(directory.path, [
          'push',
          '--set-upstream',
          'origin',
          'topic',
        ]);
        final pushed = await backend.previewInteractiveRebase(
          opened.repositoryId,
          plan,
        );
        expect(pushed.pushedCommits, isTrue);
        expect(pushed.canExecute, isFalse);
        expect(pushed.blockingMessage, contains('already pushed'));
      } finally {
        if (remote.existsSync()) await remote.delete(recursive: true);
      }

      final gitPath = await runGit(directory.path, [
        'rev-parse',
        '--git-path',
        'rebase-merge',
      ]);
      final operationDirectory = Directory(
        Directory(gitPath).isAbsolute
            ? gitPath
            : '${directory.path}${Platform.pathSeparator}$gitPath',
      );
      await operationDirectory.create(recursive: true);
      try {
        final inProgress = await backend.previewInteractiveRebase(
          opened.repositoryId,
          plan,
        );
        expect(inProgress.operationInProgress, GitConflictOperation.rebase);
        expect(inProgress.canExecute, isFalse);
        expect(inProgress.blockingMessage, contains('in-progress'));
      } finally {
        if (operationDirectory.existsSync()) {
          await operationDirectory.delete(recursive: true);
        }
      }
    });
  });

  test(
    'rejects a plan that does not match the captured linear range',
    () async {
      await withTempDirectory((directory) async {
        await createRepository(directory.path);
        await runGit(directory.path, ['switch', '--create', 'topic']);
        await commitFile(directory.path, 'one.txt', 'one\n', 'one');
        final upstream = await runGit(directory.path, ['rev-parse', 'main']);
        final backend = DartGitBackend();
        final opened = await backend.openRepository(directory.path);
        final outsideRangePlan = GitInteractiveRebasePlan(
          repositoryId: opened.repositoryId,
          upstreamRevision: upstream,
          entries: [
            GitInteractiveRebaseEntry(
              originalOid: upstream,
              subject: 'base is outside the selected range',
              action: GitInteractiveRebaseAction.pick,
              originalIndex: 0,
            ),
          ],
        );

        final preview = await backend.previewInteractiveRebase(
          opened.repositoryId,
          outsideRangePlan,
        );
        expect(preview.canExecute, isFalse);
        expect(
          preview.blockingMessage,
          contains('does not match the current linear commit range'),
        );
        expect(preview.token, isNull);
      });
    },
  );
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
