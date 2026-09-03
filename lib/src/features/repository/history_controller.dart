import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:gift/src/backend/diff.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/error.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:gift/src/backend/history.dart';

class HistoryState {
  const HistoryState({
    this.page,
    this.error,
    this.selectedOid,
    this.selectedCommitData,
    this.commitFiles,
    this.commitFilesError,
    this.commitDiff,
    this.commitDiffError,
    this.selectedPath,
    this.filters = const GitHistoryFilters(),
    this.isLoading = false,
    this.isLoadingMore = false,
    this.isLoadingCommitFiles = false,
    this.isLoadingCommitDiff = false,
  });

  final GitHistoryPage? page;
  final GitError? error;
  final String? selectedOid;
  final GitCommit? selectedCommitData;
  final List<GitCommitFileChange>? commitFiles;
  final GitError? commitFilesError;
  final GitCommitDiff? commitDiff;
  final GitError? commitDiffError;
  final String? selectedPath;
  final GitHistoryFilters filters;
  final bool isLoading;
  final bool isLoadingMore;
  final bool isLoadingCommitFiles;
  final bool isLoadingCommitDiff;

  GitCommit? get selectedCommit {
    final selectedCommitData = this.selectedCommitData;
    if (selectedCommitData != null) return selectedCommitData;
    final selectedOid = this.selectedOid;
    final commits = page?.commits;
    if (selectedOid == null || commits == null) return null;
    for (final commit in commits) {
      if (commit.oid == selectedOid) return commit;
    }
    return null;
  }

  HistoryState copyWith({
    GitHistoryPage? page,
    bool clearPage = false,
    GitError? error,
    bool clearError = false,
    String? selectedOid,
    bool clearSelectedOid = false,
    GitCommit? selectedCommitData,
    bool clearSelectedCommitData = false,
    List<GitCommitFileChange>? commitFiles,
    bool clearCommitFiles = false,
    GitError? commitFilesError,
    bool clearCommitFilesError = false,
    GitCommitDiff? commitDiff,
    bool clearCommitDiff = false,
    GitError? commitDiffError,
    bool clearCommitDiffError = false,
    String? selectedPath,
    bool clearSelectedPath = false,
    GitHistoryFilters? filters,
    bool? isLoading,
    bool? isLoadingMore,
    bool? isLoadingCommitFiles,
    bool? isLoadingCommitDiff,
  }) {
    return HistoryState(
      page: clearPage ? null : page ?? this.page,
      error: clearError ? null : error ?? this.error,
      selectedOid: clearSelectedOid ? null : selectedOid ?? this.selectedOid,
      selectedCommitData: clearSelectedCommitData
          ? null
          : selectedCommitData ?? this.selectedCommitData,
      commitFiles: clearCommitFiles ? null : commitFiles ?? this.commitFiles,
      commitFilesError: clearCommitFilesError
          ? null
          : commitFilesError ?? this.commitFilesError,
      commitDiff: clearCommitDiff ? null : commitDiff ?? this.commitDiff,
      commitDiffError: clearCommitDiffError
          ? null
          : commitDiffError ?? this.commitDiffError,
      selectedPath: clearSelectedPath
          ? null
          : selectedPath ?? this.selectedPath,
      filters: filters ?? this.filters,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isLoadingCommitFiles: isLoadingCommitFiles ?? this.isLoadingCommitFiles,
      isLoadingCommitDiff: isLoadingCommitDiff ?? this.isLoadingCommitDiff,
    );
  }
}

/// Loads snapshot-bound history pages and lazily inspects selected commits.
class HistoryController extends ChangeNotifier {
  HistoryController({
    required this.gateway,
    required this.repositoryId,
    this.pageSize = 30,
  });

  final GitGateway gateway;
  final RepositoryId repositoryId;
  final int pageSize;
  HistoryState _state = const HistoryState();
  var _historyRequestId = 0;
  var _detailsRequestId = 0;
  var _diffRequestId = 0;
  var _disposed = false;

