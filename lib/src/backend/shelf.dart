import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'domain.dart';
import 'objects.dart';

/// The maximum patch gift will keep in its app-local shelf store.
const maxShelfPatchBytes = 4 * 1024 * 1024;
const _maxShelfMetadataBytes = 8 * 1024 * 1024;

enum GitShelfActionOutcome {
  shelved,
  unshelved,
  restored,
  imported,
  deleted,
  conflict,
  baseMissing,
}

/// A changelist is local gift organization. It is deliberately not a Git
/// index or stash, so changing it never changes repository history.
class GitChangelist {
  GitChangelist({
    required this.id,
    required this.name,
    required Iterable<String> paths,
    required this.isActive,
  }) : paths = List.unmodifiable(paths);

  final String id;
  final String name;
  final List<String> paths;
  final bool isActive;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'paths': paths,
    'active': isActive,
  };

  factory GitChangelist.fromJson(Map<Object?, Object?> json) {
    return GitChangelist(
      id: _requiredString(json, 'id'),
      name: _requiredString(json, 'name'),
      paths: _stringList(json['paths']),
      isActive: json['active'] == true,
    );
  }
}

class GitShelf {
  GitShelf({
    required this.id,
    required this.name,
    required this.baseRevision,
    required Iterable<String> paths,
    required List<int> patchBytes,
    required this.createdAt,
    this.imported = false,
  }) : paths = List.unmodifiable(paths),
       patchBytes = List.unmodifiable(patchBytes);

  final String id;
  final String name;
  final String? baseRevision;
  final List<String> paths;
  final List<int> patchBytes;
  final DateTime createdAt;
  final bool imported;

  String get patchHash => hashGitObjectBytes(patchBytes);

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'baseRevision': baseRevision,
    'paths': paths,
    'patch': base64Encode(patchBytes),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'imported': imported,
  };

  factory GitShelf.fromJson(Map<Object?, Object?> json) {
    final encoded = _requiredString(json, 'patch');
    final patch = base64Decode(encoded);
    if (patch.length > maxShelfPatchBytes) {
      throw const FormatException('shelf patch exceeds the safety limit');
    }
    return GitShelf(
      id: _requiredString(json, 'id'),
      name: _requiredString(json, 'name'),
      baseRevision: json['baseRevision'] as String?,
      paths: _stringList(json['paths']),
      patchBytes: patch,
      createdAt: DateTime.parse(_requiredString(json, 'createdAt')),
      imported: json['imported'] == true,
    );
  }
}

class GitChangelistSnapshot {
  GitChangelistSnapshot({
    required this.repositoryId,
    required Iterable<GitChangelist> lists,
    required this.fingerprint,
  }) : lists = List.unmodifiable(lists);

  final RepositoryId repositoryId;
  final List<GitChangelist> lists;
  final String fingerprint;

  GitChangelist? get active => lists.where((list) => list.isActive).firstOrNull;
}

class GitShelfSnapshot {
  GitShelfSnapshot({
    required this.repositoryId,
    required Iterable<GitShelf> shelves,
    required this.fingerprint,
  }) : shelves = List.unmodifiable(shelves);

  final RepositoryId repositoryId;
  final List<GitShelf> shelves;
  final String fingerprint;
}

class GitShelfActionResult {
  const GitShelfActionResult({
    required this.repositoryId,
    required this.outcome,
    required this.changelists,
    required this.shelves,
    this.shelf,
    required this.summary,
  });

  final RepositoryId repositoryId;
  final GitShelfActionOutcome outcome;
  final GitChangelistSnapshot changelists;
  final GitShelfSnapshot shelves;
  final GitShelf? shelf;
  final String summary;
}

class GitShelfStoreData {
  GitShelfStoreData({
    required Iterable<GitChangelist> changelists,
    required Iterable<GitShelf> shelves,
  }) : changelists = List.unmodifiable(changelists),
       shelves = List.unmodifiable(shelves);

