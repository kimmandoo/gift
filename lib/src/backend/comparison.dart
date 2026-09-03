import 'dart:convert';

import 'domain.dart';
import 'diff.dart';
import 'objects.dart';
import 'status.dart';

enum GitComparisonSourceKind {
  revision,
  branch,
  tag,
  workingTree,
  clipboard,
  text,
}

/// A comparison endpoint is typed before it reaches the Git executor.
class GitComparisonSource {
  const GitComparisonSource({
    required this.kind,
    required this.value,
    this.label,
  });

  const GitComparisonSource.revision(this.value, {this.label})
    : kind = GitComparisonSourceKind.revision;

  const GitComparisonSource.branch(this.value, {this.label})
    : kind = GitComparisonSourceKind.branch;

  const GitComparisonSource.tag(this.value, {this.label})
    : kind = GitComparisonSourceKind.tag;

  const GitComparisonSource.workingTree({this.label})
    : kind = GitComparisonSourceKind.workingTree,
      value = '';

  const GitComparisonSource.clipboard(this.value, {this.label = 'Clipboard'})
    : kind = GitComparisonSourceKind.clipboard;

  const GitComparisonSource.text(this.value, {this.label = 'External text'})
    : kind = GitComparisonSourceKind.text;

  final GitComparisonSourceKind kind;
  final String value;
  final String? label;

  String get displayName =>
      label ??
      switch (kind) {
        GitComparisonSourceKind.workingTree => 'Working tree',
        GitComparisonSourceKind.clipboard => 'Clipboard',
        GitComparisonSourceKind.text => 'External text',
        _ => value,
      };

  bool get isText =>
      kind == GitComparisonSourceKind.clipboard ||
      kind == GitComparisonSourceKind.text;

  String get identityValue =>
      isText ? hashGitObjectBytes(utf8.encode(value)) : value;
}

class GitComparisonRequest {
  const GitComparisonRequest({
    required this.repositoryId,
    required this.left,
    required this.right,
    this.path,
  });

  final RepositoryId repositoryId;
  final GitComparisonSource left;
  final GitComparisonSource right;
  final String? path;

  String get queryKey => [
    left.kind.name,
    left.identityValue,
    right.kind.name,
    right.identityValue,
    path ?? '',
  ].join('\u001f');
}

enum GitComparisonContentState {
  available,
  missing,
  binary,
  oversized,
  unreadable,
}

class GitComparisonContent {
  const GitComparisonContent({
    required this.state,
    this.text,
    this.byteLength = 0,
    this.contentHash = '',
  });

  const GitComparisonContent.available(String text, {int? byteLength})
    : this(
        state: GitComparisonContentState.available,
        text: text,
        byteLength: byteLength ?? 0,
      );

  const GitComparisonContent.missing()
    : this(state: GitComparisonContentState.missing);

  const GitComparisonContent.binary({int byteLength = 0})
    : this(state: GitComparisonContentState.binary, byteLength: byteLength);

  const GitComparisonContent.oversized({int byteLength = 0})
    : this(state: GitComparisonContentState.oversized, byteLength: byteLength);

  const GitComparisonContent.unreadable()
    : this(state: GitComparisonContentState.unreadable);

  final GitComparisonContentState state;
  final String? text;
  final int byteLength;
  final String contentHash;

  bool get isAvailable => state == GitComparisonContentState.available;
  bool get isBinary => state == GitComparisonContentState.binary;
  bool get isMissing => state == GitComparisonContentState.missing;
  bool get isOversized => state == GitComparisonContentState.oversized;
}

class GitThreeWayComparisonRequest {
  const GitThreeWayComparisonRequest({
    required this.repositoryId,
    required this.base,
    required this.left,
    required this.right,
    required this.path,
  });

  final RepositoryId repositoryId;
  final GitComparisonSource base;
  final GitComparisonSource left;
  final GitComparisonSource right;
  final String path;

  String get queryKey => [
    base.kind.name,
    base.identityValue,
    left.kind.name,
    left.identityValue,
    right.kind.name,
    right.identityValue,
    path,
  ].join('\u001f');
}

class GitThreeWayComparisonSnapshot {
  const GitThreeWayComparisonSnapshot({
    required this.request,
    required this.base,
    required this.left,
    required this.right,
    required this.fingerprint,
  });

  final GitThreeWayComparisonRequest request;
  final GitComparisonContent base;
  final GitComparisonContent left;
  final GitComparisonContent right;
  final String fingerprint;

