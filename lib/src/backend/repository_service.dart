import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'domain.dart';
import 'branch.dart';
import 'commit.dart';
import 'discard.dart';
import 'diff.dart';
import 'error.dart';
import 'executor.dart';
import 'history.dart';
import 'remote.dart';
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
    _discardPreviews.removeWhere(
      (_, record) => !record.expiresAt.isAfter(_now()),
    );
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

  void cancelDiscardPreview(DiscardPreview preview) {
    final record = _discardPreviews[preview.token];
    if (record?.repositoryId == preview.repositoryId &&
        record?.path == preview.path) {
      _discardPreviews.remove(preview.token);
    }
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

  Future<GitHistoryPage> getHistory(
    RepositoryId repositoryId, {
    int limit = 50,
    int offset = 0,
  }) async {
    if (limit < 1 || limit > 100 || offset < 0) {
      throw const GitError(
        category: GitErrorCategory.parseFailure,
        userMessage: 'Git history paging values are invalid.',
        diagnostic: 'history limit must be 1..100 and offset must be >= 0',
        retryable: false,
      );
    }
    final handle = await state.lookup(repositoryId);
    final output = await _runner.run(
      GitInvocation(
        program: gitPath,
        args: [
          'log',
          '--all',
          '--no-color',
          '--no-decorate',
          '--date=iso-strict',
          '--topo-order',
          '--format=%H%x00%P%x00%an%x00%ae%x00%aI%x00%s%x00%b%x00%x1e',
          '--max-count=${limit + 1}',
          '--skip=$offset',
        ],
        cwd: handle.root,
        kind: GitOperationKind.read,
        outputPolicy: const OutputPolicy.capture(maxBytes: 8 * 1024 * 1024),
      ),
    );
    try {
      return parseGitHistory(
        output.stdout,
        repositoryId: repositoryId,
        offset: offset,
        limit: limit,
      );
    } on FormatException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        GitError(
          category: GitErrorCategory.parseFailure,
          userMessage: 'Git returned an unreadable history.',
          diagnostic: error.message,
          retryable: false,
        ),
        stackTrace,
      );
    }
  }

  Future<List<GitBranch>> getBranches(RepositoryId repositoryId) async {
    final handle = await state.lookup(repositoryId);
    final output = await _runner.run(
      GitInvocation(
        program: gitPath,
        args: const [
          'for-each-ref',
          '--sort=refname',
          '--format=%(refname:short)%00%(objectname)%00%(upstream:short)%00%(HEAD)',
          'refs/heads/',
        ],
        cwd: handle.root,
        kind: GitOperationKind.read,
        outputPolicy: const OutputPolicy.capture(maxBytes: 512 * 1024),
      ),
    );
    try {
      return parseGitBranches(output.stdout);
    } on FormatException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        GitError(
          category: GitErrorCategory.parseFailure,
          userMessage: 'Git returned an unreadable branch list.',
          diagnostic: error.message,
          retryable: false,
        ),
        stackTrace,
      );
    }
  }

  Future<GitBranchActionResult> createBranch(
    RepositoryId repositoryId,
    String name,
  ) => _runBranchAction(repositoryId, name, const ['switch', '--create']);

  Future<GitBranchActionResult> switchBranch(
    RepositoryId repositoryId,
    String name,
  ) => _runBranchAction(repositoryId, name, const ['switch']);

  Future<GitBranchActionResult> _runBranchAction(
    RepositoryId repositoryId,
    String name,
    List<String> command,
  ) async {
    _validateBranchName(name);
    return state.runMutation(repositoryId, () async {
      final handle = await state.lookup(repositoryId);
      try {
        await _runner.run(
          GitInvocation(
            program: gitPath,
            args: [...command, name],
            cwd: handle.root,
            kind: GitOperationKind.mutation,
            outputPolicy: const OutputPolicy.capture(maxBytes: 128 * 1024),
          ),
        );
      } on GitError catch (error, stackTrace) {
        Error.throwWithStackTrace(_mapBranchError(error), stackTrace);
      }
      final status = await getStatus(repositoryId);
      return GitBranchActionResult(
        repositoryId: repositoryId,
        branchName: name,
        status: status,
      );
    });
  }

  Future<List<GitRemote>> getRemotes(RepositoryId repositoryId) async {
    final handle = await state.lookup(repositoryId);
    final output = await _runner.run(
      GitInvocation(
        program: gitPath,
        args: const ['remote', '--verbose'],
        cwd: handle.root,
        kind: GitOperationKind.read,
        outputPolicy: const OutputPolicy.capture(maxBytes: 512 * 1024),
      ),
    );
    try {
      return parseGitRemotes(output.stdout);
    } on FormatException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        GitError(
          category: GitErrorCategory.parseFailure,
          userMessage: 'Git returned an unreadable remote list.',
          diagnostic: error.message,
          retryable: false,
        ),
        stackTrace,
      );
    }
  }

  Future<GitRemoteOperationResult> fetch(
    RepositoryId repositoryId,
    String remote, {
    GitCancellationToken? cancellationToken,
  }) => _runRemote(
    repositoryId,
    remote,
    GitRemoteOperation.fetch,
    cancellationToken: cancellationToken,
  );

  Future<GitRemoteOperationResult> pull(
    RepositoryId repositoryId,
    String remote, {
    GitCancellationToken? cancellationToken,
  }) => _runRemote(
    repositoryId,
    remote,
    GitRemoteOperation.pull,
    cancellationToken: cancellationToken,
  );

  Future<GitRemoteOperationResult> push(
    RepositoryId repositoryId,
    String remote, {
    GitCancellationToken? cancellationToken,
  }) => _runRemote(
    repositoryId,
    remote,
    GitRemoteOperation.push,
    cancellationToken: cancellationToken,
  );

  Future<GitRemoteOperationResult> _runRemote(
    RepositoryId repositoryId,
    String remote,
    GitRemoteOperation operation, {
    GitCancellationToken? cancellationToken,
  }) async {
    _validateRemoteName(remote);
    return state.runMutation(repositoryId, () async {
      final handle = await state.lookup(repositoryId);
      final status = await getStatus(repositoryId);
      final branch = status.branch.head;
      if ((operation == GitRemoteOperation.pull ||
              operation == GitRemoteOperation.push) &&
          (branch == null || branch.isEmpty || branch == '(detached)')) {
        throw const GitError(
          category: GitErrorCategory.detachedHead,
          userMessage: 'Switch to a branch before synchronizing.',
          diagnostic: 'remote operation requested while HEAD was detached',
          retryable: false,
        );
      }
      final args = switch (operation) {
        GitRemoteOperation.fetch => ['fetch', '--prune', remote],
        GitRemoteOperation.pull => ['pull', '--ff-only', remote, branch!],
        GitRemoteOperation.push => ['push', remote, branch!],
      };
      late final ProcessOutput output;
      try {
        output = await _runner.run(
          GitInvocation(
            program: gitPath,
            args: args,
            cwd: handle.root,
            kind: GitOperationKind.remote,
            outputPolicy: const OutputPolicy.capture(maxBytes: 2 * 1024 * 1024),
            cancellationToken: cancellationToken,
          ),
        );
      } on GitError catch (error, stackTrace) {
        Error.throwWithStackTrace(_mapRemoteError(error), stackTrace);
      }
      final refreshed = await getStatus(repositoryId);
      final outputText = redactBytes([...output.stdout, ...output.stderr])
          .trim();
      return GitRemoteOperationResult(
        repositoryId: repositoryId,
        remote: remote,
        operation: operation,
        status: refreshed,
        summary: outputText.isEmpty ? 'Operation complete.' : outputText,
      );
    });
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

  Future<GitStatusSnapshot> stagePatch(
    RepositoryId repositoryId,
    GitPatchSelection selection,
  ) => _applyPatchSelection(
    repositoryId,
    selection,
    expectedScope: GitDiffScope.workingTree,
  );

  Future<GitStatusSnapshot> unstagePatch(
    RepositoryId repositoryId,
    GitPatchSelection selection,
  ) => _applyPatchSelection(
    repositoryId,
    selection,
    expectedScope: GitDiffScope.staged,
    reverse: true,
  );

  /// Creates a commit from all currently staged content.
  ///
  /// The message is sent as UTF-8 on stdin through `--file=-`. This keeps
  /// arbitrary user text out of argv and preserves shell-safe execution.
  Future<GitCommitResult> commit(
    RepositoryId repositoryId,
    String message,
  ) async {
    if (message.trim().isEmpty) {
      throw const GitError(
        category: GitErrorCategory.parseFailure,
        userMessage: 'Enter a commit message.',
        diagnostic: 'commit message was empty or whitespace only',
        retryable: false,
      );
    }

    return state.runMutation(repositoryId, () async {
      final before = await getStatus(repositoryId);
      if (before.staged.isEmpty) {
        throw const GitError(
          category: GitErrorCategory.dirtyWorktree,
          userMessage: 'Stage at least one change before committing.',
          diagnostic: 'commit requested without staged changes',
          retryable: false,
        );
      }

      final handle = await state.lookup(repositoryId);
      try {
        await _runner.run(
          GitInvocation(
            program: gitPath,
            args: const ['commit', '--file=-'],
            cwd: handle.root,
            stdin: utf8.encode(message),
            kind: GitOperationKind.mutation,
            outputPolicy: const OutputPolicy.capture(maxBytes: 256 * 1024),
          ),
        );
      } on GitError catch (error, stackTrace) {
        Error.throwWithStackTrace(_mapCommitError(error), stackTrace);
      }

      final status = await getStatus(repositoryId);
      final commitOid = status.branch.oid;
      if (commitOid == null || commitOid.isEmpty) {
        throw const GitError(
          category: GitErrorCategory.parseFailure,
          userMessage: 'Git created a commit without returning its ID.',
          diagnostic: 'post-commit status did not contain branch.oid',
          retryable: false,
        );
      }
      return GitCommitResult(
        repositoryId: repositoryId,
        commitOid: commitOid,
        status: status,
      );
    });
  }

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

  void cancelDiscardPreview(DiscardPreview preview) {
    state.cancelDiscardPreview(preview);
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

  Future<GitStatusSnapshot> _applyPatchSelection(
    RepositoryId repositoryId,
    GitPatchSelection selection, {
    required GitDiffScope expectedScope,
    bool reverse = false,
  }) async {
    if (selection.scope != expectedScope) {
      throw const GitError(
        category: GitErrorCategory.stalePatch,
        userMessage: 'Choose the matching staged or working-tree diff.',
        diagnostic: 'patch operation scope did not match its command',
        retryable: false,
      );
    }
    return state.runMutation(repositoryId, () async {
      final status = await getStatus(repositoryId);
      final change = _findChange(status, selection.path);
      if (change == null ||
          change.isConflicted ||
          (expectedScope == GitDiffScope.workingTree
              ? !change.isUnstaged
              : !change.isStaged)) {
        throw const GitError(
          category: GitErrorCategory.stalePatch,
          userMessage: 'The selected change is no longer available.',
          diagnostic: 'patch operation status facet was no longer present',
          retryable: false,
        );
      }
      final diff = await getDiff(
        repositoryId,
        selection.path,
        scope: expectedScope,
        originalPath: change.originalPath,
      );
      final patch = buildSelectedPatch(diff, selection, reverse: reverse);
      final handle = await state.lookup(repositoryId);
      try {
        await _runner.run(
          GitInvocation(
            program: gitPath,
            args: ['apply', '--cached', if (reverse) '--reverse'],
            cwd: handle.root,
            stdin: patch.bytes,
            kind: GitOperationKind.mutation,
            outputPolicy: const OutputPolicy.capture(maxBytes: 256 * 1024),
          ),
        );
      } on GitError catch (error, stackTrace) {
        if (error.category == GitErrorCategory.processFailed) {
          Error.throwWithStackTrace(
            error.copyWith(
              category: GitErrorCategory.patchRejected,
              userMessage: 'Git could not apply the selected changes.',
              diagnostic: 'partial patch was rejected: ${error.diagnostic}',
              retryable: false,
            ),
            stackTrace,
          );
        }
        rethrow;
      }
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

GitError _mapCommitError(GitError error) {
  if (error.category != GitErrorCategory.processFailed ||
      !RegExp(
        r'\b(?:hook|pre-commit|commit-msg|pre-merge-commit|post-commit)\b',
        caseSensitive: false,
      ).hasMatch(error.diagnostic)) {
    return error;
  }
  return error.copyWith(
    category: GitErrorCategory.hookRejected,
    userMessage: 'The commit hook rejected this commit.',
    retryable: false,
  );
}

GitError _mapBranchError(GitError error) {
  if (error.category != GitErrorCategory.processFailed) return error;
  final diagnostic = error.diagnostic;
  if (RegExp(
    r'(local changes|would be overwritten|uncommitted changes)',
    caseSensitive: false,
  ).hasMatch(diagnostic)) {
    return error.copyWith(
      category: GitErrorCategory.dirtyWorktree,
      userMessage: 'Commit or stash local changes before switching branches.',
      retryable: false,
    );
  }
  if (RegExp(r'already exists', caseSensitive: false).hasMatch(diagnostic)) {
    return error.copyWith(
      userMessage: 'That branch already exists.',
      retryable: false,
    );
  }
  return error;
}

void _validateBranchName(String name) {
  final invalid =
      name.isEmpty ||
      name != name.trim() ||
      name.startsWith('-') ||
      name.endsWith('.') ||
      name.endsWith('/') ||
      name.startsWith('.') ||
      name.startsWith('/') ||
      name.contains('..') ||
      name.contains('@{') ||
      RegExp(r'[\u0000-\u0020~^:?*\\\[\]]').hasMatch(name) ||
      name.contains('//');
  if (invalid) {
    throw const GitError(
      category: GitErrorCategory.parseFailure,
      userMessage: 'Enter a valid branch name.',
      diagnostic: 'branch name failed Git ref validation',
      retryable: false,
    );
  }
}

void _validateRemoteName(String name) {
  if (name.isEmpty ||
      name != name.trim() ||
      name.contains('\u0000') ||
      RegExp(r'[\s/]').hasMatch(name)) {
    throw const GitError(
      category: GitErrorCategory.parseFailure,
      userMessage: 'Enter a valid remote name.',
      diagnostic: 'remote name was empty or contained whitespace/path syntax',
      retryable: false,
    );
  }
}

GitError _mapRemoteError(GitError error) {
  if (error.category != GitErrorCategory.processFailed) return error;
  final diagnostic = error.diagnostic;
  if (RegExp(
    r'(authentication failed|could not read username|permission denied|access denied)',
    caseSensitive: false,
  ).hasMatch(diagnostic)) {
    return error.copyWith(
      category: GitErrorCategory.authenticationRequired,
      userMessage: 'Git needs authentication for this remote.',
      retryable: true,
    );
  }
  if (RegExp(
    r'(could not resolve host|connection timed out|network is unreachable|failed to connect)',
    caseSensitive: false,
  ).hasMatch(diagnostic)) {
    return error.copyWith(
      category: GitErrorCategory.networkUnavailable,
      userMessage: 'The remote could not be reached.',
      retryable: true,
    );
  }
  if (RegExp(
    r'(non-fast-forward|rejected.*fetch first|updates were rejected)',
    caseSensitive: false,
  ).hasMatch(diagnostic)) {
    return error.copyWith(
      category: GitErrorCategory.nonFastForward,
      userMessage:
          'The remote rejected this push because it is not fast-forward.',
      retryable: false,
    );
  }
  if (RegExp(
    r'(merge conflict|automatic merge failed|conflict)',
    caseSensitive: false,
  ).hasMatch(diagnostic)) {
    return error.copyWith(
      category: GitErrorCategory.mergeConflict,
      userMessage: 'Git could not complete the operation because of conflicts.',
      retryable: false,
    );
  }
  return error;
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
