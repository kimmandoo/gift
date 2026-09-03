import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gift/src/backend/comparison.dart';
import 'package:gift/src/backend/dart_git_backend.dart';
import 'package:gift/src/backend/error.dart';

void main() {
  test('parses NUL-delimited rename and ordinary comparison records', () {
    final files = parseGitComparisonFiles(
      utf8.encode(
        'R100\u0000old name.txt\u0000new name.txt\u0000A\u0000added.txt\u0000',
      ),
    );

    expect(files, hasLength(2));
    expect(files.first.status, GitComparisonFileStatus.renamed);
    expect(files.first.oldPath, 'old name.txt');
    expect(files.first.path, 'new name.txt');
    expect(files.last.status, GitComparisonFileStatus.added);
  });

  test('compares revisions and scopes the result to a folder', () async {
    final directory = await Directory.systemTemp.createTemp('gift-compare-');
    addTearDown(() => directory.delete(recursive: true));
    await git(directory.path, ['init', '--quiet']);
    await git(directory.path, ['config', 'user.name', 'Compare Tester']);
    await git(directory.path, ['config', 'user.email', 'compare@test']);
    await Directory('${directory.path}/src').create();
    await File('${directory.path}/src/notes.txt').writeAsString('before\n');
    await git(directory.path, ['add', '--', 'src/notes.txt']);
    await git(directory.path, ['commit', '--quiet', '-m', 'before']);
    await File('${directory.path}/src/notes.txt').writeAsString('after\n');
    await git(directory.path, ['add', '--', 'src/notes.txt']);
    await git(directory.path, ['commit', '--quiet', '-m', 'after']);

    final backend = DartGitBackend();
    final opened = await backend.openRepository(directory.path);
    final comparison = await backend.compareRevisions(
      opened.repositoryId,
      'HEAD~1',
      'HEAD',
      path: 'src',
    );

    expect(comparison.request.left.value, 'HEAD~1');
    expect(comparison.request.right.value, 'HEAD');
    expect(comparison.files.single.path, 'src/notes.txt');
    expect(comparison.files.single.status, GitComparisonFileStatus.modified);
    expect(comparison.fingerprint, isNotEmpty);

    final diff = await backend.getComparisonDiff(
      opened.repositoryId,
      comparison,
      'src/notes.txt',
    );
    expect(diff.lines.any((line) => line.text == '+after'), isTrue);

    await File('${directory.path}/src/notes.txt').writeAsString('latest\n');
    await git(directory.path, ['add', '--', 'src/notes.txt']);
    await git(directory.path, ['commit', '--quiet', '-m', 'move head']);

    await expectLater(
      backend.getComparisonDiff(
        opened.repositoryId,
        comparison,
        'src/notes.txt',
      ),
      throwsA(
        isA<GitError>().having(
          (error) => error.category,
          'category',
          GitErrorCategory.staleComparison,
        ),
      ),
    );
  });
}

Future<void> git(String directory, List<String> args) async {
  final result = await Process.run(
    'git',
    args,
    workingDirectory: directory,
    runInShell: false,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  if (result.exitCode != 0) {
    fail('git ${args.join(' ')} failed: ${result.stderr}');
  }
}
