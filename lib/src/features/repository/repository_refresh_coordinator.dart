import 'dart:async';
import 'dart:io';

/// Coordinates filesystem-triggered refreshes with a slow fallback refresh.
///
/// The coordinator owns every timer and stream subscription it creates. A
/// burst of filesystem events produces one callback, and a callback already in
/// progress is followed by at most one queued callback.
class RepositoryRefreshCoordinator {
  RepositoryRefreshCoordinator({
    required this.onRefresh,
    this.root,
    this.events,
    this.debounce = const Duration(milliseconds: 180),
    this.fallbackInterval = const Duration(seconds: 30),
  }) : assert(debounce >= Duration.zero),
       assert(fallbackInterval > Duration.zero);

  final FutureOr<void> Function() onRefresh;
  final String? root;
  final Stream<FileSystemEvent>? events;
  final Duration debounce;
  final Duration fallbackInterval;

  StreamSubscription<FileSystemEvent>? _subscription;
  Timer? _debounceTimer;
  Timer? _fallbackTimer;
  bool _started = false;
  bool _disposed = false;
  bool _refreshInFlight = false;
  bool _refreshPending = false;

  bool get isStarted => _started;
  bool get isDisposed => _disposed;
  bool get isWatching => _subscription != null;

  /// Starts watching once. Missing or inaccessible roots degrade to fallback.
  void start() {
    if (_started || _disposed) {
      return;
    }
    _started = true;
    _fallbackTimer = Timer.periodic(
      fallbackInterval,
      (_) => unawaited(_refresh()),
    );

    final stream = events ?? _watchRoot();
    if (stream == null) {
      return;
    }
    _subscription = stream.listen(
      (_) => _scheduleRefresh(),
      onError: (_, _) {
        // Filesystem watchers can fail when a repository is moved or its
        // permissions change. The fallback timer remains authoritative.
      },
      cancelOnError: false,
    );
  }

  void _scheduleRefresh() {
    if (_disposed) {
      return;
    }
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () => unawaited(_refresh()));
  }

  Future<void> _refresh() async {
    if (_disposed) {
      return;
    }
    if (_refreshInFlight) {
      _refreshPending = true;
      return;
    }
    _refreshInFlight = true;
    try {
      await onRefresh();
    } finally {
      _refreshInFlight = false;
      if (_refreshPending && !_disposed) {
        _refreshPending = false;
        _scheduleRefresh();
      }
    }
  }

  Stream<FileSystemEvent>? _watchRoot() {
    final path = root;
    if (path == null || !Directory(path).existsSync()) {
      return null;
    }
    try {
      return Directory(path)
          .watch(events: FileSystemEvent.all, recursive: true);
    } on FileSystemException {
      return null;
    }
  }

  /// Stops all timers and listeners. Safe to call repeatedly.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _debounceTimer?.cancel();
    _fallbackTimer?.cancel();
    _debounceTimer = null;
    _fallbackTimer = null;
    _refreshPending = false;
    await _subscription?.cancel();
    _subscription = null;
  }
}