  bool get hasConflict =>
      left.isAvailable &&
      right.isAvailable &&
      left.text != right.text &&
      base.text != left.text &&
      base.text != right.text;
}

enum GitComparisonFileStatus {
  added,
  copied,
  deleted,
  modified,
  renamed,
  typeChanged,
  unmerged,
  unknown,
}

class GitComparisonFile {
  const GitComparisonFile({
    required this.path,
    required this.status,
    this.oldPath,
    this.additions = 0,
    this.deletions = 0,
    this.isBinary = false,
    this.isOversized = false,
  });

  final String path;
  final GitComparisonFileStatus status;
  final String? oldPath;
  final int additions;
  final int deletions;
  final bool isBinary;
  final bool isOversized;

  String get statusLabel => switch (status) {
    GitComparisonFileStatus.added => 'A',
    GitComparisonFileStatus.copied => 'C',
    GitComparisonFileStatus.deleted => 'D',
    GitComparisonFileStatus.modified => 'M',
    GitComparisonFileStatus.renamed => 'R',
    GitComparisonFileStatus.typeChanged => 'T',
    GitComparisonFileStatus.unmerged => 'U',
    GitComparisonFileStatus.unknown => '?',
  };
}

class GitComparisonSnapshot {
  GitComparisonSnapshot({
    required this.request,
    required List<GitComparisonFile> files,
    required this.fingerprint,
  }) : files = List.unmodifiable(files);

  final GitComparisonRequest request;
  final List<GitComparisonFile> files;
  final String fingerprint;
}

enum GitComparisonTransferAction { apply, revert }

class GitComparisonTransferResult {
  const GitComparisonTransferResult({
    required this.repositoryId,
    required this.path,
    required this.action,
    required this.status,
    required this.summary,
  });

  final RepositoryId repositoryId;
  final String path;
  final GitComparisonTransferAction action;
  final GitStatusSnapshot status;
  final String summary;
}

/// Parses `git diff --name-status -z` without using display order as identity.
List<GitComparisonFile> parseGitComparisonFiles(List<int> output) {
  final fields = utf8.decode(output, allowMalformed: true).split('\u0000');
  final files = <GitComparisonFile>[];
  var index = 0;
  while (index < fields.length) {
    final status = fields[index++];
    if (status.isEmpty) continue;
    final code = status[0];
    GitComparisonFileStatus fileStatus;
    switch (code) {
      case 'A':
        fileStatus = GitComparisonFileStatus.added;
      case 'C':
        fileStatus = GitComparisonFileStatus.copied;
      case 'D':
        fileStatus = GitComparisonFileStatus.deleted;
      case 'M':
        fileStatus = GitComparisonFileStatus.modified;
      case 'R':
        fileStatus = GitComparisonFileStatus.renamed;
      case 'T':
        fileStatus = GitComparisonFileStatus.typeChanged;
      case 'U':
        fileStatus = GitComparisonFileStatus.unmerged;
      default:
        fileStatus = GitComparisonFileStatus.unknown;
    }
    if (fileStatus == GitComparisonFileStatus.renamed ||
        fileStatus == GitComparisonFileStatus.copied) {
      if (index + 1 >= fields.length ||
          fields[index].isEmpty ||
          fields[index + 1].isEmpty) {
        throw FormatException('Invalid rename/copy comparison record: $status');
      }
      final oldPath = fields[index++];
      final path = fields[index++];
      files.add(
        GitComparisonFile(path: path, oldPath: oldPath, status: fileStatus),
      );
      continue;
    }
    if (index >= fields.length || fields[index].isEmpty) {
      throw FormatException('Invalid comparison record: $status');
    }
    files.add(GitComparisonFile(path: fields[index++], status: fileStatus));
  }
  return List.unmodifiable(files);
}

GitDiffScope comparisonDiffScope(GitComparisonRequest request) =>
    request.right.kind == GitComparisonSourceKind.workingTree
    ? GitDiffScope.workingTree
    : GitDiffScope.commit;

const maxComparisonTextBytes = 4 * 1024 * 1024;

String comparisonFingerprint(
  GitComparisonRequest request,
  List<int> rawOutput, {
  String? leftOid,
  String? rightOid,
}) => hashGitObjectBytes([
  ...rawOutput,
  ...request.queryKey.codeUnits,
  ...?leftOid?.codeUnits,
  ...?rightOid?.codeUnits,
]);
