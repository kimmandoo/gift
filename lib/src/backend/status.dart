import 'dart:convert';

import 'domain.dart';

/// The record kind used by Git's porcelain v2 status format.
enum GitChangeType { tracked, renamedOrCopied, unmerged, untracked }

/// The visible groups used by the Changes screen.
enum GitChangeGroup { conflicts, staged, unstaged, untracked }

/// Branch information emitted by `git status --porcelain=v2 --branch`.
class GitBranchStatus {
  const GitBranchStatus({
    this.oid,
    this.head,
    this.upstream,
    this.ahead = 0,
    this.behind = 0,
  });

  final String? oid;
  final String? head;
  final String? upstream;
  final int ahead;
  final int behind;

  bool get isDetached => head == '(detached)';
  bool get hasUpstream => upstream != null && upstream!.isNotEmpty;
}

/// One changed path and its independent index/worktree facets.
class GitChange {
  const GitChange({
    required this.type,
    required this.path,
    required this.indexStatus,
    required this.worktreeStatus,
    required this.submoduleStatus,
    this.headOid,
    this.indexOid,
    this.originalPath,
    this.renameScore,
  });

  final GitChangeType type;
  final String path;
  final String? originalPath;
  final String indexStatus;
  final String worktreeStatus;
  final String submoduleStatus;
  final String? headOid;
  final String? indexOid;
  final String? renameScore;

  bool get isUntracked => type == GitChangeType.untracked;

  bool get isConflicted =>
      type == GitChangeType.unmerged ||
      indexStatus == 'U' ||
      worktreeStatus == 'U';

  /// A non-space/non-dot index status means the next commit differs from HEAD.
  bool get isStaged => !isUntracked && _hasChangeStatus(indexStatus);

  /// A non-space/non-dot worktree status means the file differs from the index.
  bool get isUnstaged => !isUntracked && _hasChangeStatus(worktreeStatus);

  String get shortStatus => '$indexStatus$worktreeStatus';

  List<GitChangeGroup> get groups {
    final result = <GitChangeGroup>[];
    if (isConflicted) result.add(GitChangeGroup.conflicts);
    if (isStaged) result.add(GitChangeGroup.staged);
    if (isUnstaged) result.add(GitChangeGroup.unstaged);
    if (isUntracked) result.add(GitChangeGroup.untracked);
    return List.unmodifiable(result);
  }
}

/// The parser output before repository identity and generation are attached.
class ParsedGitStatus {
  ParsedGitStatus({
    required this.branch,
    required List<GitChange> changes,
    required this.contentHash,
  }) : changes = List.unmodifiable(changes);

  final GitBranchStatus branch;
  final List<GitChange> changes;
  final String contentHash;
}

/// A repository status at one point in time.
class GitStatusSnapshot {
  GitStatusSnapshot({
    required this.repositoryId,
    required this.root,
    required this.branch,
    required List<GitChange> changes,
    required this.contentHash,
    required this.generation,
  }) : changes = List.unmodifiable(changes);

  final RepositoryId repositoryId;
  final String root;
  final GitBranchStatus branch;
  final List<GitChange> changes;
  final String contentHash;
  final int generation;

  List<GitChange> get conflicts => _byGroup(GitChangeGroup.conflicts);
  List<GitChange> get staged => _byGroup(GitChangeGroup.staged);
  List<GitChange> get unstaged => _byGroup(GitChangeGroup.unstaged);
  List<GitChange> get untracked => _byGroup(GitChangeGroup.untracked);

  bool get isClean => changes.isEmpty;

  List<GitChange> _byGroup(GitChangeGroup group) => List.unmodifiable(
    changes.where((change) => change.groups.contains(group)),
  );
}

/// Parses the NUL-delimited output of
/// `git status --porcelain=v2 -z --branch`.
ParsedGitStatus parseGitStatus(List<int> output) {
  final records = _splitNul(output);
  String? oid;
  String? head;
  String? upstream;
  var ahead = 0;
  var behind = 0;
  final changes = <GitChange>[];

  for (var index = 0; index < records.length; index++) {
    final record = utf8.decode(records[index], allowMalformed: true);
    if (record.isEmpty) continue;

    switch (record[0]) {
      case '#':
        final header = _parseHeader(record);
        if (header == null) continue;
        switch (header.$1) {
          case 'oid':
            oid = header.$2;
          case 'head':
            head = header.$2;
          case 'upstream':
            upstream = header.$2;
          case 'ab':
            final values = header.$2.split(' ');
            if (values.length != 2) {
              throw GitStatusParseException(
                'Invalid branch ahead/behind header: $record',
              );
            }
            ahead = _parseSignedNumber(values[0], record);
            behind = _parseSignedNumber(values[1], record);
        }
      case '1':
        changes.add(_parseOrdinary(record));
      case '2':
        final originalPathIndex = index + 1;
        if (originalPathIndex >= records.length) {
          throw GitStatusParseException(
            'Rename record is missing its original path: $record',
          );
        }
        final originalPath = utf8.decode(
          records[originalPathIndex],
          allowMalformed: true,
        );
        index = originalPathIndex;
        changes.add(_parseRename(record, originalPath));
      case 'u':
        changes.add(_parseUnmerged(record));
      case '?':
        changes.add(_parseUntracked(record));
      case '!':
        // This parser is normally called without --ignored. Ignore records
        // if a caller adds that flag later; ignored files are not changes.
        continue;
      default:
        throw GitStatusParseException('Unknown status record: $record');
    }
  }

  return ParsedGitStatus(
    branch: GitBranchStatus(
      oid: oid,
      head: head,
      upstream: upstream,
      ahead: ahead,
      behind: behind,
    ),
    changes: changes,
    contentHash: _hashBytes(output),
  );
}

