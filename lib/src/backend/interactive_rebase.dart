import 'conflict.dart';
import 'domain.dart';
import 'status.dart';

/// The commands that can appear in an interactive rebase todo plan.
enum GitInteractiveRebaseAction { pick, reword, edit, squash, fixup, drop }

extension GitInteractiveRebaseActionText on GitInteractiveRebaseAction {
  /// The command written to Git's interactive todo file.
  String get gitValue => switch (this) {
    GitInteractiveRebaseAction.pick => 'pick',
    GitInteractiveRebaseAction.reword => 'reword',
    GitInteractiveRebaseAction.edit => 'edit',
    GitInteractiveRebaseAction.squash => 'squash',
    GitInteractiveRebaseAction.fixup => 'fixup',
    GitInteractiveRebaseAction.drop => 'drop',
  };

  String get label => switch (this) {
    GitInteractiveRebaseAction.pick => 'Pick',
    GitInteractiveRebaseAction.reword => 'Reword',
    GitInteractiveRebaseAction.edit => 'Edit',
    GitInteractiveRebaseAction.squash => 'Squash',
    GitInteractiveRebaseAction.fixup => 'Fixup',
    GitInteractiveRebaseAction.drop => 'Drop',
  };
}

/// Options that are safe to expose as explicit interactive-rebase choices.
class GitInteractiveRebaseOptions {
  const GitInteractiveRebaseOptions({
    this.autosquash = false,
    this.root = false,
    this.updateRefs = false,
  });

  final bool autosquash;
  final bool root;
  final bool updateRefs;

  List<String> toGitArguments() => [
    if (autosquash) '--autosquash',
    if (root) '--root',
    if (updateRefs) '--update-refs',
  ];
}

/// One commit in the user-editable rebase todo list.
///
/// [originalIndex] and [originalOid] refer to the captured history before any
/// reorder or action edit. They are deliberately retained so the execution
/// layer can explain what was rewritten and the UI can detect stale plans.
class GitInteractiveRebaseEntry {
  const GitInteractiveRebaseEntry({
    required this.originalOid,
    required this.subject,
    required this.action,
    required this.originalIndex,
  });

  final String originalOid;
  final String subject;
  final GitInteractiveRebaseAction action;
  final int originalIndex;

  String get queryKey =>
      [originalOid, originalIndex, action.gitValue, subject].join('\u0000');

  String get shortOid =>
      originalOid.length > 8 ? originalOid.substring(0, 8) : originalOid;

  GitInteractiveRebaseEntry copyWith({
    String? subject,
    GitInteractiveRebaseAction? action,
  }) => GitInteractiveRebaseEntry(
    originalOid: originalOid,
    subject: subject ?? this.subject,
    action: action ?? this.action,
    originalIndex: originalIndex,
  );
}

/// Machine-readable reason why a rebase plan cannot be started yet.
enum GitInteractiveRebaseIssueKind {
  emptyPlan,
  invalidUpstream,
  upstreamRequired,
  rootHasUpstream,
  invalidCommitOid,
  duplicateCommit,
  invalidOriginalIndex,
  duplicateOriginalIndex,
  invalidActionSequence,
}

class GitInteractiveRebaseIssue {
  const GitInteractiveRebaseIssue({
    required this.kind,
    required this.message,
    this.entryIndex,
  });

  final GitInteractiveRebaseIssueKind kind;
  final String message;
  final int? entryIndex;
}

/// The repository facts shown before an interactive rebase can be started.
///
/// A preview receives a token only when the plan matches the current linear
/// range and no protected or unsafe repository state was found. The token is
/// consumed by the future execution contract after the same facts are checked
/// again.
class GitInteractiveRebasePreview {
  GitInteractiveRebasePreview({
    required this.repositoryId,
    required this.plan,
    required this.currentBranch,
    required this.currentHead,
    required this.upstreamHead,
    required this.selectedCommitCount,
    required this.mergeCommitCount,
    required this.branchProtected,
    required this.pushedCommits,
    required this.detachedHead,
    required this.dirtyWorktree,
    required this.operationInProgress,
    required this.fingerprint,
    required this.requiresConfirmation,
    this.token,
    this.expiresAt,
    this.blockingMessage,
    Iterable<GitInteractiveRebaseIssue> planIssues =
        const <GitInteractiveRebaseIssue>[],
  }) : planIssues = List.unmodifiable(planIssues);

