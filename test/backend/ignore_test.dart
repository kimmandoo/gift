import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gift/src/backend/dart_git_backend.dart';
import 'package:gift/src/backend/error.dart';
import 'package:gift/src/backend/ignore.dart';

void main() {
  test(
    'distinguishes ignored, untracked, and tracked metadata states',
    () async {
      final fixture = await _createFixture('gift-ignore-');
      addTearDown(() => fixture.root.delete(recursive: true));
      final backend = DartGitBackend();
      final repository = await backend.openRepository(fixture.repository.path);

      final initial = await backend.getIgnoreSnapshot(repository.repositoryId);
      expect(
        initial.entries
            .firstWhere((entry) => entry.path == 'build/generated.txt')
            .kind,
        GitPathMetadataKind.ignored,
      );
      expect(
        initial.entries
            .firstWhere((entry) => entry.path == 'build/generated.txt')
            .source,
        GitIgnoreSource.gitignore,
      );
      expect(
        initial.entries
            .firstWhere((entry) => entry.path == 'secret.local')
            .source,
        GitIgnoreSource.infoExclude,
      );
      expect(
        initial.entries.firstWhere((entry) => entry.path == 'notes.txt').kind,
        GitPathMetadataKind.untracked,
      );
      expect(
        initial.entries.firstWhere((entry) => entry.path == 'tracked.txt').kind,
        GitPathMetadataKind.trackedModified,
      );
      expect(
        initial.entries
            .firstWhere((entry) => entry.path == 'src/cache/keep.txt')
            .kind,
        GitPathMetadataKind.untracked,
        reason:
            'nested negation should keep the file visible as untracked only',
      );

      final ignored = await backend.addIgnorePattern(
        repository.repositoryId,
        const GitIgnoreRequest(
          path: 'notes.txt',
          scope: GitIgnoreScope.repository,
        ),
      );
      final notes = ignored.snapshot.entries.singleWhere(
        (entry) => entry.path == 'notes.txt',
      );
      expect(notes.kind, GitPathMetadataKind.ignored);
      expect(notes.source, GitIgnoreSource.gitignore);
      expect(
        File('${fixture.repository.path}/.gitignore').readAsStringSync(),
        contains('/notes.txt'),
      );

      final attributes = await backend.getAttributes(
        repository.repositoryId,
        paths: const ['tracked.txt', 'binary.dat'],
      );
      final text = attributes.entries.singleWhere(
        (entry) => entry.path == 'tracked.txt',
      );
      expect(text.values['text'], 'set');
      expect(text.values['eol'], 'lf');
      final binary = attributes.entries.singleWhere(
        (entry) => entry.path == 'binary.dat',
      );
      expect(binary.values['diff'], 'custom');
      expect(binary.values['filter'], 'cleaner');
      expect(
        binary.explanations,
        contains('A named diff driver may provide textconv output.'),
      );
    },
  );

  test('rejects traversal and option-like ignore paths', () async {
    final fixture = await _createFixture('gift-ignore-invalid-');
    addTearDown(() => fixture.root.delete(recursive: true));
    final backend = DartGitBackend();
    final repository = await backend.openRepository(fixture.repository.path);

    for (final path in ['../outside.txt', '-bad', '/absolute.txt']) {
      GitError? error;
      try {
        await backend.addIgnorePattern(
          repository.repositoryId,
          GitIgnoreRequest(path: path, scope: GitIgnoreScope.repository),
        );
      } on GitError catch (caught) {
        error = caught;
      }
      expect(error?.category, GitErrorCategory.parseFailure);
    }
  });
}

class _IgnoreFixture {
  const _IgnoreFixture({required this.root, required this.repository});

  final Directory root;
  final Directory repository;
}

Future<_IgnoreFixture> _createFixture(String prefix) async {
  final root = await Directory.systemTemp.createTemp(prefix);
  final repository = Directory('${root.path}/repository');
  await repository.create();
  await _git(repository.path, ['init', '--quiet']);
  await _git(repository.path, ['config', 'user.name', 'Ignore Tester']);
  await _git(repository.path, ['config', 'user.email', 'ignore@test']);
  await File('${repository.path}/.gitignore').writeAsString(
    'build/\n*.log\n!keep.log\nsrc/cache/*\n!src/cache/keep.txt\n',
  );
  await File('${repository.path}/.gitattributes').writeAsString(
    '*.txt text eol=lf\nbinary.dat -text diff=custom filter=cleaner\n',
  );
  await File('${repository.path}/tracked.txt').writeAsString('before\n');
  await File('${repository.path}/binary.dat').writeAsBytes([0, 1, 2]);
  await _git(repository.path, [
    'add',
    '--',
    '.gitignore',
    '.gitattributes',
    'tracked.txt',
    'binary.dat',
  ]);
  await _git(repository.path, ['commit', '--quiet', '-m', 'initial']);
  await File('${repository.path}/tracked.txt').writeAsString('after\n');
  await File('${repository.path}/notes.txt').writeAsString('notes\n');
  await File('${repository.path}/keep.log').writeAsString('keep\n');
  await Directory('${repository.path}/build').create(recursive: true);
  await File('${repository.path}/build/generated.txt')
      .writeAsString('generated\n');
  await Directory('${repository.path}/src/cache').create(recursive: true);
  await File('${repository.path}/src/cache/keep.txt').writeAsString('keep\n');
  await File('${repository.path}/src/cache/other.txt').writeAsString('other\n');
  await File('${repository.path}/secret.local').writeAsString('secret\n');
  await File('${repository.path}/.git/info/exclude').writeAsString('*.local\n');
  return _IgnoreFixture(root: root, repository: repository);
}

Future<void> _git(String cwd, List<String> args) async {
  final result = await Process.run('git', args, workingDirectory: cwd);
  if (result.exitCode != 0) {
    throw ProcessException(
      'git',
      args,
      '${result.stdout}\n${result.stderr}',
      result.exitCode,
    );
  }
}
