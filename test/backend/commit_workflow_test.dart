import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gift/src/backend/commit.dart';
import 'package:gift/src/backend/dart_git_backend.dart';
import 'package:gift/src/backend/error.dart';
import 'package:gift/src/backend/executor.dart';

void main() {
  test('builds a signing flag without enabling signing by default', () {
    expect(const GitCommitOptions(sign: true).toGitArguments(), ['--gpg-sign']);
    expect(
      const GitCommitOptions(sign: true, signingKey: 'ABC123').toGitArguments(),
      ['--gpg-sign=ABC123'],
    );
    expect(const GitCommitOptions().toGitArguments(), isEmpty);
  });

  test(
    'rejects empty messages and empty staged sets before mutation',
    () async {
      await withTempDirectory((directory) async {
        await createCommittedRepository(directory.path);
        final backend = DartGitBackend();
        final opened = await backend.openRepository(directory.path);

        await expectLater(
          backend.commit(opened.repositoryId, '  '),
          throwsA(
            isA<GitError>()
                .having(
                  (error) => error.category,
                  'category',
                  GitErrorCategory.parseFailure,
                )
                .having(
                  (error) => error.commitOutcome,
                  'commit outcome',
                  GitCommitOutcome.notCreated,
                ),
          ),
        );
        await expectLater(
          backend.commit(opened.repositoryId, 'nothing staged'),
          throwsA(
            isA<GitError>()
                .having(
                  (error) => error.category,
                  'category',
                  GitErrorCategory.dirtyWorktree,
                )
                .having(
                  (error) => error.commitOutcome,
                  'commit outcome',
                  GitCommitOutcome.notCreated,
                ),
          ),
        );
        expect(
          (await backend.getHistory(opened.repositoryId)).commits,
          hasLength(1),
        );
      });
    },
  );

  test(
    'preflights local and global identity without starting a commit',
    () async {
      await withTempDirectory((directory) async {
        await initRepository(directory.path);
        await configure(directory.path, 'user.name', '');
        await configure(directory.path, 'user.email', '');
        await File('${directory.path}/new.txt').writeAsString('new\n');

        final backend = DartGitBackend();
        final opened = await backend.openRepository(directory.path);
        await backend.stage(opened.repositoryId, 'new.txt');

        final preflight = await backend.preflightCommit(opened.repositoryId);
        expect(preflight.identity.isComplete, isFalse);
        expect(preflight.failure?.category, GitErrorCategory.missingIdentity);
        expect(preflight.failure?.userMessage, contains('user.name'));
        expect(preflight.failure?.diagnostic, contains('local'));
        expect(preflight.failure?.commitOutcome, GitCommitOutcome.notCreated);
        expect(
          (await backend.getStatus(opened.repositoryId)).staged,
          isNotEmpty,
        );
      });
    },
  );

  test('loads a bounded configured commit template', () async {
    await withTempDirectory((directory) async {
      await createCommittedRepository(directory.path);
      final template = File('${directory.path}/template with spaces.txt');
      await template.writeAsString('Template subject\n\n# Explain why\n');
      await configure(directory.path, 'commit.template', template.path);

      final backend = DartGitBackend();
      final opened = await backend.openRepository(directory.path);
      final loaded = await backend.loadCommitTemplate(opened.repositoryId);

      expect(loaded.path, template.path);
      expect(loaded.contents, 'Template subject\n\n# Explain why\n');
      expect(loaded.isConfigured, isTrue);
    });
  });

  test('applies amend, sign-off, cleanup, and author options', () async {
    await withTempDirectory((directory) async {
      await createCommittedRepository(directory.path);
      await File('${directory.path}/tracked.txt').writeAsString('amended\n');
      final backend = DartGitBackend();
      final opened = await backend.openRepository(directory.path);
      await backend.stage(opened.repositoryId, 'tracked.txt');

      final result = await backend.commit(
        opened.repositoryId,
        'Amended UTF-8: café 🚀\n\n# retained\n',
        options: const GitCommitOptions(
          amend: true,
          signOff: true,
          cleanup: GitCommitCleanupMode.verbatim,
          author: GitCommitAuthor(
            name: 'Override Author',
            email: 'override@example.test',
          ),
        ),
      );

      expect(result.options.amend, isTrue);
      expect(result.options.signOff, isTrue);
      expect(result.status.isClean, isTrue);
      expect(result.historyChanged, isTrue);
      final log = await runGit(directory.path, const [
        'show',
        '-s',
        '--format=%an <%ae>%x00%B',
      ]);
      expect(log, contains('Override Author <override@example.test>'));
      expect(log, contains('Signed-off-by: Gift Test <gift@example.test>'));
      expect(log, contains('# retained'));
      expect(
        await runGit(directory.path, const ['rev-list', '--count', 'HEAD']),
        '1',
      );
    });
  });

  test('rejects amend on an unborn branch', () async {
    await withTempDirectory((directory) async {
      await initRepository(directory.path);
      await configure(directory.path, 'user.name', 'Gift Test');
      await configure(directory.path, 'user.email', 'gift@example.test');
      await File('${directory.path}/new.txt').writeAsString('new\n');
      await runGit(directory.path, const ['add', '--', 'new.txt']);

      final backend = DartGitBackend();
      final opened = await backend.openRepository(directory.path);
      final preflight = await backend.preflightCommit(
        opened.repositoryId,
        options: const GitCommitOptions(amend: true),
      );

      expect(preflight.hasHead, isFalse);
      expect(preflight.failure?.category, GitErrorCategory.unbornBranch);
      await expectLater(
        backend.commit(
          opened.repositoryId,
          'cannot amend root',
          options: const GitCommitOptions(amend: true),
        ),
        throwsA(
          isA<GitError>().having(
            (error) => error.category,
            'category',
            GitErrorCategory.unbornBranch,
          ),
        ),
      );
      expect((await backend.getStatus(opened.repositoryId)).staged, isNotEmpty);
    });
  });

  test(
    'maps configured signing failures without exposing raw diagnostics',
    () async {
      await withTempDirectory((directory) async {
        await createCommittedRepository(directory.path);
        await File('${directory.path}/tracked.txt').writeAsString('signed\n');
        await configure(directory.path, 'commit.gpgSign', 'true');
        await configure(
          directory.path,
          'gpg.program',
          '${directory.path}/missing-gpg',
        );

        final backend = DartGitBackend();
        final opened = await backend.openRepository(directory.path);
        await backend.stage(opened.repositoryId, 'tracked.txt');

        await expectLater(
          backend.commit(opened.repositoryId, 'will not sign'),
          throwsA(
            isA<GitError>()
                .having(
                  (error) => error.category,
                  'category',
                  GitErrorCategory.signingFailed,
                )
                .having(
                  (error) => error.commitOutcome,
                  'commit outcome',
                  GitCommitOutcome.notCreated,
                ),
          ),
        );
        expect(
          (await backend.getStatus(opened.repositoryId)).staged,
          isNotEmpty,
        );
      });
    },
  );

  test('reports a created commit when the post-commit refresh fails', () async {
    await withTempDirectory((directory) async {
      await createCommittedRepository(directory.path);
      await File('${directory.path}/tracked.txt').writeAsString('updated\n');
      final runner = FailingSecondStatusRunner();
      final backend = DartGitBackend(runner: runner);
      final opened = await backend.openRepository(directory.path);
      await backend.stage(opened.repositoryId, 'tracked.txt');

      await expectLater(
        backend.commit(opened.repositoryId, 'refresh will fail'),
        throwsA(
          isA<GitError>()
              .having(
                (error) => error.category,
                'category',
                GitErrorCategory.commitRefreshFailed,
              )
              .having(
                (error) => error.commitOutcome,
                'commit outcome',
                GitCommitOutcome.createdButRefreshFailed,
              ),
        ),
      );
      expect(
        await runGit(directory.path, const ['rev-list', '--count', 'HEAD']),
        '2',
      );
    });
  });
}

