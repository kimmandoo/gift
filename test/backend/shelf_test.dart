import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gift/src/backend/dart_git_backend.dart';
import 'package:gift/src/backend/error.dart';
import 'package:gift/src/backend/shelf.dart';

void main() {
  test(
    'persists changelists and repeatedly restores a reusable shelf',
    () async {
      final directory = await Directory.systemTemp.createTemp('gift-shelf-');
      addTearDown(() => directory.delete(recursive: true));
      await git(directory.path, ['init', '--quiet']);
      await git(directory.path, ['config', 'user.name', 'Shelf Tester']);
      await git(directory.path, ['config', 'user.email', 'shelf@test']);
      await File('${directory.path}/notes.txt').writeAsString('before\n');
      await git(directory.path, ['add', '--', 'notes.txt']);
      await git(directory.path, ['commit', '--quiet', '-m', 'before']);
      await File('${directory.path}/notes.txt').writeAsString('shelved\n');

      final backend = DartGitBackend();
      final opened = await backend.openRepository(directory.path);
      final created = await backend.createChangelist(
        opened.repositoryId,
        'Review later',
      );
      expect(created.lists.any((list) => list.name == 'Review later'), isTrue);
      final reviewList = created.lists.firstWhere(
        (list) => list.name == 'Review later',
      );
      final moved = await backend.moveChangelistPaths(
        opened.repositoryId,
        const ['notes.txt'],
        reviewList.id,
      );
      expect(moved.lists.firstWhere((list) => list.id == reviewList.id).paths, [
        'notes.txt',
      ]);

      final reloaded = DartGitBackend();
      final reopened = await reloaded.openRepository(directory.path);
      final persisted = await reloaded.getChangelists(reopened.repositoryId);
      expect(
        persisted.lists.map((list) => list.name),
        contains('Review later'),
      );

      final shelved = await backend.shelve(
        opened.repositoryId,
        name: 'parking lot',
        paths: const ['notes.txt'],
      );
      expect(shelved.outcome, GitShelfActionOutcome.shelved);
      expect(
        await File('${directory.path}/notes.txt').readAsString(),
        'before\n',
      );
      final shelf = shelved.shelf!;
      expect(shelf.baseRevision, isNotEmpty);

      final first = await backend.unshelve(opened.repositoryId, shelf.id);
      expect(first.outcome, GitShelfActionOutcome.unshelved);
      expect(
        await File('${directory.path}/notes.txt').readAsString(),
        'shelved\n',
      );

      final repeated = await backend.unshelve(opened.repositoryId, shelf.id);
      expect(repeated.outcome, GitShelfActionOutcome.conflict);
      expect(
        (await backend.getShelves(opened.repositoryId)).shelves,
        isNotEmpty,
      );

      final restored = await backend.restoreShelf(
        opened.repositoryId,
        shelf.id,
      );
      expect(restored.outcome, GitShelfActionOutcome.restored);
      expect(
        await File('${directory.path}/notes.txt').readAsString(),
        'before\n',
      );

      final patch = await backend.exportShelf(opened.repositoryId, shelf.id);
      expect(patch, isNotEmpty);
      final imported = await backend.importShelf(
        opened.repositoryId,
        'copy',
        patch,
      );
      expect(imported.outcome, GitShelfActionOutcome.imported);
      expect((await backend.getStashes(opened.repositoryId)).entries, isEmpty);
    },
  );

  test(
    'reports missing shelf bases and rejects unsafe imported paths',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'gift-shelf-loss-',
      );
      addTearDown(() => directory.delete(recursive: true));
      await git(directory.path, ['init', '--quiet']);
      await git(directory.path, ['config', 'user.name', 'Shelf Tester']);
      await git(directory.path, ['config', 'user.email', 'shelf@test']);
      await File('${directory.path}/notes.txt').writeAsString('before\n');
      await git(directory.path, ['add', '--', 'notes.txt']);
      await git(directory.path, ['commit', '--quiet', '-m', 'before']);
      final backend = DartGitBackend();
      final opened = await backend.openRepository(directory.path);
      final imported = await backend.importShelf(
        opened.repositoryId,
        'old patch',
        utf8.encode(
          'diff --git a/notes.txt b/notes.txt\n'
          '--- a/notes.txt\n'
          '+++ b/notes.txt\n'
          '@@ -1 +1 @@\n'
          '-before\n'
          '+after\n',
        ),
        baseRevision: 'gone-revision',
      );
      final missingBase = await backend.unshelve(
        opened.repositoryId,
        imported.shelf!.id,
      );
      expect(missingBase.outcome, GitShelfActionOutcome.baseMissing);

      final deleted = await backend.deleteShelf(
        opened.repositoryId,
        imported.shelf!.id,
      );
      expect(deleted.outcome, GitShelfActionOutcome.deleted);

      await expectLater(
        backend.importShelf(
          opened.repositoryId,
          'unsafe',
          utf8.encode(
            'diff --git a/../../outside b/../../outside\n'
            '--- a/../../outside\n'
            '+++ b/../../outside\n',
          ),
        ),
        throwsA(isA<GitError>()),
      );
    },
  );
}

Future<void> git(String directory, List<String> args) async {
  final result = await Process.run(
    'git',
    args,
    workingDirectory: directory,
    runInShell: false,
  );
  if (result.exitCode != 0) {
    throw StateError('git ${args.join(' ')} failed: ${result.stderr}');
  }
}
