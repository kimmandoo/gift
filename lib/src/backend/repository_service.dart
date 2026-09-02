import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'domain.dart';
import 'discard.dart';
import 'diff.dart';
import 'error.dart';
import 'executor.dart';
import 'status.dart';

/// In-memory registry for repository roots and session-local opaque IDs.
///
/// The registry deliberately never accepts a root supplied back by the UI:
/// later operations will resolve an ID through this object first.
class AppState {
  AppState({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final Map<RepositoryId, _RepositoryRecord> _repositories = {};
  final Map<RepositoryId, _MutationQueue> _mutationQueues = {};
  final Map<String, _DiscardPreviewRecord> _discardPreviews = {};
  final DateTime Function() _now;

  static const discardPreviewLifetime = Duration(minutes: 2);

  RepositoryOpened register(String root) {
    final repositoryId = RepositoryId(value: _newRepositoryId());
    _repositories[repositoryId] = _RepositoryRecord(root);
    return RepositoryOpened(repositoryId: repositoryId, root: root);
  }

  Future<RepositoryHandle> lookup(RepositoryId repositoryId) async {
    final record = _repositories[repositoryId];
    if (record == null) {
      throw const GitError(
        category: GitErrorCategory.invalidOpaqueId,
        userMessage: 'The repository handle is not valid for this session.',
        diagnostic: 'repository ID was not found in this registry',
        retryable: false,
      );
    }
    if (!Directory(record.root).existsSync()) {
      throw const GitError(
        category: GitErrorCategory.repositoryMoved,
        userMessage: 'The repository folder is no longer available.',
        diagnostic: 'registered repository root does not exist',
        retryable: true,
      );
    }
    return RepositoryHandle(root: record.root, generation: record.generation);
  }

  int updateStatusGeneration(RepositoryId repositoryId, String contentHash) {
    final record = _repositories[repositoryId];
    if (record == null) {
      throw const GitError(
        category: GitErrorCategory.invalidOpaqueId,
        userMessage: 'The repository handle is not valid for this session.',
        diagnostic: 'status generation requested for an unknown repository ID',
        retryable: false,
      );
    }
    if (record.statusHash != contentHash) {
      record.statusHash = contentHash;
      record.statusGeneration++;
    }
    return record.statusGeneration;
  }

  /// Serializes mutations for one repository while allowing different
  /// repositories to continue independently.
  Future<T> runMutation<T>(
    RepositoryId repositoryId,
    Future<T> Function() action,
  ) {
    final queue = _mutationQueues.putIfAbsent(repositoryId, _MutationQueue.new);
    return queue.run(action);
  }

  DiscardPreview issueDiscardPreview({
    required RepositoryId repositoryId,
    required String path,
    required String statusHash,
    required String diffHash,
  }) {
    final token = _newOpaqueToken();
    final expiresAt = _now().add(discardPreviewLifetime);
    _discardPreviews[token] = _DiscardPreviewRecord(
      repositoryId: repositoryId,
      path: path,
      statusHash: statusHash,
      diffHash: diffHash,
      expiresAt: expiresAt,
    );
    return DiscardPreview(
      repositoryId: repositoryId,
      token: token,
      path: path,
      expiresAt: expiresAt,
    );
  }

  _DiscardPreviewRecord _validateDiscardPreview(
    RepositoryId repositoryId,
    DiscardPreview preview,
  ) {
    final record = _discardPreviews[preview.token];
    if (record == null ||
        record.repositoryId != repositoryId ||
        record.repositoryId != preview.repositoryId ||
        record.path != preview.path ||
        !record.expiresAt.isAfter(_now())) {
      _discardPreviews.remove(preview.token);
      throw const GitError(
        category: GitErrorCategory.staleConfirmation,
        userMessage:
            'This discard confirmation has expired or is no longer valid.',
        diagnostic: 'discard preview token was missing, changed, or expired',
        retryable: false,
      );
    }
    return record;
  }

  void consumeDiscardPreview(String token) {
    _discardPreviews.remove(token);
  }
}

class _DiscardPreviewRecord {
  const _DiscardPreviewRecord({
    required this.repositoryId,
    required this.path,
    required this.statusHash,
    required this.diffHash,
    required this.expiresAt,
  });

  final RepositoryId repositoryId;
  final String path;
  final String statusHash;
  final String diffHash;
  final DateTime expiresAt;
}

class _MutationQueue {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() action) {
    final previous = _tail;
    final finished = Completer<void>();
    _tail = finished.future;
    return previous.then((_) => action()).whenComplete(() {
      if (!finished.isCompleted) finished.complete();
    });
  }
}

class RepositoryHandle {
  const RepositoryHandle({required this.root, required this.generation});

  final String root;
  final int generation;
}

class RepositoryService {
  RepositoryService({
    required this.gitPath,
    required this.state,
    ProcessGitRunner? runner,
  }) : _runner = runner ?? const ProcessGitRunner();

  final String gitPath;
  final ProcessGitRunner _runner;
  final AppState state;

