import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'error.dart';

/// Describes why a Git process is being run. Mutation and remote operations
/// will use this value for serialization and cancellation in later tasks.
enum GitOperationKind { read, mutation, remote }

/// Captures the terminal lifecycle outcome for diagnostics without retaining
/// process objects or input payloads.
enum GitOperationOutcome { completed, failed, cancelled, timedOut }

/// A cooperative cancellation signal shared by a UI operation and its
/// ProcessGitRunner invocation.
class GitCancellationToken {
  Completer<void>? _completer;
  var _isCancelled = false;

  bool get isCancelled => _isCancelled;

  Future<void> get whenCancelled {
    return (_completer ??= Completer<void>()).future;
  }

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    _completer?.complete();
  }
}

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
    this.cancellationToken,
    this.timeout,
    Map<String, String>? environment,
    Iterable<String> sensitiveValues = const <String>[],
    this.cleanup,
  }) : args = List.unmodifiable(args),
       stdin = stdin == null ? null : List<int>.unmodifiable(stdin),
       environment = environment == null
           ? null
           : Map<String, String>.unmodifiable(environment),
       sensitiveValues = List.unmodifiable(
         sensitiveValues.where((value) => value.isNotEmpty),
       );

  final String program;
  final List<String> args;
  final String cwd;
  final List<int>? stdin;
  final GitOperationKind kind;
  final OutputPolicy outputPolicy;
  final GitCancellationToken? cancellationToken;
  final Duration? timeout;
  final Map<String, String>? environment;
  final List<String> sensitiveValues;
  final Future<void> Function()? cleanup;
}

/// A bounded, credential-safe record of one Git process invocation. Stdin is
/// deliberately represented only by its byte count because commit messages
/// and credentials may be supplied there.
class GitOperationRecord {
  GitOperationRecord({
    required this.startedAt,
    required this.duration,
    required this.program,
    required List<String> args,
    required this.cwd,
    required this.kind,
    required this.succeeded,
    required this.exitCode,
    required this.diagnostic,
    required this.stdinBytes,
    this.outcome = GitOperationOutcome.completed,
  }) : args = List.unmodifiable(args);

  final DateTime startedAt;
  final Duration duration;
  final String program;
  final List<String> args;
  final String cwd;
  final GitOperationKind kind;
  final bool succeeded;
  final int? exitCode;
  final String diagnostic;
  final int stdinBytes;
  final GitOperationOutcome outcome;

  String get command => [program, ...args].join(' ');
}

/// Process-local operation history used by the recovery diagnostics view.
/// It is intentionally bounded and can be filtered to one registered root.
class GitOperationHistory {
  GitOperationHistory._();

  static final shared = GitOperationHistory._();
  static const maxRecords = 200;
  final List<GitOperationRecord> _records = [];

  void clear() => _records.clear();

  List<GitOperationRecord> records({String? cwd, int limit = 100}) {
    final boundedLimit = limit.clamp(0, maxRecords);
    final filtered = cwd == null
        ? _records
        : _records.where((record) => record.cwd == cwd).toList(growable: false);
    return List.unmodifiable(filtered.reversed.take(boundedLimit));
  }

  void add({
    required GitInvocation invocation,
    required DateTime startedAt,
    required Duration duration,
    required bool succeeded,
    required int? exitCode,
    required String diagnostic,
    GitOperationOutcome? outcome,
  }) {
    _records.add(
      GitOperationRecord(
        startedAt: startedAt,
        duration: duration,
        succeeded: succeeded,
        exitCode: exitCode,
        program: redactBytes(
          utf8.encode(invocation.program),
          sensitiveValues: invocation.sensitiveValues,
        ),
        args: [
          for (final arg in invocation.args)
            _redactOperationArgument(
              arg,
              sensitiveValues: invocation.sensitiveValues,
            ),
        ],
        cwd: invocation.cwd,
        kind: invocation.kind,
        diagnostic: _boundOperationText(
          redactBytes(
            utf8.encode(diagnostic),
            sensitiveValues: invocation.sensitiveValues,
          ),
        ),
        stdinBytes: invocation.stdin?.length ?? 0,
        outcome:
            outcome ??
            (succeeded
                ? GitOperationOutcome.completed
                : GitOperationOutcome.failed),
      ),
    );
    if (_records.length > maxRecords) {
      _records.removeRange(0, _records.length - maxRecords);
    }
  }
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
  const ProcessGitRunner({this.defaultTimeout = const Duration(minutes: 2)});

