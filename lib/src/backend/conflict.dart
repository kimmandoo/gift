import 'dart:convert';

import 'domain.dart';

/// The Git operation that left an unmerged index behind.
enum GitConflictOperation { merge, rebase, cherryPick, revert }

/// A content state is explicit so the UI never treats unavailable bytes as an
/// empty file. [notLoaded] is used by the index parser before Git loads a
/// side's blob.
enum GitConflictContentState {
  notLoaded,
  available,
  missing,
  binary,
  tooLarge,
  unreadable,
}

class GitConflictContent {
  const GitConflictContent({
    required this.state,
    this.text,
    this.byteLength = 0,
  });

  const GitConflictContent.notLoaded()
    : state = GitConflictContentState.notLoaded,
      text = null,
      byteLength = 0;

  const GitConflictContent.missing()
    : state = GitConflictContentState.missing,
      text = null,
      byteLength = 0;

  final GitConflictContentState state;
  final String? text;
  final int byteLength;

  bool get isAvailable => state == GitConflictContentState.available;
  bool get isEditable => isAvailable && text != null;
}

/// One index stage or the working-tree result for a conflicted path.
class GitConflictSide {
  const GitConflictSide({
    required this.stage,
    this.mode,
    this.oid,
    this.content = const GitConflictContent.notLoaded(),
  });

  final int stage;
  final String? mode;
  final String? oid;
  final GitConflictContent content;

  bool get exists => oid != null;
}

/// All index stages for one path. A missing base or side is meaningful for
/// add/add and modify/delete conflicts and is therefore kept as null.
class GitConflictEntry {
  const GitConflictEntry({
    required this.path,
    this.base,
    this.ours,
    this.theirs,
    this.result,
    this.originalPath,
  });

  final String path;
  final String? originalPath;
  final GitConflictSide? base;
  final GitConflictSide? ours;
  final GitConflictSide? theirs;
  final GitConflictSide? result;

  bool get hasWorkingResult =>
      result?.content.state != GitConflictContentState.missing;

  GitConflictSide? sideForStage(int stage) => switch (stage) {
    1 => base,
    2 => ours,
    3 => theirs,
    _ => null,
  };

  GitConflictEntry copyWith({
    GitConflictSide? base,
    GitConflictSide? ours,
    GitConflictSide? theirs,
    GitConflictSide? result,
    String? originalPath,
  }) {
    return GitConflictEntry(
      path: path,
      base: base ?? this.base,
      ours: ours ?? this.ours,
      theirs: theirs ?? this.theirs,
      result: result ?? this.result,
      originalPath: originalPath ?? this.originalPath,
    );
  }
}

/// Metadata read from the repository's in-progress operation files.
class GitConflictOperationMetadata {
  const GitConflictOperationMetadata({
    required this.operation,
    this.mergeHeads = const <String>[],
    this.headName,
    this.onto,
    this.currentStep,
    this.totalSteps,
  });

  final GitConflictOperation operation;
  final List<String> mergeHeads;
  final String? headName;
  final String? onto;
  final int? currentStep;
  final int? totalSteps;

  bool get hasProgress => currentStep != null || totalSteps != null;
}

/// The complete, bounded conflict view at one index/worktree point in time.
class GitConflictSnapshot {
  GitConflictSnapshot({
    required this.repositoryId,
    required List<GitConflictEntry> conflicts,
    required this.fingerprint,
    this.operation,
  }) : conflicts = List.unmodifiable(conflicts);

  final RepositoryId repositoryId;
  final List<GitConflictEntry> conflicts;
  final String fingerprint;
  final GitConflictOperationMetadata? operation;

  bool get hasConflicts => conflicts.isNotEmpty;
  bool get canContinue => operation != null && !hasConflicts;
}

enum GitConflictResolutionAction {
  acceptOurs,
  acceptTheirs,
  editResult,
  markResolved,
}

class GitConflictResolutionResult {
  const GitConflictResolutionResult({
    required this.repositoryId,
    required this.path,
    required this.action,
    required this.snapshot,
    required this.summary,
  });

  final RepositoryId repositoryId;
  final String path;
  final GitConflictResolutionAction action;
  final GitConflictSnapshot snapshot;
  final String summary;

  bool get isResolved =>
      !snapshot.conflicts.any((conflict) => conflict.path == path);
}

enum GitConflictOperationAction { continueOperation, abort }

enum GitConflictOperationState {
  continued,
  completed,
  aborted,
  conflicted,
  cancelled,
}

class GitConflictOperationResult {
  const GitConflictOperationResult({
    required this.repositoryId,
    required this.operation,
    required this.action,
    required this.state,
    required this.snapshot,
    required this.summary,
  });

  final RepositoryId repositoryId;
  final GitConflictOperationMetadata operation;
  final GitConflictOperationAction action;
  final GitConflictOperationState state;
  final GitConflictSnapshot snapshot;
  final String summary;
}

/// The raw stage record produced by `git ls-files -u -z`.
class GitUnmergedIndexRecord {
  const GitUnmergedIndexRecord({
    required this.path,
    required this.mode,
    required this.oid,
    required this.stage,
  });

  final String path;
  final String mode;
  final String oid;
  final int stage;
}

/// Parses Git's NUL-delimited unmerged index records into one row per path.
///
/// Git separates the stage metadata from the path with a tab even when the
/// path itself contains spaces or tabs. The parser preserves that path and
/// never treats it as a shell fragment.
List<GitConflictEntry> parseGitUnmergedIndex(List<int> output) {
  final records = <String>[];
  var start = 0;
  for (var index = 0; index < output.length; index++) {
    if (output[index] != 0) continue;
    if (index > start) {
      records.add(
        utf8.decode(output.sublist(start, index), allowMalformed: true),
      );
    }
    start = index + 1;
  }
  if (start < output.length) {
    records.add(utf8.decode(output.sublist(start), allowMalformed: true));
  }

  final grouped = <String, Map<int, GitConflictSide>>{};
  for (final record in records) {
    final tab = record.indexOf('\t');
    if (tab <= 0 || tab == record.length - 1) {
      throw FormatException('Invalid unmerged index record: $record');
    }
    final fields = record.substring(0, tab).split(RegExp(r'\s+'));
    if (fields.length != 3 || fields[0].length != 6) {
      throw FormatException('Invalid unmerged index metadata: $record');
    }
    final stage = int.tryParse(fields[2]);
    if (stage == null || stage < 1 || stage > 3 || fields[1].isEmpty) {
      throw FormatException('Invalid unmerged index stage: $record');
    }
    final path = record.substring(tab + 1);
    final stages = grouped.putIfAbsent(path, () => <int, GitConflictSide>{});
    if (stages.containsKey(stage)) {
      throw FormatException('Duplicate unmerged index stage: $record');
    }
    stages[stage] = GitConflictSide(
      stage: stage,
      mode: fields[0],
      oid: fields[1],
    );
  }

  final basePaths = grouped.entries
      .where((entry) => entry.value[1] != null)
      .map((entry) => entry.key)
      .toList(growable: false);
  return List.unmodifiable(
    grouped.entries.map(
      (entry) => GitConflictEntry(
        path: entry.key,
        originalPath: entry.value[1] == null && basePaths.length == 1
            ? basePaths.single
            : null,
        base: entry.value[1],
        ours: entry.value[2],
        theirs: entry.value[3],
      ),
    ),
  );
}

String hashConflictBytes(Iterable<int> bytes) {
  var hash = 0xcbf29ce484222325;
  for (final byte in bytes) {
    hash ^= byte;
    hash *= 0x100000001b3;
    hash &= 0xffffffffffffffff;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}
