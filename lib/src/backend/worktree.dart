import 'dart:convert';

import 'domain.dart';
import 'error.dart';
import 'status.dart';

enum GitWorktreeAction { remove, lock, unlock, prune }

/// One linked worktree as reported by Git. Paths are absolute repository
/// paths; the backend never asks the UI to construct a shell command from
/// them.
class GitWorktree {
  const GitWorktree({
    required this.path,
    this.head,
    this.branch,
    this.isMain = false,
    this.isCurrent = false,
    this.isLocked = false,
    this.lockReason,
    this.isPrunable = false,
    this.pruneReason,
    this.isDirty = false,
    this.dirtyPaths = const [],
  });

  final String path;
  final String? head;
  final String? branch;
  final bool isMain;
  final bool isCurrent;
  final bool isLocked;
  final String? lockReason;
  final bool isPrunable;
  final String? pruneReason;
  final bool isDirty;
  final List<String> dirtyPaths;

  bool get isDetached => branch == null && head != null;
  bool get exists => !isPrunable;

  GitWorktree copyWith({
    bool? isMain,
    bool? isCurrent,
    bool? isDirty,
    List<String>? dirtyPaths,
  }) => GitWorktree(
    path: path,
    head: head,
    branch: branch,
    isMain: isMain ?? this.isMain,
    isCurrent: isCurrent ?? this.isCurrent,
    isLocked: isLocked,
    lockReason: lockReason,
    isPrunable: isPrunable,
    pruneReason: pruneReason,
    isDirty: isDirty ?? this.isDirty,
    dirtyPaths: dirtyPaths ?? this.dirtyPaths,
  );
}

class GitWorktreeSnapshot {
  GitWorktreeSnapshot({
    required this.repositoryId,
    required List<GitWorktree> worktrees,
    required this.fingerprint,
  }) : worktrees = List.unmodifiable(worktrees);

  final RepositoryId repositoryId;
  final List<GitWorktree> worktrees;
  final String fingerprint;
}

class GitWorktreeCreateRequest {
  const GitWorktreeCreateRequest({
    required this.path,
    this.branch,
    this.startPoint,
    this.createBranch = true,
    this.detach = false,
  });

  final String path;
  final String? branch;
  final String? startPoint;
  final bool createBranch;
  final bool detach;

  String get queryKey =>
      [path, branch ?? '', startPoint ?? '', createBranch, detach].join('|');
}

class GitWorktreeCreateResult {
  const GitWorktreeCreateResult({
    required this.repositoryId,
    required this.request,
    required this.worktree,
    required this.snapshot,
    required this.summary,
  });

  final RepositoryId repositoryId;
  final GitWorktreeCreateRequest request;
  final GitWorktree worktree;
  final GitWorktreeSnapshot snapshot;
  final String summary;
}

class GitWorktreeActionRequest {
  const GitWorktreeActionRequest({
    required this.action,
    required this.path,
    this.confirmDirty = false,
    this.lockReason,
    this.confirmationToken,
  });

  final GitWorktreeAction action;
  final String path;
  final bool confirmDirty;
  final String? lockReason;
  final String? confirmationToken;

  String get queryKey =>
      [action.name, path, confirmDirty, lockReason ?? ''].join('|');
}

class GitWorktreeActionPreview {
  const GitWorktreeActionPreview({
    required this.repositoryId,
    required this.request,
    required this.worktree,
    required this.dirtyPaths,
    required this.requiresConfirmation,
    required this.fingerprint,
    this.blockingMessage,
    this.token,
    this.expiresAt,
  });

  final RepositoryId repositoryId;
  final GitWorktreeActionRequest request;
  final GitWorktree worktree;
  final List<String> dirtyPaths;
  final bool requiresConfirmation;
  final String fingerprint;
  final String? blockingMessage;
  final String? token;
  final DateTime? expiresAt;

  bool get canExecute =>
      token != null &&
      expiresAt != null &&
      expiresAt!.isAfter(DateTime.now()) &&
      blockingMessage == null;
}

class GitWorktreeActionResult {
  const GitWorktreeActionResult({
    required this.repositoryId,
    required this.request,
    required this.action,
    required this.status,
    required this.snapshot,
    required this.summary,
  });

  final RepositoryId repositoryId;
  final GitWorktreeActionRequest request;
  final GitWorktreeAction action;
  final GitStatusSnapshot status;
  final GitWorktreeSnapshot snapshot;
  final String summary;
}

/// Parses the NUL-delimited porcelain records emitted by
/// `git worktree list --porcelain -z`.
List<GitWorktree> parseGitWorktrees(List<int> output) {
  final result = <GitWorktree>[];
  final text = utf8.decode(output, allowMalformed: true);
  final records = <String>[];
  final fields = <String>[];
  for (final field in text.split('\u0000')) {
    if (field.isEmpty) {
      if (fields.isNotEmpty) {
        records.add(fields.join('\n'));
        fields.clear();
      }
    } else {
      fields.add(field);
    }
  }
  if (fields.isNotEmpty) records.add(fields.join('\n'));
  for (final rawRecord in records) {
    final record = rawRecord.trim();
    if (record.isEmpty) continue;
    String? path;
    String? head;
    String? branch;
    var locked = false;
    String? lockReason;
    var prunable = false;
    String? pruneReason;
    var bare = false;
    for (final rawLine in record.split('\n')) {
      final line = rawLine.trimRight();
      if (line.startsWith('worktree ')) {
        path = line.substring('worktree '.length);
      } else if (line.startsWith('HEAD ')) {
        head = line.substring('HEAD '.length).trim();
      } else if (line.startsWith('branch ')) {
        final value = line.substring('branch '.length).trim();
        branch = value.startsWith('refs/heads/')
            ? value.substring('refs/heads/'.length)
            : value;
      } else if (line == 'detached') {
        branch = null;
      } else if (line == 'bare') {
        bare = true;
      } else if (line == 'locked' || line.startsWith('locked ')) {
        locked = true;
        final value = line.substring('locked'.length).trim();
        lockReason = value.isEmpty ? null : value;
      } else if (line == 'prunable' || line.startsWith('prunable ')) {
        prunable = true;
        final value = line.substring('prunable'.length).trim();
        pruneReason = value.isEmpty ? null : value;
      }
    }
    if (path == null || path.isEmpty) {
      throw const FormatException('Worktree record did not contain a path.');
    }
    result.add(
      GitWorktree(
        path: path,
        head: head,
        branch: bare ? null : branch,
        isLocked: locked,
        lockReason: lockReason,
        isPrunable: prunable,
        pruneReason: pruneReason,
      ),
    );
  }
  return List.unmodifiable(result);
}

GitError worktreeInputError(String message, String diagnostic) => GitError(
  category: GitErrorCategory.parseFailure,
  userMessage: message,
  diagnostic: diagnostic,
  retryable: false,
);
