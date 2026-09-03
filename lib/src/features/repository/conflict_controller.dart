import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:gift/src/backend/conflict.dart';
import 'package:gift/src/backend/error.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:gift/src/backend/domain.dart';

class ConflictState {
  const ConflictState({
    this.snapshot,
    this.selectedIndex = 0,
    this.error,
    this.operationResult,
    this.isLoading = false,
    this.isMutating = false,
  });

  final GitConflictSnapshot? snapshot;
  final int selectedIndex;
  final GitError? error;
  final GitConflictOperationResult? operationResult;
  final bool isLoading;
  final bool isMutating;

  GitConflictEntry? get selectedConflict {
    final conflicts = snapshot?.conflicts;
    if (conflicts == null ||
        selectedIndex < 0 ||
        selectedIndex >= conflicts.length) {
      return null;
    }
    return conflicts[selectedIndex];
  }

  bool get canContinue => snapshot?.canContinue ?? false;
  bool get canAbort => snapshot?.operation != null;

  ConflictState copyWith({
    GitConflictSnapshot? snapshot,
    bool clearSnapshot = false,
    int? selectedIndex,
    GitError? error,
    bool clearError = false,
    GitConflictOperationResult? operationResult,
    bool clearOperationResult = false,
    bool? isLoading,
    bool? isMutating,
  }) {
    return ConflictState(
      snapshot: clearSnapshot ? null : snapshot ?? this.snapshot,
      selectedIndex: selectedIndex ?? this.selectedIndex,
      error: clearError ? null : error ?? this.error,
      operationResult: clearOperationResult
          ? null
          : operationResult ?? this.operationResult,
      isLoading: isLoading ?? this.isLoading,
      isMutating: isMutating ?? this.isMutating,
    );
  }
}

/// Owns one conflict workspace's selection and serializes its mutations.
class ConflictController extends ChangeNotifier {
  ConflictController({required this.gateway, required this.repositoryId});

  final GitGateway gateway;
  final RepositoryId repositoryId;

  ConflictState _state = const ConflictState();
  var _request = 0;
  var _mutationInFlight = false;
  var _started = false;
  var _disposed = false;

  ConflictState get state => _state;

  void start() {
    if (_started || _disposed) return;
    _started = true;
    unawaited(refresh());
  }

  Future<void> refresh() async {
    if (_disposed || _mutationInFlight) return;
    final request = ++_request;
    final firstLoad = _state.snapshot == null;
    _setState(_state.copyWith(clearError: true, isLoading: firstLoad));
    try {
      final snapshot = await gateway.getConflicts(repositoryId);
      if (_disposed || request != _request) return;
      final nextIndex = snapshot.conflicts.isEmpty
          ? 0
          : _state.selectedIndex.clamp(0, snapshot.conflicts.length - 1);
      _setState(
        _state.copyWith(
          snapshot: snapshot,
          selectedIndex: nextIndex,
          clearError: true,
          isLoading: false,
        ),
      );
    } on GitError catch (error) {
      if (_disposed || request != _request) return;
      _setState(_state.copyWith(error: error, isLoading: false));
    }
  }

  void select(int index) {
    final count = _state.snapshot?.conflicts.length ?? 0;
    if (_disposed || count == 0 || index < 0 || index >= count) return;
    _setState(
      _state.copyWith(
        selectedIndex: index,
        clearError: true,
        clearOperationResult: true,
      ),
    );
  }

  void selectNext() {
    final count = _state.snapshot?.conflicts.length ?? 0;
    if (count == 0) return;
    select((_state.selectedIndex + 1) % count);
  }

  void selectPrevious() {
    final count = _state.snapshot?.conflicts.length ?? 0;
    if (count == 0) return;
    select((_state.selectedIndex - 1 + count) % count);
  }

  bool get canAcceptOurs =>
      !_mutationInFlight && _state.selectedConflict?.ours != null;

  bool get canAcceptTheirs =>
      !_mutationInFlight && _state.selectedConflict?.theirs != null;

  bool get canEditResult {
    final result = _state.selectedConflict?.result?.content.state;
    return !_mutationInFlight &&
        result != GitConflictContentState.binary &&
        result != GitConflictContentState.tooLarge &&
        result != GitConflictContentState.unreadable;
  }

  Future<void> acceptOurs() => _resolve(
    (snapshot, conflict) => gateway.acceptConflictOurs(
      repositoryId,
      conflict.path,
      fingerprint: snapshot.fingerprint,
    ),
  );

  Future<void> acceptTheirs() => _resolve(
    (snapshot, conflict) => gateway.acceptConflictTheirs(
      repositoryId,
      conflict.path,
      fingerprint: snapshot.fingerprint,
    ),
  );

  Future<void> editResult(String content) => _resolve(
    (snapshot, conflict) => gateway.editConflictResult(
      repositoryId,
      conflict.path,
      content,
      fingerprint: snapshot.fingerprint,
    ),
  );

  Future<void> markResolved({bool deleteResult = false}) => _resolve(
    (snapshot, conflict) => gateway.markConflictResolved(
      repositoryId,
      conflict.path,
      fingerprint: snapshot.fingerprint,
      deleteResult: deleteResult,
    ),
  );

  Future<void> continueOperation() => _runOperation(
    (fingerprint) =>
        gateway.continueConflict(repositoryId, fingerprint: fingerprint),
  );

  Future<void> abortOperation() => _runOperation(
    (fingerprint) =>
        gateway.abortConflict(repositoryId, fingerprint: fingerprint),
  );

  Future<void> _resolve(
    Future<GitConflictResolutionResult> Function(
      GitConflictSnapshot,
      GitConflictEntry,
    )
    operation,
  ) async {
    if (_disposed || _mutationInFlight) return;
    final snapshot = _state.snapshot;
    final conflict = _state.selectedConflict;
    if (snapshot == null || conflict == null) return;
    _beginMutation();
    try {
      final result = await operation(snapshot, conflict);
      if (_disposed) return;
      final nextIndex = result.snapshot.conflicts.isEmpty
          ? 0
          : _state.selectedIndex.clamp(0, result.snapshot.conflicts.length - 1);
      _setState(
        _state.copyWith(
          snapshot: result.snapshot,
          selectedIndex: nextIndex,
          clearError: true,
          isMutating: false,
        ),
      );
    } on GitError catch (error) {
      if (!_disposed) {
        _setState(_state.copyWith(error: error, isMutating: false));
      }
    } finally {
      _mutationInFlight = false;
    }
  }

  Future<void> _runOperation(
    Future<GitConflictOperationResult> Function(String fingerprint) operation,
  ) async {
    if (_disposed || _mutationInFlight) return;
    final snapshot = _state.snapshot;
    if (snapshot == null || snapshot.operation == null) return;
    _beginMutation();
    try {
      final result = await operation(snapshot.fingerprint);
      if (_disposed) return;
      _setState(
        _state.copyWith(
          snapshot: result.snapshot,
          operationResult: result,
          clearError: true,
          isMutating: false,
        ),
      );
    } on GitError catch (error) {
      if (!_disposed) {
        _setState(_state.copyWith(error: error, isMutating: false));
      }
    } finally {
      _mutationInFlight = false;
    }
  }

  void _beginMutation() {
    _mutationInFlight = true;
    _setState(
      _state.copyWith(
        clearError: true,
        clearOperationResult: true,
        isMutating: true,
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _setState(ConflictState state) {
    if (_disposed) return;
    _state = state;
    notifyListeners();
  }
}