  Future<RepositoryOpened> openRepository(String path) async {
    // Step 1: resolve the user's selection before passing it to Git.
    final workingDirectory = await _canonicalizeDirectory(path);

    // Step 2: reject bare repositories because the workspace needs a
    // working tree.
    final bareOutput = await _runForRepository(workingDirectory, const [
      'rev-parse',
      '--is-bare-repository',
    ]);
    final bare = utf8.decode(bareOutput.stdout, allowMalformed: true).trim();
    switch (bare) {
      case 'true':
        throw const GitError(
          category: GitErrorCategory.unsupportedRepositoryState,
          userMessage: 'Bare repositories cannot be opened in the workspace.',
          diagnostic: 'git rev-parse --is-bare-repository returned true',
          retryable: false,
        );
      case 'false':
        break;
      default:
        throw GitError(
          category: GitErrorCategory.parseFailure,
          userMessage: 'Git returned an unrecognized repository state.',
          diagnostic: 'unexpected bare-repository result: $bare',
          retryable: false,
        );
    }

    // Step 3: ask Git for the real root so nested folders open the same
    // workspace as their parent repository.
    final rootOutput = await _runForRepository(workingDirectory, const [
      'rev-parse',
      '--show-toplevel',
    ]);
    final reportedRoot = utf8
        .decode(rootOutput.stdout, allowMalformed: true)
        .trim();
    if (reportedRoot.isEmpty) {
      throw const GitError(
        category: GitErrorCategory.parseFailure,
        userMessage: 'Git returned an empty repository root.',
        diagnostic: 'rev-parse --show-toplevel returned no path',
        retryable: false,
      );
    }
    final canonicalRoot = await _canonicalizeDirectory(
      reportedRoot,
      moved: true,
    );
    return state.register(canonicalRoot);
  }

  Future<GitStatusSnapshot> getStatus(RepositoryId repositoryId) async {
    // The UI gives us only an opaque ID. Resolve it before using a path.
    final handle = await state.lookup(repositoryId);
    try {
      final output = await _runGit(handle.root, const [
        'status',
        '--porcelain=v2',
        '-z',
        '--branch',
      ]);
      final parsed = parseGitStatus(output.stdout);
      final generation = state.updateStatusGeneration(
        repositoryId,
        parsed.contentHash,
      );
      return GitStatusSnapshot(
        repositoryId: repositoryId,
        root: handle.root,
        branch: parsed.branch,
        changes: parsed.changes,
        contentHash: parsed.contentHash,
        generation: generation,
      );
    } on GitStatusParseException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        GitError(
          category: GitErrorCategory.parseFailure,
          userMessage: 'Git returned an unreadable status.',
          diagnostic: error.message,
          retryable: false,
        ),
        stackTrace,
      );
    }
  }

  Future<GitDiffSnapshot> getDiff(
    RepositoryId repositoryId,
    String path, {
    GitDiffScope scope = GitDiffScope.workingTree,
    String? originalPath,
  }) async {
    if (path.isEmpty ||
        path.contains('\u0000') ||
        originalPath?.contains('\u0000') == true) {
      throw const GitError(
        category: GitErrorCategory.parseFailure,
        userMessage: 'Git could not inspect that file path.',
        diagnostic: 'diff path was empty or contained a NUL byte',
        retryable: false,
      );
    }

    final handle = await state.lookup(repositoryId);
    final args = <String>[
      'diff',
      '--no-color',
      '--no-ext-diff',
      '--find-renames',
      '--unified=3',
      if (scope == GitDiffScope.staged) '--cached',
      '--',
      ...?originalPath == null ? null : [originalPath],
      path,
    ];
    final output = await _runner.run(
      GitInvocation(
        program: gitPath,
        args: args,
        cwd: handle.root,
        kind: GitOperationKind.read,
        outputPolicy: const OutputPolicy.capture(maxBytes: 4 * 1024 * 1024),
      ),
    );
    return parseUnifiedDiff(
      output.stdout,
      path: path,
      scope: scope,
    ).copyWith(repositoryId: repositoryId);
  }

  Future<GitStatusSnapshot> stage(RepositoryId repositoryId, String path) =>
      _mutatePath(repositoryId, const ['add'], path);

  Future<GitStatusSnapshot> unstage(RepositoryId repositoryId, String path) =>
      _mutatePath(repositoryId, const ['restore', '--staged'], path);

  Future<DiscardPreview> createDiscardPreview(
    RepositoryId repositoryId,
    String path,
  ) async {
    _validatePath(path);
    final status = await getStatus(repositoryId);
    final change = _findChange(status, path);
    if (change == null ||
        change.isUntracked ||
        change.isConflicted ||
        !change.isUnstaged) {
      throw const GitError(
        category: GitErrorCategory.dirtyWorktree,
        userMessage: 'Only tracked working-tree changes can be discarded.',
        diagnostic: 'discard preview requested for a non-discardable status',
        retryable: false,
      );
    }
    final diff = await getDiff(
      repositoryId,
      path,
      originalPath: change.originalPath,
    );
    return state.issueDiscardPreview(
      repositoryId: repositoryId,
      path: path,
      statusHash: status.contentHash,
      diffHash: diff.contentHash,
    );
  }

  Future<GitStatusSnapshot> discard(
    RepositoryId repositoryId,
    DiscardPreview preview,
  ) {
    return state.runMutation(repositoryId, () async {
      final record = state._validateDiscardPreview(repositoryId, preview);
      final status = await getStatus(repositoryId);
      final change = _findChange(status, record.path);
      if (status.contentHash != record.statusHash ||
          change == null ||
          change.isUntracked ||
          change.isConflicted ||
          !change.isUnstaged) {
        throw _staleDiscardError('status changed after the discard preview');
      }
      final diff = await getDiff(
        repositoryId,
        record.path,
        originalPath: change.originalPath,
      );
      if (diff.contentHash != record.diffHash) {
        throw _staleDiscardError('working-tree content changed after preview');
      }

      final handle = await state.lookup(repositoryId);
      // The path is supplied as a separate argv value after the `--` marker.
      // Keeping this invocation separate makes the preview token the only
      // source of the path used for the destructive operation.
      await _runner.run(
        GitInvocation(
          program: gitPath,
          args: ['restore', '--worktree', '--', record.path],
          cwd: handle.root,
          kind: GitOperationKind.mutation,
          outputPolicy: const OutputPolicy.capture(maxBytes: 64 * 1024),
        ),
      );
      state.consumeDiscardPreview(preview.token);
      return getStatus(repositoryId);
    });
  }

  Future<GitStatusSnapshot> _mutatePath(
    RepositoryId repositoryId,
    List<String> command,
    String path,
  ) async {
    _validatePath(path);
    return state.runMutation(repositoryId, () async {
      final handle = await state.lookup(repositoryId);
      await _runner.run(
        GitInvocation(
          program: gitPath,
          args: [...command, '--', path],
          cwd: handle.root,
          kind: GitOperationKind.mutation,
          outputPolicy: const OutputPolicy.capture(maxBytes: 64 * 1024),
        ),
      );
      // Return the post-mutation snapshot so the UI can update immediately.
      return getStatus(repositoryId);
    });
  }

  void _validatePath(String path) {
    if (path.isEmpty || path.contains('\u0000')) {
      throw const GitError(
        category: GitErrorCategory.parseFailure,
        userMessage: 'Git could not update that file path.',
        diagnostic: 'mutation path was empty or contained a NUL byte',
        retryable: false,
      );
    }
  }

  Future<ProcessOutput> _runGit(String cwd, List<String> args) => _runner.run(
    GitInvocation(
      program: gitPath,
      args: args,
      cwd: cwd,
      kind: GitOperationKind.read,
      outputPolicy: const OutputPolicy.capture(
        maxBytes: CaptureOutputPolicy.defaultCaptureBytes,
      ),
    ),
  );

  Future<ProcessOutput> _runForRepository(String cwd, List<String> args) async {
    try {
      return await _runGit(cwd, args);
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(_asNotRepository(error), stackTrace);
    }
  }
}

