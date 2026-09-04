import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gift/src/backend/error.dart';
import 'package:gift/src/backend/executor.dart';
import 'package:gift/src/backend/remote_branch.dart';
import 'package:gift/src/backend/repository_service.dart';

void main() {
  test('reports malformed remote refs as a remote branch error', () async {
    await _expectParseError(
      remoteOutput: utf8.encode('origin/main\n'),
      localOutput: _validLocalOutput,
      expectedMessage: 'Git returned an unreadable remote branch list.',
      expectedDiagnosticPrefix: 'remote refs:',
    );
  });

  test('recovers remote refs with the simple fallback format', () async {
    final directory = await Directory.systemTemp.createTemp(
      'gift-branch-recovery-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final state = AppState();
    final repository = state.register(directory.path);
    final service = RepositoryService(
      gitPath: 'git',
      state: state,
      runner: _BranchSnapshotRunner(
        remoteOutput: utf8.encode('unexpected remote output\n'),
        fallbackRemoteOutput: utf8.encode(
          'refs/remotes/origin/main\u0000${'a' * 40}\n',
        ),
        localOutput: _validLocalOutput,
      ),
    );

    final snapshot = await service.getRemoteBranchSnapshot(
      repository.repositoryId,
    );

    expect(snapshot.branches, hasLength(1));
    expect(snapshot.branches.single.name, 'origin/main');
    expect(snapshot.branches.single.remote, 'origin');
    expect(snapshot.branches.single.branch, 'main');
  });

  test('reports malformed local refs as a local branch error', () async {
    await _expectParseError(
      remoteOutput: _validRemoteOutput,
      localOutput: utf8.encode('main\n'),
      expectedMessage: 'Git returned an unreadable local branch list.',
      expectedDiagnosticPrefix: 'local refs:',
    );
  });
  test('parses full refs with optional symref and configured remote names', () {
    final refs = parseGitRemoteBranches(
      utf8.encode(
        'refs/remotes/team/origin/main\u0000${'a' * 40}\r\n'
        'refs/remotes/team/origin/HEAD\u0000${'a' * 40}\u0000'
        'refs/remotes/team/origin/main\r\n',
      ),
      remoteNames: const ['team/origin'],
    );

    expect(refs, hasLength(2));
    expect(refs.first.name, 'team/origin/main');
    expect(refs.first.remote, 'team/origin');
    expect(refs.first.branch, 'main');
    expect(refs.first.isSymbolicHead, isFalse);
    expect(refs.last.branch, 'HEAD');
    expect(refs.last.isSymbolicHead, isTrue);
  });
}

Future<void> _expectParseError({
  required List<int> remoteOutput,
  required List<int> localOutput,
  required String expectedMessage,
  required String expectedDiagnosticPrefix,
}) async {
  final directory = await Directory.systemTemp.createTemp('gift-branch-parse-');
  addTearDown(() => directory.delete(recursive: true));
  final state = AppState();
  final repository = state.register(directory.path);
  final service = RepositoryService(
    gitPath: 'git',
    state: state,
    runner: _BranchSnapshotRunner(
      remoteOutput: remoteOutput,
      localOutput: localOutput,
    ),
  );

  await expectLater(
    service.getRemoteBranchSnapshot(repository.repositoryId),
    throwsA(
      isA<GitError>()
          .having((error) => error.userMessage, 'message', expectedMessage)
          .having(
            (error) => error.diagnostic,
            'diagnostic',
            startsWith(expectedDiagnosticPrefix),
          ),
    ),
  );
}

final _validRemoteOutput = utf8.encode('origin/main\u0000${'a' * 40}\u0000\n');
final _validLocalOutput = utf8.encode('main\u0000${'b' * 40}\u0000\u0000\n');

class _BranchSnapshotRunner extends ProcessGitRunner {
  _BranchSnapshotRunner({
    required this.remoteOutput,
    required this.localOutput,
    this.fallbackRemoteOutput,
  });
  final List<int> remoteOutput;
  final List<int> localOutput;
  final List<int>? fallbackRemoteOutput;

  @override
  Future<ProcessOutput> run(GitInvocation invocation) async {
    final args = invocation.args;
    final stdout = args.isNotEmpty && args.first == 'status'
        ? utf8.encode('# branch.head main\u0000')
        : args.contains('refs/remotes/')
        ? args.any((arg) => arg.contains('symref'))
              ? remoteOutput
              : fallbackRemoteOutput ?? remoteOutput
        : args.contains('refs/heads/')
        ? localOutput
        : const <int>[];
    return ProcessOutput(stdout: stdout, stderr: const [], exitCode: 0);
  }
}
