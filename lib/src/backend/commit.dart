import 'domain.dart';
import 'status.dart';

/// The result of creating one new commit.
///
/// Returning the refreshed status with the commit ID lets the screen update
/// from one backend operation instead of guessing what Git changed.
class GitCommitResult {
  const GitCommitResult({
    required this.repositoryId,
    required this.commitOid,
    required this.status,
  });

  final RepositoryId repositoryId;
  final String commitOid;
  final GitStatusSnapshot status;
}
