import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gift/src/backend/dart_git_backend.dart';
import 'package:gift/src/backend/history.dart';

void main() {
  test(
    'renders a repository with one local branch on one graph lane',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'gift-single-branch-history-',
      );
      addTearDown(() => directory.delete(recursive: true));

      await git(directory.path, ['init', '--quiet']);
      await git(directory.path, ['config', 'user.name', 'History Tester']);
      await git(directory.path, ['config', 'user.email', 'history@test']);
      await File('${directory.path}/main.txt').writeAsString('main\n');
      await git(directory.path, ['add', '--', 'main.txt']);
      await git(directory.path, ['commit', '--quiet', '-m', 'initial']);
      final mainBranch = (await gitOutput(directory.path, [
        'branch',
        '--show-current',
      ])).trim();

      await git(directory.path, ['switch', '--quiet', '--create', 'old-work']);
      await File('${directory.path}/side.txt').writeAsString('side\n');
      await git(directory.path, ['add', '--', 'side.txt']);
      await git(directory.path, ['commit', '--quiet', '-m', 'old work']);
      await git(directory.path, [
        'tag',
        '--annotate',
        'old-side',
        'old-work',
        '-m',
        'old side',
      ]);
      await git(directory.path, ['switch', '--quiet', mainBranch]);
      await File('${directory.path}/main.txt').writeAsString('main\nnext\n');
      await git(directory.path, ['add', '--', 'main.txt']);
      await git(directory.path, ['commit', '--quiet', '-m', 'main work']);
      await git(directory.path, [
        'merge',
        '--quiet',
        '--no-ff',
        'old-work',
        '-m',
        'merge old work',
      ]);
      await git(directory.path, ['branch', '--delete', 'old-work']);

      final backend = DartGitBackend();
      final opened = await backend.openRepository(directory.path);
      final history = await backend.getHistory(opened.repositoryId);

      expect(history.collapseToSingleLane, isFalse);
      expect(history.commits.first.laneCount, 2);
      expect(
        history.commits
            .firstWhere((commit) => commit.subject == 'old work')
            .refs
            .map((ref) => ref.name),
        contains('refs/tags/old-side'),
      );
    },
  );

  test('keeps a bounded history cursor stable while refs advance and inspects a commit', () async {
    final directory = await Directory.systemTemp.createTemp('gift-history-');
    addTearDown(() => directory.delete(recursive: true));

    await git(directory.path, ['init', '--quiet']);
    await git(directory.path, ['config', 'user.name', 'History Tester']);
    await git(directory.path, ['config', 'user.email', 'history@test']);
    await File('${directory.path}/notes.txt').writeAsString('first\n');
    await git(directory.path, ['add', '--', 'notes.txt']);
    await git(directory.path, ['commit', '--quiet', '-m', 'initial']);
    await File('${directory.path}/notes.txt').writeAsString('first\nneedle\n');
    await git(directory.path, ['add', '--', 'notes.txt']);
    await git(directory.path, ['commit', '--quiet', '-m', 'needle 변경 🚀']);

    final backend = DartGitBackend();
    final opened = await backend.openRepository(directory.path);
    final firstPage = await backend.getHistory(
      opened.repositoryId,
      query: const GitHistoryQuery(limit: 1),
    );

    expect(firstPage.commits.single.subject, 'needle 변경 🚀');
    expect(firstPage.nextCursor, isNotNull);

    await File('${directory.path}/notes.txt')
        .writeAsString('first\nneedle\nnew ref tip\n');
    await git(directory.path, ['add', '--', 'notes.txt']);
    await git(directory.path, ['commit', '--quiet', '-m', 'new ref tip']);

    final secondPage = await backend.getHistory(
      opened.repositoryId,
      query: GitHistoryQuery(limit: 1, cursor: firstPage.nextCursor),
    );
    expect(secondPage.commits.single.subject, 'initial');

    final files = await backend.getCommitFiles(
      opened.repositoryId,
      firstPage.commits.single.oid,
    );
    expect(files.single.path, 'notes.txt');

    final diff = await backend.getCommitDiff(
      opened.repositoryId,
      firstPage.commits.single.oid,
      'notes.txt',
    );
    expect(diff.lines.any((line) => line.text == '+needle'), isTrue);

    final filtered = await backend.getHistory(
      opened.repositoryId,
      query: const GitHistoryQuery(filters: GitHistoryFilters(text: 'needle')),
    );
    expect(filtered.commits.map((commit) => commit.subject), ['needle 변경 🚀']);

    final byPath = await backend.getHistory(
      opened.repositoryId,
      query: const GitHistoryQuery(
        filters: GitHistoryFilters(path: 'notes.txt'),
      ),
    );
    expect(
      byPath.commits.map((commit) => commit.subject),
      contains('needle 변경 🚀'),
    );

    final byAuthor = await backend.getHistory(
      opened.repositoryId,
      query: const GitHistoryQuery(
        filters: GitHistoryFilters(author: 'History Tester'),
      ),
    );
    expect(byAuthor.commits, isNotEmpty);
  });

  test(
    'inspects root, deleted, and binary commit paths with ref filters',
    () async {
      final directory = await Directory.systemTemp.createTemp('gift-history-');
      addTearDown(() => directory.delete(recursive: true));

      await git(directory.path, ['init', '--quiet']);
      await git(directory.path, ['config', 'user.name', 'History Tester']);
      await git(directory.path, ['config', 'user.email', 'history@test']);
      await File('${directory.path}/deleted.txt').writeAsString('remove me\n');
      await git(directory.path, ['add', '--', 'deleted.txt']);
      await git(directory.path, ['commit', '--quiet', '-m', 'root commit']);
      final rootOid = (await gitOutput(directory.path, [
        'rev-parse',
        'HEAD',
      ])).trim();

      await File('${directory.path}/deleted.txt').delete();
      await File('${directory.path}/image.bin').writeAsBytes([0, 1, 2, 0, 255]);
      await git(directory.path, ['add', '--all']);
      await git(directory.path, ['commit', '--quiet', '-m', 'delete binary']);

      final backend = DartGitBackend();
      final opened = await backend.openRepository(directory.path);
      final latest = await backend.getHistory(
        opened.repositoryId,
        query: GitHistoryQuery(
          limit: 5,
          filters: GitHistoryFilters(
            ref: 'HEAD',
            authoredAfter: DateTime(2020),
            authoredBefore: DateTime(2030),
          ),
        ),
      );
      expect(latest.commits, hasLength(2));
      expect(
        latest.commits.first.refs.map((ref) => ref.name),
        contains('HEAD'),
      );

      final latestFiles = await backend.getCommitFiles(
        opened.repositoryId,
        latest.commits.first.oid,
      );
      expect(
        latestFiles.map((file) => file.status),
        contains(GitCommitFileStatus.deleted),
      );
      expect(latestFiles.map((file) => file.path), contains('image.bin'));

      final binary = await backend.getCommitDiff(
        opened.repositoryId,
        latest.commits.first.oid,
        'image.bin',
      );
      expect(binary.isBinary, isTrue);

      final root = await backend.getCommit(opened.repositoryId, rootOid);
      final rootFiles = await backend.getCommitFiles(
        opened.repositoryId,
        root.oid,
      );
      expect(rootFiles.single.status, GitCommitFileStatus.added);
      expect(rootFiles.single.path, 'deleted.txt');
    },
  );
}

Future<void> git(String directory, List<String> args) async {
  await gitOutput(directory, args);
}

Future<String> gitOutput(String directory, List<String> args) async {
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
  return result.stdout as String;
}
