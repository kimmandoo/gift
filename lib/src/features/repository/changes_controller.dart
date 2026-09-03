import 'dart:async';

import 'package:gift/src/backend/commit.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/discard.dart';
import 'package:gift/src/backend/diff.dart';
import 'package:gift/src/backend/error.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:gift/src/backend/status.dart';
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
    this.commitPreflight,
    this.commitPreflightError,
    this.discardPreview,
    this.discardError,
    this.isLoading = false,
    this.isRefreshing = false,
    this.isDiffLoading = false,
    this.isMutating = false,
    this.isCommitting = false,
    this.isCommitPreflighting = false,
    this.isDiscardPreparing = false,
    this.diffScope = GitDiffScope.workingTree,
    this.selectedDiffHunks = const <int>{},
    this.selectedDiffLines = const <int>{},
  });

  final GitStatusSnapshot? snapshot;
  final GitError? error;
  final String? selectedPath;
  final GitDiffSnapshot? diff;
  final GitError? diffError;
  final GitError? mutationError;
  final GitCommitResult? commitResult;
  final GitError? commitError;
  final GitCommitPreflight? commitPreflight;
  final GitError? commitPreflightError;
  final DiscardPreview? discardPreview;
  final GitError? discardError;
  final bool isLoading;
  final bool isRefreshing;
  final bool isDiffLoading;
  final bool isMutating;
  final bool isCommitting;
  final bool isCommitPreflighting;
  final bool isDiscardPreparing;
  final GitDiffScope diffScope;
  final Set<int> selectedDiffHunks;
  final Set<int> selectedDiffLines;

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
    GitCommitPreflight? commitPreflight,
    bool clearCommitPreflight = false,
    GitError? commitPreflightError,
    bool clearCommitPreflightError = false,
    DiscardPreview? discardPreview,
    bool clearDiscardPreview = false,
    GitError? discardError,
    bool clearDiscardError = false,
    bool? isLoading,
    bool? isRefreshing,
    bool? isDiffLoading,
    bool? isMutating,
    bool? isCommitting,
    bool? isCommitPreflighting,
    bool? isDiscardPreparing,
    GitDiffScope? diffScope,
    Set<int>? selectedDiffHunks,
    Set<int>? selectedDiffLines,
    bool clearDiffSelection = false,
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
      commitPreflight: clearCommitPreflight
          ? null
          : commitPreflight ?? this.commitPreflight,
      commitPreflightError: clearCommitPreflightError
          ? null
          : commitPreflightError ?? this.commitPreflightError,
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
      isCommitPreflighting: isCommitPreflighting ?? this.isCommitPreflighting,
      isDiscardPreparing: isDiscardPreparing ?? this.isDiscardPreparing,
      diffScope: diffScope ?? this.diffScope,
      selectedDiffHunks: clearDiffSelection
          ? const <int>{}
          : selectedDiffHunks ?? this.selectedDiffHunks,
      selectedDiffLines: clearDiffSelection
          ? const <int>{}
          : selectedDiffLines ?? this.selectedDiffLines,
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
  var _commitPreflightRequest = 0;
  var _discardPreviewRequest = 0;
  int? _lastDiffLineIndex;
  var _started = false;
  var _disposed = false;

  ChangesState get state => _state;

  /// Starts the first load and the timer that keeps the list current.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    _pollTimer = Timer.periodic(
      pollInterval,
      (_) => unawaited(_refresh(showProgress: false)),
    );
    unawaited(refresh());
  }

  /// Fetches status once and exposes progress for an explicit user refresh.
  Future<void> refresh() => _refresh(showProgress: true);

  Future<void> _refresh({required bool showProgress}) async {
    if (_requestInFlight || _mutationInFlight || _disposed) return;
    _requestInFlight = true;
    final firstLoad = _state.snapshot == null;
    final exposeProgress = firstLoad || showProgress;
    if (exposeProgress) {
      _setState(
        _state.copyWith(
          clearError: true,
          isLoading: firstLoad,
          isRefreshing: true,
        ),
      );
    }

    try {
      final snapshot = await gateway.getStatus(repositoryId);
      final selectedPath = _state.selectedPath;
      final previousSnapshot = _state.snapshot;
      final statusChanged =
          previousSnapshot == null ||
          previousSnapshot.contentHash != snapshot.contentHash;
      final selectionStillExists =
          selectedPath != null &&
          snapshot.changes.any((change) => change.path == selectedPath);
      final selectionChanged = selectedPath != null && !selectionStillExists;
      if (!statusChanged &&
          !selectionChanged &&
          !exposeProgress &&
          _state.error == null) {
        return;
      }
      if (statusChanged || selectedPath == null) _lastDiffLineIndex = null;
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
          clearDiffSelection: !selectionStillExists || statusChanged,
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
        clearDiffSelection: true,
      ),
    );
    _lastDiffLineIndex = null;
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
        clearDiffSelection: true,
        isDiffLoading: true,
      ),
    );
    _lastDiffLineIndex = null;
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

  bool get canStagePatch => _canApplyPatch(GitDiffScope.workingTree);

  bool get canUnstagePatch => _canApplyPatch(GitDiffScope.staged);

  /// Counts changed lines selected directly or through their hunk checkbox.
  /// Keeping this calculation here prevents the view from duplicating the
  /// selection rules when it describes the pending partial operation.
  int get selectedDiffChangeCount {
    final diff = _state.diff;
    if (diff == null) return 0;
    final indexes = <int>{
      ..._state.selectedDiffLines.where(
        (index) =>
            index >= 0 &&
            index < diff.lines.length &&
            _isChangedDiffLine(diff.lines[index]),
      ),
    };
    for (final hunkIndex in _state.selectedDiffHunks) {
      if (hunkIndex < 0 || hunkIndex >= diff.hunks.length) continue;
      for (final line in diff.hunks[hunkIndex].lines) {
        final index = diff.lines.indexOf(line);
        if (index >= 0 && _isChangedDiffLine(line)) indexes.add(index);
      }
    }
    return indexes.length;
  }

  bool _canApplyPatch(GitDiffScope scope) {
    final change = _selectedChange;
    return _state.diff?.scope == scope &&
        _state.diff != null &&
        _hasSelectedDiffChange &&
        change != null &&
        !change.isConflicted &&
        (scope == GitDiffScope.workingTree
            ? change.isUnstaged
            : change.isStaged);
  }

  bool get _hasSelectedDiffChange {
    final diff = _state.diff;
    if (diff == null) return false;
    if (_state.selectedDiffHunks.any(
      (index) => index >= 0 && index < diff.hunks.length,
    )) {
      return true;
    }
    return _state.selectedDiffLines.any(
      (index) =>
          index >= 0 &&
          index < diff.lines.length &&
          (diff.lines[index].kind == GitDiffLineKind.addition ||
              diff.lines[index].kind == GitDiffLineKind.deletion),
    );
  }

  bool isDiffHunkSelected(int hunkIndex) {
    final diff = _state.diff;
    if (diff == null || hunkIndex < 0 || hunkIndex >= diff.hunks.length) {
      return false;
    }
    if (_state.selectedDiffHunks.contains(hunkIndex)) return true;
    final changedLines = diff.hunks[hunkIndex].lines
        .map(diff.lines.indexOf)
        .where((index) => index >= 0)
        .where((index) => _isChangedDiffLine(diff.lines[index]))
        .toList();
    return changedLines.isNotEmpty &&
        changedLines.every(_state.selectedDiffLines.contains);
  }

  bool isDiffLineSelected(int lineIndex) {
    final diff = _state.diff;
    if (diff == null || lineIndex < 0 || lineIndex >= diff.lines.length) {
      return false;
    }
    final line = diff.lines[lineIndex];
    return line.hunkIndex != null &&
        (_state.selectedDiffHunks.contains(line.hunkIndex) ||
            _state.selectedDiffLines.contains(lineIndex));
  }

  void toggleDiffHunk(int hunkIndex, bool selected) {
    final diff = _state.diff;
    if (diff == null || hunkIndex < 0 || hunkIndex >= diff.hunks.length) {
      return;
    }
    final hunks = Set<int>.from(_state.selectedDiffHunks);
    final lines = Set<int>.from(_state.selectedDiffLines);
    if (selected) {
      hunks.add(hunkIndex);
    } else {
      hunks.remove(hunkIndex);
      for (final line in diff.hunks[hunkIndex].lines) {
        final lineIndex = diff.lines.indexOf(line);
        if (lineIndex >= 0) lines.remove(lineIndex);
      }
    }
    _setState(
      _state.copyWith(
        selectedDiffHunks: Set.unmodifiable(hunks),
        selectedDiffLines: Set.unmodifiable(lines),
      ),
    );
  }

  void toggleDiffLine(int lineIndex, bool selected, {bool extend = false}) {
    final diff = _state.diff;
    if (diff == null ||
        lineIndex < 0 ||
        lineIndex >= diff.lines.length ||
        !_isChangedDiffLine(diff.lines[lineIndex])) {
      return;
    }
    final lines = Set<int>.from(_state.selectedDiffLines);
    final hunks = Set<int>.from(_state.selectedDiffHunks);
    final hunkIndex = diff.lines[lineIndex].hunkIndex;
    if (!selected && hunkIndex != null && hunks.remove(hunkIndex)) {
      for (final line in diff.hunks[hunkIndex].lines) {
        final index = diff.lines.indexOf(line);
        if (index >= 0 && index != lineIndex && _isChangedDiffLine(line)) {
          lines.add(index);
        }
      }
    }
    final start = extend && _lastDiffLineIndex != null
        ? _lastDiffLineIndex!
        : lineIndex;
    final lower = start < lineIndex ? start : lineIndex;
    final upper = start < lineIndex ? lineIndex : start;
    for (var index = lower; index <= upper; index++) {
      if (!_isChangedDiffLine(diff.lines[index])) continue;
      if (selected) {
        lines.add(index);
      } else {
        lines.remove(index);
      }
    }
    _lastDiffLineIndex = lineIndex;
    _setState(
      _state.copyWith(
        selectedDiffHunks: Set.unmodifiable(hunks),
        selectedDiffLines: Set.unmodifiable(lines),
      ),
    );
  }

  Future<void> stageSelectedPatch() =>
      _applySelectedPatch(gateway.stagePatch, GitDiffScope.workingTree);

  Future<void> unstageSelectedPatch() =>
      _applySelectedPatch(gateway.unstagePatch, GitDiffScope.staged);

  Future<void> _applySelectedPatch(
    Future<GitStatusSnapshot> Function(RepositoryId, GitPatchSelection)
    operation,
    GitDiffScope scope,
  ) async {
    if (_disposed || _mutationInFlight || !_canApplyPatch(scope)) return;
    final diff = _state.diff!;
    final selection = GitPatchSelection(
      repositoryId: repositoryId,
      path: diff.path,
      scope: diff.scope,
      contentHash: diff.contentHash,
      hunkIndexes: _state.selectedDiffHunks,
      lineIndexes: _state.selectedDiffLines,
    );
    _mutationInFlight = true;
    _setState(_state.copyWith(clearMutationError: true, isMutating: true));
    try {
      final snapshot = await operation(repositoryId, selection);
      if (_disposed) return;
      final selected = snapshot.changes
          .where((candidate) => candidate.path == diff.path)
          .firstOrNull;
      _setState(
        _state.copyWith(
          snapshot: snapshot,
          selectedPath: selected?.path,
          clearSelectedPath: selected == null,
          clearDiff: true,
          clearDiffError: true,
          clearDiffSelection: true,
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

  bool get canCommit => _state.snapshot?.staged.isNotEmpty == true;

  /// Runs the non-mutating checks used by the guided commit options panel.
  Future<GitCommitPreflight?> preflightCommit({
    GitCommitOptions options = const GitCommitOptions(),
  }) async {
    if (_disposed) return null;
    final request = ++_commitPreflightRequest;
    _setState(
      _state.copyWith(
        clearCommitPreflight: true,
        clearCommitPreflightError: true,
        isCommitPreflighting: true,
      ),
    );
    try {
      final preflight = await gateway.preflightCommit(
        repositoryId,
        options: options,
      );
      if (request != _commitPreflightRequest || _disposed) return null;
      _setState(
        _state.copyWith(
          commitPreflight: preflight,
          clearCommitPreflightError: true,
          isCommitPreflighting: false,
        ),
      );
      return preflight;
    } on GitError catch (error) {
      if (request == _commitPreflightRequest && !_disposed) {
        _setState(
          _state.copyWith(
            commitPreflightError: error,
            isCommitPreflighting: false,
          ),
        );
      }
      return null;
    }
  }

  /// Commits every staged path and applies Git's post-commit status snapshot.
  Future<void> commit(
    String message, {
    GitCommitOptions options = const GitCommitOptions(),
  }) async {
    if (_disposed || _mutationInFlight || !canCommit) return;
    _mutationInFlight = true;
    _setState(
      _state.copyWith(
        clearMutationError: true,
        clearCommitResult: true,
        clearCommitError: true,
        clearCommitPreflight: true,
        clearCommitPreflightError: true,
        clearDiscardPreview: true,
        clearDiscardError: true,
        clearDiff: true,
        clearDiffError: true,
        clearDiffSelection: true,
        isMutating: true,
        isCommitting: true,
      ),
    );
    try {
      final result = await gateway.commit(
        repositoryId,
        message,
        options: options,
      );
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

  bool _isChangedDiffLine(GitDiffLine line) =>
      line.kind == GitDiffLineKind.addition ||
      line.kind == GitDiffLineKind.deletion;

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
