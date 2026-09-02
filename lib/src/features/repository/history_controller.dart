import 'dart:async';

import 'package:gitshiba/src/backend/domain.dart';
import 'package:gitshiba/src/backend/error.dart';
import 'package:gitshiba/src/backend/git_gateway.dart';
import 'package:gitshiba/src/backend/history.dart';
import 'package:flutter/foundation.dart';

class HistoryState {
  const HistoryState({
    this.page,
    this.error,
    this.selectedOid,
    this.isLoading = false,
    this.isLoadingMore = false,
  });

  final GitHistoryPage? page;
  final GitError? error;
  final String? selectedOid;
  final bool isLoading;
  final bool isLoadingMore;

  GitCommit? get selectedCommit {
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
    bool? isLoading,
    bool? isLoadingMore,
  }) {
    return HistoryState(
      page: clearPage ? null : page ?? this.page,
      error: clearError ? null : error ?? this.error,
      selectedOid: clearSelectedOid ? null : selectedOid ?? this.selectedOid,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

/// Loads bounded history pages and keeps the selected commit visible.
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
  var _requestInFlight = false;
  var _disposed = false;

  HistoryState get state => _state;

  void start() {
    if (_disposed || _state.isLoading || _state.page != null) return;
    unawaited(refresh());
  }

  Future<void> refresh() async {
    if (_disposed || _requestInFlight) return;
    _requestInFlight = true;
    _setState(
      _state.copyWith(clearError: true, isLoading: true, isLoadingMore: false),
    );
    try {
      final page = await gateway.getHistory(
        repositoryId,
        limit: pageSize,
        offset: 0,
      );
      _setState(
        _state.copyWith(
          page: page,
          clearError: true,
          clearSelectedOid: true,
          isLoading: false,
        ),
      );
    } on GitError catch (error) {
      _setState(_state.copyWith(error: error, isLoading: false));
    } finally {
      _requestInFlight = false;
    }
  }

  Future<void> loadMore() async {
    final page = _state.page;
    if (_disposed ||
        _requestInFlight ||
        page == null ||
        !page.hasMore ||
        _state.isLoadingMore) {
      return;
    }
    _requestInFlight = true;
    _setState(_state.copyWith(clearError: true, isLoadingMore: true));
    try {
      final nextPage = await gateway.getHistory(
        repositoryId,
        limit: page.limit,
        offset: page.offset + page.commits.length,
      );
      _setState(
        _state.copyWith(
          page: GitHistoryPage(
            repositoryId: page.repositoryId,
            commits: assignGraphLanes([...page.commits, ...nextPage.commits]),
            offset: page.offset,
            limit: page.limit,
            hasMore: nextPage.hasMore,
          ),
          clearError: true,
          isLoadingMore: false,
        ),
      );
    } on GitError catch (error) {
      _setState(_state.copyWith(error: error, isLoadingMore: false));
    } finally {
      _requestInFlight = false;
    }
  }

  void selectCommit(GitCommit commit) {
    if (_disposed) return;
    _setState(_state.copyWith(selectedOid: commit.oid, clearError: true));
  }

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
