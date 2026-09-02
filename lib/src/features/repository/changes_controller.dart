import 'dart:async';

import 'package:branchline/src/backend/domain.dart';
import 'package:branchline/src/backend/error.dart';
import 'package:branchline/src/backend/git_gateway.dart';
import 'package:branchline/src/backend/status.dart';
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
    this.isLoading = false,
    this.isRefreshing = false,
  });

  final GitStatusSnapshot? snapshot;
  final GitError? error;
  final String? selectedPath;
  final bool isLoading;
  final bool isRefreshing;

  ChangesState copyWith({
    GitStatusSnapshot? snapshot,
    bool clearSnapshot = false,
    GitError? error,
    bool clearError = false,
    String? selectedPath,
    bool clearSelectedPath = false,
    bool? isLoading,
    bool? isRefreshing,
  }) {
    return ChangesState(
      snapshot: clearSnapshot ? null : snapshot ?? this.snapshot,
      error: clearError ? null : error ?? this.error,
      selectedPath: clearSelectedPath
          ? null
          : selectedPath ?? this.selectedPath,
      isLoading: isLoading ?? this.isLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
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
    if (_requestInFlight || _disposed) return;
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
      _setState(
        _state.copyWith(
          snapshot: snapshot,
          clearError: true,
          selectedPath: selectionStillExists ? selectedPath : null,
          clearSelectedPath: !selectionStillExists,
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
    _setState(_state.copyWith(selectedPath: path));
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
