import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gift/src/backend/error.dart';
import 'package:gift/src/backend/executor.dart';
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

  test('reports malformed local refs as a local branch error', () async {
    await _expectParseError(
      remoteOutput: _validRemoteOutput,
      localOutput: utf8.encode('main\n'),
      expectedMessage: 'Git returned an unreadable local branch list.',
      expectedDiagnosticPrefix: 'local refs:',
    );
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
  });

  final List<int> remoteOutput;
  final List<int> localOutput;

  @override
  Future<ProcessOutput> run(GitInvocation invocation) async {
    final args = invocation.args;
    final stdout = args.isNotEmpty && args.first == 'status'
        ? utf8.encode('# branch.head main\u0000')
        : args.contains('refs/remotes/')
        ? remoteOutput
        : args.contains('refs/heads/')
        ? localOutput
        : const <int>[];
    return ProcessOutput(stdout: stdout, stderr: const [], exitCode: 0);
  }
}
