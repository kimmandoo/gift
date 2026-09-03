import 'dart:convert';

import 'domain.dart';
import 'status.dart';

enum GitPathMetadataKind { ignored, untracked, trackedModified }

enum GitIgnoreSource { gitignore, infoExclude, global, commandLine, unknown }

enum GitIgnoreScope { repository, localExclude }

class GitIgnoreEntry {
  const GitIgnoreEntry({
    required this.path,
    required this.kind,
    this.source = GitIgnoreSource.unknown,
    this.sourcePath,
    this.line,
    this.pattern,
  });

  final String path;
  final GitPathMetadataKind kind;
  final GitIgnoreSource source;
  final String? sourcePath;
  final int? line;
  final String? pattern;

  bool get isIgnored => kind == GitPathMetadataKind.ignored;
}

class GitIgnoreSnapshot {
  GitIgnoreSnapshot({
    required this.repositoryId,
    required List<GitIgnoreEntry> entries,
    required this.fingerprint,
  }) : entries = List.unmodifiable(entries);

  final RepositoryId repositoryId;
  final List<GitIgnoreEntry> entries;
  final String fingerprint;

  List<GitIgnoreEntry> get ignored => entries
      .where((entry) => entry.kind == GitPathMetadataKind.ignored)
      .toList(growable: false);

  List<GitIgnoreEntry> get untracked => entries
      .where((entry) => entry.kind == GitPathMetadataKind.untracked)
      .toList(growable: false);

  List<GitIgnoreEntry> get trackedModified => entries
      .where((entry) => entry.kind == GitPathMetadataKind.trackedModified)
      .toList(growable: false);
}

class GitIgnoreRequest {
  const GitIgnoreRequest({required this.path, required this.scope});

  final String path;
  final GitIgnoreScope scope;

  String get queryKey => '${scope.name}|$path';
}

class GitIgnoreActionResult {
  const GitIgnoreActionResult({
    required this.repositoryId,
    required this.request,
    required this.snapshot,
    required this.status,
    required this.pattern,
    required this.changed,
    required this.summary,
  });

  final RepositoryId repositoryId;
  final GitIgnoreRequest request;
  final GitIgnoreSnapshot snapshot;
  final GitStatusSnapshot status;
  final String pattern;
  final bool changed;
  final String summary;
}

class GitAttributeEntry {
  GitAttributeEntry({required this.path, required Map<String, String> values})
    : values = Map.unmodifiable(values);

  final String path;
  final Map<String, String> values;

  List<String> get explanations => explainGitAttributes(values);
}

class GitAttributesSnapshot {
  GitAttributesSnapshot({
    required this.repositoryId,
    required List<GitAttributeEntry> entries,
    required this.fingerprint,
  }) : entries = List.unmodifiable(entries);

  final RepositoryId repositoryId;
  final List<GitAttributeEntry> entries;
  final String fingerprint;
}

class ParsedGitIgnoreStatus {
  ParsedGitIgnoreStatus({
    required List<GitIgnoreEntry> entries,
    required this.contentHash,
  }) : entries = List.unmodifiable(entries);

  final List<GitIgnoreEntry> entries;
  final String contentHash;
}

class GitIgnoreRule {
  const GitIgnoreRule({
    required this.sourcePath,
    required this.line,
    required this.pattern,
    required this.path,
  });

  final String sourcePath;
  final int line;
  final String pattern;
  final String path;

  GitIgnoreSource get source {
    final normalized = sourcePath.replaceAll('\\', '/');
    if (normalized == '.git/info/exclude' ||
        normalized.endsWith('/.git/info/exclude')) {
      return GitIgnoreSource.infoExclude;
    }
    if (normalized.endsWith('/.gitignore') || normalized == '.gitignore') {
      return GitIgnoreSource.gitignore;
    }
    if (normalized.startsWith('command line')) {
      return GitIgnoreSource.commandLine;
    }
    if (normalized.isEmpty) return GitIgnoreSource.unknown;
    return GitIgnoreSource.global;
  }
}

