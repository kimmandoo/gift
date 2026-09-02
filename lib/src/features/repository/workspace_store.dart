import 'package:shared_preferences/shared_preferences.dart';

/// The durable part of a workspace.
///
/// Only canonical paths are stored. Repository IDs are created again by the
/// backend after a restart, so an old session handle can never be reused.
class WorkspaceSnapshot {
  const WorkspaceSnapshot({required this.paths, required this.activePath});

  final List<String> paths;
  final String? activePath;

  @override
  int get hashCode => Object.hash(Object.hashAll(paths), activePath);

  @override
  bool operator ==(Object other) =>
      identical(other, this) ||
      other is WorkspaceSnapshot &&
          _listEquals(other.paths, paths) &&
          other.activePath == activePath;
}

class WorkspaceStore {
  WorkspaceStore(this._preferences) : _memoryPaths = null;

  WorkspaceStore.inMemory()
    : _preferences = null,
      _memoryPaths = <String>[],
      _memoryActivePath = null;

  static const pathsKey = 'workspace_repository_paths';
  static const activePathKey = 'workspace_active_path';

  final SharedPreferences? _preferences;
  final List<String>? _memoryPaths;
  String? _memoryActivePath;

  Future<WorkspaceSnapshot> load() async {
    final paths = _uniquePaths(_readPaths());
    final activePath = _readActivePath()?.trim();
    return WorkspaceSnapshot(
      paths: List.unmodifiable(paths),
      activePath: paths.contains(activePath) ? activePath : null,
    );
  }

  Future<void> save({
    required List<String> paths,
    required String? activePath,
  }) async {
    final uniquePaths = <String>[];
    for (final path in paths) {
      final trimmed = path.trim();
      if (trimmed.isNotEmpty && !uniquePaths.contains(trimmed)) {
        uniquePaths.add(trimmed);
      }
    }
    final storedActivePath = uniquePaths.contains(activePath?.trim())
        ? activePath!.trim()
        : null;
    if (_memoryPaths case final memoryPaths?) {
      memoryPaths
        ..clear()
        ..addAll(uniquePaths);
      _memoryActivePath = storedActivePath;
      return;
    }
    await _preferences!.setStringList(pathsKey, uniquePaths);
    if (storedActivePath == null) {
      await _preferences.remove(activePathKey);
    } else {
      await _preferences.setString(activePathKey, storedActivePath);
    }
  }

  List<String> _readPaths() {
    if (_memoryPaths case final paths?) return List<String>.from(paths);
    return List<String>.from(
      _preferences!.getStringList(pathsKey) ?? const <String>[],
    );
  }

  String? _readActivePath() {
    if (_memoryPaths != null) return _memoryActivePath;
    return _preferences!.getString(activePathKey);
  }
}

bool _listEquals(List<String> first, List<String> second) {
  if (first.length != second.length) return false;
  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) return false;
  }
  return true;
}

List<String> _uniquePaths(Iterable<String> paths) {
  final unique = <String>[];
  for (final path in paths) {
    final trimmed = path.trim();
    if (trimmed.isNotEmpty && !unique.contains(trimmed)) unique.add(trimmed);
  }
  return unique;
}
