import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gift/src/backend/dart_git_backend.dart';
import 'package:gift/src/backend/error.dart';
import 'package:gift/src/backend/push.dart';

void main() {
  test(
    'previews the local commits and files that a push will publish',
    () async {
      final root = await Directory.systemTemp.createTemp('gift-push-review-');
      addTearDown(() => root.delete(recursive: true));
      final remote = Directory('${root.path}/origin.git');
      final repository = Directory('${root.path}/work');
      await remote.create();
      await repository.create();
      await _git(remote.path, ['init', '--bare', '--quiet']);
      await _git(repository.path, ['init', '--quiet']);
      await _git(repository.path, ['config', 'user.name', 'Push Tester']);
      await _git(repository.path, ['config', 'user.email', 'push@test']);
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
      await File('${repository.path}/feature.txt').writeAsString('feature\n');
      await _git(repository.path, ['add', '--', 'feature.txt']);
      await _git(repository.path, ['commit', '--quiet', '-m', 'add feature']);

      final backend = DartGitBackend();
      final opened = await backend.openRepository(repository.path);
      final preview = await backend.previewPush(
        opened.repositoryId,
        const GitPushRequest(remote: 'origin'),
      );

      expect(preview.remote, 'origin');
      expect(preview.targetBranch, 'main');
      expect(preview.localHead, hasLength(40));
      expect(preview.remoteHead, hasLength(40));
      expect(preview.commits.map((commit) => commit.subject), ['add feature']);
      expect(preview.changedPaths, contains('feature.txt'));
      expect(preview.canExecute, isTrue);

      final result = await backend.executePush(
        opened.repositoryId,
        preview.request,
      );
      expect(result.state, GitPushState.completed);
      expect(
        await _gitOutput(remote.path, ['rev-parse', 'refs/heads/main']),
        preview.localHead,
      );
    },
  );

  test('pushes only the selected commit target and named tags', () async {
    final fixture = await _createFixture('gift-push-target-');
    addTearDown(() => fixture.root.delete(recursive: true));
    final backend = DartGitBackend();
    final opened = await backend.openRepository(fixture.repository.path);
    final newBranch = await backend.previewPush(
      opened.repositoryId,
      const GitPushRequest(remote: 'origin', branch: 'new-target'),
    );
    expect(newBranch.remoteHead, isNull);
    await backend.executePush(opened.repositoryId, newBranch.request);
    expect(
      await _gitOutput(fixture.remote.path, [
        'rev-parse',
        'refs/heads/new-target',
      ]),
      newBranch.targetOid,
    );

    await File('${fixture.repository.path}/one.txt').writeAsString('one\n');
    await _git(fixture.repository.path, ['add', '--', 'one.txt']);
    await _git(fixture.repository.path, ['commit', '--quiet', '-m', 'one']);
    await File('${fixture.repository.path}/two.txt').writeAsString('two\n');
    await _git(fixture.repository.path, ['add', '--', 'two.txt']);
    await _git(fixture.repository.path, ['commit', '--quiet', '-m', 'two']);
    final selectedOid = await _gitOutput(fixture.repository.path, [
      'rev-parse',
      'HEAD^',
    ]);
    final selected = await backend.previewPush(
      opened.repositoryId,
      GitPushRequest(
        remote: 'origin',
        target: GitPushTarget.selectedCommit,
        commitOid: selectedOid,
      ),
    );

    expect(selected.commits.map((commit) => commit.subject), ['one']);
    expect(selected.changedPaths, contains('one.txt'));
    await backend.executePush(opened.repositoryId, selected.request);
    expect(
      await _gitOutput(fixture.remote.path, ['rev-parse', 'refs/heads/main']),
      selectedOid,
    );

    await _git(fixture.repository.path, ['tag', 'v1']);
    final tags = await backend.previewPush(
      opened.repositoryId,
      const GitPushRequest(remote: 'origin', target: GitPushTarget.allTags),
    );
    expect(tags.tags.map((tag) => tag.name), ['v1']);
    await backend.executePush(opened.repositoryId, tags.request);
    expect(
      await _gitOutput(fixture.remote.path, ['rev-parse', 'refs/tags/v1']),
      await _gitOutput(fixture.repository.path, ['rev-parse', 'HEAD']),
    );
  });

  test(
    'rejects a stale review and classifies a remote non-fast-forward',
    () async {
      final fixture = await _createFixture('gift-push-stale-');
      addTearDown(() => fixture.root.delete(recursive: true));
      await _commitLocal(fixture.repository, 'local', 'local.txt', 'local\n');
      final backend = DartGitBackend();
      final opened = await backend.openRepository(fixture.repository.path);
      final review = await backend.previewPush(
        opened.repositoryId,
        const GitPushRequest(remote: 'origin'),
      );
      await _createRemoteCommit(fixture);

      GitError? stale;
      try {
        await backend.executePush(opened.repositoryId, review.request);
      } on GitError catch (error) {
        stale = error;
      }
      expect(stale?.category, GitErrorCategory.stalePushPreview);

      final rejectedReview = await backend.previewPush(
        opened.repositoryId,
        const GitPushRequest(remote: 'origin'),
      );
      final rejected = await backend.executePush(
        opened.repositoryId,
        rejectedReview.request,
      );
      expect(rejected.state, GitPushState.rejected);
      expect(rejected.failureCategory, GitErrorCategory.nonFastForward);
      expect(
        rejected.recoveryActions,
        containsAll([
          GitPushRecoveryAction.merge,
          GitPushRecoveryAction.rebase,
        ]),
      );
    },
  );

  test('blocks force-with-lease on protected branches', () async {
    final fixture = await _createFixture('gift-push-protected-');
    addTearDown(() => fixture.root.delete(recursive: true));
    await _commitLocal(fixture.repository, 'local', 'local.txt', 'local\n');
    final remoteHead = await _gitOutput(fixture.remote.path, [
      'rev-parse',
      'refs/heads/main',
    ]);
    final backend = DartGitBackend();
    final opened = await backend.openRepository(fixture.repository.path);
    final preview = await backend.previewPush(
      opened.repositoryId,
      GitPushRequest(
        remote: 'origin',
        forceWithLease: true,
        expectedRemoteOid: remoteHead,
      ),
    );

    expect(preview.protectedBranch, isTrue);
    expect(preview.canExecute, isFalse);
    expect(preview.blockingMessage, contains('protected branch'));
  });

  test(
    'publishes a reviewed non-protected branch with force-with-lease',
    () async {
      final fixture = await _createFixture('gift-push-lease-');
      addTearDown(() => fixture.root.delete(recursive: true));
      await _git(fixture.repository.path, ['switch', '--create', 'feature']);
      await _git(fixture.repository.path, [
        'push',
        '--quiet',
        'origin',
        'feature',
      ]);
      await _commitLocal(
        fixture.repository,
        'feature update',
        'feature.txt',
        'feature\n',
      );
      final remoteHead = await _gitOutput(fixture.remote.path, [
        'rev-parse',
        'refs/heads/feature',
      ]);
      final backend = DartGitBackend();
      final opened = await backend.openRepository(fixture.repository.path);
      final preview = await backend.previewPush(
        opened.repositoryId,
        GitPushRequest(
          remote: 'origin',
          branch: 'feature',
          forceWithLease: true,
          expectedRemoteOid: remoteHead,
        ),
      );

      expect(preview.protectedBranch, isFalse);
      expect(preview.canExecute, isTrue);
      final result = await backend.executePush(
        opened.repositoryId,
        preview.request,
      );
      expect(result.state, GitPushState.completed);
      expect(
        await _gitOutput(fixture.remote.path, [
          'rev-parse',
          'refs/heads/feature',
        ]),
        preview.localHead,
      );
    },
  );
  test(
    'publishes an untracked branch and links its chosen destination',
    () async {
      final fixture = await _createFixture('gift-push-link-');
      addTearDown(() => fixture.root.delete(recursive: true));
      await _git(fixture.repository.path, ['switch', '--create', 'feature']);
      await _commitLocal(
        fixture.repository,
        'feature',
        'feature.txt',
        'feature\n',
      );
      final backend = DartGitBackend();
      final opened = await backend.openRepository(fixture.repository.path);

      final preview = await backend.previewPush(
        opened.repositoryId,
        const GitPushRequest(
          remote: 'origin',
          branch: 'review/feature',
          setUpstream: true,
        ),
      );
      expect(preview.canExecute, isTrue);

      final result = await backend.executePush(
        opened.repositoryId,
        preview.request,
      );
      final upstream = await backend.getUpstream(opened.repositoryId);

      expect(result.state, GitPushState.completed);
      expect(upstream.remote, 'origin');
      expect(upstream.remoteBranch, 'review/feature');
      expect(
        await _gitOutput(fixture.remote.path, [
          'rev-parse',
          'refs/heads/review/feature',
        ]),
        preview.localHead,
      );
    },
  );
}