ParsedGitIgnoreStatus parseGitIgnoreStatus(List<int> output) {
  final records = _splitNul(output);
  final ignored = <String>[];
  for (final recordBytes in records) {
    if (recordBytes.length < 3) continue;
    final record = utf8.decode(recordBytes, allowMalformed: true);
    if (record.startsWith('! ')) ignored.add(record.substring(2));
  }

  // The regular parser supplies the same branch-independent tracked and
  // untracked records, while deliberately ignoring the `!` records above.
  final parsed = parseGitStatus(output);
  final entries = <GitIgnoreEntry>[
    for (final change in parsed.changes)
      GitIgnoreEntry(
        path: change.path,
        kind: change.isUntracked
            ? GitPathMetadataKind.untracked
            : GitPathMetadataKind.trackedModified,
      ),
    for (final path in ignored)
      GitIgnoreEntry(path: path, kind: GitPathMetadataKind.ignored),
  ];
  return ParsedGitIgnoreStatus(
    entries: entries,
    contentHash: parsed.contentHash,
  );
}

List<GitIgnoreRule> parseGitIgnoreRules(List<int> output) {
  final fields = _splitNul(output);
  final rules = <GitIgnoreRule>[];
  for (var index = 0; index + 3 < fields.length; index += 4) {
    final sourcePath = utf8.decode(fields[index], allowMalformed: true);
    final lineText = utf8.decode(fields[index + 1], allowMalformed: true);
    final pattern = utf8.decode(fields[index + 2], allowMalformed: true);
    final path = utf8.decode(fields[index + 3], allowMalformed: true);
    final line = int.tryParse(lineText);
    if (sourcePath.isEmpty || line == null || path.isEmpty) continue;
    rules.add(
      GitIgnoreRule(
        sourcePath: sourcePath,
        line: line,
        pattern: pattern,
        path: path,
      ),
    );
  }
  return List.unmodifiable(rules);
}

List<GitAttributeEntry> parseGitAttributes(
  List<int> output, {
  Iterable<String> requestedPaths = const [],
}) {
  final values = <String, Map<String, String>>{};
  final fields = _splitNul(output);
  for (var index = 0; index + 2 < fields.length; index += 3) {
    final path = utf8.decode(fields[index], allowMalformed: true);
    final attribute = utf8.decode(fields[index + 1], allowMalformed: true);
    final value = utf8.decode(fields[index + 2], allowMalformed: true);
    if (path.isEmpty || attribute.isEmpty) continue;
    values.putIfAbsent(path, () => {})[attribute] = value;
  }
  for (final path in requestedPaths) {
    values.putIfAbsent(path, () => {});
  }
  return [
    for (final entry in values.entries)
      GitAttributeEntry(path: entry.key, values: entry.value),
  ];
}

List<String> explainGitAttributes(Map<String, String> values) {
  final explanations = <String>[];
  final text = values['text'];
  if (text == 'set' || text == 'auto') {
    explanations.add('Git treats this path as text for normalization.');
  } else if (text == 'unset') {
    explanations.add(
      'Git treats this path as binary and avoids text normalization.',
    );
  }
  final eol = values['eol'];
  if (eol != null && eol != 'unspecified') {
    explanations.add('The working-tree line ending is configured as $eol.');
  }
  final diff = values['diff'];
  if (diff != null && diff != 'unspecified' && diff != 'unset') {
    explanations.add('A named diff driver may provide textconv output.');
  }
  final filter = values['filter'];
  if (filter != null && filter != 'unspecified' && filter != 'unset') {
    explanations.add(
      'A clean/smudge filter is configured; inspection does not execute it.',
    );
  }
  final encoding = values['working-tree-encoding'];
  if (encoding != null && encoding != 'unspecified') {
    explanations.add('Git uses the $encoding working-tree encoding.');
  }
  return List.unmodifiable(explanations);
}

List<List<int>> _splitNul(List<int> output) {
  final records = <List<int>>[];
  var start = 0;
  for (var index = 0; index < output.length; index++) {
    if (output[index] != 0) continue;
    if (index > start) records.add(output.sublist(start, index));
    start = index + 1;
  }
  if (start < output.length) records.add(output.sublist(start));
  return records;
}