class GitStatusParser {
  const GitStatusParser();

  ParsedGitStatus parse(List<int> output) => parseGitStatus(output);
}

class GitStatusParseException extends FormatException {
  GitStatusParseException(super.message);
}

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

(String, String)? _parseHeader(String record) {
  final knownHeaders = <String, String>{
    '# branch.oid ': 'oid',
    '# branch.head ': 'head',
    '# branch.upstream ': 'upstream',
    '# branch.ab ': 'ab',
  };
  for (final entry in knownHeaders.entries) {
    if (record.startsWith(entry.key)) {
      return (entry.value, record.substring(entry.key.length));
    }
  }
  return null;
}

GitChange _parseOrdinary(String record) {
  final fields = _fields(record, metadataCount: 7);
  return GitChange(
    type: GitChangeType.tracked,
    indexStatus: _oneCharacter(fields[0], record),
    worktreeStatus: _oneCharacter(fields[0], record, offset: 1),
    submoduleStatus: fields[1],
    headOid: fields[2],
    indexOid: fields[3],
    path: fields[7],
  );
}

GitChange _parseRename(String record, String originalPath) {
  final fields = _fields(record, metadataCount: 8);
  final status = _oneCharacter(fields[0], record);
  return GitChange(
    type: GitChangeType.renamedOrCopied,
    indexStatus: status,
    worktreeStatus: _oneCharacter(fields[0], record, offset: 1),
    submoduleStatus: fields[1],
    headOid: fields[2],
    indexOid: fields[3],
    renameScore: fields[7],
    path: fields[8],
    originalPath: originalPath,
  );
}

GitChange _parseUnmerged(String record) {
  final fields = _fields(record, metadataCount: 9);
  return GitChange(
    type: GitChangeType.unmerged,
    indexStatus: _oneCharacter(fields[0], record),
    worktreeStatus: _oneCharacter(fields[0], record, offset: 1),
    submoduleStatus: fields[1],
    headOid: fields[2],
    indexOid: fields[3],
    path: fields[9],
  );
}

GitChange _parseUntracked(String record) {
  final fields = _fields(record, metadataCount: 0);
  return GitChange(
    type: GitChangeType.untracked,
    indexStatus: '?',
    worktreeStatus: '?',
    submoduleStatus: 'N...',
    path: fields[0],
  );
}

List<String> _fields(String record, {required int metadataCount}) {
  if (record.length < 3 || record[1] != ' ') {
    throw GitStatusParseException('Malformed status record: $record');
  }

  var start = 2;
  final fields = <String>[];
  for (var index = 0; index < metadataCount; index++) {
    final separator = record.indexOf(' ', start);
    if (separator < 0) {
      throw GitStatusParseException('Malformed status record: $record');
    }
    fields.add(record.substring(start, separator));
    start = separator + 1;
  }
  if (start >= record.length) {
    throw GitStatusParseException('Status record has no path: $record');
  }
  fields.add(record.substring(start));
  return fields;
}

String _oneCharacter(String value, String record, {int offset = 0}) {
  if (value.length != 2 || offset >= value.length) {
    throw GitStatusParseException('Invalid XY status in record: $record');
  }
  return value[offset];
}

bool _hasChangeStatus(String value) => value != ' ' && value != '.';

int _parseSignedNumber(String value, String record) {
  final parsed = int.tryParse(value);
  if (parsed == null || (!value.startsWith('+') && !value.startsWith('-'))) {
    throw GitStatusParseException('Invalid branch count in record: $record');
  }
  return parsed;
}

String _hashBytes(List<int> bytes) {
  var hash = 0xcbf29ce484222325;
  for (final byte in bytes) {
    hash ^= byte;
    hash *= 0x100000001b3;
    hash &= 0xffffffffffffffff;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}