class _PushFixture {
  const _PushFixture({
    required this.root,
    required this.remote,
    required this.repository,
  });

  final Directory root;
  final Directory remote;
  final Directory repository;
}

Future<_PushFixture> _createFixture(String prefix) async {
  final root = await Directory.systemTemp.createTemp(prefix);
  final remote = Directory('${root.path}/origin.git');
  final repository = Directory('${root.path}/work');
  await remote.create();
  await repository.create();
  await _git(remote.path, ['init', '--bare', '--quiet']);
  await _git(repository.path, ['init', '--quiet']);
  await _git(repository.path, ['config', 'user.name', 'Push Tester']);
  await _git(repository.path, ['config', 'user.email', 'push@test']);
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
  return _PushFixture(root: root, remote: remote, repository: repository);
}

Future<void> _commitLocal(
  Directory repository,
  String subject,
  String path,
  String contents,
) async {
  await File('${repository.path}/$path').writeAsString(contents);
  await _git(repository.path, ['add', '--', path]);
  await _git(repository.path, ['commit', '--quiet', '-m', subject]);
}

Future<void> _createRemoteCommit(_PushFixture fixture) async {
  final updater = Directory('${fixture.root.path}/updater');
  await _git(fixture.root.path, [
    'clone',
    '--quiet',
    '--branch',
    'main',
    fixture.remote.path,
    updater.path,
  ]);
  await _git(updater.path, ['config', 'user.name', 'Remote Tester']);
  await _git(updater.path, ['config', 'user.email', 'remote@test']);
  await _commitLocal(updater, 'remote', 'remote.txt', 'remote\n');
  await _git(updater.path, ['push', '--quiet', 'origin', 'main']);
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

Future<String> _gitOutput(String cwd, List<String> args) async {
  final result = await Process.run('git', args, workingDirectory: cwd);
  if (result.exitCode != 0) {
    throw ProcessException(
      'git',
      args,
      '${result.stdout}\n${result.stderr}',
      result.exitCode,
    );
  }
  return result.stdout.toString().trim();
}
