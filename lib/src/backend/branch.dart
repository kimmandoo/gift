import 'dart:convert';

import 'domain.dart';
import 'status.dart';

/// A local branch and the upstream information Git reports for it.
class GitBranch {
  const GitBranch({
    required this.name,
    this.oid,
    this.upstream,
    this.isCurrent = false,
    this.ahead = 0,
    this.behind = 0,
  });

  final String name;
  final String? oid;
  final String? upstream;
  final bool isCurrent;
  final int ahead;
  final int behind;

  bool get hasUpstream => upstream != null && upstream!.isNotEmpty;
}

/// The refreshed repository state after creating or switching a branch.
class GitBranchActionResult {
  const GitBranchActionResult({
    required this.repositoryId,
    required this.branchName,
    required this.status,
  });

  final RepositoryId repositoryId;
  final String branchName;
  final GitStatusSnapshot status;
}

/// Parses `git for-each-ref` rows without depending on localized output.
List<GitBranch> parseGitBranches(List<int> output) {
  final branches = <GitBranch>[];
  final text = utf8.decode(output, allowMalformed: true);
  for (final rawLine in text.split('\n')) {
    final line = rawLine.trimRight();
    if (line.isEmpty) continue;
    final fields = line.split('\u0000');
    if (fields.length != 4 || fields[0].isEmpty) {
      throw FormatException('Invalid Git branch record: $line');
    }
    branches.add(
      GitBranch(
        name: fields[0],
        oid: fields[1].isEmpty ? null : fields[1],
        upstream: fields[2].isEmpty ? null : fields[2],
        isCurrent: fields[3].trim() == '*',
      ),
    );
  }
  return List.unmodifiable(branches);
}
