import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gift/src/backend/dart_git_backend.dart';
import 'package:gift/src/backend/executor.dart';
import 'package:gift/src/backend/recovery.dart';

void main() {
  test(
    'browses reflog and creates a new branch from a reviewed entry',
    () async {
      final fixture = await _createFixture('gift-recovery-');
      addTearDown(() => fixture.root.delete(recursive: true));
      final backend = DartGitBackend();
      final opened = await backend.openRepository(fixture.repository.path);
      final reflog = await backend.getReflog(opened.repositoryId, limit: 20);

      expect(reflog.entries, isNotEmpty);
      final entry = reflog.entries.last;
      final preview = await backend.previewRecoveryBranch(
        opened.repositoryId,
        GitRecoveryBranchRequest(
          branchName: 'recovery/old-head',
          oid: entry.oid,
          reflogFingerprint: reflog.fingerprint,
        ),
      );
      expect(preview.canExecute, isTrue);
      expect(preview.entry.oid, entry.oid);

      final result = await backend.createRecoveryBranch(
        opened.repositoryId,
        preview,
      );
      expect(result.branchName, 'recovery/old-head');
      expect(
        (await _git(fixture.repository.path, [
          'show-ref',
          '--verify',
          'refs/heads/recovery/old-head',
        ])),
        startsWith(entry.oid),
      );
    },
  );

  test('records bounded redacted Git operation diagnostics', () async {
    final fixture = await _createFixture('gift-operation-console-');
    addTearDown(() => fixture.root.delete(recursive: true));
    final backend = DartGitBackend();
    final opened = await backend.openRepository(fixture.repository.path);
    await backend.getStatus(opened.repositoryId);
    final records = await backend.getOperationRecords(opened.repositoryId);

    expect(records, isNotEmpty);
    expect(records.every((record) => record.stdinBytes == 0), isTrue);
    expect(records.any((record) => record.args.contains('status')), isTrue);
    expect(records.every((record) => record.diagnostic.length <= 4096), isTrue);

    GitOperationHistory.shared.clear();
    await const ProcessGitRunner().run(
      GitInvocation(
        program: 'git',
        args: ['-c', 'access_token=hidden-value', '--version'],
        cwd: fixture.repository.path,
        kind: GitOperationKind.read,
        outputPolicy: const OutputPolicy.capture(maxBytes: 16 * 1024),
      ),
    );
    final redacted = GitOperationHistory.shared.records().single;
    expect(redacted.command, isNot(contains('hidden-value')));
    expect(redacted.command, contains('***'));
  });
}

class _RecoveryFixture {
  const _RecoveryFixture({required this.root, required this.repository});

  final Directory root;
  final Directory repository;
}

Future<_RecoveryFixture> _createFixture(String prefix) async {
  final root = await Directory.systemTemp.createTemp(prefix);
  final repository = Directory('${root.path}/repository');
  await repository.create();
  await _runGit(repository.path, ['init', '--quiet']);
  await _runGit(repository.path, ['config', 'user.name', 'Recovery Tester']);
  await _runGit(repository.path, ['config', 'user.email', 'recovery@test']);
  await File('${repository.path}/README.md').writeAsString('one\n');
  await _runGit(repository.path, ['add', '--', 'README.md']);
  await _runGit(repository.path, ['commit', '--quiet', '-m', 'one']);
  await File('${repository.path}/README.md').writeAsString('two\n');
  await _runGit(repository.path, ['commit', '--quiet', '-am', 'two']);
  return _RecoveryFixture(root: root, repository: repository);
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

Future<void> _runGit(String cwd, List<String> args) async {
  await _git(cwd, args);
}
