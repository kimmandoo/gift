import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitshiba/src/backend/dart_git_backend.dart';
import 'package:gitshiba/src/backend/diff.dart';
import 'package:gitshiba/src/backend/domain.dart';
import 'package:gitshiba/src/backend/error.dart';
import 'package:gitshiba/src/backend/executor.dart';
import 'package:gitshiba/src/backend/repository_service.dart';

void main() {
  test(
    'builds a patch from selected parsed lines without accepting raw text',
    () {
      final repositoryId = const RepositoryId(value: 'partial-repository');
      final diff = parseUnifiedDiff(
        utf8.encode('''diff --git a/notes.txt b/notes.txt
--- a/notes.txt
+++ b/notes.txt
@@ -1,3 +1,4 @@
 first
-remove this
+keep this staged
 second
+leave this unstaged
'''),
        path: 'notes.txt',
        scope: GitDiffScope.workingTree,
      );
      final selectedLine = diff.lines.indexWhere(
        (line) => line.text == '+keep this staged',
      );

      final patch = buildSelectedPatch(
        diff,
        GitPatchSelection(
          repositoryId: repositoryId,
          path: 'notes.txt',
          scope: GitDiffScope.workingTree,
          contentHash: diff.contentHash,
          lineIndexes: [selectedLine],
        ),
      );

      final patchText = utf8.decode(patch.bytes);
      expect(patchText, contains('+keep this staged'));
      expect(patchText, isNot(contains('+leave this unstaged')));
      expect(patchText, isNot(contains('-remove this')));
    },
  );

  test(
    'stages and unstages selected hunks against a real Git fixture',
    () async {
      await withTempDirectory((directory) async {
        await createCommittedRepository(directory.path, lineCount: 20);
        final file = File('${directory.path}/notes.txt');
        final lines = List<String>.generate(20, (index) => 'line ${index + 1}');
        lines[1] = 'first changed';
        lines[17] = 'second changed';
        await file.writeAsString('${lines.join('\n')}\n');

        final backend = DartGitBackend();
        final opened = await backend.openRepository(directory.path);
        final working = await backend.getDiff(opened.repositoryId, 'notes.txt');
        expect(working.hunks, hasLength(2));

        final selection = GitPatchSelection(
          repositoryId: opened.repositoryId,
          path: 'notes.txt',
          scope: GitDiffScope.workingTree,
          contentHash: working.contentHash,
          hunkIndexes: const [0],
        );
        final staged = await backend.stagePatch(opened.repositoryId, selection);
        expect(
          staged.staged.map((change) => change.path),
          contains('notes.txt'),
        );
        expect(
          staged.unstaged.map((change) => change.path),
          contains('notes.txt'),
        );

        final stagedDiff = await backend.getDiff(
          opened.repositoryId,
          'notes.txt',
          scope: GitDiffScope.staged,
        );
        expect(
          stagedDiff.lines.any((line) => line.text == '+first changed'),
          isTrue,
        );
        expect(
          stagedDiff.lines.any((line) => line.text == '+second changed'),
          isFalse,
        );

        final remainingWorkingDiff = await backend.getDiff(
          opened.repositoryId,
          'notes.txt',
        );
        expect(
          remainingWorkingDiff.lines.any(
            (line) => line.text == '+second changed',
          ),
          isTrue,
        );
        expect(
          remainingWorkingDiff.lines.any(
            (line) => line.text == '+first changed',
          ),
          isFalse,
        );

        final firstAddition = stagedDiff.lines.indexWhere(
          (line) => line.text == '+first changed',
        );
        final unstaged = await backend.unstagePatch(
          opened.repositoryId,
          GitPatchSelection(
            repositoryId: opened.repositoryId,
            path: 'notes.txt',
            scope: GitDiffScope.staged,
            contentHash: stagedDiff.contentHash,
            lineIndexes: [firstAddition],
          ),
        );
        expect(
          unstaged.staged.map((change) => change.path),
          contains('notes.txt'),
        );
        expect(
          unstaged.unstaged.map((change) => change.path),
          contains('notes.txt'),
        );
        final remainingStagedDiff = await backend.getDiff(
          opened.repositoryId,
          'notes.txt',
          scope: GitDiffScope.staged,
        );
        expect(remainingStagedDiff.additions, 0);
        expect(remainingStagedDiff.deletions, 1);
      });
    },
  );

  test('rejects a rename-only diff as unavailable for partial staging', () {
    final diff = parseUnifiedDiff(
      utf8.encode('''diff --git a/old-name.txt b/new-name.txt
similarity index 100%
rename from old-name.txt
rename to new-name.txt
'''),
      path: 'new-name.txt',
      scope: GitDiffScope.workingTree,
    );

    expect(diff.isRename, isTrue);
    expect(diff.hunks, isEmpty);
    expect(
      () => buildSelectedPatch(
        diff,
        GitPatchSelection(
          repositoryId: const RepositoryId(value: 'rename-repository'),
          path: 'new-name.txt',
          scope: GitDiffScope.workingTree,
          contentHash: diff.contentHash,
          hunkIndexes: const [0],
        ),
      ),
      throwsA(
        isA<GitError>().having(
          (error) => error.category,
          'category',
          GitErrorCategory.patchRejected,
        ),
      ),
    );
  });

  test('rejects a selection when the diff content became stale', () async {
    await withTempDirectory((directory) async {
      await createCommittedRepository(directory.path);
      final file = File('${directory.path}/notes.txt');
      await file.writeAsString('line one changed\nline two\n');

      final backend = DartGitBackend();
      final opened = await backend.openRepository(directory.path);
      final diff = await backend.getDiff(opened.repositoryId, 'notes.txt');
      final selectedLine = diff.lines.indexWhere(
        (line) => line.kind == GitDiffLineKind.addition,
      );
      await file.writeAsString('line one changed again\nline two\n');

      await expectLater(
        backend.stagePatch(
          opened.repositoryId,
          GitPatchSelection(
            repositoryId: opened.repositoryId,
            path: 'notes.txt',
            scope: GitDiffScope.workingTree,
            contentHash: diff.contentHash,
            lineIndexes: [selectedLine],
          ),
        ),
        throwsA(
          isA<GitError>().having(
            (error) => error.category,
            'category',
            GitErrorCategory.stalePatch,
          ),
        ),
      );
      expect((await backend.getStatus(opened.repositoryId)).staged, isEmpty);
    });
  });

  test('maps a Git apply failure to a recoverable patch error', () async {
    await withTempDirectory((directory) async {
      await createCommittedRepository(directory.path);
      final file = File('${directory.path}/notes.txt');
      await file.writeAsString('line one changed\nline two\n');

      final service = RepositoryService(
        gitPath: 'git',
        state: AppState(),
        runner: RejectingPatchRunner(),
      );
      final opened = await service.openRepository(directory.path);
      final diff = await service.getDiff(opened.repositoryId, 'notes.txt');
      final selectedLine = diff.lines.indexWhere(
        (line) => line.kind == GitDiffLineKind.addition,
      );

      await expectLater(
        service.stagePatch(
          opened.repositoryId,
          GitPatchSelection(
            repositoryId: opened.repositoryId,
            path: 'notes.txt',
            scope: GitDiffScope.workingTree,
            contentHash: diff.contentHash,
            lineIndexes: [selectedLine],
          ),
        ),
        throwsA(
          isA<GitError>().having(
            (error) => error.category,
            'category',
            GitErrorCategory.patchRejected,
          ),
        ),
      );
    });
  });

  test(
    'stages a no-newline text hunk and rejects binary partial staging',
    () async {
      await withTempDirectory((directory) async {
        await createCommittedRepository(
          directory.path,
          fileName: 'notes.txt',
          newline: false,
        );
        final file = File('${directory.path}/notes.txt');
        await file.writeAsString('changed without newline');
        final backend = DartGitBackend();
        final opened = await backend.openRepository(directory.path);
        final diff = await backend.getDiff(opened.repositoryId, 'notes.txt');
        expect(
          diff.lines.any((line) => line.kind == GitDiffLineKind.noNewline),
          isTrue,
        );
        await backend.stagePatch(
          opened.repositoryId,
          GitPatchSelection(
            repositoryId: opened.repositoryId,
            path: 'notes.txt',
            scope: GitDiffScope.workingTree,
            contentHash: diff.contentHash,
            hunkIndexes: const [0],
          ),
        );

        final binary = File('${directory.path}/image.bin');
        await binary.writeAsBytes([0, 1, 2]);
        await expectGitSuccess([
          'add',
          '--',
          'image.bin',
        ], workingDirectory: directory.path);
        await expectGitSuccess([
          'commit',
          '--quiet',
          '-m',
          'add binary',
        ], workingDirectory: directory.path);
        await binary.writeAsBytes([0, 1, 3]);
        final binaryDiff = await backend.getDiff(
          opened.repositoryId,
          'image.bin',
        );
        expect(binaryDiff.isBinary, isTrue);
        await expectLater(
          backend.stagePatch(
            opened.repositoryId,
            GitPatchSelection(
              repositoryId: opened.repositoryId,
              path: 'image.bin',
              scope: GitDiffScope.workingTree,
              contentHash: binaryDiff.contentHash,
              hunkIndexes: const [0],
            ),
          ),
          throwsA(
            isA<GitError>().having(
              (error) => error.category,
              'category',
              GitErrorCategory.patchRejected,
            ),
          ),
        );
      });
    },
  );
}

