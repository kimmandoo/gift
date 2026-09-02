import 'dart:async';

import 'package:gitshiba/src/backend/commit.dart';
import 'package:gitshiba/src/backend/domain.dart';
import 'package:gitshiba/src/backend/discard.dart';
import 'package:gitshiba/src/backend/diff.dart';
import 'package:gitshiba/src/backend/error.dart';
import 'package:gitshiba/src/backend/git_gateway.dart';
import 'package:gitshiba/src/backend/status.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Stable inputs used by the Riverpod controller family.
class ChangesControllerArgs {
  const ChangesControllerArgs({
    required this.gateway,
    required this.repositoryId,
  });

  final GitGateway gateway;
  final RepositoryId repositoryId;

  @override
  int get hashCode => Object.hash(gateway, repositoryId);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChangesControllerArgs &&
          identical(other.gateway, gateway) &&
          other.repositoryId == repositoryId;
}

/// The visible state for the Changes screen.
class ChangesState {
  const ChangesState({
    this.snapshot,
    this.error,
    this.selectedPath,
    this.diff,
    this.diffError,
    this.mutationError,
    this.commitResult,
    this.commitError,
    this.discardPreview,
    this.discardError,
    this.isLoading = false,
    this.isRefreshing = false,
    this.isDiffLoading = false,
    this.isMutating = false,
    this.isCommitting = false,
    this.isDiscardPreparing = false,
    this.diffScope = GitDiffScope.workingTree,
  });

  final GitStatusSnapshot? snapshot;
  final GitError? error;
  final String? selectedPath;
  final GitDiffSnapshot? diff;
  final GitError? diffError;
  final GitError? mutationError;
  final GitCommitResult? commitResult;
  final GitError? commitError;
  final DiscardPreview? discardPreview;
  final GitError? discardError;
  final bool isLoading;
  final bool isRefreshing;
  final bool isDiffLoading;
  final bool isMutating;
  final bool isCommitting;
  final bool isDiscardPreparing;
  final GitDiffScope diffScope;

  ChangesState copyWith({
    GitStatusSnapshot? snapshot,
    bool clearSnapshot = false,
    GitError? error,
    bool clearError = false,
    String? selectedPath,
    bool clearSelectedPath = false,
    GitDiffSnapshot? diff,
    bool clearDiff = false,
    GitError? diffError,
    bool clearDiffError = false,
    GitError? mutationError,
    bool clearMutationError = false,
    GitCommitResult? commitResult,
    bool clearCommitResult = false,
    GitError? commitError,
    bool clearCommitError = false,
    DiscardPreview? discardPreview,
    bool clearDiscardPreview = false,
    GitError? discardError,
    bool clearDiscardError = false,
    bool? isLoading,
    bool? isRefreshing,
    bool? isDiffLoading,
    bool? isMutating,
    bool? isCommitting,
    bool? isDiscardPreparing,
    GitDiffScope? diffScope,
  }) {
    return ChangesState(
      snapshot: clearSnapshot ? null : snapshot ?? this.snapshot,
      error: clearError ? null : error ?? this.error,
      selectedPath: clearSelectedPath
          ? null
          : selectedPath ?? this.selectedPath,
      diff: clearDiff ? null : diff ?? this.diff,
      diffError: clearDiffError ? null : diffError ?? this.diffError,
      mutationError: clearMutationError
          ? null
          : mutationError ?? this.mutationError,
      commitResult: clearCommitResult
          ? null
          : commitResult ?? this.commitResult,
      commitError: clearCommitError ? null : commitError ?? this.commitError,
      discardPreview: clearDiscardPreview
          ? null
          : discardPreview ?? this.discardPreview,
      discardError: clearDiscardError
          ? null
          : discardError ?? this.discardError,
      isLoading: isLoading ?? this.isLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      isDiffLoading: isDiffLoading ?? this.isDiffLoading,
      isMutating: isMutating ?? this.isMutating,
      isCommitting: isCommitting ?? this.isCommitting,
      isDiscardPreparing: isDiscardPreparing ?? this.isDiscardPreparing,
      diffScope: diffScope ?? this.diffScope,
    );
  }
}

