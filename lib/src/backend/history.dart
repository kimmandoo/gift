import 'dart:convert';

import 'domain.dart';

/// Bounded filters applied to a history snapshot.
class GitHistoryFilters {
  const GitHistoryFilters({
    this.text = '',
    this.author = '',
    this.path = '',
    this.ref = '',
    this.authoredAfter,
    this.authoredBefore,
  });

  final String text;
  final String author;
  final String path;
  final String ref;
  final DateTime? authoredAfter;
  final DateTime? authoredBefore;

  bool get isEmpty =>
      text.isEmpty &&
      author.isEmpty &&
      path.isEmpty &&
      ref.isEmpty &&
      authoredAfter == null &&
      authoredBefore == null;

  /// The cursor binds a page sequence to exactly these filter values.
  String get queryKey => [
    text,
    author,
    path,
    ref,
    authoredAfter?.toUtc().toIso8601String() ?? '',
    authoredBefore?.toUtc().toIso8601String() ?? '',
  ].join('\u001f');
}

/// A stable history position over a captured set of ref tips.
class GitHistoryCursor {
  GitHistoryCursor({
    required Iterable<String> snapshotTips,
    required this.position,
    required this.queryKey,
    Iterable<GitCommitRef> snapshotRefs = const <GitCommitRef>[],
  }) : snapshotTips = List.unmodifiable(snapshotTips),
       snapshotRefs = List.unmodifiable(snapshotRefs);

  final List<String> snapshotTips;
  final List<GitCommitRef> snapshotRefs;
  final int position;
  final String queryKey;
}

/// A query for one bounded history page.
class GitHistoryQuery {
  const GitHistoryQuery({
    this.limit = 50,
    this.filters = const GitHistoryFilters(),
    this.cursor,
  });

  final int limit;
  final GitHistoryFilters filters;
  final GitHistoryCursor? cursor;
}

/// A ref attached to a commit in the captured history snapshot.
class GitCommitRef {
  const GitCommitRef({required this.name, required this.targetOid});

  final String name;
  final String targetOid;

  String get shortName {
    for (final prefix in const ['refs/heads/', 'refs/remotes/', 'refs/tags/']) {
      if (name.startsWith(prefix)) return name.substring(prefix.length);
    }
    return name;
  }

  String get kind {
    if (name.startsWith('refs/heads/')) return 'branch';
    if (name.startsWith('refs/remotes/')) return 'remote';
    if (name.startsWith('refs/tags/')) return 'tag';
    return 'ref';
  }
}

enum GitCommitFileStatus {
  added,
  copied,
  deleted,
  modified,
  renamed,
  typeChanged,
  unmerged,
  unknown,
}

/// One path changed by a commit. A rename keeps its previous path separately.
class GitCommitFileChange {
  const GitCommitFileChange({
    required this.status,
    required this.path,
    this.oldPath,
  });

  final GitCommitFileStatus status;
  final String path;
  final String? oldPath;

  bool get isDeleted => status == GitCommitFileStatus.deleted;

  String get statusLabel {
    switch (status) {
      case GitCommitFileStatus.added:
        return 'A';
      case GitCommitFileStatus.copied:
        return 'C';
      case GitCommitFileStatus.deleted:
        return 'D';
      case GitCommitFileStatus.modified:
        return 'M';
      case GitCommitFileStatus.renamed:
        return 'R';
      case GitCommitFileStatus.typeChanged:
        return 'T';
      case GitCommitFileStatus.unmerged:
        return 'U';
      case GitCommitFileStatus.unknown:
        return '?';
    }
  }
}

/// One commit row returned by the local history query.
class GitCommit {
  const GitCommit({
    required this.oid,
    required this.parents,
    required this.authorName,
    required this.authorEmail,
    required this.authoredAt,
    required this.subject,
    required this.body,
    this.refs = const [],
    this.lane = 0,
    this.laneCount = 1,
    this.graphSegments = const [],
    this.graphHasIncoming = false,
  });

  final String oid;
  final List<String> parents;
  final String authorName;
  final String authorEmail;
  final DateTime authoredAt;
  final String subject;
  final String body;
  final List<GitCommitRef> refs;
  final int lane;
  final int laneCount;
  final List<GitGraphSegment> graphSegments;
  final bool graphHasIncoming;

  String get shortOid => oid.length > 8 ? oid.substring(0, 8) : oid;

  GitCommit withGraph({
    required int lane,
    required int laneCount,
    required List<GitGraphSegment> graphSegments,
    required bool graphHasIncoming,
  }) {
    return GitCommit(
      oid: oid,
      parents: parents,
      authorName: authorName,
      authorEmail: authorEmail,
      authoredAt: authoredAt,
      subject: subject,
      body: body,
      refs: refs,
      lane: lane,
      laneCount: laneCount,
      graphSegments: List.unmodifiable(graphSegments),
      graphHasIncoming: graphHasIncoming,
    );
  }
}

