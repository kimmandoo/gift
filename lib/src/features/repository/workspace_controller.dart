import 'package:flutter/foundation.dart';
import 'package:gitflu/src/backend/domain.dart';
import 'package:gitflu/src/backend/error.dart';
import 'package:gitflu/src/backend/git_gateway.dart';
import 'package:gitflu/src/features/repository/changes_controller.dart';
import 'package:gitflu/src/features/repository/history_controller.dart';
import 'package:gitflu/src/features/repository/recent_repository_store.dart';
import 'package:gitflu/src/features/repository/workspace_store.dart';

/// One visible tab and its session-local repository state.
///
/// The path is durable. The repository ID and ChangesController are created
/// for this process only, which keeps one tab's selections and mutations away
/// from every other tab.
class WorkspaceTab {
  const WorkspaceTab({
    required this.path,
    this.repository,
    this.error,
    this.isLoading = false,
    this.changesController,
    this.historyController,
  });

  final String path;
  final RepositoryOpened? repository;
  final GitError? error;
  final bool isLoading;
  final ChangesController? changesController;
  final HistoryController? historyController;

  bool get isAvailable => repository != null;

  String get displayName {
    final cleaned = path.replaceFirst(RegExp(r'[/\\]+$'), '');
    if (cleaned.isEmpty) return path;
    final separator = cleaned.lastIndexOf(RegExp(r'[/\\]'));
    return separator == -1 ? cleaned : cleaned.substring(separator + 1);
  }
}

class WorkspaceState {
  const WorkspaceState({
    this.tabs = const <WorkspaceTab>[],
    this.activeIndex = 0,
    this.isRestoring = false,
    this.openingPath,
  });

  final List<WorkspaceTab> tabs;
  final int activeIndex;
  final bool isRestoring;
  final String? openingPath;

  WorkspaceTab? get activeTab =>
      activeIndex >= 0 && activeIndex < tabs.length ? tabs[activeIndex] : null;

  WorkspaceState copyWith({
    List<WorkspaceTab>? tabs,
    int? activeIndex,
    bool? isRestoring,
    String? openingPath,
    bool clearOpeningPath = false,
  }) {
    return WorkspaceState(
      tabs: tabs ?? this.tabs,
      activeIndex: activeIndex ?? this.activeIndex,
      isRestoring: isRestoring ?? this.isRestoring,
      openingPath: clearOpeningPath ? null : openingPath ?? this.openingPath,
    );
  }
}

class WorkspaceController extends ChangeNotifier {
  WorkspaceController({
    required this.gateway,
    required this.store,
    this.recentStore,
    this.changesPollInterval = const Duration(seconds: 3),
  });

  final GitGateway gateway;
  final WorkspaceStore store;
  final RecentRepositoryStore? recentStore;
  final Duration changesPollInterval;

  WorkspaceState _state = const WorkspaceState();
  Future<void> _pendingPersistence = Future<void>.value();
  var _didRestore = false;
  var _disposed = false;

  WorkspaceState get state => _state;

  Future<void> restore() async {
    if (_didRestore || _disposed) return;
    _didRestore = true;
    _setState(_state.copyWith(isRestoring: true));
    final saved = await store.load();
    if (_disposed) return;

    final paths = _uniquePaths(saved.paths);
    final activePath = saved.activePath;
    var resolvedActivePath = activePath;
    var tabs = paths
        .map((path) => WorkspaceTab(path: path, isLoading: true))
        .toList(growable: true);
    _setState(
      WorkspaceState(
        tabs: List.unmodifiable(tabs),
        activeIndex: _indexForPath(paths, activePath),
        isRestoring: true,
      ),
    );

    final seenRoots = <String>{};
    for (var index = 0; index < paths.length; index++) {
      final path = paths[index];
      try {
        final repository = await gateway.openRepository(path);
        if (_disposed) return;
        if (!seenRoots.add(repository.root)) {
          tabs[index] = WorkspaceTab(
            path: path,
            error: const GitError(
              category: GitErrorCategory.unsupportedRepositoryState,
              userMessage: 'This repository is already open in another tab.',
              diagnostic: 'duplicate canonical workspace root during restore',
              retryable: false,
            ),
          );
        } else {
          tabs[index] = _availableTab(repository);
          if (path == activePath) resolvedActivePath = repository.root;
        }
      } on GitError catch (error) {
        if (_disposed) return;
        tabs[index] = WorkspaceTab(path: path, error: error);
      }
      _setState(
        _state.copyWith(tabs: List.unmodifiable(tabs), isRestoring: true),
      );
    }
    tabs = _removeDuplicateCanonicalTabs(tabs);
    _setState(
      _state.copyWith(
        tabs: List.unmodifiable(tabs),
        activeIndex: _indexForPath(
          tabs.map((tab) => tab.path).toList(growable: false),
          resolvedActivePath,
        ),
        isRestoring: false,
      ),
    );
    await _persist();
  }

