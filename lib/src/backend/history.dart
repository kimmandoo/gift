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

  String get shortOid => oid.length > 8 ? oid.substring(0, 8) : oid;

  GitCommit withGraph({required int lane, required int laneCount}) {
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
    );
  }
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
    commits: _assignGraphLanes(pageCommits),
    offset: offset,
    limit: limit,
    hasMore: hasMore,
  );
}

List<GitCommit> _assignGraphLanes(List<GitCommit> commits) {
  // Keep empty lane slots instead of compacting after a branch line ends. This
  // makes a side parent stay on the same visual lane as later rows.
  final lanes = <String?>[];
  return [
    for (final commit in commits)
      (() {
        var lane = lanes.indexOf(commit.oid);
        if (lane < 0) {
          lane = lanes.indexOf(null);
          if (lane < 0) {
            lane = lanes.length;
            lanes.add(null);
          }
        }
        final parents = <String>[];
        for (final parent in commit.parents) {
          if (!parents.contains(parent)) parents.add(parent);
        }
        if (parents.isEmpty) {
          lanes[lane] = null;
        } else {
          lanes[lane] = parents.first;
          for (var index = 1; index < parents.length; index++) {
            lanes.insert(lane + index, parents[index]);
          }
        }
        return commit.withGraph(
          lane: lane,
          laneCount: lanes.length > lane ? lanes.length : lane + 1,
        );
      })(),
  ];
}