class FailingSecondStatusRunner extends ProcessGitRunner {
  var _statusCalls = 0;

  @override
  Future<ProcessOutput> run(GitInvocation invocation) {
    if (invocation.args.isNotEmpty && invocation.args.first == 'status') {
      _statusCalls++;
      if (_statusCalls == 2) {
        throw const GitError(
          category: GitErrorCategory.processFailed,
          userMessage: 'Git status failed.',
          diagnostic: 'simulated post-commit refresh failure',
          retryable: true,
        );
      }
    }
    return super.run(invocation);
  }
}

Future<void> initRepository(String path) async {
  await runGit(path, const ['init', '--quiet']);
}

Future<void> createCommittedRepository(String path) async {
  await initRepository(path);
  await configure(path, 'user.name', 'Gift Test');
  await configure(path, 'user.email', 'gift@example.test');
  await File('$path/tracked.txt').writeAsString('initial\n');
  await runGit(path, const ['add', '--', 'tracked.txt']);
  await runGit(path, const ['commit', '--quiet', '-m', 'initial']);
}

Future<void> configure(String path, String key, String value) async {
  await runGit(path, ['config', '--local', key, value]);
}

Future<String> runGit(String path, List<String> args) async {
  final result = await Process.run(
    'git',
    args,
    workingDirectory: path,
    runInShell: false,
  );
  expect(
    result.exitCode,
    0,
    reason: 'git $args failed:\n${result.stdout}\n${result.stderr}',
  );
  return utf8.decode(utf8.encode(result.stdout.toString())).trim();
}

Future<void> withTempDirectory(Future<void> Function(Directory) action) async {
  final directory = await Directory.systemTemp.createTemp('gift-commit-test-');
  try {
    await action(directory);
  } finally {
    if (directory.existsSync()) await directory.delete(recursive: true);
  }
}