  final Duration defaultTimeout;

  Future<ProcessOutput> run(GitInvocation invocation) async {
    final startedAt = DateTime.now();
    final stopwatch = Stopwatch()..start();
    try {
      final output = await _run(invocation);
      GitOperationHistory.shared.add(
        invocation: invocation,
        startedAt: startedAt,
        duration: stopwatch.elapsed,
        succeeded: true,
        exitCode: output.exitCode,
        diagnostic: redactBytes(
          output.stderr,
          sensitiveValues: invocation.sensitiveValues,
        ),
        outcome: GitOperationOutcome.completed,
      );
      return output;
    } on Object catch (error) {
      GitOperationHistory.shared.add(
        invocation: invocation,
        startedAt: startedAt,
        duration: stopwatch.elapsed,
        succeeded: false,
        exitCode: error is GitError ? error.exitCode : null,
        diagnostic: error is GitError ? error.diagnostic : '$error',
        outcome: _operationOutcome(error),
      );
      rethrow;
    } finally {
      try {
        await invocation.cleanup?.call();
      } on Object {
        // Temporary auth helpers are best-effort cleanup. The Git result is
        // more useful than replacing it with a cleanup failure.
      }
    }
  }

  Future<ProcessOutput> _run(GitInvocation invocation) async {
    if (invocation.cancellationToken?.isCancelled == true) {
      throw _cancelledError();
    }
    // 1. Start Git with separate argv values. No shell command string is built.
    late final Process process;
    try {
      process = await Process.start(
        invocation.program,
        invocation.args,
        workingDirectory: invocation.cwd,
        runInShell: false,
        includeParentEnvironment: true,
        environment: {
          'GIT_TERMINAL_PROMPT': '0',
          'GCM_INTERACTIVE': 'Never',
          ...?invocation.environment,
        },
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
    final outcome = await Future.any<_ProcessOutcome>([
      exitCodeFuture.then(_ProcessOutcome.completed),
      if (invocation.cancellationToken case final token?)
        token.whenCancelled.then((_) => const _ProcessOutcome.cancelled()),
      Future<void>.delayed(invocation.timeout ?? defaultTimeout)
          .then((_) => const _ProcessOutcome.timedOut()),
    ]);
    if (!outcome.completedNormally) {
      await _terminateProcessTree(process);
    }

    // 4. Wait for all output and for Git to exit before interpreting the
    // result. The readers have already drained any bytes beyond the limit.
    final outputResults = await outputFutures;
    final exitCode = await exitCodeFuture;
    final stdout = outputResults[0]! as _ReadResult;
    final stderr = outputResults[1]! as _ReadResult;
    final stdinError = outputResults[2];

    if (outcome.wasCancelled) {
      throw _cancelledError(exitCode: exitCode);
    }
    if (outcome.didTimeOut) {
      throw GitError(
        category: GitErrorCategory.timeout,
        userMessage: 'The Git operation took too long and was stopped.',
        diagnostic: 'the Git process exceeded its configured timeout',
        retryable: true,
        exitCode: exitCode,
      );
    }

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
        diagnostic: redactBytes(
          stderr.bytes,
          sensitiveValues: invocation.sensitiveValues,
        ),
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

/// Terminates the process and descendants without retaining them after the
/// invocation completes. POSIX descendants are read from `/proc`; Windows
/// uses the platform-provided process-tree termination command.
Future<void> _terminateProcessTree(Process process) async {
  if (Platform.isWindows) {
    try {
      await Process.run('taskkill', [
        '/PID',
        '${process.pid}',
        '/T',
        '/F',
      ], runInShell: false).timeout(const Duration(seconds: 1));
    } on Object {
      process.kill();
    }
  } else {
    final descendants = await _linuxDescendantPids(process.pid);
    for (final pid in descendants.reversed) {
      Process.killPid(pid, ProcessSignal.sigterm);
    }
    process.kill(ProcessSignal.sigterm);
  }

  try {
    await process.exitCode.timeout(const Duration(milliseconds: 750));
    return;
  } on TimeoutException {
    // Escalate only when graceful termination did not close the process.
  } on Object {
    return;
  }

  if (!Platform.isWindows) {
    final descendants = await _linuxDescendantPids(process.pid);
    for (final pid in descendants.reversed) {
      Process.killPid(pid, ProcessSignal.sigkill);
    }
    process.kill(ProcessSignal.sigkill);
  } else {
    process.kill();
  }
  try {
    await process.exitCode.timeout(const Duration(milliseconds: 750));
  } on Object {
    // The original invocation will still be bounded by its closed pipes.
  }
}

Future<List<int>> _linuxDescendantPids(int rootPid) async {
  if (!Platform.isLinux) {
    return const <int>[];
  }
  final pending = <int>[rootPid];
  final descendants = <int>[];
  final seen = <int>{rootPid};
  while (pending.isNotEmpty) {
    final parent = pending.removeLast();
    final childrenFile = File('/proc/$parent/task/$parent/children');
    try {
      final text = await childrenFile.readAsString();
      for (final token in text.trim().split(RegExp(r'\\s+'))) {
        final child = int.tryParse(token);
        if (child == null || !seen.add(child)) continue;
        descendants.add(child);
        pending.add(child);
      }
    } on Object {
      // The process may have exited between the PID and /proc reads.
    }
  }
  return descendants;
}

GitOperationOutcome _operationOutcome(Object error) {
  if (error is GitError) {
    if (error.category == GitErrorCategory.cancelled) {
      return GitOperationOutcome.cancelled;
    }
    if (error.category == GitErrorCategory.timeout) {
      return GitOperationOutcome.timedOut;
    }
  }
  return GitOperationOutcome.failed;
}

String _redactOperationArgument(
  String value, {
  Iterable<String> sensitiveValues = const <String>[],
}) {
  var redacted = redactBytes(
    utf8.encode(value),
    sensitiveValues: sensitiveValues,
  );
  redacted = redacted.replaceAllMapped(
    RegExp(
      r'(access[_-]?token|refresh[_-]?token|password|passwd|secret|token)([=:])[^\s&]+',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}${match.group(2)}***',
  );
  return _boundOperationText(redacted);
}

String _boundOperationText(String value) =>
    value.length <= 4096 ? value : '${value.substring(0, 4096)}…';

enum _ProcessOutcomeKind { completed, cancelled, timedOut }

class _ProcessOutcome {
  const _ProcessOutcome.completed(this.exitCode)
    : kind = _ProcessOutcomeKind.completed;
  const _ProcessOutcome.cancelled()
    : kind = _ProcessOutcomeKind.cancelled,
      exitCode = null;
  const _ProcessOutcome.timedOut()
    : kind = _ProcessOutcomeKind.timedOut,
      exitCode = null;

  final _ProcessOutcomeKind kind;
  final int? exitCode;
  bool get completedNormally => kind == _ProcessOutcomeKind.completed;
  bool get wasCancelled => kind == _ProcessOutcomeKind.cancelled;
  bool get didTimeOut => kind == _ProcessOutcomeKind.timedOut;
}

GitError _cancelledError({int? exitCode}) => GitError(
  category: GitErrorCategory.cancelled,
  userMessage: 'The Git operation was cancelled.',
  diagnostic: 'the operation cancellation token stopped the process',
  retryable: true,
  exitCode: exitCode,
);

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

String redactBytes(
  List<int> input, {
  Iterable<String> sensitiveValues = const <String>[],
}) {
  var value = utf8.decode(input, allowMalformed: true);
  final values = sensitiveValues.where((secret) => secret.isNotEmpty).toList()
    ..sort((left, right) => right.length.compareTo(left.length));
  for (final secret in values) {
    value = value.replaceAll(secret, '***');
  }
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
