import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:gift/src/backend/dart_git_backend.dart';
import 'package:gift/src/backend/branch.dart';
import 'package:gift/src/backend/commit.dart';
import 'package:gift/src/backend/discard.dart';
import 'package:gift/src/backend/diff.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/error.dart';
import 'package:gift/src/backend/executor.dart';
import 'package:gift/src/backend/git_installation_service.dart';
import 'package:gift/src/backend/repository_service.dart';
import 'package:gift/src/backend/remote.dart';
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
    expect(
      redactBytes(
        utf8.encode('Authorization: Bearer private-token'),
        sensitiveValues: const ['private-token'],
      ),
      'Authorization: Bearer ***',
    );
  });

  test('starts the Dart backend and reports health', () {
    final health = DartGitBackend().health();

    expect(health, const Health(product: 'gift', coreVersion: '1.0.0'));
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
      final missingPath = '${Directory.systemTemp.path}/missing-gift-git';

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
    'skips an unusable Git candidate and tries the next PATH entry',
    () async {
      await withTempDirectory((directory) async {
        final firstDirectory = Directory('${directory.path}/first')
          ..createSync();
        final secondDirectory = Directory('${directory.path}/second')
          ..createSync();
        final executableName = Platform.isWindows ? 'git.exe' : 'git';
        final first = File(
          '${firstDirectory.path}${Platform.pathSeparator}$executableName',
        )..writeAsStringSync('');
        final second = File(
          '${secondDirectory.path}${Platform.pathSeparator}$executableName',
        )..writeAsStringSync('');
        final firstPath = first.resolveSymbolicLinksSync();
        final runner = _DiscoveryRunner(failingPath: firstPath);
        final pathSeparator = Platform.isWindows ? ';' : ':';
        final service = GitInstallationService(
          runner: runner,
          environment: {
            'PATH':
                '${firstDirectory.path}$pathSeparator${secondDirectory.path}',
          },
        );

        final installation = await service.getOrDiscover();

        expect(installation.executablePath, second.resolveSymbolicLinksSync());
        expect(runner.programs, [firstPath, installation.executablePath]);
      });
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

  test(
    'reads status facets and increments generation only on changes',
    () async {
      await withTempDirectory((directory) async {
        await expectGitSuccess([
          'init',
          '--quiet',
        ], workingDirectory: directory.path);
        await expectGitSuccess([
          'config',
          'user.name',
          'Gift Test',
        ], workingDirectory: directory.path);
        await expectGitSuccess([
          'config',
          'user.email',
          'gift@example.test',
        ], workingDirectory: directory.path);

        final tracked = File('${directory.path}/tracked.txt');
        await tracked.writeAsString('initial\n');
        await expectGitSuccess([
          'add',
          'tracked.txt',
        ], workingDirectory: directory.path);
        await expectGitSuccess([
          'commit',
          '--quiet',
          '-m',
          'initial',
        ], workingDirectory: directory.path);

        final backend = DartGitBackend();
        final opened = await backend.openRepository(directory.path);
        final clean = await backend.getStatus(opened.repositoryId);
        expect(clean.isClean, isTrue);
        expect(clean.generation, 1);

        await tracked.writeAsString('staged\n');
        await expectGitSuccess([
          'add',
          'tracked.txt',
        ], workingDirectory: directory.path);
        await tracked.writeAsString('staged and unstaged\n');
        await File('${directory.path}/notes.txt').writeAsString('todo\n');

        final changed = await backend.getStatus(opened.repositoryId);
        expect(changed.generation, 2);
        expect(
          changed.staged.map((change) => change.path),
          contains('tracked.txt'),
        );
        expect(
          changed.unstaged.map((change) => change.path),
          contains('tracked.txt'),
        );
        expect(
          changed.untracked.map((change) => change.path),
          contains('notes.txt'),
        );

        final unchanged = await backend.getStatus(opened.repositoryId);
        expect(unchanged.generation, 2);
        expect(unchanged.contentHash, changed.contentHash);
      });
    },
  );

  test(
    'reads staged and working-tree unified diffs with rename metadata',
    () async {
      await withTempDirectory((directory) async {
        await expectGitSuccess([
          'init',
          '--quiet',
        ], workingDirectory: directory.path);
        await expectGitSuccess([
          'config',
          'user.name',
          'Gift Test',
        ], workingDirectory: directory.path);
        await expectGitSuccess([
          'config',
          'user.email',
          'gift@example.test',
        ], workingDirectory: directory.path);

        final tracked = File('${directory.path}/tracked.txt');
        final original = File('${directory.path}/old.txt');
        await tracked.writeAsString('initial\n');
        await original.writeAsString('rename me\n');
        await expectGitSuccess(['add', '.'], workingDirectory: directory.path);
        await expectGitSuccess([
          'commit',
          '--quiet',
          '-m',
          'initial',
        ], workingDirectory: directory.path);

        final backend = DartGitBackend();
        final opened = await backend.openRepository(directory.path);
        await tracked.writeAsString('working tree\n');

        final workingTree = await backend.getDiff(
          opened.repositoryId,
          'tracked.txt',
        );
        expect(workingTree.scope, GitDiffScope.workingTree);
        expect(workingTree.additions, 1);
        expect(workingTree.deletions, 1);
        expect(
          workingTree.lines.any((line) => line.text == '+working tree'),
          isTrue,
        );

        await expectGitSuccess([
          'add',
          'tracked.txt',
        ], workingDirectory: directory.path);
        final staged = await backend.getDiff(
          opened.repositoryId,
          'tracked.txt',
          scope: GitDiffScope.staged,
        );
        expect(staged.scope, GitDiffScope.staged);
        expect(
          staged.lines.any((line) => line.text == '+working tree'),
          isTrue,
        );

        await expectGitSuccess([
          'mv',
          'old.txt',
          'new.txt',
        ], workingDirectory: directory.path);
        final renamed = await backend.getDiff(
          opened.repositoryId,
          'new.txt',
          scope: GitDiffScope.staged,
          originalPath: 'old.txt',
        );
        expect(renamed.isRename, isTrue);
        expect(renamed.oldPath, 'old.txt');
        expect(renamed.newPath, 'new.txt');
      });
    },
  );

  test(
    'stages and unstages a selected path, including shell characters',
    () async {
      await withTempDirectory((directory) async {
        await expectGitSuccess([
          'init',
          '--quiet',
        ], workingDirectory: directory.path);
        await expectGitSuccess([
          'config',
          'user.name',
          'Gift Test',
        ], workingDirectory: directory.path);
        await expectGitSuccess([
          'config',
          'user.email',
          'gift@example.test',
        ], workingDirectory: directory.path);

        final path = 'notes & plan.txt';
        final file = File('${directory.path}/$path');
        await file.writeAsString('initial\n');
        await expectGitSuccess([
          'add',
          '--',
          path,
        ], workingDirectory: directory.path);
        await expectGitSuccess([
          'commit',
          '--quiet',
          '-m',
          'initial',
        ], workingDirectory: directory.path);

        final backend = DartGitBackend();
        final opened = await backend.openRepository(directory.path);
        await file.writeAsString('changed\n');

        final staged = await backend.stage(opened.repositoryId, path);
        expect(staged.staged.map((change) => change.path), contains(path));
        expect(staged.unstaged, isEmpty);

        final unstaged = await backend.unstage(opened.repositoryId, path);
        expect(unstaged.staged, isEmpty);
        expect(unstaged.unstaged.map((change) => change.path), contains(path));
      });
    },
  );

  test('serializes mutations for one repository handle', () async {
    final state = AppState();
    final repository = state.register(Directory.systemTemp.path);
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    var active = 0;
    var maximumActive = 0;
    var secondStarted = false;

    Future<int> mutation(Future<void> Function() body) {
      return state.runMutation(repository.repositoryId, () async {
        active++;
        maximumActive = max(maximumActive, active);
        await body();
        active--;
        return maximumActive;
      });
    }

    final first = mutation(() async {
      firstStarted.complete();
      await releaseFirst.future;
    });
    await firstStarted.future;
    final second = mutation(() async {
      secondStarted = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(secondStarted, isFalse);

    releaseFirst.complete();
    await Future.wait([first, second]);
    expect(maximumActive, 1);
  });

  test(
    'commits a UTF-8 message through stdin and returns fresh status',
    () async {
      await withTempDirectory((directory) async {
        await createCommittedRepository(directory.path, 'tracked.txt');
        final file = File('${directory.path}/tracked.txt');
        await file.writeAsString('updated\n');

        final backend = DartGitBackend();
        final opened = await backend.openRepository(directory.path);
        await backend.stage(opened.repositoryId, 'tracked.txt');

        const message = '수정: café 🚀';
        final result = await backend.commit(opened.repositoryId, message);

        expect(result, isA<GitCommitResult>());
        expect(result.commitOid, hasLength(40));
        expect(result.status.isClean, isTrue);
        expect(result.status.branch.oid, result.commitOid);

        final log = await Process.run(
          'git',
          const ['log', '-1', '--format=%B'],
          workingDirectory: directory.path,
          runInShell: false,
          stdoutEncoding: utf8,
          stderrEncoding: utf8,
        );
        expect(log.exitCode, 0);
        expect((log.stdout as String).trim(), message);
      });
    },
  );

  test('maps a rejected commit hook to hookRejected', () async {
    await withTempDirectory((directory) async {
      await createCommittedRepository(directory.path, 'tracked.txt');
      await File('${directory.path}/tracked.txt').writeAsString('updated\n');

      final hook = File('${directory.path}/.git/hooks/pre-commit');
      await hook.writeAsString(
        '#!/bin/sh\n'
        'echo "pre-commit hook rejected this commit" >&2\n'
        'exit 1\n',
      );
      if (!Platform.isWindows) {
        final chmod = await Process.run('chmod', [
          '+x',
          hook.path,
        ], runInShell: false);
        expect(chmod.exitCode, 0);
      }

      final backend = DartGitBackend();
      final opened = await backend.openRepository(directory.path);
      await backend.stage(opened.repositoryId, 'tracked.txt');

      await expectLater(
        backend.commit(opened.repositoryId, 'will be rejected'),
        throwsA(
          isA<GitError>()
              .having(
                (error) => error.category,
                'category',
                GitErrorCategory.hookRejected,
              )
              .having(
                (error) => error.userMessage,
                'userMessage',
                'The commit hook rejected this commit.',
              ),
        ),
      );

      final status = await backend.getStatus(opened.repositoryId);
      expect(
        status.staged.map((change) => change.path),
        contains('tracked.txt'),
      );
    });
  });

  test('reads bounded history pages and commit metadata', () async {
    await withTempDirectory((directory) async {
      await createCommittedRepository(directory.path, 'tracked.txt');
      final file = File('${directory.path}/tracked.txt');
      await file.writeAsString('second\n');
      await expectGitSuccess([
        'add',
        '--',
        'tracked.txt',
      ], workingDirectory: directory.path);
      await expectGitSuccess([
        'commit',
        '--quiet',
        '-m',
        'second commit',
      ], workingDirectory: directory.path);

      final backend = DartGitBackend();
      final opened = await backend.openRepository(directory.path);
      final firstPage = await backend.getHistory(opened.repositoryId, limit: 1);
      expect(firstPage.commits, hasLength(1));
      expect(firstPage.commits.single.subject, 'second commit');
      expect(firstPage.commits.single.parents, hasLength(1));
      expect(firstPage.hasMore, isTrue);

      final secondPage = await backend.getHistory(
        opened.repositoryId,
        limit: 1,
        offset: 1,
      );
      expect(secondPage.commits.single.subject, 'initial');
      expect(secondPage.hasMore, isFalse);
    });
  });

  test('creates and switches local branches with refreshed status', () async {
    await withTempDirectory((directory) async {
      await createCommittedRepository(directory.path, 'tracked.txt');
      final backend = DartGitBackend();
      final opened = await backend.openRepository(directory.path);
      final originalBranch = (await backend.getStatus(opened.repositoryId))
          .branch
          .head!;

      final created = await backend.createBranch(
        opened.repositoryId,
        'feature/history',
      );
      expect(created.branchName, 'feature/history');
      expect(created.status.branch.head, 'feature/history');

      final branches = await backend.getBranches(opened.repositoryId);
      expect(
        branches.map((branch) => branch.name),
        contains('feature/history'),
      );
      expect(
        branches.singleWhere((branch) => branch.isCurrent).name,
        'feature/history',
      );
      expect(
        branches
            .singleWhere((branch) => branch.name == originalBranch)
            .relation,
        GitBranchRelation.sameTip,
      );

      final switched = await backend.switchBranch(
        opened.repositoryId,
        originalBranch,
      );
      expect(switched.status.branch.head, originalBranch);
    });
  });

  test('rejects invalid local branch names before running Git', () async {
    await withTempDirectory((directory) async {
      await createCommittedRepository(directory.path, 'tracked.txt');
      final backend = DartGitBackend();
      final opened = await backend.openRepository(directory.path);

      await expectLater(
        backend.createBranch(opened.repositoryId, 'bad..name'),
        throwsA(
          isA<GitError>().having(
            (error) => error.category,
            'category',
            GitErrorCategory.parseFailure,
          ),
        ),
      );
    });
  });

  test('pushes to and fetches from a local remote', () async {
    await withTempDirectory((directory) async {
      final repository = Directory('${directory.path}/working');
      final remote = Directory('${directory.path}/remote.git');
      await repository.create();
      await remote.create();
      await createCommittedRepository(repository.path, 'tracked.txt');
      await expectGitSuccess([
        'init',
        '--bare',
        '--quiet',
      ], workingDirectory: remote.path);
      await expectGitSuccess([
        'remote',
        'add',
        'origin',
        remote.path,
      ], workingDirectory: repository.path);

      final backend = DartGitBackend();
      final opened = await backend.openRepository(repository.path);
      final remotes = await backend.getRemotes(opened.repositoryId);
      expect(remotes.single.name, 'origin');
      expect(remotes.single.fetchUrl, remote.path);
      expect(remotes.single.pushUrl, remote.path);

      final pushed = await backend.push(opened.repositoryId, 'origin');
      expect(pushed.operation, GitRemoteOperation.push);
      expect(pushed.status.isClean, isTrue);
      final fetched = await backend.fetch(opened.repositoryId, 'origin');
      expect(fetched.operation, GitRemoteOperation.fetch);
      final pulled = await backend.pull(opened.repositoryId, 'origin');
      expect(pulled.operation, GitRemoteOperation.pull);
    });
  });

  test(
    'cancels a running process and returns a typed cancellation error',
    () async {
      GitOperationHistory.shared.clear();
      final token = GitCancellationToken();
      final program = Platform.isWindows
          ? (Platform.environment['ComSpec'] ?? 'cmd.exe')
          : 'sleep';
      final args = Platform.isWindows
          ? const ['/d', '/c', 'ping', '127.0.0.1', '-n', '6', '>', 'NUL']
          : const ['5'];
      final future = const ProcessGitRunner().run(
        GitInvocation(
          program: program,
          args: args,
          cwd: Directory.systemTemp.path,
          kind: GitOperationKind.remote,
          outputPolicy: const OutputPolicy.capture(maxBytes: 1024),
          cancellationToken: token,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      token.cancel();

      await expectLater(
        future,
        throwsA(
          isA<GitError>().having(
            (error) => error.category,
            'category',
            GitErrorCategory.cancelled,
          ),
        ),
      );
      expect(
        GitOperationHistory.shared.records().single.outcome,
        GitOperationOutcome.cancelled,
      );
    },
  );

  test('times out a process that does not finish', () async {
    GitOperationHistory.shared.clear();
    final program = Platform.isWindows
        ? (Platform.environment['ComSpec'] ?? 'cmd.exe')
        : 'sleep';
    final args = Platform.isWindows
        ? const ['/d', '/c', 'ping', '127.0.0.1', '-n', '6', '>', 'NUL']
        : const ['5'];

    await expectLater(
      const ProcessGitRunner(defaultTimeout: Duration(milliseconds: 50)).run(
        GitInvocation(
          program: program,
          args: args,
          cwd: Directory.systemTemp.path,
          kind: GitOperationKind.read,
          outputPolicy: const OutputPolicy.capture(maxBytes: 1024),
        ),
      ),
      throwsA(
        isA<GitError>().having(
          (error) => error.category,
          'category',
          GitErrorCategory.timeout,
        ),
      ),
    );
    expect(
      GitOperationHistory.shared.records().single.outcome,
      GitOperationOutcome.timedOut,
    );
  });

  test('discards only the working-tree side after a fresh preview', () async {
    await withTempDirectory((directory) async {
      await createCommittedRepository(directory.path, 'tracked.txt');
      final file = File('${directory.path}/tracked.txt');
      final backend = DartGitBackend();
      final opened = await backend.openRepository(directory.path);

      await file.writeAsString('staged\n');
      final staged = await backend.stage(opened.repositoryId, 'tracked.txt');
      expect(
        staged.staged.map((change) => change.path),
        contains('tracked.txt'),
      );
      await file.writeAsString('staged plus working-tree\n');

      final preview = await backend.createDiscardPreview(
        opened.repositoryId,
        'tracked.txt',
      );
      final afterDiscard = await backend.discard(opened.repositoryId, preview);

      expect(
        afterDiscard.staged.map((change) => change.path),
        contains('tracked.txt'),
      );
      expect(afterDiscard.unstaged, isEmpty);
      expect(await file.readAsString(), 'staged\n');
      await expectStaleDiscard(backend, opened.repositoryId, preview);
    });
  });

  test('revokes a discard preview when confirmation is cancelled', () async {
    await withTempDirectory((directory) async {
      await createCommittedRepository(directory.path, 'tracked.txt');
      final file = File('${directory.path}/tracked.txt');
      await file.writeAsString('changed\n');
      final backend = DartGitBackend();
      final opened = await backend.openRepository(directory.path);
      final preview = await backend.createDiscardPreview(
        opened.repositoryId,
        'tracked.txt',
      );

      await backend.cancelDiscardPreview(preview);

      await expectStaleDiscard(backend, opened.repositoryId, preview);
      expect(await file.readAsString(), 'changed\n');
    });
  });

  test(
    'rejects a changed, expired, or path-mismatched discard preview',
    () async {
      await withTempDirectory((directory) async {
        await createCommittedRepository(directory.path, 'tracked.txt');
        final file = File('${directory.path}/tracked.txt');
        var now = DateTime(2026, 9, 2, 12);
        final backend = DartGitBackend(state: AppState(now: () => now));
        final opened = await backend.openRepository(directory.path);

        await file.writeAsString('first change\n');
        final changedPreview = await backend.createDiscardPreview(
          opened.repositoryId,
          'tracked.txt',
        );
        await file.writeAsString('second change\n');
        await expectStaleDiscard(backend, opened.repositoryId, changedPreview);
        expect(await file.readAsString(), 'second change\n');

        final mismatchedSource = await backend.createDiscardPreview(
          opened.repositoryId,
          'tracked.txt',
        );
        final mismatched = DiscardPreview(
          repositoryId: opened.repositoryId,
          token: mismatchedSource.token,
          path: 'other.txt',
          expiresAt: mismatchedSource.expiresAt,
        );
        await expectStaleDiscard(backend, opened.repositoryId, mismatched);

        final expired = await backend.createDiscardPreview(
          opened.repositoryId,
          'tracked.txt',
        );
        now = now.add(const Duration(minutes: 3));
        await expectStaleDiscard(backend, opened.repositoryId, expired);

        final untracked = File('${directory.path}/untracked.txt');
        await untracked.writeAsString('keep me\n');
        await expectLater(
          backend.createDiscardPreview(opened.repositoryId, 'untracked.txt'),
          throwsA(
            isA<GitError>().having(
              (error) => error.category,
              'category',
              GitErrorCategory.dirtyWorktree,
            ),
          ),
        );
        expect(await untracked.readAsString(), 'keep me\n');
      });
    },
  );
}

class _DiscoveryRunner extends ProcessGitRunner {
  _DiscoveryRunner({required this.failingPath});

  final String failingPath;
  final programs = <String>[];

  @override
  Future<ProcessOutput> run(GitInvocation invocation) async {
    programs.add(invocation.program);
    if (invocation.program == failingPath) {
      throw const GitError(
        category: GitErrorCategory.processFailed,
        userMessage: 'Git reported an error.',
        diagnostic: 'simulated unusable Git candidate',
        retryable: true,
      );
    }
    return ProcessOutput(
      stdout: utf8.encode('git version 2.51.0\n'),
      stderr: const <int>[],
      exitCode: 0,
    );
  }
}

Future<void> createCommittedRepository(String path, String fileName) async {
  await expectGitSuccess(['init', '--quiet'], workingDirectory: path);
  await expectGitSuccess([
    'config',
    'user.name',
    'Gift Test',
  ], workingDirectory: path);
  await expectGitSuccess([
    'config',
    'user.email',
    'gift@example.test',
  ], workingDirectory: path);
  await File('$path/$fileName').writeAsString('initial\n');
  await expectGitSuccess(['add', '--', fileName], workingDirectory: path);
  await expectGitSuccess([
    'commit',
    '--quiet',
    '-m',
    'initial',
  ], workingDirectory: path);
}

Future<void> expectStaleDiscard(
  DartGitBackend backend,
  RepositoryId repositoryId,
  DiscardPreview preview,
) async {
  await expectLater(
    backend.discard(repositoryId, preview),
    throwsA(
      isA<GitError>().having(
        (error) => error.category,
        'category',
        GitErrorCategory.staleConfirmation,
      ),
    ),
  );
}

Future<void> withTempDirectory(Future<void> Function(Directory) action) async {
  final directory = await Directory.systemTemp.createTemp('gift-test-');
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