  Future<WorkspaceTab?> openPath(String path, {int? replaceIndex}) async {
    final requestedPath = path.trim();
    if (requestedPath.isEmpty || _disposed) return null;

    final existingIndex = _findPath(requestedPath);
    if (existingIndex != null && state.tabs[existingIndex].isAvailable) {
      select(existingIndex);
      return state.tabs[existingIndex];
    }
    final targetIndex = replaceIndex ?? existingIndex;

    _setState(_state.copyWith(openingPath: requestedPath));
    try {
      final repository = await gateway.openRepository(requestedPath);
      if (_disposed) return null;
      final canonicalIndex = _findCanonicalPath(repository.root);
      if (canonicalIndex != null && canonicalIndex != targetIndex) {
        if (targetIndex != null && _isValidIndex(targetIndex)) {
          _disposeTab(state.tabs[targetIndex]);
          final tabs = List<WorkspaceTab>.from(state.tabs)
            ..removeAt(targetIndex);
          final nextIndex = canonicalIndex > targetIndex
              ? canonicalIndex - 1
              : canonicalIndex;
          _setState(
            _state.copyWith(
              tabs: List.unmodifiable(tabs),
              activeIndex: nextIndex,
              clearOpeningPath: true,
            ),
          );
        } else {
          select(canonicalIndex);
          _setState(_state.copyWith(clearOpeningPath: true));
        }
        await _persist();
        return state.tabs[state.activeIndex];
      }

      final newTab = _availableTab(repository);
      final tabs = List<WorkspaceTab>.from(state.tabs);
      final index = targetIndex != null && _isValidIndex(targetIndex)
          ? targetIndex
          : tabs.length;
      if (index < tabs.length) {
        _disposeTab(tabs[index]);
        tabs[index] = newTab;
      } else {
        tabs.add(newTab);
      }
      _setState(
        _state.copyWith(
          tabs: List.unmodifiable(tabs),
          activeIndex: index,
          clearOpeningPath: true,
        ),
      );
      await recentStore?.add(repository.root);
      await _persist();
      return newTab;
    } on GitError catch (error) {
      if (_disposed) return null;
      if (targetIndex != null && _isValidIndex(targetIndex)) {
        final tabs = List<WorkspaceTab>.from(state.tabs);
        tabs[targetIndex] = WorkspaceTab(path: requestedPath, error: error);
        _setState(
          _state.copyWith(
            tabs: List.unmodifiable(tabs),
            activeIndex: targetIndex,
            clearOpeningPath: true,
          ),
        );
        await _persist();
      } else {
        final tabs = List<WorkspaceTab>.from(state.tabs)
          ..add(WorkspaceTab(path: requestedPath, error: error));
        _setState(
          _state.copyWith(
            tabs: List.unmodifiable(tabs),
            activeIndex: tabs.length - 1,
            clearOpeningPath: true,
          ),
        );
        await _persist();
      }
      return null;
    }
  }

  Future<void> retryUnavailable(int index, String replacementPath) async {
    if (!_isValidIndex(index)) return;
    await openPath(replacementPath, replaceIndex: index);
  }

  void select(int index) {
    if (!_isValidIndex(index) || state.activeIndex == index) return;
    _setState(_state.copyWith(activeIndex: index));
    _persist();
  }

  void selectNext() {
    if (state.tabs.isEmpty) return;
    select((state.activeIndex + 1) % state.tabs.length);
  }

