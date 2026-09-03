import 'history.dart';
import 'status.dart';
import 'domain.dart';

enum GitFileHistoryScope { file, directory, selection }

/// A bounded query for one path. Line ranges are metadata for selection
/// history; Git still receives only the validated repository path.
class GitFileHistoryQuery {
  const GitFileHistoryQuery({
    required this.path,
    this.scope = GitFileHistoryScope.file,
    this.follow = false,
    this.lineStart,
    this.lineEnd,
    this.limit = 50,
    this.offset = 0,
  });

  final String path;
  final GitFileHistoryScope scope;
  final bool follow;
  final int? lineStart;
  final int? lineEnd;
  final int limit;
  final int offset;

  String get queryKey => [
    scope.name,
    path,
    follow,
    lineStart ?? '',
    lineEnd ?? '',
    limit,
    offset,
  ].join('\u001f');
}

class GitFileHistoryEntry {
  const GitFileHistoryEntry({
    required this.commit,
    required this.path,
    this.originalPath,
  });

  final GitCommit commit;
  final String path;
  final String? originalPath;

  String get oid => commit.oid;
  String get subject => commit.subject;
  String get authorName => commit.authorName;
  DateTime get authoredAt => commit.authoredAt;
}

class GitFileHistorySnapshot {
  GitFileHistorySnapshot({
    required this.repositoryId,
    required this.query,
    required Iterable<GitFileHistoryEntry> entries,
    required this.fingerprint,
    required this.workingTreeFingerprint,
    required this.hasMore,
  }) : entries = List.unmodifiable(entries);

  final RepositoryId repositoryId;
  final GitFileHistoryQuery query;
  final List<GitFileHistoryEntry> entries;
  final String fingerprint;
  final String workingTreeFingerprint;
  final bool hasMore;
}

/// Blame flags are typed so whitespace, movement, and copy detection cannot
/// become arbitrary command-line arguments.
class GitBlameOptions {
  const GitBlameOptions({
    this.ignoreWhitespace = false,
    this.detectMoves = false,
    this.detectCopies = false,
  });

  final bool ignoreWhitespace;
  final bool detectMoves;
  final bool detectCopies;

  String get queryKey =>
      '$ignoreWhitespace\u001f$detectMoves\u001f$detectCopies';
}

class GitBlameLine {
  const GitBlameLine({
    required this.lineNumber,
    required this.text,
    required this.commitOid,
    required this.authorName,
    required this.authoredAt,
    required this.originalLineNumber,
    required this.originalPath,
  });

  final int lineNumber;
  final String text;
  final String commitOid;
  final String authorName;
  final DateTime? authoredAt;
  final int originalLineNumber;
  final String originalPath;

  bool get isWorkingTree => commitOid.replaceAll('0', '').isEmpty;
}

class GitBlameSnapshot {
  GitBlameSnapshot({
    required this.repositoryId,
    required this.path,
    required Iterable<GitBlameLine> lines,
    required this.options,
    required this.fingerprint,
  }) : lines = List.unmodifiable(lines);

  final RepositoryId repositoryId;
  final String path;
  final List<GitBlameLine> lines;
  final GitBlameOptions options;
  final String fingerprint;
}

enum GitRevisionGetOutcome { restored, missing, binary, oversized, conflict }

class GitRevisionGetResult {
  const GitRevisionGetResult({
    required this.repositoryId,
    required this.path,
    required this.revision,
    required this.outcome,
    required this.status,
    required this.summary,
  });

  final RepositoryId repositoryId;
  final String path;
  final String revision;
  final GitRevisionGetOutcome outcome;
  final GitStatusSnapshot status;
  final String summary;
}
