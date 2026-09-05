import 'package:gift/src/backend/status.dart';

enum GitRepositoryPathKind { file, directory }

class GitRepositoryPath {
  const GitRepositoryPath({required this.path, required this.kind});

  final String path;
  final GitRepositoryPathKind kind;
}

class GitRepositoryPathSnapshot {
  GitRepositoryPathSnapshot({
    required Iterable<GitRepositoryPath> paths,
    required this.fingerprint,
    this.isTruncated = false,
  }) : paths = List.unmodifiable(paths);

  final List<GitRepositoryPath> paths;
  final String fingerprint;
  final bool isTruncated;

  List<GitRepositoryPath> matching(
    String query, {
    GitRepositoryPathKind? kind,
    int limit = 100,
  }) {
    final normalized = query.trim().replaceAll('\\', '/').toLowerCase();
    return paths
        .where(
          (entry) =>
              (kind == null || entry.kind == kind) &&
              (normalized.isEmpty ||
                  entry.path.toLowerCase().contains(normalized)),
        )
        .take(limit)
        .toList(growable: false);
  }

  factory GitRepositoryPathSnapshot.fromStatus(GitStatusSnapshot status) {
    final values = <String>{};
    for (final change in status.changes) {
      values.add(change.path);
      if (change.originalPath case final original?) values.add(original);
    }
    return GitRepositoryPathSnapshot(
      paths: values.map(
        (path) =>
            GitRepositoryPath(path: path, kind: GitRepositoryPathKind.file),
      ),
      fingerprint:
          '${status.generation}:${status.contentHash}:${values.join('|')}',
    );
  }
}
