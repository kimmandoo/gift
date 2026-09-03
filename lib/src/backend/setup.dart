import 'domain.dart';
import 'error.dart';
import 'status.dart';

class GitCloneRequest {
  const GitCloneRequest({
    required this.source,
    required this.destination,
    this.branch,
    this.depth,
    this.recursive = false,
  });

  final String source;
  final String destination;
  final String? branch;
  final int? depth;
  final bool recursive;

  String get queryKey =>
      [source, destination, branch ?? '', depth ?? '', recursive].join('|');
}

class GitInitRequest {
  const GitInitRequest({required this.path, this.initialBranch});

  final String path;
  final String? initialBranch;
}

class GitRepositorySetupResult {
  const GitRepositorySetupResult({
    required this.repository,
    required this.summary,
  });

  final RepositoryOpened repository;
  final String summary;
}

class GitUnshallowResult {
  const GitUnshallowResult({
    required this.repositoryId,
    required this.status,
    required this.wasShallow,
    required this.isShallow,
    required this.summary,
  });

  final RepositoryId repositoryId;
  final GitStatusSnapshot status;
  final bool wasShallow;
  final bool isShallow;
  final String summary;
}

class GitDiscoveredRoot {
  const GitDiscoveredRoot({required this.path, required this.relativePath});

  final String path;
  final String relativePath;
}

class GitRootDiscoverySnapshot {
  GitRootDiscoverySnapshot({
    required this.path,
    required List<GitDiscoveredRoot> roots,
    required this.fingerprint,
    this.isTruncated = false,
  }) : roots = List.unmodifiable(roots);

  final String path;
  final List<GitDiscoveredRoot> roots;
  final String fingerprint;
  final bool isTruncated;
}

GitError setupInputError(String message, String diagnostic) => GitError(
  category: GitErrorCategory.parseFailure,
  userMessage: message,
  diagnostic: diagnostic,
  retryable: false,
);
