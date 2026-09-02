import 'domain.dart';

/// A short-lived, path-bound authorization to discard one working-tree diff.
///
/// The backend keeps the matching fingerprint privately. The UI only carries
/// this opaque token between the preview and confirmation steps.
class DiscardPreview {
  const DiscardPreview({
    required this.repositoryId,
    required this.token,
    required this.path,
    required this.expiresAt,
  });

  final RepositoryId repositoryId;
  final String token;
  final String path;
  final DateTime expiresAt;

  bool get isExpired => !expiresAt.isAfter(DateTime.now());
}
