import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

class RecentRepository {
  const RecentRepository(this.path);

  final String path;
  String get displayName {
    final normalized = _withoutTrailingSeparators();
    final separator = _lastSeparatorIndex(normalized);
    if (separator < 0) return normalized;
    final name = normalized.substring(separator + 1);
    return name.isEmpty ? normalized : name;
  }

  String get parentPath {
    final normalized = _withoutTrailingSeparators();
    final separator = _lastSeparatorIndex(normalized);
    if (separator < 0) return '';
    if (separator == 0) return normalized.substring(0, 1);
    return normalized.substring(0, separator);
  }

  String _withoutTrailingSeparators() {
    var end = path.length;
    while (end > 1) {
      final codeUnit = path.codeUnitAt(end - 1);
      if (codeUnit != 47 && codeUnit != 92) break;
      end--;
    }
    return path.substring(0, end);
  }

  int _lastSeparatorIndex(String value) {
    final slash = value.lastIndexOf('/');
    final backslash = value.lastIndexOf(r'\');
    return slash > backslash ? slash : backslash;
  }

  bool get exists => Directory(path).existsSync();
}

class RecentRepositoryStore {
  RecentRepositoryStore(this._preferences) : _memoryPaths = null;

  RecentRepositoryStore.inMemory()
    : _preferences = null,
      _memoryPaths = <String>[];

  static const pathsKey = 'recent_repository_paths';
  static const maxRecentRepositories = 10;

  final SharedPreferences? _preferences;
  final List<String>? _memoryPaths;

  Future<List<RecentRepository>> load() async =>
      _readPaths().map(RecentRepository.new).toList(growable: false);

  Future<void> add(String path) async {
    final normalizedPath = path.trim();
    if (normalizedPath.isEmpty) return;

    final paths = _readPaths()
      ..remove(normalizedPath)
      ..insert(0, normalizedPath);
    if (paths.length > maxRecentRepositories) {
      paths.removeRange(maxRecentRepositories, paths.length);
    }
    await _writePaths(paths);
  }

  Future<void> remove(String path) async {
    final paths = _readPaths()..remove(path);
    await _writePaths(paths);
  }

  List<String> _readPaths() {
    if (_memoryPaths case final paths?) return List<String>.from(paths);
    return List<String>.from(
      _preferences!.getStringList(pathsKey) ?? const <String>[],
    );
  }

  Future<void> _writePaths(List<String> paths) async {
    if (_memoryPaths case final memoryPaths?) {
      memoryPaths
        ..clear()
        ..addAll(paths);
      return;
    }
    await _preferences!.setStringList(pathsKey, paths);
  }
}
