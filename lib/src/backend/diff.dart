import 'dart:convert';

import 'domain.dart';
import 'error.dart';

/// Selects which side of a changed file should be compared with HEAD.
enum GitDiffScope { workingTree, staged }

/// Gives the UI a small amount of structure without making it understand
/// Git's complete patch format.
enum GitDiffLineKind {
  metadata,
  hunkHeader,
  context,
  addition,
  deletion,
  noNewline,
}

class GitDiffLine {
  const GitDiffLine({
    required this.kind,
    required this.text,
    this.oldLineNumber,
    this.newLineNumber,
    this.hunkIndex,
  });

  final GitDiffLineKind kind;
  final String text;
  final int? oldLineNumber;
  final int? newLineNumber;
  final int? hunkIndex;
}

/// One independently selectable hunk in a parsed diff.
class GitDiffHunk {
  GitDiffHunk({
    required this.index,
    required this.oldStart,
    required this.oldCount,
    required this.newStart,
    required this.newCount,
    required this.section,
    required List<GitDiffLine> lines,
  }) : lines = List.unmodifiable(lines);

  final int index;
  final int oldStart;
  final int oldCount;
  final int newStart;
  final int newCount;
  final String section;
  final List<GitDiffLine> lines;

  bool get hasChanges => lines.any(
    (line) =>
        line.kind == GitDiffLineKind.addition ||
        line.kind == GitDiffLineKind.deletion,
  );

  String header({required int oldCount, required int newCount}) {
    final oldRange = oldCount == 1 ? '$oldStart' : '$oldStart,$oldCount';
    final newRange = newCount == 1 ? '$newStart' : '$newStart,$newCount';
    return '@@ -$oldRange +$newRange @@$section';
  }
}

/// A selection that is bound to the exact diff it was created from.
///
/// The UI supplies indexes from parsed hunks and lines. It never supplies raw
/// patch text, so the backend remains the only place that can build argv and
/// patch input for Git.
class GitPatchSelection {
  GitPatchSelection({
    required this.repositoryId,
    required this.path,
    required this.scope,
    required this.contentHash,
    Iterable<int> hunkIndexes = const <int>[],
    Iterable<int> lineIndexes = const <int>[],
  }) : hunkIndexes = Set.unmodifiable(hunkIndexes),
       lineIndexes = Set.unmodifiable(lineIndexes);

  final RepositoryId repositoryId;
  final String path;
  final GitDiffScope scope;
  final String contentHash;
  final Set<int> hunkIndexes;
  final Set<int> lineIndexes;

  bool get isEmpty => hunkIndexes.isEmpty && lineIndexes.isEmpty;
}

/// The bounded stdin payload produced from a safe parsed selection.
class GitPatch {
  GitPatch({required List<int> bytes, required this.selectedChangeCount})
    : bytes = List.unmodifiable(bytes);

  final List<int> bytes;
  final int selectedChangeCount;
}

/// A parsed, bounded unified diff for one requested path.
class GitDiffSnapshot {
  GitDiffSnapshot({
    required this.path,
    required this.scope,
    required List<GitDiffLine> lines,
    required this.contentHash,
    this.repositoryId,
    this.oldPath,
    this.newPath,
    this.isBinary = false,
    this.isRename = false,
    List<String> patchHeader = const <String>[],
    List<GitDiffHunk> hunks = const <GitDiffHunk>[],
  }) : lines = List.unmodifiable(lines),
       patchHeader = List.unmodifiable(patchHeader),
       hunks = List.unmodifiable(hunks);

  final RepositoryId? repositoryId;
  final String path;
  final GitDiffScope scope;
  final List<GitDiffLine> lines;
  final String contentHash;
  final String? oldPath;
  final String? newPath;
  final bool isBinary;
  final bool isRename;
  final List<String> patchHeader;
  final List<GitDiffHunk> hunks;

  int get additions =>
      lines.where((line) => line.kind == GitDiffLineKind.addition).length;

  int get deletions =>
      lines.where((line) => line.kind == GitDiffLineKind.deletion).length;

  bool get isEmpty => lines.isEmpty && !isBinary && !isRename;