class _RepositoryRecord {
  _RepositoryRecord(this.root);

  final String root;
  int generation = 0;
  String? statusHash;
  int statusGeneration = 0;
}

GitChange? _findChange(GitStatusSnapshot snapshot, String path) {
  for (final change in snapshot.changes) {
    if (change.path == path) return change;
  }
  return null;
}

GitError _staleDiscardError(String diagnostic) {
  return GitError(
    category: GitErrorCategory.staleConfirmation,
    userMessage:
        'The file changed before it could be discarded. Review it again.',
    diagnostic: diagnostic,
    retryable: true,
  );
}

Future<String> _canonicalizeDirectory(String path, {bool moved = false}) async {
  final directory = Directory(path);
  try {
    if (!await directory.exists()) {
      throw const FileSystemException('directory does not exist');
    }
    return await directory.resolveSymbolicLinks();
  } on Object catch (error) {
    throw GitError(
      category: moved
          ? GitErrorCategory.repositoryMoved
          : GitErrorCategory.notRepository,
      userMessage: moved
          ? 'The repository folder is no longer available.'
          : 'The selected folder is not a Git repository.',
      diagnostic: 'could not resolve selected folder: $error',
      retryable: moved,
    );
  }
}

GitError _asNotRepository(Object error) {
  if (error is GitError && error.category == GitErrorCategory.processFailed) {
    return GitError(
      category: GitErrorCategory.notRepository,
      userMessage: 'The selected folder is not a Git repository.',
      diagnostic: error.diagnostic,
      retryable: false,
      exitCode: error.exitCode,
    );
  }
  if (error is GitError) return error;
  return GitError(
    category: GitErrorCategory.notRepository,
    userMessage: 'The selected folder is not a Git repository.',
    diagnostic: '$error',
    retryable: false,
  );
}

String _newRepositoryId() {
  final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}

String _newOpaqueToken() => _newRepositoryId();
