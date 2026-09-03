import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gift/src/backend/dart_git_backend.dart';
import 'package:gift/src/backend/hosting.dart';

void main() {
  test('parses safe provider metadata and builds hosted links', () async {
    final fixture = await _createFixture('gift-hosting-');
    addTearDown(() => fixture.root.delete(recursive: true));
    final backend = DartGitBackend();
    final opened = await backend.openRepository(fixture.repository.path);
    final head = await _git(fixture.repository.path, ['rev-parse', 'HEAD']);

    final hosting = await backend.getHostingRepository(opened.repositoryId);
    expect(hosting.repository?.provider, GitHostingProvider.github);
    expect(hosting.repository?.owner, 'acme');
    expect(hosting.repository?.name, 'tools');
    expect(hosting.sanitizedRemoteUrl, 'https://github.com/acme/tools');
    expect(hosting.sanitizedRemoteUrl, isNot(contains('super-secret')));

    final links = await backend.getHostingLinks(
      opened.repositoryId,
      head,
      path: 'lib/my file.dart',
      lineStart: 7,
      lineEnd: 9,
    );
    expect(links.repository?.url, 'https://github.com/acme/tools');
    expect(links.commit?.url, 'https://github.com/acme/tools/commit/$head');
    expect(
      links.file?.url,
      'https://github.com/acme/tools/blob/$head/lib/my%20file.dart',
    );
    expect(
      links.blame?.url,
      'https://github.com/acme/tools/blame/$head/lib/my%20file.dart#L7-L9',
    );

    final review = await backend.getHostingReviewCapability(
      opened.repositoryId,
    );
    expect(review.provider, GitHostingProvider.github);
    expect(review.isSupported, isFalse);
    expect(review.reason, isNotEmpty);
  });

  test('supports nested GitLab groups and keeps local Git available', () async {
    final gitLab = parseGitHostingRemote(
      'git@gitlab.com:group/team/project.git',
    );
    expect(gitLab?.provider, GitHostingProvider.gitlab);
    expect(gitLab?.owner, 'group/team');
    expect(gitLab?.name, 'project');

    expect(
      parseGitHostingRemote('https://example.test/acme/tools.git'),
      isNull,
    );
    expect(
      parseGitHostingRemote(
        'https://account:token-value@github.com/acme/private.git',
      )?.webBase,
      'https://github.com/acme/private',
    );

    final fixture = await _createFixture('gift-hosting-local-');
    addTearDown(() => fixture.root.delete(recursive: true));
    await _git(fixture.repository.path, [
      'remote',
      'set-url',
      'origin',
      'https://example.test/acme/tools.git',
    ]);
    final backend = DartGitBackend();
    final opened = await backend.openRepository(fixture.repository.path);
    final snapshot = await backend.getHostingRepository(opened.repositoryId);
    expect(snapshot.repository, isNull);
    expect(snapshot.isAvailable, isFalse);
    expect(snapshot.reason, contains('supported'));

    final links = await backend.getHostingLinks(
      opened.repositoryId,
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    expect(links.links, isEmpty);
    expect(await backend.getStatus(opened.repositoryId), isNotNull);
  });
}

class _HostingFixture {
  const _HostingFixture({required this.root, required this.repository});

  final Directory root;
  final Directory repository;
}

Future<_HostingFixture> _createFixture(String prefix) async {
  final root = await Directory.systemTemp.createTemp(prefix);
  final repository = Directory('${root.path}/repository');
  await repository.create();
  await _git(repository.path, ['init', '--quiet']);
  await _git(repository.path, ['config', 'user.name', 'Hosting Tester']);
  await _git(repository.path, ['config', 'user.email', 'hosting@test']);
  await File('${repository.path}/README.md').writeAsString('hosting\n');
  await _git(repository.path, ['add', '--', 'README.md']);
  await _git(repository.path, ['commit', '--quiet', '-m', 'hosting']);
  await _git(repository.path, [
    'remote',
    'add',
    'origin',
    'https://build-user:super-secret@github.com/acme/tools.git',
  ]);
  return _HostingFixture(root: root, repository: repository);
}

Future<String> _git(String cwd, List<String> args) async {
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