  GitDiffSnapshot copyWith({RepositoryId? repositoryId}) {
    return GitDiffSnapshot(
      repositoryId: repositoryId ?? this.repositoryId,
      path: path,
      scope: scope,
      lines: lines,
      contentHash: contentHash,
      oldPath: oldPath,
      newPath: newPath,
      isBinary: isBinary,
      isRename: isRename,
      patchHeader: patchHeader,
      hunks: hunks,
    );
  }
}

GitDiffSnapshot parseUnifiedDiff(
  List<int> bytes, {
  required String path,
  required GitDiffScope scope,
}) {
  final text = utf8.decode(bytes, allowMalformed: true);
  final rawLines = text.split('\n');
  if (rawLines.isNotEmpty && rawLines.last.isEmpty) rawLines.removeLast();

  final lines = <GitDiffLine>[];
  String? oldPath;
  String? newPath;
  var sawOldHeader = false;
  var sawNewHeader = false;
  var sawRename = false;
  var isBinary = false;
  int? oldLineNumber;
  int? newLineNumber;
  var inHunk = false;
  final patchHeader = <String>[];
  final hunks = <GitDiffHunk>[];
  var hunkIndex = -1;
  var currentHunkLines = <GitDiffLine>[];
  int? currentOldStart;
  int? currentOldCount;
  int? currentNewStart;
  int? currentNewCount;
  String currentSection = '';

  void finishHunk() {
    if (currentOldStart == null ||
        currentOldCount == null ||
        currentNewStart == null ||
        currentNewCount == null) {
      return;
    }
    hunks.add(
      GitDiffHunk(
        index: hunkIndex,
        oldStart: currentOldStart!,
        oldCount: currentOldCount!,
        newStart: currentNewStart!,
        newCount: currentNewCount!,
        section: currentSection,
        lines: currentHunkLines,
      ),
    );
    currentHunkLines = <GitDiffLine>[];
    currentOldStart = null;
    currentOldCount = null;
    currentNewStart = null;
    currentNewCount = null;
    currentSection = '';
    inHunk = false;
  }

  void addLine(GitDiffLine line) {
    lines.add(line);
    if (inHunk) {
      currentHunkLines.add(line);
    } else {
      patchHeader.add(line.text);
    }
  }

  for (var rawLine in rawLines) {
    if (rawLine.endsWith('\r')) {
      rawLine = rawLine.substring(0, rawLine.length - 1);
    }

    if (rawLine.startsWith('diff --git ')) {
      if (inHunk) finishHunk();
      final line = _metadata(rawLine);
      addLine(line);
      inHunk = false;
      continue;
    }
    if (rawLine.startsWith('Binary files ') || rawLine == 'GIT binary patch') {
      isBinary = true;
      addLine(_metadata(rawLine));
      continue;
    }
    if (rawLine.startsWith('rename from ')) {
      oldPath = _plainPath(rawLine.substring('rename from '.length));
      sawRename = true;
      addLine(_metadata(rawLine));
      continue;
    }
    if (rawLine.startsWith('rename to ')) {
      newPath = _plainPath(rawLine.substring('rename to '.length));
      sawRename = true;
      addLine(_metadata(rawLine));
      continue;
    }
    // Once a hunk starts, a deleted line can itself begin with "--- ".
    // Only the file headers before the first hunk should update paths.
    if (!inHunk && rawLine.startsWith('--- ')) {
      oldPath = _patchPath(rawLine.substring(4), prefix: 'a/');
      sawOldHeader = true;
      addLine(_metadata(rawLine));
      inHunk = false;
      continue;
    }
    if (!inHunk && rawLine.startsWith('+++ ')) {
      newPath = _patchPath(rawLine.substring(4), prefix: 'b/');
      sawNewHeader = true;
      inHunk = false;
      addLine(_metadata(rawLine));
      continue;
    }
    if (rawLine == r'\ No newline at end of file') {
      addLine(
        GitDiffLine(
          kind: GitDiffLineKind.noNewline,
          text: rawLine,
          hunkIndex: inHunk ? hunkIndex : null,
        ),
      );
      continue;
    }

    final hunk = _hunkPattern.firstMatch(rawLine);
    if (hunk != null) {
      finishHunk();
      hunkIndex++;
      currentOldStart = int.parse(hunk.group(1)!);
      currentOldCount = int.parse(hunk.group(2) ?? '1');
      currentNewStart = int.parse(hunk.group(3)!);
      currentNewCount = int.parse(hunk.group(4) ?? '1');
      currentSection = hunk.group(5) ?? '';
      oldLineNumber = currentOldStart;
      newLineNumber = currentNewStart;
      inHunk = true;
      lines.add(
        GitDiffLine(
          kind: GitDiffLineKind.hunkHeader,
          text: rawLine,
          hunkIndex: hunkIndex,
        ),
      );
      continue;
    }

    if (inHunk && rawLine.isNotEmpty) {
      final first = rawLine[0];
      if (first == ' ') {
        addLine(
          GitDiffLine(
            kind: GitDiffLineKind.context,
            text: rawLine,
            oldLineNumber: oldLineNumber,
            newLineNumber: newLineNumber,
            hunkIndex: hunkIndex,
          ),
        );
        oldLineNumber = _increment(oldLineNumber);
        newLineNumber = _increment(newLineNumber);
        continue;
      }
      if (first == '+') {
        addLine(
          GitDiffLine(
            kind: GitDiffLineKind.addition,
            text: rawLine,
            newLineNumber: newLineNumber,
            hunkIndex: hunkIndex,
          ),
        );
        newLineNumber = _increment(newLineNumber);
        continue;
      }
      if (first == '-') {
        addLine(
          GitDiffLine(
            kind: GitDiffLineKind.deletion,
            text: rawLine,
            oldLineNumber: oldLineNumber,
            hunkIndex: hunkIndex,
          ),
        );
        oldLineNumber = _increment(oldLineNumber);
        continue;
      }
    }

    addLine(_metadata(rawLine));
  }

  finishHunk();

  final rename =
      sawRename || (oldPath != null && newPath != null && oldPath != newPath);
  return GitDiffSnapshot(
    path: path,
    scope: scope,
    lines: List.unmodifiable(lines),
    contentHash: _hash(bytes),
    oldPath: oldPath ?? (sawOldHeader ? null : path),
    newPath: newPath ?? (sawNewHeader ? null : path),
    isBinary: isBinary,
    isRename: rename,
    patchHeader: patchHeader,
    hunks: hunks,
  );
}

