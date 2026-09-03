import 'dart:convert';

import 'domain.dart';
import 'remote.dart';
import 'status.dart';

enum GitStashAction { create, apply, pop, drop, branch }

enum GitStashActionState { completed, conflicted, cancelled }

class GitStashEntry {
  const GitStashEntry({
    required this.oid,
    required this.selector,
    required this.subject,
    this.branch,
    this.createdAt,
  });

  final String oid;
  final String selector;
  final String subject;
  final String? branch;
  final DateTime? createdAt;
}

class GitStashSnapshot {
  GitStashSnapshot({
    required this.repositoryId,
    required List<GitStashEntry> entries,
    required this.fingerprint,
  }) : entries = List.unmodifiable(entries);

  final RepositoryId repositoryId;
  final List<GitStashEntry> entries;
  final String fingerprint;
}

class GitStashActionResult {
  const GitStashActionResult({
    required this.repositoryId,
    required this.action,
    required this.state,
    required this.status,
    required this.snapshot,
    required this.summary,
    this.stashOid,
  });

  final RepositoryId repositoryId;
  final GitStashAction action;
  final GitStashActionState state;
  final GitStatusSnapshot status;
  final GitStashSnapshot snapshot;
  final String summary;
  final String? stashOid;

  bool get hasConflicts => state == GitStashActionState.conflicted;
}

enum GitTagKind { lightweight, annotated }

enum GitTagAction { create, delete }

class GitTag {
  const GitTag({
    required this.name,
    required this.targetOid,
    required this.kind,
    this.tagObjectOid,
    this.subject,
    this.message,
    this.tagger,
    this.createdAt,
  });

  final String name;
  final String targetOid;
  final GitTagKind kind;
  final String? tagObjectOid;
  final String? subject;
  final String? message;
  final String? tagger;
  final DateTime? createdAt;
}

class GitTagSnapshot {
  GitTagSnapshot({
    required this.repositoryId,
    required List<GitTag> tags,
    required this.fingerprint,
  }) : tags = List.unmodifiable(tags);

  final RepositoryId repositoryId;
  final List<GitTag> tags;
  final String fingerprint;
}

class GitTagActionResult {
  const GitTagActionResult({
    required this.repositoryId,
    required this.action,
    required this.status,
    required this.snapshot,
    required this.summary,
    this.tag,
  });

  final RepositoryId repositoryId;
  final GitTagAction action;
  final GitStatusSnapshot status;
  final GitTagSnapshot snapshot;
  final String summary;
  final GitTag? tag;
}

enum GitObjectPreviewAction { dropStash, deleteTag, removeRemote, pruneRemote }

/// A short-lived confirmation bound to an object identity and its current
/// repository snapshot. The token is opaque to the UI and cannot be reused.
class GitObjectPreview {
  GitObjectPreview({
    required this.repositoryId,
    required this.action,
    required this.objectName,
    required this.fingerprint,
    required this.token,
    required this.expiresAt,
    List<String> details = const [],
    this.objectId,
  }) : details = List.unmodifiable(details);

  final RepositoryId repositoryId;
  final GitObjectPreviewAction action;
  final String objectName;
  final String? objectId;
  final String fingerprint;
  final List<String> details;
  final String token;
  final DateTime expiresAt;

  bool get canExecute => expiresAt.isAfter(DateTime.now());
}

enum GitRemoteAction { add, rename, setUrl, remove, prune, pushTag }

class GitRemoteActionResult {
  GitRemoteActionResult({
    required this.repositoryId,
    required this.action,
    required List<GitRemote> remotes,
    required this.status,
    required this.summary,
    this.remoteName,
  }) : remotes = List.unmodifiable(remotes);

  final RepositoryId repositoryId;
  final GitRemoteAction action;
  final List<GitRemote> remotes;
  final GitStatusSnapshot status;
  final String summary;
  final String? remoteName;
}

class GitUpstreamSnapshot {
  const GitUpstreamSnapshot({
    required this.repositoryId,
    required this.branch,
    this.remote,
    this.remoteBranch,
    this.ahead = 0,
    this.behind = 0,
  });

  final RepositoryId repositoryId;
  final String? branch;
  final String? remote;
  final String? remoteBranch;
  final int ahead;
  final int behind;

  bool get hasUpstream => remote != null && remoteBranch != null;
}

enum GitUpstreamAction { set, unset, publish }

class GitUpstreamActionResult {
  const GitUpstreamActionResult({
    required this.repositoryId,
    required this.action,
    required this.status,
    required this.upstream,
    required this.summary,
  });

  final RepositoryId repositoryId;
  final GitUpstreamAction action;
  final GitStatusSnapshot status;
  final GitUpstreamSnapshot upstream;
  final String summary;
}

List<GitStashEntry> parseGitStashes(List<int> output) {
  final entries = <GitStashEntry>[];
  final text = utf8.decode(output, allowMalformed: true);
  for (final rawLine in text.split('\n')) {
    final line = rawLine.trimRight();
    if (line.isEmpty) continue;
    final fields = line.split('\u0000');
    if (fields.length < 4 || !_isObjectOid(fields[0])) {
      throw FormatException('Invalid Git stash record: $line');
    }
    final subject = fields[2];
    final branch = RegExp(r'^(?:(?:WIP|index) on|On) ([^:]+):')
        .firstMatch(subject)
        ?.group(1);
    entries.add(
      GitStashEntry(
        oid: fields[0],
        selector: fields[1],
        subject: subject,
        branch: branch,
        createdAt: DateTime.tryParse(fields[3]),
      ),
    );
  }
  return List.unmodifiable(entries);
}

List<GitTag> parseGitTags(List<int> output) {
  final tags = <GitTag>[];
  final text = utf8.decode(output, allowMalformed: true);
  for (final rawLine in text.split('\n')) {
    final line = rawLine.trimRight();
    if (line.isEmpty) continue;
    final fields = line.split('\u0000');
    if (fields.length < 3 || fields[0].isEmpty) {
      throw FormatException('Invalid Git tag record: $line');
    }
    final kind = fields[2] == 'tag'
        ? GitTagKind.annotated
        : GitTagKind.lightweight;
    final targetOid = kind == GitTagKind.annotated
        ? fields.length > 3
              ? fields[3]
              : ''
        : fields[1];
    if (!_isObjectOid(targetOid)) {
      throw FormatException('Git tag does not point to a commit: $line');
    }
    tags.add(
      GitTag(
        name: fields[0],
        targetOid: targetOid,
        kind: kind,
        tagObjectOid: kind == GitTagKind.annotated ? fields[1] : null,
        subject: fields.length > 5 && fields[5].isNotEmpty ? fields[5] : null,
        createdAt: fields.length > 6 ? DateTime.tryParse(fields[6]) : null,
      ),
    );
  }
  return List.unmodifiable(tags);
}

String hashGitObjectBytes(List<int> bytes) {
  var hash = 0xcbf29ce484222325;
  for (final byte in bytes) {
    hash ^= byte;
    hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

bool _isObjectOid(String value) =>
    RegExp(r'^[0-9a-fA-F]{40,64}$').hasMatch(value);