  void selectPrevious() {
    if (state.tabs.isEmpty) return;
    select((state.activeIndex - 1 + state.tabs.length) % state.tabs.length);
  }

  Future<void> close(int index) async {
    if (!_isValidIndex(index)) return;
    _disposeTab(state.tabs[index]);
    final tabs = List<WorkspaceTab>.from(state.tabs)..removeAt(index);
    var activeIndex = state.activeIndex;
    if (tabs.isEmpty) {
      activeIndex = 0;
    } else if (activeIndex > index) {
      activeIndex--;
    } else if (activeIndex >= tabs.length) {
      activeIndex = tabs.length - 1;
    }
    _setState(
      _state.copyWith(tabs: List.unmodifiable(tabs), activeIndex: activeIndex),
    );
    await _persist();
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    if (!_isValidIndex(oldIndex)) return;
    if (newIndex < 0 || newIndex >= state.tabs.length) return;
    final activePath = state.activeTab?.path;
    final tabs = List<WorkspaceTab>.from(state.tabs);
    final tab = tabs.removeAt(oldIndex);
    tabs.insert(newIndex, tab);
    final activeIndex = activePath == null
        ? state.activeIndex
        : tabs.indexWhere((item) => item.path == activePath);
    _setState(
      _state.copyWith(
        tabs: List.unmodifiable(tabs),
        activeIndex: activeIndex == -1 ? 0 : activeIndex,
      ),
    );
    await _persist();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final tab in state.tabs) {
      _disposeTab(tab);
    }
    super.dispose();
  }

  WorkspaceTab _availableTab(RepositoryOpened repository) {
    return WorkspaceTab(
      path: repository.root,
      repository: repository,
      changesController: ChangesController(
        gateway: gateway,
        repositoryId: repository.repositoryId,
        pollInterval: changesPollInterval,
      ),
      historyController: HistoryController(
        gateway: gateway,
        repositoryId: repository.repositoryId,
      ),
    );
  }

  int? _findPath(String path) {
    for (var index = 0; index < state.tabs.length; index++) {
      if (state.tabs[index].path == path) return index;
    }
    return null;
  }

  int? _findCanonicalPath(String path) {
    for (var index = 0; index < state.tabs.length; index++) {
      if (state.tabs[index].repository?.root == path) return index;
    }
    return null;
  }

  bool _isValidIndex(int index) => index >= 0 && index < state.tabs.length;

  Future<void> _persist() {
    // Queue writes so a fast tab click cannot finish after a later reorder or
    // close and restore an older active path in SharedPreferences.
    _pendingPersistence = _pendingPersistence.then((_) async {
      if (_disposed) return;
      await store.save(
        paths: state.tabs.map((tab) => tab.path).toList(growable: false),
        activePath: state.activeTab?.path,
      );
    });
    return _pendingPersistence;
  }

  void _setState(WorkspaceState state) {
    if (_disposed) return;
    _state = state;
    notifyListeners();
  }

  void _disposeTab(WorkspaceTab tab) {
    tab.changesController?.dispose();
    tab.historyController?.dispose();
  }

  List<WorkspaceTab> _removeDuplicateCanonicalTabs(List<WorkspaceTab> tabs) {
    final seenRoots = <String>{};
    final uniqueTabs = <WorkspaceTab>[];
    for (final tab in tabs) {
      final root = tab.repository?.root;
      if (root != null && !seenRoots.add(root)) {
        _disposeTab(tab);
        continue;
      }
      if (tab.error?.diagnostic ==
          'duplicate canonical workspace root during restore') {
        continue;
      }
      uniqueTabs.add(tab);
    }
    return uniqueTabs;
  }
}

List<String> _uniquePaths(Iterable<String> paths) {
  final unique = <String>[];
  for (final path in paths) {
    final trimmed = path.trim();
    if (trimmed.isNotEmpty && !unique.contains(trimmed)) unique.add(trimmed);
  }
  return unique;
}

int _indexForPath(List<String> paths, String? path) {
  if (path == null) return 0;
  final index = paths.indexOf(path);
  return index == -1 ? 0 : index;
}