  final List<GitChangelist> changelists;
  final List<GitShelf> shelves;

  Map<String, Object?> toJson() => {
    'version': 1,
    'changelists': changelists.map((list) => list.toJson()).toList(),
    'shelves': shelves.map((shelf) => shelf.toJson()).toList(),
  };

  factory GitShelfStoreData.fromJson(Map<Object?, Object?> json) {
    final rawLists = json['changelists'];
    final rawShelves = json['shelves'];
    if (rawLists is! List || rawShelves is! List) {
      throw const FormatException('shelf metadata has invalid collections');
    }
    return GitShelfStoreData(
      changelists: rawLists.whereType<Map<Object?, Object?>>().map(
        GitChangelist.fromJson,
      ),
      shelves: rawShelves.whereType<Map<Object?, Object?>>().map(
        GitShelf.fromJson,
      ),
    );
  }
}

abstract interface class GitShelfStore {
  Future<GitShelfStoreData> read(String repositoryRoot);

  Future<void> write(String repositoryRoot, GitShelfStoreData data);
}

/// Persists metadata below Git's private directory. It does not create or
/// alter refs, index entries, or stash commits, and is therefore safe to use
/// alongside the repository's native stash workflow.
class FileGitShelfStore implements GitShelfStore {
  const FileGitShelfStore();

  @override
  Future<GitShelfStoreData> read(String repositoryRoot) async {
    final file = await _metadataFile(repositoryRoot);
    if (!await file.exists()) {
      return GitShelfStoreData(changelists: const [], shelves: const []);
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > _maxShelfMetadataBytes) {
      throw const FormatException('shelf metadata exceeds the safety limit');
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<Object?, Object?>) {
      throw const FormatException('shelf metadata root is not an object');
    }
    return GitShelfStoreData.fromJson(decoded);
  }

  @override
  Future<void> write(String repositoryRoot, GitShelfStoreData data) async {
    final file = await _metadataFile(repositoryRoot);
    final bytes = utf8.encode(jsonEncode(data.toJson()));
    if (bytes.length > _maxShelfMetadataBytes) {
      throw const FormatException('shelf metadata exceeds the safety limit');
    }
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(file.path);
  }

  Future<File> _metadataFile(String repositoryRoot) async {
    final dotGit = File('$repositoryRoot/.git');
    final gitDirectory = Directory(dotGit.path);
    if (await gitDirectory.exists()) {
      return File('${gitDirectory.path}/gift/shelves.json');
    }
    if (await dotGit.exists()) {
      final content = await dotGit.readAsString();
      final line = content
          .split(RegExp(r'\r?\n'))
          .where((line) => line.startsWith('gitdir:'))
          .firstOrNull;
      if (line != null) {
        final rawPath = line.substring('gitdir:'.length).trim();
        final resolved = Directory(rawPath).isAbsolute
            ? rawPath
            : Directory('$repositoryRoot/$rawPath').absolute.path;
        return File('$resolved/gift/shelves.json');
      }
    }
    throw const FileSystemException('Git metadata directory is unavailable');
  }
}

/// Small deterministic test double for persistence and controller tests.
class MemoryGitShelfStore implements GitShelfStore {
  final Map<String, GitShelfStoreData> _data = {};

  @override
  Future<GitShelfStoreData> read(String repositoryRoot) async =>
      _data[repositoryRoot] ??
      GitShelfStoreData(changelists: const [], shelves: const []);

  @override
  Future<void> write(String repositoryRoot, GitShelfStoreData data) async {
    _data[repositoryRoot] = data;
  }
}

String _requiredString(Map<Object?, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('shelf metadata field $key is invalid');
  }
  return value;
}

List<String> _stringList(Object? value) {
  if (value is! List || value.any((item) => item is! String)) {
    throw const FormatException('shelf metadata path list is invalid');
  }
  return value.cast<String>();
}
