import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gift/src/backend/conflict.dart';
import 'package:gift/src/backend/dart_git_backend.dart';
import 'package:gift/src/backend/error.dart';

void main() {
  test('parses base, ours, and theirs from unmerged index stages', () {
    final conflicts = parseGitUnmergedIndex(
      utf8.encode(
        '100644 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa 1\tfile.txt\u0000'
        '100644 bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb 2\tfile.txt\u0000'
        '100644 cccccccccccccccccccccccccccccccccccccccc 3\tfile.txt\u0000',
      ),
    );

    expect(conflicts, hasLength(1));
    expect(conflicts.single.path, 'file.txt');
    expect(conflicts.single.base?.oid, startsWith('a'));
    expect(conflicts.single.ours?.oid, startsWith('b'));
    expect(conflicts.single.theirs?.oid, startsWith('c'));
  });

  test(
    'loads merge sides, rejects stale edits, and continues after resolution',
    () async {
      await withTempDirectory((directory) async {
        await createRepository(directory.path);
        await runGit(directory.path, ['switch', '--create', 'feature']);
        await File('${directory.path}/base.txt').writeAsString('feature\n');
        await runGit(directory.path, ['add', '--', 'base.txt']);
        await runGit(directory.path, ['commit', '-m', 'feature change']);
        await runGit(directory.path, ['switch', 'main']);
        await File('${directory.path}/base.txt').writeAsString('main\n');
        await runGit(directory.path, ['add', '--', 'base.txt']);
        await runGit(directory.path, ['commit', '-m', 'main change']);
        await runGit(directory.path, [
          'merge',
          'feature',
        ], expectSuccess: false);

        final backend = DartGitBackend();
        final opened = await backend.openRepository(directory.path);
        final initial = await backend.getConflicts(opened.repositoryId);
        expect(initial.operation?.operation, GitConflictOperation.merge);
        expect(initial.conflicts, hasLength(1));
        final conflict = initial.conflicts.single;
        expect(conflict.base?.oid, isNotNull);
        expect(conflict.base?.content.state, GitConflictContentState.available);
        expect(conflict.base?.content.text, 'base\n');
        expect(conflict.ours?.content.text, 'main\n');
        expect(conflict.theirs?.content.text, 'feature\n');
        expect(conflict.result?.content.text, contains('<<<<<<<'));

        await File('${directory.path}/base.txt').writeAsString('changed\n');
        await expectLater(
          backend.editConflictResult(
            opened.repositoryId,
            'base.txt',
            'resolved\n',
            fingerprint: initial.fingerprint,
          ),
          throwsA(
            isA<GitError>().having(
              (error) => error.category,
              'category',
              GitErrorCategory.staleConflict,
            ),
          ),
        );

        final current = await backend.getConflicts(opened.repositoryId);
        final edited = await backend.editConflictResult(
          opened.repositoryId,
          'base.txt',
          'resolved\n',
          fingerprint: current.fingerprint,
        );
        expect(edited.snapshot.conflicts, hasLength(1));
        final marked = await backend.markConflictResolved(
          opened.repositoryId,
          'base.txt',
          fingerprint: edited.snapshot.fingerprint,
        );
        expect(marked.snapshot.conflicts, isEmpty);
        final continued = await backend.continueConflict(
          opened.repositoryId,
          fingerprint: marked.snapshot.fingerprint,
        );
        expect(continued.state, GitConflictOperationState.completed);
        expect(
          await runGit(directory.path, ['status', '--porcelain']),
          isEmpty,
        );
      });
    },
  );

  test(
    'represents add/add and modify/delete sides without guessing content',
    () async {
      await withTempDirectory((directory) async {
        await createRepository(directory.path);
        await runGit(directory.path, ['switch', '--create', 'add-side']);
        await File('${directory.path}/added.txt').writeAsString('ours\n');
        await runGit(directory.path, ['add', '--', 'added.txt']);
        await runGit(directory.path, ['commit', '-m', 'ours add']);
        await runGit(directory.path, ['switch', 'main']);
        await File('${directory.path}/added.txt').writeAsString('theirs\n');
        await runGit(directory.path, ['add', '--', 'added.txt']);
        await runGit(directory.path, ['commit', '-m', 'theirs add']);
        await runGit(directory.path, [
          'merge',
          'add-side',
        ], expectSuccess: false);

        final backend = DartGitBackend();
        final opened = await backend.openRepository(directory.path);
        final addAdd = await backend.getConflicts(opened.repositoryId);
        expect(addAdd.conflicts, hasLength(1));
        expect(addAdd.conflicts.single.base, isNull);
        expect(addAdd.conflicts.single.ours?.content.text, 'theirs\n');
        expect(addAdd.conflicts.single.theirs?.content.text, 'ours\n');
        await backend.abortConflict(
          opened.repositoryId,
          fingerprint: addAdd.fingerprint,
        );

        await runGit(directory.path, ['switch', '--create', 'delete-side']);
        await File('${directory.path}/base.txt').writeAsString('changed\n');
        await runGit(directory.path, ['add', '--', 'base.txt']);
        await runGit(directory.path, ['commit', '-m', 'modify base']);
        await runGit(directory.path, ['switch', 'main']);
        await runGit(directory.path, ['rm', '--', 'base.txt']);
        await runGit(directory.path, ['commit', '-m', 'delete base']);
        await runGit(directory.path, [
          'merge',
          'delete-side',
        ], expectSuccess: false);
        final modifyDelete = await backend.getConflicts(opened.repositoryId);
        expect(modifyDelete.conflicts, hasLength(1));
        final entry = modifyDelete.conflicts.single;
        expect(entry.ours, isNull);
        expect(entry.theirs?.content.text, 'changed\n');
        final deleted = await backend.acceptConflictTheirs(
          opened.repositoryId,
          entry.path,
          fingerprint: modifyDelete.fingerprint,
        );
        expect(deleted.snapshot.conflicts, isEmpty);
      });
    },
  );

  test(
    'marks binary conflict sides as binary rather than editable text',
    () async {
      await withTempDirectory((directory) async {
        await createRepository(directory.path);
        await File('${directory.path}/image.bin').writeAsBytes([0, 1, 2]);
        await runGit(directory.path, ['add', '--', 'image.bin']);
        await runGit(directory.path, ['commit', '-m', 'binary base']);
        await runGit(directory.path, ['switch', '--create', 'binary-side']);
        await File('${directory.path}/image.bin').writeAsBytes([0, 3, 2]);
        await runGit(directory.path, ['add', '--', 'image.bin']);
        await runGit(directory.path, ['commit', '-m', 'binary ours']);
        await runGit(directory.path, ['switch', 'main']);
        await File('${directory.path}/image.bin').writeAsBytes([0, 4, 2]);
        await runGit(directory.path, ['add', '--', 'image.bin']);
        await runGit(directory.path, ['commit', '-m', 'binary theirs']);
        await runGit(directory.path, [
          'merge',
          'binary-side',
        ], expectSuccess: false);

        final backend = DartGitBackend();
        final opened = await backend.openRepository(directory.path);
        final snapshot = await backend.getConflicts(opened.repositoryId);
        final entry = snapshot.conflicts.single;
        expect(entry.ours?.content.state, GitConflictContentState.binary);
        expect(entry.theirs?.content.state, GitConflictContentState.binary);
        await expectLater(
          backend.editConflictResult(
            opened.repositoryId,
            entry.path,
            'not binary',
            fingerprint: snapshot.fingerprint,
          ),
          throwsA(
            isA<GitError>().having(
              (error) => error.category,
              'category',
              GitErrorCategory.conflictResolutionNotAllowed,
            ),
          ),
        );
        await backend.abortConflict(
          opened.repositoryId,
          fingerprint: snapshot.fingerprint,
        );
      });
    },
  );

  test('identifies rebase and cherry-pick conflict metadata', () async {
    await withTempDirectory((directory) async {
      await createRepository(directory.path);
      await runGit(directory.path, ['switch', '--create', 'rebase-side']);
      await File('${directory.path}/base.txt').writeAsString('rebase side\n');
      await runGit(directory.path, ['add', '--', 'base.txt']);
      await runGit(directory.path, ['commit', '-m', 'rebase side']);
      await runGit(directory.path, ['switch', 'main']);
      await File('${directory.path}/base.txt').writeAsString('main side\n');
      await runGit(directory.path, ['add', '--', 'base.txt']);
      await runGit(directory.path, ['commit', '-m', 'main side']);
      await runGit(directory.path, ['switch', 'rebase-side']);
      await runGit(directory.path, ['rebase', 'main'], expectSuccess: false);

      final backend = DartGitBackend();
      final opened = await backend.openRepository(directory.path);
      final rebase = await backend.getConflicts(opened.repositoryId);
      expect(rebase.operation?.operation, GitConflictOperation.rebase);
      expect(rebase.operation?.headName, 'rebase-side');
      await backend.abortConflict(
        opened.repositoryId,
        fingerprint: rebase.fingerprint,
      );

      await runGit(directory.path, ['switch', 'main']);
      final cherrySource = await runGit(directory.path, [
        'rev-parse',
        'rebase-side',
      ]);
      await runGit(directory.path, [
        'cherry-pick',
        cherrySource,
      ], expectSuccess: false);
      final cherryPick = await backend.getConflicts(opened.repositoryId);
      expect(cherryPick.operation?.operation, GitConflictOperation.cherryPick);
      expect(cherryPick.operation?.mergeHeads, contains(cherrySource));
      await backend.abortConflict(
        opened.repositoryId,
        fingerprint: cherryPick.fingerprint,
      );
    });
  });

  test('keeps rename-related conflict paths addressable', () async {
    await withTempDirectory((directory) async {
      await createRepository(directory.path);
      await runGit(directory.path, ['switch', '--create', 'rename-side']);
      await runGit(directory.path, ['mv', 'base.txt', 'renamed.txt']);
      await runGit(directory.path, ['commit', '-m', 'rename base']);
      await runGit(directory.path, ['switch', 'main']);
      await runGit(directory.path, ['mv', 'base.txt', 'main-renamed.txt']);
      await runGit(directory.path, ['commit', '-m', 'rename base differently']);
      await runGit(directory.path, [
        'merge',
        'rename-side',
      ], expectSuccess: false);

      final backend = DartGitBackend();
      final opened = await backend.openRepository(directory.path);
      final snapshot = await backend.getConflicts(opened.repositoryId);
      expect(snapshot.conflicts, isNotEmpty);
      expect(
        snapshot.conflicts.any(
          (conflict) => conflict.originalPath == 'base.txt',
        ),
        isTrue,
      );
      await backend.abortConflict(
        opened.repositoryId,
        fingerprint: snapshot.fingerprint,
      );
    });
  });
}

Future<void> createRepository(String path) async {
  await runGit(path, ['init', '--initial-branch=main']);
  await runGit(path, ['config', 'user.name', 'Gift Test']);
  await runGit(path, ['config', 'user.email', 'gift@example.test']);
  await File('$path/base.txt').writeAsString('base\n');
  await runGit(path, ['add', '--', 'base.txt']);
  await runGit(path, ['commit', '-m', 'base']);
}

Future<String> runGit(
  String path,
  List<String> args, {
  bool expectSuccess = true,
}) async {
  final result = await Process.run(
    'git',
    args,
    workingDirectory: path,
    runInShell: false,
  );
  if (expectSuccess && result.exitCode != 0) {
    throw StateError('git ${args.join(' ')} failed: ${result.stderr}');
  }
  if (!expectSuccess && result.exitCode == 0) {
    throw StateError('git ${args.join(' ')} unexpectedly succeeded');
  }
  return '${result.stdout}'.trim();
}

Future<void> withTempDirectory(
  Future<void> Function(Directory directory) body,
) async {
  final directory = await Directory.systemTemp.createTemp('gift-conflict-');
  try {
    await body(directory);
  } finally {
    if (directory.existsSync()) await directory.delete(recursive: true);
  }
}
