import 'dart:convert';

import 'domain.dart';
import 'signing.dart';

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
    this.signature,
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
  final GitCommitSignature? signature;
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
      signature: signature,
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
    this.collapseToSingleLane = false,
  });

  final RepositoryId repositoryId;
  final List<GitCommit> commits;
  final int offset;
  final int limit;
  final bool hasMore;
  final GitHistoryCursor? nextCursor;
  final bool collapseToSingleLane;
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
  bool collapseToSingleLane = false,
}) {
  final text = utf8.decode(output, allowMalformed: true);
  final parsed = <GitCommit>[];
  for (final rawRecord in text.split('\u001e')) {
    final record = rawRecord;
    if (record.trim().isEmpty) continue;
    final fields = record.split('\u0000');
    // The format ends with a NUL before the record separator, so the split
    // contains one final empty field after the commit body. Newer queries add
    // four signature fields before that terminator.
    if (fields.length != 7 &&
        fields.length != 8 &&
        fields.length != 9 &&
        fields.length != 12) {
      throw FormatException('Invalid Git history record: $record');
    }
    // Git appends a line ending after the record separator on some versions,
    // so every record after the first can begin with `\n` (or `\r\n`). The
    // OID is structural data and must be normalized before matching parents
    // and refs or assigning graph lanes.
    final oid = fields[0].trim();
    final authorDate = DateTime.tryParse(fields[4]);
    if (oid.isEmpty || authorDate == null) {
      throw FormatException('Invalid Git history metadata: $record');
    }
    final refs = snapshotRefs
        .where((ref) => ref.targetOid == oid)
        .toList(growable: false);
    final signature = fields.length == 12
        ? parseGitCommitSignature(
            status: fields[7],
            signer: fields[8],
            key: fields[9],
            fingerprint: fields[10],
          )
        : null;
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
        signature: signature,
      ),
    );
  }

  final hasMore = parsed.length > limit;
  final pageCommits = hasMore ? parsed.take(limit).toList() : parsed;
  // A single ref tip is enough to flatten a genuinely linear history, but a
  // merge commit still needs its second parent lane. Keep the optimization
  // local to pages that contain no merge topology so old repositories do not
  // render a misleading one-dimensional graph.
  final useSingleGraphLane =
      collapseToSingleLane &&
      pageCommits.every((commit) => commit.parents.length <= 1);
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
    commits: useSingleGraphLane
        ? assignSingleGraphLane(pageCommits)
        : assignGraphLanes(pageCommits),
    offset: offset,
    limit: limit,
    hasMore: hasMore,
    nextCursor: nextCursor,
    collapseToSingleLane: useSingleGraphLane,
  );
}

/// Connects the displayed commit rows on one axis when history has one tip.
List<GitCommit> assignSingleGraphLane(List<GitCommit> commits) {
  return [
    for (var index = 0; index < commits.length; index++)
      commits[index].withGraph(
        lane: 0,
        laneCount: 1,
        graphSegments: index + 1 < commits.length
            ? const [GitGraphSegment(fromLane: 0, toLane: 0)]
            : const [],
        graphHasIncoming: index > 0,
      ),
  ];
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
        // Once a lane has joined or ended, close its empty slot immediately.
        // Leaving an interior null in place makes the surviving ancestry drift
        // right and renders an unnecessary parallel column on later rows.
        after.removeWhere((oid) => oid == null);
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