  final RepositoryId repositoryId;
  final GitInteractiveRebasePlan plan;
  final String? currentBranch;
  final String currentHead;
  final String? upstreamHead;
  final int selectedCommitCount;
  final int mergeCommitCount;
  final bool branchProtected;
  final bool pushedCommits;
  final bool detachedHead;
  final bool dirtyWorktree;
  final GitConflictOperation? operationInProgress;
  final String fingerprint;
  final bool requiresConfirmation;
  final String? token;
  final DateTime? expiresAt;
  final String? blockingMessage;
  final List<GitInteractiveRebaseIssue> planIssues;

  bool get canExecute =>
      plan.isValid &&
      blockingMessage == null &&
      token != null &&
      expiresAt != null &&
      expiresAt!.isAfter(DateTime.now());
}

/// The only phases accepted by the interactive-rebase execution boundary.
enum GitInteractiveRebasePhase { start, continueOperation, skip, abort }

enum GitInteractiveRebaseExecutionState {
  completed,
  paused,
  conflicted,
  aborted,
  cancelled,
}

enum GitInteractiveRebaseRecoveryAction { continueOperation, skip, abort }

/// A recovery request bound to the current conflict/operation snapshot.
class GitInteractiveRebaseRecoveryRequest {
  const GitInteractiveRebaseRecoveryRequest({
    required this.action,
    required this.fingerprint,
  });

  final GitInteractiveRebaseRecoveryAction action;
  final String fingerprint;
}

/// The outcome of starting or explicitly recovering an interactive rebase.
class GitInteractiveRebaseResult {
  GitInteractiveRebaseResult({
    required this.repositoryId,
    required this.phase,
    required this.state,
    required this.status,
    required this.previousHead,
    required this.resultingHead,
    required this.summary,
    Iterable<String> originalCommitOids = const <String>[],
    Map<String, String> rewrittenCommitOids = const <String, String>{},
    Iterable<String> recoveryRefs = const <String>[],
    Iterable<GitInteractiveRebaseRecoveryAction> recoveryActions =
        const <GitInteractiveRebaseRecoveryAction>[],
    this.recoveryFingerprint,
  }) : originalCommitOids = List.unmodifiable(originalCommitOids),
       rewrittenCommitOids = Map.unmodifiable(rewrittenCommitOids),
       recoveryRefs = List.unmodifiable(recoveryRefs),
       recoveryActions = List.unmodifiable(recoveryActions);

  final RepositoryId repositoryId;
  final GitInteractiveRebasePhase phase;
  final GitInteractiveRebaseExecutionState state;
  final GitStatusSnapshot status;
  final String previousHead;
  final String resultingHead;
  final String summary;
  final List<String> originalCommitOids;
  final Map<String, String> rewrittenCommitOids;
  final List<String> recoveryRefs;
  final List<GitInteractiveRebaseRecoveryAction> recoveryActions;
  final String? recoveryFingerprint;

  bool get historyChanged =>
      state == GitInteractiveRebaseExecutionState.completed;

  bool get isRecoverable => recoveryActions.isNotEmpty;
}

/// A reviewed, immutable interactive rebase plan.
///
/// This is intentionally only the preflight model. Repository state checks,
/// todo-file execution, conflict recovery, and rewritten-object reporting are
/// separate backend steps so a plan can be displayed and tested before Git is
/// allowed to rewrite history.
class GitInteractiveRebasePlan {
  GitInteractiveRebasePlan({
    required this.repositoryId,
    required Iterable<GitInteractiveRebaseEntry> entries,
    this.upstreamRevision,
    this.options = const GitInteractiveRebaseOptions(),
  }) : entries = List.unmodifiable(entries);

  final RepositoryId repositoryId;
  final String? upstreamRevision;
  final List<GitInteractiveRebaseEntry> entries;
  final GitInteractiveRebaseOptions options;

  String get queryKey => [
    upstreamRevision ?? '',
    options.autosquash,
    options.root,
    options.updateRefs,
    ...entries.map((entry) => entry.queryKey),
  ].join('\u0000');

  bool get isValid => validationIssues.isEmpty;

