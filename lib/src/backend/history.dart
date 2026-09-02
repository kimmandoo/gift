import 'dart:convert';

import 'domain.dart';

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
  });

  final RepositoryId repositoryId;
  final List<GitCommit> commits;
  final int offset;
  final int limit;
  final bool hasMore;
}

/// Parses the NUL-separated fields and record separators emitted by
/// `git log --format`. A page requests one extra row so `hasMore` does not
/// require an unbounded second process.
GitHistoryPage parseGitHistory(
  List<int> output, {
  required RepositoryId repositoryId,
  required int offset,
  required int limit,
}) {
  final text = utf8.decode(output, allowMalformed: true);
  final parsed = <GitCommit>[];
  for (final rawRecord in text.split('\u001e')) {
    final record = rawRecord;
    if (record.trim().isEmpty) continue;
    final fields = record.split('\u0000');
    // The format ends with a NUL before the record separator, so the split
    // contains one final empty field after the commit body.
    if (fields.length != 7 && fields.length != 8) {
      throw FormatException('Invalid Git history record: $record');
    }
    final oid = fields[0];
    final authorDate = DateTime.tryParse(fields[4]);
    if (oid.isEmpty || authorDate == null) {
      throw FormatException('Invalid Git history metadata: $record');
    }
    parsed.add(
      GitCommit(
        oid: oid,
        parents: fields[1].isEmpty ? const [] : fields[1].split(' '),
        authorName: fields[2],
        authorEmail: fields[3],
        authoredAt: authorDate,
        subject: fields[5],
        body: fields[6].trim(),
      ),
    );
  }

  final hasMore = parsed.length > limit;
  final pageCommits = hasMore ? parsed.take(limit).toList() : parsed;
  return GitHistoryPage(
    repositoryId: repositoryId,
    commits: assignGraphLanes(pageCommits),
    offset: offset,
    limit: limit,
    hasMore: hasMore,
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