  HistoryState get state => _state;

  void start() {
    if (_disposed || _state.isLoading || _state.page != null) return;
    unawaited(refresh());
  }

  Future<void> refresh({GitHistoryFilters? filters}) async {
    final requestId = ++_historyRequestId;
    final nextFilters = filters ?? _state.filters;
    _detailsRequestId++;
    _diffRequestId++;
    _setState(
      _state.copyWith(
        clearPage: true,
        clearError: true,
        clearSelectedOid: true,
        clearSelectedCommitData: true,
        clearCommitFiles: true,
        clearCommitFilesError: true,
        clearCommitDiff: true,
        clearCommitDiffError: true,
        clearSelectedPath: true,
        filters: nextFilters,
        isLoading: true,
        isLoadingMore: false,
        isLoadingCommitFiles: false,
        isLoadingCommitDiff: false,
      ),
    );
    try {
      final page = await gateway.getHistory(
        repositoryId,
        query: GitHistoryQuery(limit: pageSize, filters: nextFilters),
      );
      if (requestId != _historyRequestId) return;
      _setState(
        _state.copyWith(page: page, clearError: true, isLoading: false),
      );
    } on GitError catch (error) {
      if (requestId != _historyRequestId) return;
      _setState(_state.copyWith(error: error, isLoading: false));
    }
  }

  Future<void> loadMore() async {
    final page = _state.page;
    if (_disposed ||
        page == null ||
        !page.hasMore ||
        _state.isLoadingMore ||
        page.nextCursor == null) {
      return;
    }
    final requestId = ++_historyRequestId;
    _setState(_state.copyWith(clearError: true, isLoadingMore: true));
    try {
      final nextPage = await gateway.getHistory(
        repositoryId,
        query: GitHistoryQuery(
          limit: page.limit,
          filters: _state.filters,
          cursor: page.nextCursor,
        ),
      );
      if (requestId != _historyRequestId) return;
      final combinedCommits = [...page.commits, ...nextPage.commits];
      final collapseToSingleLane =
          page.collapseToSingleLane &&
          nextPage.collapseToSingleLane &&
          combinedCommits.every((commit) => commit.parents.length <= 1);
      _setState(
        _state.copyWith(
          page: GitHistoryPage(
            repositoryId: page.repositoryId,
            commits: collapseToSingleLane
                ? assignSingleGraphLane(combinedCommits)
                : assignGraphLanes(combinedCommits),
            offset: page.offset,
            limit: page.limit,
            hasMore: nextPage.hasMore,
            nextCursor: nextPage.nextCursor,
            collapseToSingleLane: collapseToSingleLane,
          ),
          clearError: true,
          isLoadingMore: false,
        ),
      );
    } on GitError catch (error) {
      if (requestId != _historyRequestId) return;
      _setState(_state.copyWith(error: error, isLoadingMore: false));
    }
  }

  Future<void> applyFilters(GitHistoryFilters filters) =>
      refresh(filters: filters);

  void selectCommit(GitCommit commit) {
    if (_disposed) return;
    final requestId = ++_detailsRequestId;
    _diffRequestId++;
    _setState(
      _state.copyWith(
        selectedOid: commit.oid,
        selectedCommitData: commit,
        clearCommitFiles: true,
        clearCommitFilesError: true,
        clearCommitDiff: true,
        clearCommitDiffError: true,
        clearSelectedPath: true,
        isLoadingCommitFiles: true,
        isLoadingCommitDiff: false,
        clearError: true,
      ),
    );
    unawaited(_loadCommitFiles(commit, requestId));
  }