Future<void> createCommittedRepository(
  String path, {
  String fileName = 'notes.txt',
  bool newline = true,
  int lineCount = 2,
}) async {
  await expectGitSuccess(['init', '--quiet'], workingDirectory: path);
  await expectGitSuccess([
    'config',
    'user.name',
    'Gitshiba Test',
  ], workingDirectory: path);
  await expectGitSuccess([
    'config',
    'user.email',
    'gitshiba@example.test',
  ], workingDirectory: path);
  final file = File('$path/$fileName');
  final content = lineCount == 2
      ? (newline ? 'line one\nline two\n' : 'line one')
      : List<String>.generate(
              lineCount,
              (index) => 'line ${index + 1}',
            ).join('\n') +
            (newline ? '\n' : '');
  await file.writeAsString(content);
  await expectGitSuccess(['add', '--', fileName], workingDirectory: path);
  await expectGitSuccess([
    'commit',
    '--quiet',
    '-m',
    'initial',
  ], workingDirectory: path);
}

Future<void> withTempDirectory(
  Future<void> Function(Directory directory) body,
) async {
  final directory = await Directory.systemTemp.createTemp('gitshiba-partial-');
  try {
    await body(directory);
  } finally {
    await directory.delete(recursive: true);
  }
}

Future<void> expectGitSuccess(
  List<String> args, {
  required String workingDirectory,
}) async {
  final result = await Process.run(
    'git',
    args,
    workingDirectory: workingDirectory,
    runInShell: false,
  );
  expect(
    result.exitCode,
    0,
    reason: 'git ${args.join(' ')} failed: ${result.stderr}',
  );
}

class RejectingPatchRunner extends ProcessGitRunner {
  RejectingPatchRunner() : super(defaultTimeout: const Duration(seconds: 5));

  @override
  Future<ProcessOutput> run(GitInvocation invocation) {
    if (invocation.args.firstOrNull == 'apply') {
      throw const GitError(
        category: GitErrorCategory.processFailed,
        userMessage: 'Git reported an error.',
        diagnostic: 'fixture rejected the generated patch',
        retryable: false,
        exitCode: 1,
      );
    }
    return super.run(invocation);
  }
}
