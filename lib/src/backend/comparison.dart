import 'dart:convert';

import 'domain.dart';
import 'diff.dart';
import 'objects.dart';

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

  final GitComparisonSourceKind kind;
  final String value;
  final String? label;

  String get displayName => label ?? value;
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
    left.value,
    right.kind.name,
    right.value,
    path ?? '',
  ].join('\u001f');
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
  });

  final String path;
  final GitComparisonFileStatus status;
  final String? oldPath;
  final int additions;
  final int deletions;
  final bool isBinary;

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