/// Converts a parsed selection into a patch without accepting caller text.
///
/// A working-tree patch is applied forward to the index. A staged patch is
/// applied in reverse, so unselected additions and deletions need opposite
/// treatment to keep the patch preimage aligned with the current index.
GitPatch buildSelectedPatch(
  GitDiffSnapshot diff,
  GitPatchSelection selection, {
  bool reverse = false,
}) {
  if (diff.repositoryId != null &&
      diff.repositoryId != selection.repositoryId) {
    throw const GitError(
      category: GitErrorCategory.stalePatch,
      userMessage: 'This diff belongs to a different repository.',
      diagnostic: 'patch selection repository ID did not match the diff',
      retryable: false,
    );
  }
  if (diff.path != selection.path || diff.scope != selection.scope) {
    throw const GitError(
      category: GitErrorCategory.stalePatch,
      userMessage: 'This diff selection is no longer current.',
      diagnostic: 'patch selection path or scope did not match the diff',
      retryable: false,
    );
  }
  if (diff.contentHash != selection.contentHash) {
    throw const GitError(
      category: GitErrorCategory.stalePatch,
      userMessage: 'The file changed. Refresh the diff and select it again.',
      diagnostic: 'patch selection content hash did not match the diff',
      retryable: false,
    );
  }
  if (diff.isBinary || diff.hunks.isEmpty) {
    throw const GitError(
      category: GitErrorCategory.patchRejected,
      userMessage: 'Partial staging is available only for text hunks.',
      diagnostic: 'selected diff was binary or contained no text hunks',
      retryable: false,
    );
  }
  if (selection.isEmpty) {
    throw const GitError(
      category: GitErrorCategory.patchRejected,
      userMessage: 'Select at least one changed line.',
      diagnostic: 'patch selection contained no hunks or lines',
      retryable: false,
    );
  }
  if (selection.hunkIndexes.any(
        (index) => index < 0 || index >= diff.hunks.length,
      ) ||
      selection.lineIndexes.any(
        (index) => index < 0 || index >= diff.lines.length,
      )) {
    throw const GitError(
      category: GitErrorCategory.stalePatch,
      userMessage: 'This diff selection is no longer current.',
      diagnostic: 'patch selection referenced a missing hunk or line',
      retryable: false,
    );
  }

  final patchLines = <String>[...diff.patchHeader];
  var selectedChangeCount = 0;
  for (final hunk in diff.hunks) {
    final hunkLines = <String>[];
    var oldCount = 0;
    var newCount = 0;
    var hunkSelectedChangeCount = 0;
    var lastSourceLineWasEmitted = false;
    for (final line in hunk.lines) {
      final globalIndex = diff.lines.indexOf(line);
      final selected =
          selection.hunkIndexes.contains(hunk.index) ||
          selection.lineIndexes.contains(globalIndex);
      switch (line.kind) {
        case GitDiffLineKind.context:
          hunkLines.add(line.text);
          oldCount++;
          newCount++;
          lastSourceLineWasEmitted = true;
        case GitDiffLineKind.addition:
          if (selected) {
            hunkLines.add(line.text);
            newCount++;
            hunkSelectedChangeCount++;
            lastSourceLineWasEmitted = true;
          } else if (reverse) {
            // An unselected addition is already present in the index while
            // reversing a staged patch, so it must remain context.
            hunkLines.add(' ${line.text.substring(1)}');
            oldCount++;
            newCount++;
            lastSourceLineWasEmitted = true;
          } else {
            // An unselected addition is still only in the working tree, so
            // leave it out of a forward patch applied to the index.
            lastSourceLineWasEmitted = false;
          }
        case GitDiffLineKind.deletion:
          if (selected) {
            hunkLines.add(line.text);
            oldCount++;
            hunkSelectedChangeCount++;
            lastSourceLineWasEmitted = true;
          } else if (reverse) {
            // An unselected deletion is already absent from the index while
            // reversing a staged patch, so it must be omitted entirely.
            lastSourceLineWasEmitted = false;
          } else {
            // An unselected deletion stays in the index, so it is context in
            // the partial patch applied to the index.
            hunkLines.add(' ${line.text.substring(1)}');
            oldCount++;
            newCount++;
            lastSourceLineWasEmitted = true;
          }
        case GitDiffLineKind.noNewline:
          if (lastSourceLineWasEmitted) hunkLines.add(line.text);
        case GitDiffLineKind.metadata || GitDiffLineKind.hunkHeader:
          // Headers are owned by the parsed hunk and are regenerated below.
          break;
      }
    }
    if (hunkSelectedChangeCount == 0) continue;
    patchLines.add(hunk.header(oldCount: oldCount, newCount: newCount));
    patchLines.addAll(hunkLines);
    selectedChangeCount += hunkSelectedChangeCount;
  }

  if (selectedChangeCount == 0) {
    throw const GitError(
      category: GitErrorCategory.patchRejected,
      userMessage: 'Select at least one changed line.',
      diagnostic: 'selection contained only context or unavailable lines',
      retryable: false,
    );
  }
  return GitPatch(
    bytes: utf8.encode('${patchLines.join('\n')}\n'),
    selectedChangeCount: selectedChangeCount,
  );
}

final _hunkPattern = RegExp(
  r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@(.*)$',
);

GitDiffLine _metadata(String text) =>
    GitDiffLine(kind: GitDiffLineKind.metadata, text: text);

String? _patchPath(String value, {required String prefix}) {
  final path = value.split('\t').first;
  if (path == '/dev/null') return null;
  return path.startsWith(prefix) ? path.substring(prefix.length) : path;
}

String _plainPath(String value) =>
    value.startsWith('a/') || value.startsWith('b/')
    ? value.substring(2)
    : value;

int? _increment(int? value) => value == null ? null : value + 1;

String _hash(List<int> bytes) {
  var hash = 0xcbf29ce484222325;
  for (final byte in bytes) {
    hash ^= byte;
    hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}
