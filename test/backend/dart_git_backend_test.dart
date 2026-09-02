import 'dart:convert';
import 'dart:io';

import 'package:branchline/src/backend/dart_git_backend.dart';
import 'package:branchline/src/backend/domain.dart';
import 'package:branchline/src/backend/error.dart';
import 'package:branchline/src/backend/executor.dart';
import 'package:branchline/src/backend/git_installation_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses vendor-suffixed Git versions', () {
    final version = parseGitVersion(
      utf8.encode('git version 2.51.0.windows.1\n'),
    );

    expect(version.major, 2);
    expect(version.minor, 51);
    expect(version.patch, 0);
    expect(version.suffix, 'windows.1');
    expect(version.toString(), '2.51.0.windows.1');
  });

  test('rejects Git versions below the minimum', () {
    expect(
      () => const GitVersion(2, 34, 9).ensureSupported(),
      throwsA(
        isA<GitError>().having(
          (error) => error.category,
          'category',
          GitErrorCategory.unsupportedGitVersion,
        ),
      ),
    );
  });

  test('redacts credentials from remote URLs and sensitive values', () {
    expect(
      redactRemote('https://alice:secret@example.com/org/repo.git'),
      'https://***@example.com/org/repo.git',
    );
    expect(redactRemote('token=one password=two'), 'token=*** password=***');
  });

  test('starts the Dart backend and reports health', () {
    final health = DartGitBackend().health();

    expect(health, const Health(product: 'Branchline', coreVersion: '1.0.0'));
  });

  test(
    'runs Git with an exact argv and a path containing shell characters',
    () async {
      await withTempDirectory((directory) async {
        final repository = Directory(
          '${directory.path}/repo with spaces & ampersand',
        );
        await repository.create();
        await expectGitSuccess([
          'init',
          '--quiet',
        ], workingDirectory: repository.path);

        final installation = await GitInstallationService().getOrDiscover();
        final output = await const ProcessGitRunner().run(
          GitInvocation(
            program: installation.executablePath,
            args: const ['rev-parse', '--show-toplevel'],
            cwd: repository.path,
            kind: GitOperationKind.read,
            outputPolicy: const OutputPolicy.capture(
              maxBytes: CaptureOutputPolicy.defaultCaptureBytes,
            ),
          ),
        );

        expect(
          Directory(utf8.decode(output.stdout).trim())
              .resolveSymbolicLinksSync(),
          repository.resolveSymbolicLinksSync(),
        );
      });
    },
  );

  test('bounds captured output while draining a large Git response', () async {
    await withTempDirectory((directory) async {
      await expectGitSuccess([
        'init',
        '--quiet',
      ], workingDirectory: directory.path);
      final blob = await writeBlob(directory.path);
      final input = utf8.encode('$blob\n' * 256);
      final invocation = GitInvocation(
        program:
            (await GitInstallationService().getOrDiscover()).executablePath,
        args: const ['cat-file', '--batch'],
        cwd: directory.path,
        stdin: input,
        kind: GitOperationKind.read,
        outputPolicy: const OutputPolicy.capture(maxBytes: 64),
      );

      await expectLater(
        const ProcessGitRunner().run(invocation),
        throwsA(
          isA<GitError>().having(
            (error) => error.category,
            'category',
            GitErrorCategory.outputOverflow,
          ),
        ),
      );
    });
  });

  test(
    'discovers Git from PATH and preserves the previous installation',
    () async {
      final service = GitInstallationService();
      final discovered = await service.getOrDiscover();
      final missingPath = '${Directory.systemTemp.path}/missing-branchline-git';

      await expectLater(
        service.configureGitPath(missingPath),
        throwsA(
          isA<GitError>().having(
            (error) => error.category,
            'category',
            GitErrorCategory.invalidGitPath,
          ),
        ),
      );
      expect(service.current, discovered);
    },
  );

  test(
    'opens a nested directory and keeps an opaque repository handle local',
    () async {
      await withTempDirectory((directory) async {
        final repository = Directory('${directory.path}/repository');
        final nested = Directory('${repository.path}/src/nested');
        await nested.create(recursive: true);
        await expectGitSuccess([
          'init',
          '--quiet',
        ], workingDirectory: repository.path);

        final backend = DartGitBackend();
        final opened = await backend.openRepository(nested.path);

        expect(opened.root, repository.resolveSymbolicLinksSync());
        expect(opened.repositoryId.value, isNotEmpty);
        expect((await backend.lookup(opened.repositoryId)).root, opened.root);

        final otherBackend = DartGitBackend();
        await expectLater(
          otherBackend.lookup(opened.repositoryId),
          throwsA(
            isA<GitError>().having(
              (error) => error.category,
              'category',
              GitErrorCategory.invalidOpaqueId,
            ),
          ),
        );
      });
    },
  );

  test('rejects non-repositories and bare repositories', () async {
    await withTempDirectory((directory) async {
      final backend = DartGitBackend();
      await expectLater(
        backend.openRepository(directory.path),
        throwsA(
          isA<GitError>().having(
            (error) => error.category,
            'category',
            GitErrorCategory.notRepository,
          ),
        ),
      );

      final bare = Directory('${directory.path}/bare.git');
      await expectGitSuccess(['init', '--bare', '--quiet', bare.path]);
      await expectLater(
        backend.openRepository(bare.path),
        throwsA(
          isA<GitError>().having(
            (error) => error.category,
            'category',
            GitErrorCategory.unsupportedRepositoryState,
          ),
        ),
      );
    });
  });
}

Future<void> withTempDirectory(Future<void> Function(Directory) action) async {
  final directory = await Directory.systemTemp.createTemp('branchline-test-');
  try {
    await action(directory);
  } finally {
    if (directory.existsSync()) await directory.delete(recursive: true);
  }
}

Future<void> expectGitSuccess(
  List<String> args, {
  String? workingDirectory,
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
    reason: 'git $args failed:\n${result.stdout}\n${result.stderr}',
  );
}

Future<String> writeBlob(String workingDirectory) async {
  final process = await Process.start(
    'git',
    const ['hash-object', '-w', '--stdin'],
    workingDirectory: workingDirectory,
    runInShell: false,
  );
  process.stdin.add(utf8.encode('payload\n'));
  await process.stdin.close();
  final stdout = await process.stdout.transform(utf8.decoder).join();
  await process.stderr.drain<void>();
  expect(await process.exitCode, 0);
  return stdout.trim();
}
