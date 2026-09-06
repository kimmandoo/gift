import 'domain.dart';

/// Whether the Git LFS extension can be invoked for a repository.
enum GitLfsInstallationStatus { available, missing }

/// The state of a tracked path in the working tree.
enum GitLfsFileState { hydrated, pointer, missing }

class GitLfsFile {
  const GitLfsFile({
    required this.path,
    required this.state,
    this.oid,
    this.size,
  });

  final String path;
  final GitLfsFileState state;
  final String? oid;
  final int? size;

  bool get needsPull =>
      state == GitLfsFileState.pointer || state == GitLfsFileState.missing;
}

class GitLfsSnapshot {
  const GitLfsSnapshot({
    required this.repositoryId,
    required this.installation,
    required this.filteredPaths,
    required this.files,
    required this.diagnostics,
    required this.fingerprint,
    this.version,
  });

  final RepositoryId repositoryId;
  final GitLfsInstallationStatus installation;
  final String? version;
  final List<String> filteredPaths;
  final List<GitLfsFile> files;
  final List<String> diagnostics;
  final String fingerprint;

  bool get isAvailable => installation == GitLfsInstallationStatus.available;
  bool get hasLfsFilters => filteredPaths.isNotEmpty;
  bool get hasPointers =>
      files.any((file) => file.state == GitLfsFileState.pointer);
  bool get hasMissingObjects =>
      files.any((file) => file.state == GitLfsFileState.missing);
  bool get requiresAttention =>
      hasLfsFilters && (!isAvailable || hasPointers || hasMissingObjects);
}

class GitLfsPullResult {
  const GitLfsPullResult({
    required this.repositoryId,
    required this.snapshot,
    required this.summary,
  });

  final RepositoryId repositoryId;
  final GitLfsSnapshot snapshot;
  final String summary;
}
