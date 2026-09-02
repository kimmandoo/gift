import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'domain.dart';
import 'diff.dart';
import 'error.dart';
import 'executor.dart';
import 'status.dart';

/// In-memory registry for repository roots and session-local opaque IDs.
///
/// The registry deliberately never accepts a root supplied back by the UI:
/// later operations will resolve an ID through this object first.
class AppState {
  final Map<RepositoryId, _RepositoryRecord> _repositories = {};

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
