import 'dart:convert';
import 'dart:io';

import 'error.dart';

/// Describes why a Git process is being run. Mutation and remote operations
/// will use this value for serialization and cancellation in later tasks.
enum GitOperationKind { read, mutation, remote }

sealed class OutputPolicy {
  const OutputPolicy._({required this.limit});

  const factory OutputPolicy.capture({required int maxBytes}) =
      CaptureOutputPolicy;

  const factory OutputPolicy.stream({required int maxChunkBytes}) =
      StreamOutputPolicy;

  final int limit;
}

final class CaptureOutputPolicy extends OutputPolicy {
  const CaptureOutputPolicy({int maxBytes = defaultCaptureBytes})
    : super._(limit: maxBytes);

  static const defaultCaptureBytes = 16 * 1024 * 1024;
}

final class StreamOutputPolicy extends OutputPolicy {
  const StreamOutputPolicy({int maxChunkBytes = 64 * 1024})
    : super._(limit: maxChunkBytes);
}

class GitInvocation {
  GitInvocation({
    required this.program,
    required List<String> args,
    required this.cwd,
    List<int>? stdin,
    required this.kind,
    required this.outputPolicy,
  }) : args = List.unmodifiable(args),
       stdin = stdin == null ? null : List<int>.unmodifiable(stdin);

  final String program;
  final List<String> args;
  final String cwd;
  final List<int>? stdin;
  final GitOperationKind kind;
  final OutputPolicy outputPolicy;
}

class ProcessOutput {
  const ProcessOutput({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
  });

  final List<int> stdout;
  final List<int> stderr;
  final int? exitCode;
}

class ProcessGitRunner {
  const ProcessGitRunner();

  Future<ProcessOutput> run(GitInvocation invocation) async {
    // 1. Start Git with separate argv values. No shell command string is built.
    late final Process process;
    try {
      process = await Process.start(
        invocation.program,
        invocation.args,
        workingDirectory: invocation.cwd,
        runInShell: false,
        includeParentEnvironment: true,
      );
    } on ProcessException catch (error) {
      throw _spawnError(invocation.program, error);
    } on Object catch (error) {
      throw GitError(
        category: GitErrorCategory.processSpawnFailed,
        userMessage: 'Git could not be started.',
        diagnostic: '${invocation.program}: $error',
        retryable: true,
      );
    }

    // 2. Read both pipes at the same time. Waiting for only one pipe can
    // deadlock when Git fills the other pipe with diagnostics.
    final stdoutFuture = _readPipe(process.stdout, invocation.outputPolicy);
    final stderrFuture = _readPipe(process.stderr, invocation.outputPolicy);

    // 3. Close stdin even when this invocation has no payload so Git sees EOF.
    final stdinFuture = _writeStdin(process.stdin, invocation.stdin);
    final outputFutures = Future.wait<Object?>([
      stdoutFuture,
      stderrFuture,
      stdinFuture,
    ]);
    final exitCodeFuture = process.exitCode;

    // 4. Wait for all output and for Git to exit before interpreting the
    // result. The readers have already drained any bytes beyond the limit.
    final outputResults = await outputFutures;
    final exitCode = await exitCodeFuture;
    final stdout = outputResults[0]! as _ReadResult;
    final stderr = outputResults[1]! as _ReadResult;
    final stdinError = outputResults[2];

    if (stdinError case final Object error?) {
      if (error is! SocketException || error.osError?.errorCode != 32) {
        throw GitError(
          category: GitErrorCategory.processFailed,
          userMessage: 'Git could not receive its input.',
          diagnostic: '$error',
          retryable: true,
          exitCode: exitCode,
        );
      }
    }

    // 5. Turn process failures into typed, user-safe errors.
    if (stdout.exceeded || stderr.exceeded) {
      if (invocation.outputPolicy is CaptureOutputPolicy) {
        throw GitError(
          category: GitErrorCategory.outputOverflow,
          userMessage: 'Git returned more output than the configured limit.',
          diagnostic:
              'captured output exceeded ${invocation.outputPolicy.limit} bytes',
          retryable: false,
          exitCode: exitCode,
        );
      }
    }

    if (exitCode != 0) {
      throw GitError(
        category: GitErrorCategory.processFailed,
        userMessage: 'Git reported an error.',
        diagnostic: redactBytes(stderr.bytes),
        retryable: false,
        exitCode: exitCode,
      );
    }

    return ProcessOutput(
      stdout: stdout.bytes,
      stderr: stderr.bytes,
      exitCode: exitCode,
    );
  }
}

class _ReadResult {
  const _ReadResult(this.bytes, this.exceeded);

  final List<int> bytes;
  final bool exceeded;
}

Future<_ReadResult> _readPipe(
  Stream<List<int>> pipe,
  OutputPolicy policy,
) async {
  final bytes = <int>[];
  var exceeded = false;
  await for (final chunk in pipe) {
    final remaining = policy.limit - bytes.length;
    final retained = remaining < 0
        ? 0
        : remaining > chunk.length
        ? chunk.length
        : remaining;
    if (retained > 0) bytes.addAll(chunk.take(retained));
    if (retained < chunk.length && policy is CaptureOutputPolicy) {
      exceeded = true;
    }
  }
  return _ReadResult(bytes, exceeded);
}

Future<Object?> _writeStdin(IOSink sink, List<int>? input) async {
  if (input == null) {
    await sink.close();
    return null;
  }
  try {
    sink.add(input);
    await sink.close();
    return null;
  } on Object catch (error) {
    try {
      await sink.close();
    } catch (_) {
      // Preserve the original write failure.
    }
    return error;
  }
}

GitError _spawnError(String program, ProcessException error) {
  final notFound = error.errorCode == 2;
  return GitError(
    category: notFound
        ? GitErrorCategory.gitNotFound
        : GitErrorCategory.processSpawnFailed,
    userMessage: notFound
        ? 'Git could not be found.'
        : 'Git could not be started.',
    diagnostic: '$program: $error',
    retryable: true,
  );
}

String redactRemote(String remote) => redactBytes(utf8.encode(remote));

String redactBytes(List<int> input) {
  var value = utf8.decode(input, allowMalformed: true);
  value = value.replaceAllMapped(
    RegExp(r"""([A-Za-z][A-Za-z0-9+.-]*://)[^/\s?#"']*@"""),
    (match) => '${match.group(1)}***@',
  );
  value = value.replaceAllMapped(
    RegExp(
      r"""(access_token|refresh_token|password|passwd|secret|token)=([^\s&"']*)""",
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}=***',
  );
  return value;
}
