import 'dart:convert';

import 'domain.dart';
import 'error.dart';
import 'status.dart';

/// States that can coexist while a superproject's gitlink and child checkout
/// are being inspected. The parent status is never inferred from a child
/// command failure.
enum GitSubmoduleState {
  initialized,
  uninitialized,
  dirty,
  detached,
  changedCommit,
  conflicted,
  missing,
}

enum GitSubmoduleAction { init, sync, update, deinit }

class GitSubmoduleConfig {
  const GitSubmoduleConfig({
    required this.name,
    required this.path,
    required this.url,
    this.branch,
  });

  final String name;
  final String path;
  final String url;
  final String? branch;
}

class GitSubmodule {
  GitSubmodule({
    required this.name,
    required this.path,
    required this.url,
    required List<GitSubmoduleState> states,
    this.branch,
    this.expectedOid,
    this.currentOid,
    this.description,
    List<String> dirtyPaths = const [],
  }) : states = List.unmodifiable(states),
       dirtyPaths = List.unmodifiable(dirtyPaths);

  final String name;
  final String path;
  final String url;
  final String? branch;
  final String? expectedOid;
  final String? currentOid;
  final String? description;
  final List<GitSubmoduleState> states;
  final List<String> dirtyPaths;

  bool get isInitialized => states.contains(GitSubmoduleState.initialized);
  bool get isDirty => states.contains(GitSubmoduleState.dirty);
  bool get isDetached => states.contains(GitSubmoduleState.detached);
  bool get isMissing => states.contains(GitSubmoduleState.missing);
  bool get hasChangedCommit => states.contains(GitSubmoduleState.changedCommit);
  bool get isConflicted => states.contains(GitSubmoduleState.conflicted);
}

class GitSubmoduleSnapshot {
  GitSubmoduleSnapshot({
    required this.repositoryId,
    required this.root,
    required List<GitSubmodule> modules,
    required this.fingerprint,
  }) : modules = List.unmodifiable(modules);

  final RepositoryId repositoryId;
  final String root;
  final List<GitSubmodule> modules;
  final String fingerprint;
}

class GitSubmoduleActionRequest {
  const GitSubmoduleActionRequest({
    required this.action,
    this.paths = const [],
    this.recursive = false,
    this.force = false,
  });

  final GitSubmoduleAction action;
  final List<String> paths;
  final bool recursive;
  final bool force;

  String get queryKey => [action.name, ...paths, recursive, force].join('|');
}

class GitSubmoduleActionResult {
  const GitSubmoduleActionResult({
    required this.repositoryId,
    required this.request,
    required this.status,
    required this.snapshot,
    required this.summary,
  });

  final RepositoryId repositoryId;
  final GitSubmoduleActionRequest request;
  final GitStatusSnapshot status;
  final GitSubmoduleSnapshot snapshot;
  final String summary;
}

enum GitNestedRootKind { superproject, submodule, nestedRepository }

class GitNestedRoot {
  const GitNestedRoot({
    required this.path,
    required this.relativePath,
    required this.kind,
    this.submodulePath,
    this.isAvailable = true,
  });

  final String path;
  final String relativePath;
  final GitNestedRootKind kind;
  final String? submodulePath;
  final bool isAvailable;
}

class GitNestedRootSnapshot {
  GitNestedRootSnapshot({
    required this.repositoryId,
    required List<GitNestedRoot> roots,
    required this.fingerprint,
  }) : roots = List.unmodifiable(roots);

  final RepositoryId repositoryId;
  final List<GitNestedRoot> roots;
  final String fingerprint;
}

class ParsedGitmodules {
  ParsedGitmodules({required List<GitSubmoduleConfig> modules})
    : modules = List.unmodifiable(modules);

  final List<GitSubmoduleConfig> modules;
}

class GitSubmoduleStatusRecord {
  const GitSubmoduleStatusRecord({
    required this.marker,
    required this.currentOid,
    required this.path,
    this.description,
  });

  final String marker;
  final String currentOid;
  final String path;
  final String? description;
}

/// Parses the NUL-delimited `git config --null --file .gitmodules --list`
/// records. Values remain inert strings; no config command is interpreted.
ParsedGitmodules parseGitmodules(List<int> output) {
  final byName = <String, Map<String, String>>{};
  for (final record in _splitNul(output)) {
    final text = utf8.decode(record, allowMalformed: true);
    final separator = text.indexOf('\n');
    if (separator <= 0) continue;
    final key = text.substring(0, separator);
    final value = text.substring(separator + 1);
    final match = RegExp(r'^submodule\.(.+)\.(path|url|branch)$')
        .firstMatch(key);
    if (match == null) continue;
    byName.putIfAbsent(match.group(1)!, () => {})[match.group(2)!] = value;
  }
  final modules = <GitSubmoduleConfig>[];
  for (final entry in byName.entries) {
    final path = entry.value['path'];
    final url = entry.value['url'];
    if (path == null || path.isEmpty || url == null || url.isEmpty) continue;
    modules.add(
      GitSubmoduleConfig(
        name: entry.key,
        path: path,
        url: url,
        branch: entry.value['branch'],
      ),
    );
  }
  modules.sort((left, right) => left.path.compareTo(right.path));
  return ParsedGitmodules(modules: modules);
}

/// Parses `git submodule status --recursive`, preserving Git's leading marker:
/// a space is current, `-` is uninitialized, `+` differs from the gitlink, and
/// `U` is an unresolved submodule conflict.
List<GitSubmoduleStatusRecord> parseGitSubmoduleStatus(List<int> output) {
  final text = utf8.decode(output, allowMalformed: true);
  final result = <GitSubmoduleStatusRecord>[];
  for (final rawLine in text.split('\n')) {
    if (rawLine.trim().isEmpty) continue;
    final match = RegExp(
      r'^([ +-U])([0-9a-fA-F]{4,64})\s+(.+?)(?:\s+\(([^)]*)\))?$',
    ).firstMatch(rawLine.trimRight());
    if (match == null) {
      throw GitSubmoduleParseException(
        'Invalid submodule status record: $rawLine',
      );
    }
    result.add(
      GitSubmoduleStatusRecord(
        marker: match.group(1)!,
        currentOid: match.group(2)!,
        path: match.group(3)!,
        description: match.group(4),
      ),
    );
  }
  return List.unmodifiable(result);
}

class GitSubmoduleParseException extends FormatException {
  GitSubmoduleParseException(super.message);
}

GitError submoduleInputError(String message, String diagnostic) => GitError(
  category: GitErrorCategory.parseFailure,
  userMessage: message,
  diagnostic: diagnostic,
  retryable: false,
);

List<List<int>> _splitNul(List<int> output) {
  final records = <List<int>>[];
  var start = 0;
  for (var index = 0; index < output.length; index++) {
    if (output[index] != 0) continue;
    if (index > start) records.add(output.sublist(start, index));
    start = index + 1;
  }
  if (start < output.length) records.add(output.sublist(start));
  return records;
}
