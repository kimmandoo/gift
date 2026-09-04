import 'dart:convert';

import 'domain.dart';
import 'status.dart';

/// A remote-tracking branch as it exists in the local ref database.
///
/// The OID is deliberately part of the value. A UI can therefore bind a
/// checkout, comparison, or update preview to the exact remote tip it showed
/// instead of trusting a symbolic name after a fetch moves the ref.
class GitRemoteBranch {
  const GitRemoteBranch({
    required this.name,
    required this.remote,
    required this.branch,
    required this.oid,
    this.localTrackingBranch,
    this.isSymbolicHead = false,
  });

  final String name;
  final String remote;
  final String branch;
  final String oid;
  final String? localTrackingBranch;
  final bool isSymbolicHead;

  GitRemoteBranch copyWith({String? localTrackingBranch}) => GitRemoteBranch(
    name: name,
    remote: remote,
    branch: branch,
    oid: oid,
    localTrackingBranch: localTrackingBranch ?? this.localTrackingBranch,
    isSymbolicHead: isSymbolicHead,
  );
}

/// A lightweight tag or recent ref displayed alongside branch groups.
class GitRepositoryRef {
  const GitRepositoryRef({required this.name, required this.oid});

  final String name;
  final String oid;
}

class GitRemoteBranchSnapshot {
  GitRemoteBranchSnapshot({
    required this.repositoryId,
    required this.fingerprint,
    required this.currentBranch,
    required List<GitRemoteBranch> branches,
    List<GitBranchRef> localBranches = const [],
    List<GitRepositoryRef> tags = const [],
    this.incoming = 0,
    this.outgoing = 0,
    this.upstream,
  }) : branches = List.unmodifiable(branches),
       localBranches = List.unmodifiable(localBranches),
       tags = List.unmodifiable(tags);

  final RepositoryId repositoryId;
  final String fingerprint;
  final String? currentBranch;
  final String? upstream;
  final List<GitRemoteBranch> branches;
  final List<GitBranchRef> localBranches;
  final List<GitRepositoryRef> tags;
  final int incoming;
  final int outgoing;

  List<GitRemoteBranch> get remoteBranches => branches;

  List<String> get remoteNames => branches
      .where((branch) => !branch.isSymbolicHead)
      .map((branch) => branch.remote)
      .toSet()
      .toList(growable: false);
}

class GitRemoteBranchDeletePreview {
  const GitRemoteBranchDeletePreview({
    required this.repositoryId,
    required this.branch,
    required this.oid,
    required this.fingerprint,
    required this.token,
    required this.expiresAt,
  });

  final RepositoryId repositoryId;
  final GitRemoteBranch branch;
  final String oid;
  final String fingerprint;
  final String token;
  final DateTime expiresAt;

  bool get canExecute => expiresAt.isAfter(DateTime.now());
}

class GitRemoteBranchActionResult {
  const GitRemoteBranchActionResult({
    required this.repositoryId,
    required this.branch,
    required this.status,
    required this.snapshot,
    required this.summary,
  });

  final RepositoryId repositoryId;
  final GitRemoteBranch branch;
  final GitStatusSnapshot status;
  final GitRemoteBranchSnapshot snapshot;
  final String summary;
}

/// The local branch entry used by the grouped branch browser.
class GitBranchRef {
  const GitBranchRef({
    required this.name,
    required this.oid,
    this.upstream,
    this.isCurrent = false,
  });

  final String name;
  final String oid;
  final String? upstream;
  final bool isCurrent;
}

enum GitUpdateStrategy { merge, rebase, resetToRemote }

enum GitUpdateLocalChanges { reject, stash }

enum GitUpdatePhase { start, continueOperation, abort }

enum GitUpdateState { completed, conflicted, aborted, cancelled }

class GitUpdateProjectRequest {
  const GitUpdateProjectRequest({
    required this.strategy,
    this.localChanges = GitUpdateLocalChanges.reject,
    this.phase = GitUpdatePhase.start,
    this.confirmationToken,
  });

