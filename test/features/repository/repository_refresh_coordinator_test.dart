import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gift/src/features/repository/repository_refresh_coordinator.dart';

void main() {
  test('coalesces metadata bursts and stops after disposal', () async {
    final events = StreamController<FileSystemEvent>();
    addTearDown(events.close);
    var refreshes = 0;
    final coordinator = RepositoryRefreshCoordinator(
      events: events.stream,
      debounce: const Duration(milliseconds: 5),
      fallbackInterval: const Duration(hours: 1),
      onRefresh: () async {
        refreshes++;
      },
    );
    addTearDown(coordinator.dispose);

    coordinator.start();
    events
      ..add(FileSystemModifyEvent('/repo/.git/index', false, true))
      ..add(FileSystemModifyEvent('/repo/.git/HEAD', false, true))
      ..add(FileSystemModifyEvent('/repo/lib/app.dart', false, true));
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(refreshes, 1);
    await coordinator.dispose();
    events.add(
      FileSystemModifyEvent('/repo/ignored-after-dispose', false, true),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(refreshes, 1);
  });

  test('reports watcher failure for fallback recovery', () async {
    final events = StreamController<FileSystemEvent>.broadcast();
    addTearDown(events.close);
    final watchingStates = <bool>[];
    final coordinator = RepositoryRefreshCoordinator(
      events: events.stream,
      fallbackInterval: const Duration(hours: 1),
      onWatchingChanged: watchingStates.add,
      onRefresh: () {},
    );
    addTearDown(coordinator.dispose);

    coordinator.start();
    expect(coordinator.isWatching, isTrue);
    events.addError(StateError('watcher failed'));
    await Future<void>.delayed(Duration.zero);

    expect(coordinator.isWatching, isFalse);
    expect(watchingStates, [true, false]);
  });

  test('watches a real repository root when available', () async {
    final directory = await Directory.systemTemp.createTemp('gift-watch-');
    addTearDown(() => directory.delete(recursive: true));
    final refreshObserved = Completer<void>();
    var refreshes = 0;
    final watchingStates = <bool>[];
    final coordinator = RepositoryRefreshCoordinator(
      root: directory.path,
      debounce: const Duration(milliseconds: 5),
      fallbackInterval: const Duration(hours: 1),
      onRefresh: () async {
        refreshes++;
        if (!refreshObserved.isCompleted) {
          refreshObserved.complete();
        }
      },
      onWatchingChanged: watchingStates.add,
    )..start();
    addTearDown(coordinator.dispose);

    expect(watchingStates, [true]);
    expect(coordinator.isWatching, isTrue);
    await File('${directory.path}/changed.txt').writeAsString('changed');
    await refreshObserved.future.timeout(const Duration(seconds: 2));

    expect(refreshes, greaterThanOrEqualTo(1));
  });
}
