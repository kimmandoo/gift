import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gift/src/backend/dart_git_backend.dart';
import 'package:gift/src/backend/submodule.dart';

void main() {
  test(
    'maps submodule state independently and applies scoped lifecycle actions',
    () async {
      final fixture = await _createFixture('gift-submodule-');
      addTearDown(() => fixture.root.delete(recursive: true));
      final backend = DartGitBackend();
      final opened = await backend.openRepository(fixture.superproject.path);

      var snapshot = await backend.getSubmodules(opened.repositoryId);
      expect(snapshot.modules, hasLength(1));
      expect(snapshot.modules.single.path, 'modules/widget');
      expect(snapshot.modules.single.url, fixture.child.path);
      expect(snapshot.modules.single.isInitialized, isTrue);
      expect(
        snapshot.modules.single.states,
        contains(GitSubmoduleState.initialized),
      );
      expect(snapshot.modules.single.currentOid, hasLength(40));
      expect(
        snapshot.modules.single.expectedOid,
        snapshot.modules.single.currentOid,
      );

      await File('${fixture.module.path}/dirty.txt').writeAsString('dirty\n');
      snapshot = await backend.getSubmodules(opened.repositoryId);
      expect(snapshot.modules.single.states, contains(GitSubmoduleState.dirty));

      await _git(fixture.module.path, ['add', '--', 'dirty.txt']);
      await _git(fixture.module.path, [
        'commit',
        '--quiet',
        '-m',
        'module change',
      ]);
      snapshot = await backend.getSubmodules(opened.repositoryId);
      final changed = snapshot.modules.single;
      expect(changed.states, contains(GitSubmoduleState.changedCommit));
      expect(changed.expectedOid, isNot(changed.currentOid));

      await _git(fixture.module.path, [
        'checkout',
        '--quiet',
        '--detach',
        'HEAD',
      ]);
      snapshot = await backend.getSubmodules(opened.repositoryId);
      expect(
        snapshot.modules.single.states,
        contains(GitSubmoduleState.detached),
      );

      final nested = await backend.getNestedRoots(opened.repositoryId);
      expect(nested.roots.map((root) => root.relativePath), contains(''));
      expect(
        nested.roots.map((root) => root.relativePath),
        contains('modules/widget'),
      );
      expect(
        nested.roots.singleWhere((root) => root.relativePath == '').kind,
        GitNestedRootKind.superproject,
      );

      await _git(fixture.superproject.path, [
        'submodule',
        'deinit',
        '--force',
        '--',
        'modules/widget',
      ]);
      snapshot = await backend.getSubmodules(opened.repositoryId);
      expect(
        snapshot.modules.single.states,
        contains(GitSubmoduleState.uninitialized),
      );

      final initialized = await backend.executeSubmoduleAction(
        opened.repositoryId,
        const GitSubmoduleActionRequest(
          action: GitSubmoduleAction.init,
          paths: ['modules/widget'],
        ),
      );
      expect(initialized.snapshot.modules.single.isInitialized, isTrue);
      expect(initialized.status.root, fixture.superproject.path);

      final synced = await backend.executeSubmoduleAction(
        opened.repositoryId,
        const GitSubmoduleActionRequest(
          action: GitSubmoduleAction.sync,
          paths: ['modules/widget'],
        ),
      );
      expect(synced.snapshot.modules.single.url, fixture.child.path);
    },
  );
}

class _SubmoduleFixture {
  const _SubmoduleFixture({
    required this.root,
    required this.child,
    required this.superproject,
    required this.module,
  });

  final Directory root;
  final Directory child;
  final Directory superproject;
  final Directory module;
}

Future<_SubmoduleFixture> _createFixture(String prefix) async {
  final root = await Directory.systemTemp.createTemp(prefix);
  final child = Directory('${root.path}/child');
  final superproject = Directory('${root.path}/superproject');
  await child.create();
  await superproject.create();
  await _git(child.path, ['init', '--quiet']);
  await _git(child.path, ['config', 'user.name', 'Submodule Tester']);
  await _git(child.path, ['config', 'user.email', 'submodule@test']);
  await File('${child.path}/README.md').writeAsString('widget\n');
  await _git(child.path, ['add', '--', 'README.md']);
  await _git(child.path, ['commit', '--quiet', '-m', 'module']);

  await _git(superproject.path, ['init', '--quiet']);
  await _git(superproject.path, ['config', 'user.name', 'Submodule Tester']);
  await _git(superproject.path, ['config', 'user.email', 'submodule@test']);
  await _git(superproject.path, ['config', 'protocol.file.allow', 'always']);
  await File('${superproject.path}/README.md').writeAsString('parent\n');
  await _git(superproject.path, ['add', '--', 'README.md']);
  await _git(superproject.path, ['commit', '--quiet', '-m', 'parent']);
  await _git(superproject.path, ['branch', '-M', 'main']);
  await _git(superproject.path, [
    '-c',
    'protocol.file.allow=always',
    'submodule',
    'add',
    '--quiet',
    child.path,
    'modules/widget',
  ]);
  await _git('${superproject.path}/modules/widget', [
    'config',
    'user.name',
    'Submodule Tester',
  ]);
  await _git('${superproject.path}/modules/widget', [
    'config',
    'user.email',
    'submodule@test',
  ]);
  await _git(superproject.path, ['commit', '--quiet', '-am', 'add module']);

  return _SubmoduleFixture(
    root: root,
    child: child,
    superproject: superproject,
    module: Directory('${superproject.path}/modules/widget'),
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