  final GitUpdateStrategy strategy;
  final GitUpdateLocalChanges localChanges;
  final GitUpdatePhase phase;
  final String? confirmationToken;
}

class GitUpdateProjectPreview {
  const GitUpdateProjectPreview({
    required this.repositoryId,
    required this.request,
    required this.branch,
    required this.upstream,
    required this.currentOid,
    required this.upstreamOid,
    required this.incoming,
    required this.outgoing,
    required this.dirtyWorktree,
    required this.requiresConfirmation,
    required this.fingerprint,
    required this.token,
    required this.expiresAt,
    this.blockingMessage,
  });

  final RepositoryId repositoryId;
  final GitUpdateProjectRequest request;
  final String branch;
  final String upstream;
  final String currentOid;
  final String upstreamOid;
  final int incoming;
  final int outgoing;
  final bool dirtyWorktree;
  final bool requiresConfirmation;
  final String fingerprint;
  final String? token;
  final DateTime? expiresAt;
  final String? blockingMessage;

  bool get canExecute =>
      token != null &&
      expiresAt != null &&
      expiresAt!.isAfter(DateTime.now()) &&
      blockingMessage == null;
}

class GitUpdateProjectResult {
  const GitUpdateProjectResult({
    required this.repositoryId,
    required this.request,
    required this.state,
    required this.status,
    required this.summary,
    this.recoveryActions = const [],
  });

  final RepositoryId repositoryId;
  final GitUpdateProjectRequest request;
  final GitUpdateState state;
  final GitStatusSnapshot status;
  final String summary;
  final List<GitUpdatePhase> recoveryActions;

  bool get historyChanged => state == GitUpdateState.completed;
}

/// Parses full or short remote ref rows produced by `git for-each-ref`.
///
/// Git normally emits name, OID, and symbolic target. The symbolic field is
/// optional here so output that loses an empty trailing field remains usable.
/// Configured remote names disambiguate externally-created names containing
/// `/`; the app itself creates only simple remote names.
List<GitRemoteBranch> parseGitRemoteBranches(
  List<int> output, {
  Iterable<String> remoteNames = const [],
}) {
  final result = <GitRemoteBranch>[];
  final names = remoteNames.toSet().toList()
    ..sort((left, right) => right.length.compareTo(left.length));
  final text = utf8.decode(output, allowMalformed: true);
  for (final rawLine in text.split('\n')) {
    final line = rawLine.endsWith('\r')
        ? rawLine.substring(0, rawLine.length - 1)
        : rawLine;
    if (line.isEmpty) continue;
    final fields = line.split('\u0000');
    if (fields.length < 2 ||
        fields[0].isEmpty ||
        fields[1].isEmpty ||
        fields.skip(3).any((field) => field.isNotEmpty)) {
      throw FormatException('Invalid Git remote branch record: $line');
    }
    var shortName = fields[0];
    if (shortName.startsWith('refs/remotes/')) {
      shortName = shortName.substring('refs/remotes/'.length);
    } else if (shortName.startsWith('remotes/')) {
      shortName = shortName.substring('remotes/'.length);
    }
    final configuredRemote = names
        .where((name) => shortName.startsWith('$name/'))
        .firstOrNull;
    final slash = configuredRemote == null
        ? shortName.indexOf('/')
        : configuredRemote.length;
    if (slash <= 0 || slash == shortName.length - 1) {
      throw FormatException('Invalid Git remote branch name: $shortName');
    }
    final remote = configuredRemote ?? shortName.substring(0, slash);
    final branch = shortName.substring(slash + 1);
    result.add(
      GitRemoteBranch(
        name: shortName,
        remote: remote,
        branch: branch,
        oid: fields[1],
        isSymbolicHead:
            (fields.length >= 3 && fields[2].isNotEmpty) || branch == 'HEAD',
      ),
    );
  }
  return List.unmodifiable(result);
}
