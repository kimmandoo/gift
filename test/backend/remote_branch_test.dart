import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gift/src/backend/dart_git_backend.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/error.dart';
import 'package:gift/src/backend/remote_branch.dart';

void main() {
  test('groups remote refs and reports tracking divergence', () {
    final snapshot = GitRemoteBranchSnapshot(
      repositoryId: const RepositoryId(value: 'remote-repository'),
      fingerprint: 'refs-1',
      currentBranch: 'feature',
      branches: const [
        GitRemoteBranch(
          name: 'origin/main',
          remote: 'origin',
          branch: 'main',
          oid: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          localTrackingBranch: 'feature',
        ),
      ],
      incoming: 3,
      outgoing: 1,
    );

    expect(snapshot.remoteNames, ['origin']);
    expect(snapshot.branches.single.remote, 'origin');
    expect(snapshot.branches.single.localTrackingBranch, 'feature');
    expect(snapshot.incoming, 3);
    expect(snapshot.outgoing, 1);
  });

  test('reads remote refs and checks out a tracking local branch', () async {
    final root = await Directory.systemTemp.createTemp('gift-remote-branch-');
    addTearDown(() => root.delete(recursive: true));
    final remote = Directory('${root.path}/origin.git');
    final repository = Directory('${root.path}/work');
    await remote.create();
    await repository.create();
    await _git(remote.path, ['init', '--bare', '--quiet']);
    await _git(repository.path, ['init', '--quiet']);
    await _git(repository.path, ['config', 'user.name', 'Remote Tester']);
    await _git(repository.path, ['config', 'user.email', 'remote@test']);
    await File('${repository.path}/README.md').writeAsString('main\n');
    await _git(repository.path, ['add', '--', 'README.md']);
    await _git(repository.path, ['commit', '--quiet', '-m', 'main']);
    await _git(repository.path, ['branch', '-M', 'main']);
    await _git(repository.path, ['remote', 'add', 'origin', remote.path]);
    await _git(repository.path, [
      'push',
      '--quiet',
      '--set-upstream',
      'origin',
      'main',
    ]);
    await _git(repository.path, ['switch', '-c', 'feature']);
    await File('${repository.path}/feature.txt').writeAsString('feature\n');
    await _git(repository.path, ['add', '--', 'feature.txt']);
    await _git(repository.path, ['commit', '--quiet', '-m', 'feature']);
    await _git(repository.path, ['push', '--quiet', 'origin', 'feature']);
    await _git(repository.path, ['switch', 'main']);
    await _git(repository.path, ['branch', '-D', 'feature']);

    final backend = DartGitBackend();
    final opened = await backend.openRepository(repository.path);
    final snapshot = await backend.getRemoteBranchSnapshot(opened.repositoryId);
    final feature = snapshot.branches.singleWhere(
      (branch) => branch.name == 'origin/feature',
    );

    expect(feature.oid, hasLength(40));
    expect(feature.localTrackingBranch, isNull);
    final checkedOut = await backend.checkoutRemoteBranch(
      opened.repositoryId,
      feature,
    );

    expect(checkedOut.branchName, 'feature');
    expect(checkedOut.status.branch.head, 'feature');
    expect(checkedOut.status.branch.upstream, 'origin/feature');
  });

  test('previews and applies a fetched remote update with counts', () async {
    final root = await Directory.systemTemp.createTemp('gift-update-');
    addTearDown(() => root.delete(recursive: true));
    final remote = Directory('${root.path}/origin.git');
    final repository = Directory('${root.path}/work');
    final updater = Directory('${root.path}/updater');
    await remote.create();
    await repository.create();
    await _git(remote.path, ['init', '--bare', '--quiet']);
    await _git(repository.path, ['init', '--quiet']);
    await _git(repository.path, ['config', 'user.name', 'Remote Tester']);
    await _git(repository.path, ['config', 'user.email', 'remote@test']);
    await File('${repository.path}/README.md').writeAsString('before\n');
    await _git(repository.path, ['add', '--', 'README.md']);
    await _git(repository.path, ['commit', '--quiet', '-m', 'before']);
    await _git(repository.path, ['branch', '-M', 'main']);
    await _git(repository.path, ['remote', 'add', 'origin', remote.path]);
    await _git(repository.path, [
      'push',
      '--quiet',
      '--set-upstream',
      'origin',
      'main',
    ]);
    await _git(root.path, [
      'clone',
      '--quiet',
      '--branch',
      'main',
      remote.path,
      updater.path,
    ]);
    await _git(updater.path, ['config', 'user.name', 'Remote Updater']);
    await _git(updater.path, ['config', 'user.email', 'updater@test']);
    await File('${updater.path}/README.md').writeAsString('after\n');
    await _git(updater.path, ['add', '--', 'README.md']);
    await _git(updater.path, ['commit', '--quiet', '-m', 'after']);
    await _git(updater.path, ['push', '--quiet', 'origin', 'main']);

    final backend = DartGitBackend();
    final opened = await backend.openRepository(repository.path);
    await backend.fetch(opened.repositoryId, 'origin');
    final preview = await backend.previewUpdateProject(
      opened.repositoryId,
      const GitUpdateProjectRequest(strategy: GitUpdateStrategy.merge),
    );

    expect(
      preview.incoming,
      1,
      reason:
          '${preview.branch} ${preview.upstream} '
          '${preview.currentOid} ${preview.upstreamOid}',
    );
    expect(preview.outgoing, 0);
    expect(preview.canExecute, isTrue);
    final result = await backend.executeUpdateProject(
      opened.repositoryId,
      GitUpdateProjectRequest(
        strategy: GitUpdateStrategy.merge,
        confirmationToken: preview.token,
      ),
    );

    expect(result.state, GitUpdateState.completed);
    expect(result.status.branch.behind, 0);
    expect(
      await File('${repository.path}/README.md').readAsString(),
      'after\n',
    );
  });

  test('rejects an update preview after local state changes', () async {
    final root = await Directory.systemTemp.createTemp('gift-update-stale-');
    addTearDown(() => root.delete(recursive: true));
    final remote = Directory('${root.path}/origin.git');
    final repository = Directory('${root.path}/work');
    await remote.create();
    await repository.create();
    await _git(remote.path, ['init', '--bare', '--quiet']);
    await _git(repository.path, ['init', '--quiet']);
    await _git(repository.path, ['config', 'user.name', 'Remote Tester']);
    await _git(repository.path, ['config', 'user.email', 'remote@test']);
    await File('${repository.path}/README.md').writeAsString('before\n');
    await _git(repository.path, ['add', '--', 'README.md']);
    await _git(repository.path, ['commit', '--quiet', '-m', 'before']);
    await _git(repository.path, ['branch', '-M', 'main']);
    await _git(repository.path, ['remote', 'add', 'origin', remote.path]);
    await _git(repository.path, [
      'push',
      '--quiet',
      '--set-upstream',
      'origin',
      'main',
    ]);

    final backend = DartGitBackend();
    final opened = await backend.openRepository(repository.path);
    final preview = await backend.previewUpdateProject(
      opened.repositoryId,
      const GitUpdateProjectRequest(strategy: GitUpdateStrategy.merge),
    );
    await File('${repository.path}/README.md').writeAsString('changed\n');

    await expectLater(
      backend.executeUpdateProject(
        opened.repositoryId,
        GitUpdateProjectRequest(
          strategy: GitUpdateStrategy.merge,
          confirmationToken: preview.token,
        ),
      ),
      throwsA(
        isA<GitError>().having(
          (error) => error.category,
          'category',
          GitErrorCategory.staleUpdatePreview,
        ),
      ),
    );
  });

  test('requires a local-change choice and supports reset-to-remote', () async {
    final root = await Directory.systemTemp.createTemp('gift-update-choice-');
    addTearDown(() => root.delete(recursive: true));
    final remote = Directory('${root.path}/origin.git');
    final repository = Directory('${root.path}/work');
    await remote.create();
    await repository.create();
    await _git(remote.path, ['init', '--bare', '--quiet']);
    await _git(repository.path, ['init', '--quiet']);
    await _git(repository.path, ['config', 'user.name', 'Remote Tester']);
    await _git(repository.path, ['config', 'user.email', 'remote@test']);
    await File('${repository.path}/README.md').writeAsString('base\n');
    await _git(repository.path, ['add', '--', 'README.md']);
    await _git(repository.path, ['commit', '--quiet', '-m', 'base']);
    await _git(repository.path, ['branch', '-M', 'main']);
    await _git(repository.path, ['remote', 'add', 'origin', remote.path]);
    await _git(repository.path, [
      'push',
      '--quiet',
      '--set-upstream',
      'origin',
      'main',
    ]);
    await File('${repository.path}/README.md').writeAsString('local\n');
    await _git(repository.path, ['add', '--', 'README.md']);
    await _git(repository.path, ['commit', '--quiet', '-m', 'local']);

    final backend = DartGitBackend();
    final opened = await backend.openRepository(repository.path);
    final resetPreview = await backend.previewUpdateProject(
      opened.repositoryId,
      const GitUpdateProjectRequest(strategy: GitUpdateStrategy.resetToRemote),
    );
    expect(resetPreview.outgoing, 1);
    expect(resetPreview.requiresConfirmation, isTrue);
    expect(resetPreview.canExecute, isTrue);
    final reset = await backend.executeUpdateProject(
      opened.repositoryId,
      GitUpdateProjectRequest(
        strategy: GitUpdateStrategy.resetToRemote,
        confirmationToken: resetPreview.token,
      ),
    );
    expect(reset.state, GitUpdateState.completed);
    expect(await File('${repository.path}/README.md').readAsString(), 'base\n');

    await File('${repository.path}/README.md').writeAsString('uncommitted\n');
    final dirtyPreview = await backend.previewUpdateProject(
      opened.repositoryId,
      const GitUpdateProjectRequest(strategy: GitUpdateStrategy.merge),
    );
    expect(dirtyPreview.canExecute, isFalse);
    expect(dirtyPreview.blockingMessage, contains('local changes'));
    final stashPreview = await backend.previewUpdateProject(
      opened.repositoryId,
      const GitUpdateProjectRequest(
        strategy: GitUpdateStrategy.merge,
        localChanges: GitUpdateLocalChanges.stash,
      ),
    );
    final stashed = await backend.executeUpdateProject(
      opened.repositoryId,
      GitUpdateProjectRequest(
        strategy: GitUpdateStrategy.merge,
        localChanges: GitUpdateLocalChanges.stash,
        confirmationToken: stashPreview.token,
      ),
    );
    expect(stashed.state, GitUpdateState.completed);
    expect(
      await File('${repository.path}/README.md').readAsString(),
      'uncommitted\n',
    );
  });

  test('reports merge conflicts and supports abort recovery', () async {
    final root = await Directory.systemTemp.createTemp('gift-update-conflict-');
    addTearDown(() => root.delete(recursive: true));
    final remote = Directory('${root.path}/origin.git');
    final repository = Directory('${root.path}/work');
    final updater = Directory('${root.path}/updater');
    await remote.create();
    await repository.create();
    await _git(remote.path, ['init', '--bare', '--quiet']);
    await _git(repository.path, ['init', '--quiet']);
    await _git(repository.path, ['config', 'user.name', 'Remote Tester']);
    await _git(repository.path, ['config', 'user.email', 'remote@test']);
    await File('${repository.path}/README.md').writeAsString('base\n');
    await _git(repository.path, ['add', '--', 'README.md']);
    await _git(repository.path, ['commit', '--quiet', '-m', 'base']);
    await _git(repository.path, ['branch', '-M', 'main']);
    await _git(repository.path, ['remote', 'add', 'origin', remote.path]);
    await _git(repository.path, [
      'push',
      '--quiet',
      '--set-upstream',
      'origin',
      'main',
    ]);
    await _git(root.path, [
      'clone',
      '--quiet',
      '--branch',
      'main',
      remote.path,
      updater.path,
    ]);
    await _git(updater.path, ['config', 'user.name', 'Remote Updater']);
    await _git(updater.path, ['config', 'user.email', 'updater@test']);

    await File('${repository.path}/README.md').writeAsString('local\n');
    await _git(repository.path, ['add', '--', 'README.md']);
    await _git(repository.path, ['commit', '--quiet', '-m', 'local']);
    await File('${updater.path}/README.md').writeAsString('remote\n');
    await _git(updater.path, ['add', '--', 'README.md']);
    await _git(updater.path, ['commit', '--quiet', '-m', 'remote']);
    await _git(updater.path, ['push', '--quiet', 'origin', 'main']);

    final backend = DartGitBackend();
    final opened = await backend.openRepository(repository.path);
    await backend.fetch(opened.repositoryId, 'origin');
    final preview = await backend.previewUpdateProject(
      opened.repositoryId,
      const GitUpdateProjectRequest(strategy: GitUpdateStrategy.merge),
    );
    expect(preview.incoming, 1);
    expect(preview.outgoing, 1);

    final conflict = await backend.executeUpdateProject(
      opened.repositoryId,
      GitUpdateProjectRequest(
        strategy: GitUpdateStrategy.merge,
        confirmationToken: preview.token,
      ),
    );
    expect(conflict.state, GitUpdateState.conflicted);
    expect(conflict.status.conflicts, isNotEmpty);
    expect(
      conflict.recoveryActions,
      containsAll([GitUpdatePhase.continueOperation, GitUpdatePhase.abort]),
    );

    final aborted = await backend.executeUpdateProject(
      opened.repositoryId,
      const GitUpdateProjectRequest(
        strategy: GitUpdateStrategy.merge,
        phase: GitUpdatePhase.abort,
      ),
    );
    expect(aborted.state, GitUpdateState.aborted);
    expect(aborted.status.conflicts, isEmpty);
  });

  test('rejects a moved remote branch before deleting it', () async {
    final root = await Directory.systemTemp.createTemp('gift-remote-delete-');
    addTearDown(() => root.delete(recursive: true));
    final remote = Directory('${root.path}/origin.git');
    final repository = Directory('${root.path}/work');
    final updater = Directory('${root.path}/updater');
    await remote.create();
    await repository.create();
    await _git(remote.path, ['init', '--bare', '--quiet']);
    await _git(repository.path, ['init', '--quiet']);
    await _git(repository.path, ['config', 'user.name', 'Remote Tester']);
    await _git(repository.path, ['config', 'user.email', 'remote@test']);
    await File('${repository.path}/README.md').writeAsString('main\n');
    await _git(repository.path, ['add', '--', 'README.md']);
    await _git(repository.path, ['commit', '--quiet', '-m', 'main']);
    await _git(repository.path, ['branch', '-M', 'main']);
    await _git(repository.path, ['remote', 'add', 'origin', remote.path]);
    await _git(repository.path, [
      'push',
      '--quiet',
      '--set-upstream',
      'origin',
      'main',
    ]);
    await _git(repository.path, ['switch', '-c', 'feature']);
    await File('${repository.path}/feature.txt').writeAsString('one\n');
    await _git(repository.path, ['add', '--', 'feature.txt']);
    await _git(repository.path, ['commit', '--quiet', '-m', 'feature']);
    await _git(repository.path, ['push', '--quiet', 'origin', 'feature']);
    await _git(repository.path, ['switch', 'main']);

    await _git(root.path, [
      'clone',
      '--quiet',
      '--branch',
      'feature',
      remote.path,
      updater.path,
    ]);
    await _git(updater.path, ['config', 'user.name', 'Remote Updater']);
    await _git(updater.path, ['config', 'user.email', 'updater@test']);
    await File('${updater.path}/feature.txt').writeAsString('one\ntwo\n');
    await _git(updater.path, ['add', '--', 'feature.txt']);
    await _git(updater.path, ['commit', '--quiet', '-m', 'move feature']);

    final backend = DartGitBackend();
    final opened = await backend.openRepository(repository.path);
    final listed = await backend.getRemoteBranchSnapshot(opened.repositoryId);
    final feature = listed.branches.singleWhere(
      (branch) => branch.name == 'origin/feature',
    );
    final preview = await backend.previewRemoteBranchDelete(
      opened.repositoryId,
      feature,
    );
    await _git(updater.path, ['push', '--quiet', 'origin', 'feature']);

    await expectLater(
      backend.deleteRemoteBranch(opened.repositoryId, preview),
      throwsA(
        isA<GitError>().having(
          (error) => error.category,
          'category',
          GitErrorCategory.staleRemoteRef,
        ),
      ),
    );

    await backend.fetch(opened.repositoryId, 'origin');
    final refreshed = await backend.getRemoteBranchSnapshot(
      opened.repositoryId,
    );
    final refreshedFeature = refreshed.branches.singleWhere(
      (branch) => branch.name == 'origin/feature',
    );
    final refreshedPreview = await backend.previewRemoteBranchDelete(
      opened.repositoryId,
      refreshedFeature,
    );
    final deleted = await backend.deleteRemoteBranch(
      opened.repositoryId,
      refreshedPreview,
    );
    expect(
      deleted.snapshot.branches.any(
        (branch) => branch.name == 'origin/feature',
      ),
      isFalse,
    );
  });
}

Future<void> _git(String cwd, List<String> args) async {
  final result = await Process.run('git', args, workingDirectory: cwd);
  if (result.exitCode != 0) {
    fail('git ${args.join(' ')} failed: ${result.stderr}');
  }
}
