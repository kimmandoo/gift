import 'dart:convert';

import 'domain.dart';
import 'error.dart';
import 'status.dart';

class GitReflogEntry {
  const GitReflogEntry({
    required this.oid,
    required this.selector,
    required this.message,
    this.previousOid,
    this.actor,
    this.timestamp,
  });

  final String oid;
  final String? previousOid;
  final String selector;
  final String? actor;
  final DateTime? timestamp;
  final String message;
}

class GitReflogSnapshot {
  GitReflogSnapshot({
    required this.repositoryId,
    required this.ref,
    required List<GitReflogEntry> entries,
    required this.fingerprint,
  }) : entries = List.unmodifiable(entries);

  final RepositoryId repositoryId;
  final String ref;
  final List<GitReflogEntry> entries;
  final String fingerprint;
}

class GitRecoveryBranchRequest {
  const GitRecoveryBranchRequest({
    required this.branchName,
    required this.oid,
    required this.reflogFingerprint,
  });

  final String branchName;
  final String oid;
  final String reflogFingerprint;

  String get queryKey => '$branchName|$oid|$reflogFingerprint';
}

class GitRecoveryBranchPreview {
  const GitRecoveryBranchPreview({
    required this.repositoryId,
    required this.request,
    required this.entry,
    required this.fingerprint,
    required this.token,
    required this.expiresAt,
    this.blockingMessage,
  });

  final RepositoryId repositoryId;
  final GitRecoveryBranchRequest request;
  final GitReflogEntry entry;
  final String fingerprint;
  final String token;
  final DateTime expiresAt;
  final String? blockingMessage;

  bool get canExecute =>
      blockingMessage == null && expiresAt.isAfter(DateTime.now());
}

class GitRecoveryBranchResult {
  const GitRecoveryBranchResult({
    required this.repositoryId,
    required this.request,
    required this.branchName,
    required this.status,
    required this.reflog,
    required this.summary,
  });

  final RepositoryId repositoryId;
  final GitRecoveryBranchRequest request;
  final String branchName;
  final GitStatusSnapshot status;
  final GitReflogSnapshot reflog;
  final String summary;
}

/// Parses records emitted by the fixed NUL-delimited reflog format used by
/// RepositoryService. The parser does not interpret the reflog message as a
/// command or a ref.
List<GitReflogEntry> parseGitReflog(List<int> output) {
  final fields = utf8
      .decode(output, allowMalformed: true)
      .replaceAll('\u0000\n', '\u0000')
      .split('\u0000');
  while (fields.isNotEmpty && fields.last.isEmpty) {
    fields.removeLast();
  }
  if (fields.length % 6 != 0) {
    throw GitReflogParseException(
      'Reflog output did not contain complete records.',
    );
  }
  final entries = <GitReflogEntry>[];
  for (var index = 0; index < fields.length; index += 6) {
    final oid = fields[index].trim();
    final previous = fields[index + 1].trim();
    final selector = fields[index + 2].trim();
    final timestamp = DateTime.tryParse(fields[index + 3].trim());
    final actor = fields[index + 4].trim();
    final message = fields[index + 5].trimRight();
    if (!_looksLikeOid(oid) || selector.isEmpty) {
      throw GitReflogParseException(
        'Reflog record contained an invalid object or selector.',
      );
    }
    entries.add(
      GitReflogEntry(
        oid: oid,
        previousOid: _looksLikeOid(previous) ? previous : null,
        selector: selector,
        actor: actor.isEmpty ? null : actor,
        timestamp: timestamp,
        message: message,
      ),
    );
  }
  return List.unmodifiable(entries);
}

class GitReflogParseException extends FormatException {
  GitReflogParseException(super.message);
}

GitError recoveryInputError(String message, String diagnostic) => GitError(
  category: GitErrorCategory.parseFailure,
  userMessage: message,
  diagnostic: diagnostic,
  retryable: false,
);

bool _looksLikeOid(String value) =>
    RegExp(r'^[0-9a-fA-F]{40,64}$').hasMatch(value);
