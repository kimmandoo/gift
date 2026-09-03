import 'dart:convert';

import 'domain.dart';
import 'status.dart';

class GitRemote {
  const GitRemote({required this.name, this.fetchUrl, this.pushUrl});

  final String name;
  final String? fetchUrl;
  final String? pushUrl;
}

enum GitRemoteOperation { fetch, pull, push }

class GitRemoteOperationResult {
  const GitRemoteOperationResult({
    required this.repositoryId,
    required this.remote,
    required this.operation,
    required this.status,
    required this.summary,
    this.target,
  });

  final RepositoryId repositoryId;
  final String remote;
  final GitRemoteOperation operation;
  final GitStatusSnapshot status;
  final String summary;
  final String? target;
}

/// Parses the stable `git remote -v` shape without exposing raw command text
/// to the UI.
List<GitRemote> parseGitRemotes(List<int> output) {
  final records = <String, ({String? fetch, String? push})>{};
  final text = utf8.decode(output, allowMalformed: true);
  for (final rawLine in text.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    final match = RegExp(r'^(\S+)\s+(.+)\s+\((fetch|push)\)$').firstMatch(line);
    if (match == null) {
      throw FormatException('Invalid Git remote record: $line');
    }
    final name = match.group(1)!;
    final url = match.group(2)!;
    final kind = match.group(3)!;
    final current = records[name];
    records[name] = (
      fetch: kind == 'fetch' ? url : current?.fetch,
      push: kind == 'push' ? url : current?.push,
    );
  }
  return records.entries
      .map(
        (entry) => GitRemote(
          name: entry.key,
          fetchUrl: entry.value.fetch,
          pushUrl: entry.value.push,
        ),
      )
      .toList(growable: false);
}
