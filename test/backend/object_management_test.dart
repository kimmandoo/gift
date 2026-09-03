import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gift/src/backend/dart_git_backend.dart';
import 'package:gift/src/backend/error.dart';
import 'package:gift/src/backend/objects.dart';

void main() {
  test('parses stable stash and tag object identities', () {
    final stash = parseGitStashes(
      utf8.encode(
        'a${'b' * 39}\u0000stash@{0}\u0000On main: save work\u0000'
        '2026-09-03T12:00:00+09:00\n',
      ),
    );
    final tags = parseGitTags(
      utf8.encode(
        'v1.0\u0000${'c' * 40}\u0000commit\u0000\u0000\u0000Release\u0000'
        '2026-09-03T12:00:00+09:00\n',
      ),
    );

    expect(stash.single.oid, 'a${'b' * 39}');
    expect(stash.single.selector, 'stash@{0}');
    expect(stash.single.branch, 'main');
    expect(tags.single.name, 'v1.0');
    expect(tags.single.kind, GitTagKind.lightweight);
    expect(tags.single.targetOid, 'c' * 40);
  });

  test('manages stash objects and protects stale drops', () async {
    final directory = await Directory.systemTemp.createTemp('gift-objects-');
    addTearDown(() => directory.delete(recursive: true));
    await git(directory.path, ['init', '--quiet']);
    await git(directory.path, ['config', 'user.name', 'Objects Tester']);
    await git(directory.path, ['config', 'user.email', 'objects@test']);
    await File('${directory.path}/notes.txt').writeAsString('base\n');
    await git(directory.path, ['add', 'notes.txt']);
    await git(directory.path, ['commit', '--quiet', '-m', 'base']);

    await File('${directory.path}/notes.txt').writeAsString('base\nstash\n');
    await File('${directory.path}/untracked.txt').writeAsString('extra\n');
    final backend = DartGitBackend();
    final opened = await backend.openRepository(directory.path);
    final created = await backend.createStash(
      opened.repositoryId,
      message: 'save work',
      includeUntracked: true,
    );
    expect(created.snapshot.entries, hasLength(1));
    final entry = created.snapshot.entries.single;
    expect(entry.oid, matches(RegExp(r'^[0-9a-f]{40,64}$')));
    expect(created.status.isClean, isTrue);

    final applied = await backend.applyStash(
      opened.repositoryId,
      entry.oid,
      fingerprint: created.snapshot.fingerprint,
    );
    expect(applied.state, GitStashActionState.completed);
    expect((await backend.getStatus(opened.repositoryId)).unstaged, isNotEmpty);
    await git(directory.path, ['reset', '--hard', '--quiet']);
    await git(directory.path, ['clean', '-fd', '--quiet']);

    final popped = await backend.popStash(
      opened.repositoryId,
      entry.oid,
      fingerprint: applied.snapshot.fingerprint,
    );
    expect(popped.state, GitStashActionState.completed);
    expect(
      popped.snapshot.entries,
      isEmpty,
      reason:
          '${popped.summary} :: ${popped.snapshot.entries.map((entry) => '${entry.selector} ${entry.oid}').join(', ')}',
    );

    await File('${directory.path}/notes.txt').writeAsString('base\nagain\n');
    final second = await backend.createStash(
      opened.repositoryId,
      message: 'branch work',
    );
    final branchEntry = second.snapshot.entries.single;
    final branchResult = await backend.branchFromStash(
      opened.repositoryId,
      'from-stash',
      branchEntry.oid,
      fingerprint: second.snapshot.fingerprint,
    );
    expect(branchResult.state, GitStashActionState.completed);
    expect(
      (await backend.getBranches(opened.repositoryId))
          .map((branch) => branch.name),
      contains('from-stash'),
    );

    await File('${directory.path}/notes.txt').writeAsString('base\nthird\n');
    final third = await backend.createStash(
      opened.repositoryId,
      message: 'drop me',
    );
    final preview = await backend.previewStashDrop(
      opened.repositoryId,
      third.snapshot.entries.single.oid,
    );
    await File('${directory.path}/notes.txt').writeAsString('base\nchanged\n');
    final changed = await backend.createStash(
      opened.repositoryId,
      message: 'newer stash',
    );
    expect(changed.snapshot.entries, hasLength(2));
    await expectLater(
      backend.dropStash(opened.repositoryId, preview),
      throwsA(
        isA<GitError>().having(
          (error) => error.category,
          'category',
          GitErrorCategory.staleObject,
        ),
      ),
    );
  });

  test(
    'manages tags, remotes, explicit tag push, and upstream tracking',
    () async {
      final directory = await Directory.systemTemp.createTemp('gift-objects-');
      final remoteDirectory = await Directory.systemTemp.createTemp(
        'gift-remote-',
      );
      addTearDown(() => directory.delete(recursive: true));
      addTearDown(() => remoteDirectory.delete(recursive: true));
      await git(directory.path, ['init', '--quiet']);
      await git(directory.path, ['config', 'user.name', 'Objects Tester']);
      await git(directory.path, ['config', 'user.email', 'objects@test']);
      await File('${directory.path}/notes.txt').writeAsString('base\n');
      await git(directory.path, ['add', 'notes.txt']);
      await git(directory.path, ['commit', '--quiet', '-m', 'base']);
      await git(remoteDirectory.path, ['init', '--bare', '--quiet']);

      final backend = DartGitBackend();
      final opened = await backend.openRepository(directory.path);
      final lightweight = await backend.createTag(opened.repositoryId, 'v1.0');
      final annotated = await backend.createTag(
        opened.repositoryId,
        'v1.0-annotated',
        annotated: true,
        message: 'annotated release',
      );
      expect(lightweight.tag?.kind, GitTagKind.lightweight);
      expect(annotated.tag?.kind, GitTagKind.annotated);
      expect(
        (await backend.getTag(opened.repositoryId, 'v1.0-annotated')).message,
        contains('annotated release'),
      );

      final remote = await backend.addRemote(
        opened.repositoryId,
        'origin',
        remoteDirectory.path,
      );
      expect(remote.remotes.single.name, 'origin');
      final published = await backend.publishBranch(
        opened.repositoryId,
        'origin',
      );
      expect(published.upstream.remote, 'origin');
      expect(published.upstream.remoteBranch, 'master');
      expect(published.upstream.ahead, 0);
      expect(published.upstream.behind, 0);

      final pushedTag = await backend.pushTag(
        opened.repositoryId,
        'origin',
        'v1.0',
      );
      expect(pushedTag.target, 'v1.0');
      expect(
        await gitOutput(remoteDirectory.path, ['show-ref', '--tags', 'v1.0']),
        contains(lightweight.tag!.targetOid),
      );

      final renamed = await backend.renameRemote(
        opened.repositoryId,
        'origin',
        'upstream',
      );
      expect(renamed.remotes.single.name, 'upstream');
      final edited = await backend.setRemoteUrl(
        opened.repositoryId,
        'upstream',
        remoteDirectory.path,
      );
      expect(edited.remotes.single.fetchUrl, remoteDirectory.path);
      final pushUrl = '${remoteDirectory.path}/push';
      final pushEdited = await backend.setRemoteUrl(
        opened.repositoryId,
        'upstream',
        pushUrl,
        push: true,
      );
      expect(pushEdited.remotes.single.pushUrl, pushUrl);

      final staleTagPreview = await backend.previewTagDelete(
        opened.repositoryId,
        'v1.0',
      );
      await backend.createTag(opened.repositoryId, 'v1.1');
      await expectLater(
        backend.deleteTag(opened.repositoryId, staleTagPreview),
        throwsA(
          isA<GitError>().having(
            (error) => error.category,
            'category',
            GitErrorCategory.staleObject,
          ),
        ),
      );

      final tagPreview = await backend.previewTagDelete(
        opened.repositoryId,
        'v1.0-annotated',
      );
      final deletedTag = await backend.deleteTag(
        opened.repositoryId,
        tagPreview,
      );
      expect(
        deletedTag.snapshot.tags.map((tag) => tag.name),
        isNot(contains('v1.0-annotated')),
      );

      final prunePreview = await backend.previewRemotePrune(
        opened.repositoryId,
        'upstream',
      );
      final pruned = await backend.pruneRemote(
        opened.repositoryId,
        prunePreview,
      );
      expect(pruned.action, GitRemoteAction.prune);

      final staleRemovePreview = await backend.previewRemoteRemove(
        opened.repositoryId,
        'upstream',
      );
      await backend.setRemoteUrl(
        opened.repositoryId,
        'upstream',
        '${remoteDirectory.path}/alternate',
      );
      await expectLater(
        backend.removeRemote(opened.repositoryId, staleRemovePreview),
        throwsA(
          isA<GitError>().having(
            (error) => error.category,
            'category',
            GitErrorCategory.staleObject,
          ),
        ),
      );
      final removePreview = await backend.previewRemoteRemove(
        opened.repositoryId,
        'upstream',
      );
      final removed = await backend.removeRemote(
        opened.repositoryId,
        removePreview,
      );
      expect(removed.remotes, isEmpty);
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