  List<GitInteractiveRebaseIssue> get validationIssues {
    final issues = <GitInteractiveRebaseIssue>[];
    final upstream = upstreamRevision?.trim();
    if (entries.isEmpty) {
      issues.add(
        const GitInteractiveRebaseIssue(
          kind: GitInteractiveRebaseIssueKind.emptyPlan,
          message: 'At least one commit is required for an interactive rebase.',
        ),
      );
    }
    if (options.root && upstream != null && upstream.isNotEmpty) {
      issues.add(
        const GitInteractiveRebaseIssue(
          kind: GitInteractiveRebaseIssueKind.rootHasUpstream,
          message: 'A root rebase must not also specify an upstream revision.',
        ),
      );
    } else if (!options.root && (upstream == null || upstream.isEmpty)) {
      issues.add(
        const GitInteractiveRebaseIssue(
          kind: GitInteractiveRebaseIssueKind.upstreamRequired,
          message: 'An upstream revision is required unless root is selected.',
        ),
      );
    } else if (upstream != null && !_isGitObjectName(upstream)) {
      issues.add(
        const GitInteractiveRebaseIssue(
          kind: GitInteractiveRebaseIssueKind.invalidUpstream,
          message: 'The upstream revision is not a full Git object ID.',
        ),
      );
    }

    final seenOids = <String>{};
    final seenOriginalIndexes = <int>{};
    for (var index = 0; index < entries.length; index++) {
      final entry = entries[index];
      final normalizedOid = entry.originalOid.toLowerCase();
      if (!_isGitObjectName(entry.originalOid)) {
        issues.add(
          GitInteractiveRebaseIssue(
            kind: GitInteractiveRebaseIssueKind.invalidCommitOid,
            message: 'Commit ${entry.originalOid} is not a full Git object ID.',
            entryIndex: index,
          ),
        );
      } else if (!seenOids.add(normalizedOid)) {
        issues.add(
          GitInteractiveRebaseIssue(
            kind: GitInteractiveRebaseIssueKind.duplicateCommit,
            message: 'Commit ${entry.shortOid} appears more than once.',
            entryIndex: index,
          ),
        );
      }
      if (entry.originalIndex < 0) {
        issues.add(
          GitInteractiveRebaseIssue(
            kind: GitInteractiveRebaseIssueKind.invalidOriginalIndex,
            message: 'Commit ${entry.shortOid} has a negative original index.',
            entryIndex: index,
          ),
        );
      } else if (!seenOriginalIndexes.add(entry.originalIndex)) {
        issues.add(
          GitInteractiveRebaseIssue(
            kind: GitInteractiveRebaseIssueKind.duplicateOriginalIndex,
            message:
                'The captured history contains a duplicate original index.',
            entryIndex: index,
          ),
        );
      }

      if (_requiresPreviousCommit(entry.action) &&
          (index == 0 ||
              entries[index - 1].action == GitInteractiveRebaseAction.drop)) {
        issues.add(
          GitInteractiveRebaseIssue(
            kind: GitInteractiveRebaseIssueKind.invalidActionSequence,
            message:
                '${entry.action.label} must follow a commit that remains in the plan.',
            entryIndex: index,
          ),
        );
      }
    }
    return List.unmodifiable(issues);
  }

  /// Returns a plan with one row moved. Original identities and indexes stay
  /// attached to their commits after the reorder.
  GitInteractiveRebasePlan reorder(int fromIndex, int toIndex) {
    _checkIndex(fromIndex);
    _checkInsertIndex(toIndex);
    final reordered = [...entries];
    final entry = reordered.removeAt(fromIndex);
    reordered.insert(toIndex, entry);
    return GitInteractiveRebasePlan(
      repositoryId: repositoryId,
      upstreamRevision: upstreamRevision,
      entries: reordered,
      options: options,
    );
  }

  /// Returns a plan with one row's Git action changed.
  GitInteractiveRebasePlan withAction(
    int entryIndex,
    GitInteractiveRebaseAction action,
  ) {
    _checkIndex(entryIndex);
    final edited = [...entries];
    edited[entryIndex] = edited[entryIndex].copyWith(action: action);
    return GitInteractiveRebasePlan(
      repositoryId: repositoryId,
      upstreamRevision: upstreamRevision,
      entries: edited,
      options: options,
    );
  }

  void _checkIndex(int index) {
    if (index < 0 || index >= entries.length) {
      throw RangeError.index(index, entries, 'entryIndex');
    }
  }

  void _checkInsertIndex(int index) {
    if (index < 0 || index >= entries.length) {
      throw RangeError.index(index, entries, 'toIndex');
    }
  }
}

bool _requiresPreviousCommit(GitInteractiveRebaseAction action) =>
    action == GitInteractiveRebaseAction.squash ||
    action == GitInteractiveRebaseAction.fixup;

bool _isGitObjectName(String value) =>
    RegExp(r'^[0-9a-fA-F]{40}(?:[0-9a-fA-F]{24})?$').hasMatch(value.trim());