  void selectParent(String commitOid) {
    if (_disposed) return;
    final existing = _state.page?.commits.where(
      (commit) => commit.oid == commitOid,
    );
    if (existing != null && existing.isNotEmpty) {
      selectCommit(existing.first);
      return;
    }
    final requestId = ++_detailsRequestId;
    _diffRequestId++;
    _setState(
      _state.copyWith(
        selectedOid: commitOid,
        clearSelectedCommitData: true,
        clearCommitFiles: true,
        clearCommitFilesError: true,
        clearCommitDiff: true,
        clearCommitDiffError: true,
        clearSelectedPath: true,
        isLoadingCommitFiles: true,
        isLoadingCommitDiff: false,
      ),
    );
    unawaited(_loadParent(commitOid, requestId));
  }

  void selectFile(GitCommitFileChange file) {
    final commit = _state.selectedCommit;
    if (_disposed || commit == null) return;
    final requestId = ++_diffRequestId;
    _setState(
      _state.copyWith(
        selectedPath: file.path,
        clearCommitDiff: true,
        clearCommitDiffError: true,
        isLoadingCommitDiff: true,
      ),
    );
    unawaited(_loadCommitDiff(commit, file, requestId));
  }

  void selectNext() => _moveSelection(1);

  void selectPrevious() => _moveSelection(-1);

  void _moveSelection(int delta) {
    final commits = _state.page?.commits;
    if (_disposed || commits == null || commits.isEmpty) return;
    final current = _state.selectedOid == null
        ? -1
        : commits.indexWhere((commit) => commit.oid == _state.selectedOid);
    final next = current < 0
        ? (delta > 0 ? 0 : commits.length - 1)
        : (current + delta).clamp(0, commits.length - 1);
    selectCommit(commits[next]);
  }

  Future<void> _loadCommitFiles(GitCommit commit, int requestId) async {
    try {
      final files = await gateway.getCommitFiles(repositoryId, commit.oid);
      if (!_isCurrentDetails(requestId, commit.oid)) return;
      _setState(
        _state.copyWith(
          commitFiles: files,
          clearCommitFilesError: true,
          isLoadingCommitFiles: false,
        ),
      );
    } on GitError catch (error) {
      if (!_isCurrentDetails(requestId, commit.oid)) return;
      _setState(
        _state.copyWith(commitFilesError: error, isLoadingCommitFiles: false),
      );
    }
  }

  Future<void> _loadParent(String commitOid, int requestId) async {
    try {
      final commit = await gateway.getCommit(repositoryId, commitOid);
      if (!_isCurrentDetails(requestId, commitOid)) return;
      _setState(_state.copyWith(selectedCommitData: commit));
      await _loadCommitFiles(commit, requestId);
    } on GitError catch (error) {
      if (!_isCurrentDetails(requestId, commitOid)) return;
      _setState(
        _state.copyWith(commitFilesError: error, isLoadingCommitFiles: false),
      );
    }
  }

  Future<void> _loadCommitDiff(
    GitCommit commit,
    GitCommitFileChange file,
    int requestId,
  ) async {
    try {
      final diff = await gateway.getCommitDiff(
        repositoryId,
        commit.oid,
        file.path,
        originalPath: file.oldPath,
      );
      if (!_isCurrentDiff(requestId, commit.oid, file.path)) return;
      _setState(
        _state.copyWith(
          commitDiff: diff,
          clearCommitDiffError: true,
          isLoadingCommitDiff: false,
        ),
      );
    } on GitError catch (error) {
      if (!_isCurrentDiff(requestId, commit.oid, file.path)) return;
      _setState(
        _state.copyWith(commitDiffError: error, isLoadingCommitDiff: false),
      );
    }
  }

  bool _isCurrentDetails(int requestId, String commitOid) =>
      !_disposed &&
      requestId == _detailsRequestId &&
      _state.selectedOid == commitOid;

  bool _isCurrentDiff(int requestId, String commitOid, String path) =>
      !_disposed &&
      requestId == _diffRequestId &&
      _state.selectedOid == commitOid &&
      _state.selectedPath == path;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _setState(HistoryState state) {
    if (_disposed) return;
    _state = state;
    notifyListeners();
  }
}
