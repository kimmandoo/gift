import 'dart:convert';

import 'domain.dart';

/// Selects which side of a changed file should be compared with HEAD.
enum GitDiffScope { workingTree, staged }

/// Gives the UI a small amount of structure without making it understand
/// Git's complete patch format.
enum GitDiffLineKind { metadata, hunkHeader, context, addition, deletion }

class GitDiffLine {
  const GitDiffLine({
    required this.kind,
    required this.text,
    this.oldLineNumber,
    this.newLineNumber,
  });

  final GitDiffLineKind kind;
  final String text;
  final int? oldLineNumber;
  final int? newLineNumber;
}

/// A parsed, bounded unified diff for one requested path.
class GitDiffSnapshot {
  const GitDiffSnapshot({
    required this.path,
    required this.scope,
    required this.lines,
    required this.contentHash,
    this.repositoryId,
    this.oldPath,
    this.newPath,
    this.isBinary = false,
    this.isRename = false,
  });

  final RepositoryId? repositoryId;
  final String path;
  final GitDiffScope scope;
  final List<GitDiffLine> lines;
  final String contentHash;
  final String? oldPath;
  final String? newPath;
  final bool isBinary;
  final bool isRename;

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

  for (var rawLine in rawLines) {
    if (rawLine.endsWith('\r')) {
      rawLine = rawLine.substring(0, rawLine.length - 1);
    }

    if (rawLine.startsWith('diff --git ')) {
      lines.add(_metadata(rawLine));
      inHunk = false;
      continue;
    }
    if (rawLine.startsWith('Binary files ') || rawLine == 'GIT binary patch') {
      isBinary = true;
      lines.add(_metadata(rawLine));
      continue;
    }
    if (rawLine.startsWith('rename from ')) {
      oldPath = _plainPath(rawLine.substring('rename from '.length));
      sawRename = true;
      lines.add(_metadata(rawLine));
      continue;
    }
    if (rawLine.startsWith('rename to ')) {
      newPath = _plainPath(rawLine.substring('rename to '.length));
      sawRename = true;
      lines.add(_metadata(rawLine));
      continue;
    }
    // Once a hunk starts, a deleted line can itself begin with "--- ".
    // Only the file headers before the first hunk should update paths.
    if (!inHunk && rawLine.startsWith('--- ')) {
      oldPath = _patchPath(rawLine.substring(4), prefix: 'a/');
      sawOldHeader = true;
      lines.add(_metadata(rawLine));
      inHunk = false;
      continue;
    }
    if (!inHunk && rawLine.startsWith('+++ ')) {
      newPath = _patchPath(rawLine.substring(4), prefix: 'b/');
      sawNewHeader = true;
      lines.add(_metadata(rawLine));
      inHunk = false;
      continue;
    }

    final hunk = _hunkPattern.firstMatch(rawLine);
    if (hunk != null) {
      oldLineNumber = int.parse(hunk.group(1)!);
      newLineNumber = int.parse(hunk.group(3)!);
      inHunk = true;
      lines.add(GitDiffLine(kind: GitDiffLineKind.hunkHeader, text: rawLine));
      continue;
    }

    if (inHunk && rawLine.isNotEmpty) {
      final first = rawLine[0];
      if (first == ' ') {
        lines.add(
          GitDiffLine(
            kind: GitDiffLineKind.context,
            text: rawLine,
            oldLineNumber: oldLineNumber,
            newLineNumber: newLineNumber,
          ),
        );
        oldLineNumber = _increment(oldLineNumber);
        newLineNumber = _increment(newLineNumber);
        continue;
      }
      if (first == '+') {
        lines.add(
          GitDiffLine(
            kind: GitDiffLineKind.addition,
            text: rawLine,
            newLineNumber: newLineNumber,
          ),
        );
        newLineNumber = _increment(newLineNumber);
        continue;
      }
      if (first == '-') {
        lines.add(
          GitDiffLine(
            kind: GitDiffLineKind.deletion,
            text: rawLine,
            oldLineNumber: oldLineNumber,
          ),
        );
        oldLineNumber = _increment(oldLineNumber);
        continue;
      }
    }

    lines.add(_metadata(rawLine));
  }

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
  );
}

final _hunkPattern = RegExp(
  r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@(?:.*)?$',
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