/// Loads one repository status and refreshes it while the screen is visible.
class ChangesController extends ChangeNotifier {
  ChangesController({
    required this.gateway,
    required this.repositoryId,
    this.pollInterval = const Duration(seconds: 5),
  });

  final GitGateway gateway;
  final RepositoryId repositoryId;
  final Duration pollInterval;

  ChangesState _state = const ChangesState();
  Timer? _pollTimer;
  var _requestInFlight = false;
  var _mutationInFlight = false;
  var _diffRequest = 0;
  var _discardPreviewRequest = 0;
  var _started = false;
  var _disposed = false;

  ChangesState get state => _state;

  /// Starts the first load and the timer that keeps the list current.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    _pollTimer = Timer.periodic(pollInterval, (_) => refresh());
    unawaited(refresh());
  }

  /// Fetches status once. A second request is ignored while Git is running.
  Future<void> refresh() async {
    if (_requestInFlight || _mutationInFlight || _disposed) return;
    _requestInFlight = true;
    final firstLoad = _state.snapshot == null;
    _setState(
      _state.copyWith(
        clearError: true,
        isLoading: firstLoad,
        isRefreshing: true,
      ),
    );

    try {
      final snapshot = await gateway.getStatus(repositoryId);
      final selectedPath = _state.selectedPath;
      final selectionStillExists =
          selectedPath != null &&
          snapshot.changes.any((change) => change.path == selectedPath);
      if (!selectionStillExists) _diffRequest++;
      if (!selectionStillExists) _discardPreviewRequest++;
      _setState(
        _state.copyWith(
          snapshot: snapshot,
          clearError: true,
          selectedPath: selectionStillExists ? selectedPath : null,
          clearSelectedPath: !selectionStillExists,
          clearDiff: !selectionStillExists,
          clearDiffError: !selectionStillExists,
          clearMutationError: !selectionStillExists,
          clearDiscardPreview: !selectionStillExists,
          clearDiscardError: !selectionStillExists,
          isDiscardPreparing: selectionStillExists
              ? _state.isDiscardPreparing
              : false,
          isDiffLoading: selectionStillExists ? _state.isDiffLoading : false,
          isLoading: false,
          isRefreshing: false,
        ),
      );
    } on GitError catch (error) {
      _setState(
        _state.copyWith(error: error, isLoading: false, isRefreshing: false),
      );
    } finally {
      _requestInFlight = false;
    }
  }

  void selectPath(String path) {
    if (_disposed) return;
    _diffRequest++;
    _setState(
      _state.copyWith(
        selectedPath: path,
        clearDiff: true,
        clearDiffError: true,
        clearMutationError: true,
        clearCommitError: true,
        clearDiscardPreview: true,
        clearDiscardError: true,
        isDiscardPreparing: false,
        isDiffLoading: false,
      ),
    );
  }

  /// Selects a status row and lazily loads only that file's diff.
  Future<void> selectChange(GitChange change) async {
    selectPath(change.path);
    final scope = change.isStaged && !change.isUnstaged
        ? GitDiffScope.staged
        : GitDiffScope.workingTree;
    await loadDiff(
      change.path,
      originalPath: change.originalPath,
      scope: scope,
    );
  }

  /// Loads the selected file in the requested scope.
  Future<void> loadDiff(
    String path, {
    String? originalPath,
    GitDiffScope scope = GitDiffScope.workingTree,
  }) async {
    if (_disposed) return;
    final request = ++_diffRequest;
    _setState(
      _state.copyWith(
        diffScope: scope,
        clearDiff: true,
        clearDiffError: true,
        isDiffLoading: true,
      ),
    );
    try {
      final diff = await gateway.getDiff(
        repositoryId,
        path,
        scope: scope,
        originalPath: originalPath,
      );
      if (request != _diffRequest || _disposed) return;
      _setState(
        _state.copyWith(diff: diff, clearDiffError: true, isDiffLoading: false),
      );
    } on GitError catch (error) {
      if (request != _diffRequest || _disposed) return;
      _setState(_state.copyWith(diffError: error, isDiffLoading: false));
    }
  }

  bool get canStageSelected {
    final change = _selectedChange;
    return change != null &&
        !change.isConflicted &&
        (change.isUntracked || change.isUnstaged);
  }

  bool get canUnstageSelected {
    final change = _selectedChange;
    return change != null &&
        !change.isConflicted &&
        change.isStaged &&
        !change.isUntracked;
  }

  Future<void> stageSelected() => _mutateSelected(gateway.stage);

  Future<void> unstageSelected() => _mutateSelected(gateway.unstage);

  bool get canCommit => _state.snapshot?.staged.isNotEmpty == true;

  /// Commits every staged path and applies Git's post-commit status snapshot.
  Future<void> commit(String message) async {
    if (_disposed || _mutationInFlight || !canCommit) return;
    _mutationInFlight = true;
    _setState(
      _state.copyWith(
        clearMutationError: true,
        clearCommitResult: true,
        clearCommitError: true,
        clearDiscardPreview: true,
        clearDiscardError: true,
        clearDiff: true,
        clearDiffError: true,
        isMutating: true,
        isCommitting: true,
      ),
    );
    try {
      final result = await gateway.commit(repositoryId, message);
      if (_disposed) return;
      final selectedPath = _state.selectedPath;
      final selected = selectedPath == null
          ? null
          : result.status.changes
                .where((candidate) => candidate.path == selectedPath)
                .firstOrNull;
      _setState(
        _state.copyWith(
          snapshot: result.status,
          commitResult: result,
          clearCommitError: true,
          selectedPath: selected?.path,
          clearSelectedPath: selected == null,
          clearDiff: true,
          clearDiffError: true,
          isMutating: false,
          isCommitting: false,
        ),
      );
      if (selected != null) {
        await loadDiff(
          selected.path,
          originalPath: selected.originalPath,
          scope: _defaultDiffScope(selected),
        );
      }
    } on GitError catch (error) {
      if (!_disposed) {
        _setState(
          _state.copyWith(
            commitError: error,
            isMutating: false,
            isCommitting: false,
          ),
        );
      }
    } finally {
      _mutationInFlight = false;
    }
  }

  bool get canDiscardSelected {
    final change = _selectedChange;
    return change != null &&
        !change.isConflicted &&
        !change.isUntracked &&
        change.isUnstaged;
  }

  /// Creates a short-lived authorization before showing the destructive
  /// confirmation dialog.
  Future<DiscardPreview?> prepareDiscard() async {
    if (_disposed ||
        _mutationInFlight ||
        _state.isDiscardPreparing ||
        !canDiscardSelected) {
      return null;
    }
    final change = _selectedChange!;
    final request = ++_discardPreviewRequest;
    _setState(
      _state.copyWith(
        clearDiscardPreview: true,
        clearDiscardError: true,
        isDiscardPreparing: true,
      ),
    );
    try {
      final preview = await gateway.createDiscardPreview(
        repositoryId,
        change.path,
      );
      if (request != _discardPreviewRequest || _disposed) return null;
      _setState(
        _state.copyWith(
          discardPreview: preview,
          clearDiscardError: true,
          isDiscardPreparing: false,
        ),
      );
      return preview;
    } on GitError catch (error) {
      if (request == _discardPreviewRequest && !_disposed) {
        _setState(
          _state.copyWith(discardError: error, isDiscardPreparing: false),
        );
      }
      return null;
    }
  }

  void cancelDiscardPreview() {
    if (_disposed) return;
    final preview = _state.discardPreview;
    _discardPreviewRequest++;
    _setState(
      _state.copyWith(
        clearDiscardPreview: true,
        clearDiscardError: true,
        isDiscardPreparing: false,
      ),
    );
    if (preview != null) {
      if (gateway case final DiscardPreviewCancellationGateway cancellable) {
        unawaited(cancellable.cancelDiscardPreview(preview));
      }
    }
  }

  Future<void> confirmDiscard(DiscardPreview preview) async {
    if (_disposed || _mutationInFlight || _state.selectedPath != preview.path) {
      return;
    }
    _mutationInFlight = true;
    _setState(
      _state.copyWith(
        clearDiscardPreview: true,
        clearDiscardError: true,
        clearCommitResult: true,
        clearCommitError: true,
        isDiscardPreparing: false,
        isMutating: true,
        clearDiff: true,
        clearDiffError: true,
      ),
    );
    try {
      final snapshot = await gateway.discard(repositoryId, preview);
      if (_disposed) return;
      final selected = snapshot.changes
          .where((candidate) => candidate.path == preview.path)
          .firstOrNull;
      _setState(
        _state.copyWith(
          snapshot: snapshot,
          selectedPath: selected == null ? null : preview.path,
          clearSelectedPath: selected == null,
          clearDiscardPreview: true,
          clearDiscardError: true,
          clearDiff: true,
          clearDiffError: true,
          isMutating: false,
        ),
      );
      if (selected != null) {
        await loadDiff(
          selected.path,
          originalPath: selected.originalPath,
          scope: _defaultDiffScope(selected),
        );
      }
    } on GitError catch (error) {
      if (!_disposed) {
        _setState(_state.copyWith(discardError: error, isMutating: false));
      }
    } finally {
      _mutationInFlight = false;
    }
  }

  Future<void> _mutateSelected(
    Future<GitStatusSnapshot> Function(RepositoryId, String) operation,
  ) async {
    if (_disposed || _mutationInFlight) return;
    final change = _selectedChange;
    if (change == null) return;
    _mutationInFlight = true;
    _setState(
      _state.copyWith(
        clearMutationError: true,
        clearCommitResult: true,
        clearCommitError: true,
        clearDiscardPreview: true,
        clearDiscardError: true,
        clearDiff: true,
        clearDiffError: true,
        isMutating: true,
      ),
    );
    try {
      final snapshot = await operation(repositoryId, change.path);
      if (_disposed) return;
      final selected = snapshot.changes
          .where((candidate) => candidate.path == change.path)
          .firstOrNull;
      _setState(
        _state.copyWith(
          snapshot: snapshot,
          selectedPath: selected == null ? null : change.path,
          clearSelectedPath: selected == null,
          clearDiff: true,
          clearDiffError: true,
          clearMutationError: true,
          isMutating: false,
        ),
      );
      if (selected != null) {
        await loadDiff(
          selected.path,
          originalPath: selected.originalPath,
          scope: _defaultDiffScope(selected),
        );
      }
    } on GitError catch (error) {
      if (!_disposed) {
        _setState(_state.copyWith(mutationError: error, isMutating: false));
      }
    } finally {
      _mutationInFlight = false;
    }
  }

  GitChange? get _selectedChange {
    final path = _state.selectedPath;
    final snapshot = _state.snapshot;
    if (path == null || snapshot == null) return null;
    for (final change in snapshot.changes) {
      if (change.path == path) return change;
    }
    return null;
  }

  GitDiffScope _defaultDiffScope(GitChange change) {
    return change.isStaged && !change.isUnstaged
        ? GitDiffScope.staged
        : GitDiffScope.workingTree;
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    super.dispose();
  }

  void _setState(ChangesState state) {
    if (_disposed) return;
    _state = state;
    notifyListeners();
  }
}

/// The screen watches one controller for each opened repository.
final changesControllerProvider = ChangeNotifierProvider.autoDispose
    .family<ChangesController, ChangesControllerArgs>((ref, args) {
      return ChangesController(
        gateway: args.gateway,
        repositoryId: args.repositoryId,
      );
    });
