import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gift/src/backend/dart_git_backend.dart';
import 'package:gift/src/backend/error.dart';
import 'package:gift/src/backend/setup.dart';

void main() {
  test('clones, initializes, unshallows, and maps independent roots', () async {
    final fixture = await _createFixture('gift-setup-');
    addTearDown(() => fixture.root.delete(recursive: true));
    final backend = DartGitBackend();

    final cloned = await backend.cloneRepository(
      GitCloneRequest(
        source: fixture.source.path,
        destination: fixture.clone.path,
        recursive: false,
      ),
    );
    expect(File('${cloned.repository.root}/README.md').existsSync(), isTrue);

    final initialized = await backend.initRepository(
      GitInitRequest(path: fixture.empty.path, initialBranch: 'main'),
    );
    expect(initialized.repository.root, fixture.empty.path);
    expect(Directory('${fixture.empty.path}/.git').existsSync(), isTrue);

    final shallow = await backend.cloneRepository(
      GitCloneRequest(
        source: Uri.file(fixture.source.path).toString(),
        destination: fixture.shallow.path,
        depth: 1,
      ),
    );
    final unshallowed = await backend.unshallowRepository(
      shallow.repository.repositoryId,
    );
    expect(unshallowed.wasShallow, isTrue);
    expect(unshallowed.isShallow, isFalse);

    final roots = await backend.discoverRepositoryRoots(fixture.root.path);
    expect(roots.roots.map((root) => root.relativePath), contains('source'));
    expect(roots.roots.map((root) => root.relativePath), contains('nested'));
    expect(roots.roots.map((root) => root.relativePath), contains('clone'));
  });

  test('rejects unsafe and non-empty clone destinations', () async {
    final fixture = await _createFixture('gift-setup-validation-');
    addTearDown(() => fixture.root.delete(recursive: true));
    final backend = DartGitBackend();
    GitError? error;
    try {
      await backend.cloneRepository(
        GitCloneRequest(
          source: fixture.source.path,
          destination: fixture.source.path,
        ),
      );
    } on GitError catch (caught) {
      error = caught;
    }
    expect(error?.category, GitErrorCategory.parseFailure);
  });
}

class _SetupFixture {
  const _SetupFixture({
    required this.root,
    required this.source,
    required this.clone,
    required this.shallow,
    required this.empty,
    required this.nested,
  });

  final Directory root;
  final Directory source;
  final Directory clone;
  final Directory shallow;
  final Directory empty;
  final Directory nested;
}

Future<_SetupFixture> _createFixture(String prefix) async {
  final root = await Directory.systemTemp.createTemp(prefix);
  final source = Directory('${root.path}/source');
  final clone = Directory('${root.path}/clone');
  final shallow = Directory('${root.path}/shallow');
  final empty = Directory('${root.path}/empty');
  final nested = Directory('${root.path}/nested');
  await for (final directory in Stream<Directory>.fromIterable([
    source,
    empty,
    nested,
  ])) {
    await directory.create();
  }
  await _git(source.path, ['init', '--quiet']);
  await _git(source.path, ['config', 'user.name', 'Setup Tester']);
  await _git(source.path, ['config', 'user.email', 'setup@test']);
  await File('${source.path}/README.md').writeAsString('one\n');
  await _git(source.path, ['add', '--', 'README.md']);
  await _git(source.path, ['commit', '--quiet', '-m', 'one']);
  await File('${source.path}/README.md').writeAsString('two\n');
  await _git(source.path, ['commit', '--quiet', '-am', 'two']);
  await _git(nested.path, ['init', '--quiet']);
  return _SetupFixture(
    root: root,
    source: source,
    clone: clone,
    shallow: shallow,
    empty: empty,
    nested: nested,
  );
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
