import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gift/src/backend/dart_git_backend.dart';
import 'package:gift/src/backend/error.dart';
import 'package:gift/src/backend/file_history.dart';

void main() {
  test('follows a rename and returns bounded blame ownership', () async {
    final directory = await Directory.systemTemp.createTemp(
      'gift-file-history-',
    );
    addTearDown(() => directory.delete(recursive: true));
    await git(directory.path, ['init', '--quiet']);
    await git(directory.path, ['config', 'user.name', 'History Tester']);
    await git(directory.path, ['config', 'user.email', 'history@test']);
    await File('${directory.path}/notes.txt').writeAsString('first\nsecond\n');
    await git(directory.path, ['add', '--', 'notes.txt']);
    await git(directory.path, ['commit', '--quiet', '-m', 'base']);
    await Directory('${directory.path}/docs').create();
    await git(directory.path, ['mv', 'notes.txt', 'docs/renamed.txt']);
    await git(directory.path, ['commit', '--quiet', '-m', 'rename']);
    await File('${directory.path}/docs/renamed.txt')
        .writeAsString('first\nchanged\n');
    await git(directory.path, ['commit', '--quiet', '-am', 'change']);

    final backend = DartGitBackend();
    final opened = await backend.openRepository(directory.path);
    final history = await backend.getFileHistory(
      opened.repositoryId,
      const GitFileHistoryQuery(path: 'docs/renamed.txt', follow: true),
    );
    expect(history.entries, isNotEmpty);
    expect(
      history.entries.any((entry) => entry.originalPath == 'notes.txt'),
      isTrue,
    );

    final blame = await backend.getBlame(
      opened.repositoryId,
      'docs/renamed.txt',
      options: const GitBlameOptions(detectMoves: true, detectCopies: true),
    );
    expect(blame.lines, hasLength(2));
    expect(blame.lines.first.text, 'first');
    expect(blame.lines.last.commitOid, isNotEmpty);
  });

  test(
    'gets a file from a revision only when the history fingerprint is fresh',
    () async {
      final directory = await Directory.systemTemp.createTemp('gift-get-file-');
      addTearDown(() => directory.delete(recursive: true));
      await git(directory.path, ['init', '--quiet']);
      await git(directory.path, ['config', 'user.name', 'History Tester']);
      await git(directory.path, ['config', 'user.email', 'history@test']);
      await File('${directory.path}/notes.txt').writeAsString('base\n');
      await git(directory.path, ['add', '--', 'notes.txt']);
      await git(directory.path, ['commit', '--quiet', '-m', 'base']);
      await Directory('${directory.path}/docs').create();
      await git(directory.path, ['mv', 'notes.txt', 'docs/renamed.txt']);
      await git(directory.path, ['commit', '--quiet', '-m', 'rename']);
      await File('${directory.path}/docs/renamed.txt').writeAsString('local\n');

      final backend = DartGitBackend();
      final opened = await backend.openRepository(directory.path);
      final history = await backend.getFileHistory(
        opened.repositoryId,
        const GitFileHistoryQuery(path: 'docs/renamed.txt', follow: true),
      );
      final restored = await backend.getFileFromRevision(
        opened.repositoryId,
        history,
        'HEAD~0',
      );
      expect(restored.outcome, GitRevisionGetOutcome.restored);
      expect(
        await File('${directory.path}/docs/renamed.txt').readAsString(),
        'base\n',
      );

      final freshHistory = await backend.getFileHistory(
        opened.repositoryId,
        const GitFileHistoryQuery(path: 'docs/renamed.txt'),
      );
      final missing = await backend.getFileFromRevision(
        opened.repositoryId,
        freshHistory,
        'HEAD~1',
      );
      expect(missing.outcome, GitRevisionGetOutcome.missing);

      await File('${directory.path}/docs/renamed.txt')
          .writeAsString('changed\n');
      await expectLater(
        backend.getFileFromRevision(opened.repositoryId, freshHistory, 'HEAD'),
        throwsA(
          isA<GitError>().having(
            (error) => error.category,
            'category',
            GitErrorCategory.staleComparison,
          ),
        ),
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