/// One connection crossing a commit row, expressed as graph-lane indexes at
/// the row's top and bottom. A fork has several segments sharing [fromLane].
class GitGraphSegment {
  const GitGraphSegment({required this.fromLane, required this.toLane});

  final int fromLane;
  final int toLane;
}

/// A bounded page of history rows.
class GitHistoryPage {
  const GitHistoryPage({
    required this.repositoryId,
    required this.commits,
    required this.offset,
    required this.limit,
    required this.hasMore,
    this.nextCursor,
  });

  final RepositoryId repositoryId;
  final List<GitCommit> commits;
  final int offset;
  final int limit;
  final bool hasMore;
  final GitHistoryCursor? nextCursor;
}

/// Parses the NUL-separated fields and record separators emitted by
/// `git log --format`. A page requests one extra row so `hasMore` does not
/// require an unbounded second process.
GitHistoryPage parseGitHistory(
  List<int> output, {
  required RepositoryId repositoryId,
  required int offset,
  required int limit,
  GitHistoryCursor? cursor,
  Iterable<GitCommitRef> snapshotRefs = const <GitCommitRef>[],
  String queryKey = '',
}) {
  final text = utf8.decode(output, allowMalformed: true);
  final parsed = <GitCommit>[];
  for (final rawRecord in text.split('\u001e')) {
    final record = rawRecord;
    if (record.trim().isEmpty) continue;
    final fields = record.split('\u0000');
    // The format ends with a NUL before the record separator, so the split
    // contains one final empty field after the commit body.
    if (fields.length != 7 && fields.length != 8 && fields.length != 9) {
      throw FormatException('Invalid Git history record: $record');
    }
    final oid = fields[0];
    final authorDate = DateTime.tryParse(fields[4]);
    if (oid.isEmpty || authorDate == null) {
      throw FormatException('Invalid Git history metadata: $record');
    }
    final refs = snapshotRefs
        .where((ref) => ref.targetOid == oid)
        .toList(growable: false);
    parsed.add(
      GitCommit(
        oid: oid,
        parents: fields[1].isEmpty ? const [] : fields[1].split(' '),
        authorName: fields[2],
        authorEmail: fields[3],
        authoredAt: authorDate,
        subject: fields[5],
        body: fields[6].trim(),
        refs: refs,
      ),
    );
  }

  final hasMore = parsed.length > limit;
  final pageCommits = hasMore ? parsed.take(limit).toList() : parsed;
  final position = cursor?.position ?? offset;
  final nextCursor = hasMore
      ? GitHistoryCursor(
          snapshotTips: cursor?.snapshotTips ?? const <String>[],
          snapshotRefs: cursor?.snapshotRefs ?? snapshotRefs,
          position: position + pageCommits.length,
          queryKey: cursor?.queryKey ?? queryKey,
        )
      : null;
  return GitHistoryPage(
    repositoryId: repositoryId,
    commits: assignGraphLanes(pageCommits),
    offset: offset,
    limit: limit,
    hasMore: hasMore,
    nextCursor: nextCursor,
  );
}

/// Recomputes lanes for a complete visible sequence. Call this again after
/// appending a page so branches that cross the page boundary stay connected.
List<GitCommit> assignGraphLanes(List<GitCommit> commits) {
  final lanes = <String?>[];
  return [
    for (final commit in commits)
      (() {
        var lane = lanes.indexOf(commit.oid);
        final hasIncoming = lane >= 0;
        if (lane < 0) {
          lane = lanes.indexOf(null);
          if (lane < 0) {
            lane = lanes.length;
            lanes.add(null);
          }
        }
        final before = List<String?>.of(lanes);
        final parents = <String>[];
        for (final parent in commit.parents) {
          if (!parents.contains(parent)) parents.add(parent);
        }
        final after = List<String?>.of(before);
        after[lane] = null;
        for (var index = 0; index < parents.length; index++) {
          final parent = parents[index];
          if (after.contains(parent)) continue;
          if (index == 0) {
            after[lane] = parent;
          } else {
            after.insert(lane + index, parent);
          }
        }
        while (after.isNotEmpty && after.last == null) {
          after.removeLast();
        }
        final segments = <GitGraphSegment>[];
        void addSegment(int from, int to) {
          if (!segments.any(
            (segment) => segment.fromLane == from && segment.toLane == to,
          )) {
            segments.add(GitGraphSegment(fromLane: from, toLane: to));
          }
        }

        for (var index = 0; index < before.length; index++) {
          final oid = before[index];
          if (index == lane || oid == null) continue;
          final destination = after.indexOf(oid);
          if (destination >= 0) addSegment(index, destination);
        }
        for (final parent in parents) {
          final destination = after.indexOf(parent);
          if (destination >= 0) addSegment(lane, destination);
        }
        lanes
          ..clear()
          ..addAll(after);
        return commit.withGraph(
          lane: lane,
          laneCount: [
            before.length,
            after.length,
            lane + 1,
          ].reduce((left, right) => left > right ? left : right),
          graphSegments: segments,
          graphHasIncoming: hasIncoming,
        );
      })(),
  ];
}
