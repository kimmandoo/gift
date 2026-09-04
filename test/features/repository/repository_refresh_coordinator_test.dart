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

  test('watches a real repository root when available', () async {
    final directory = await Directory.systemTemp.createTemp('gift-watch-');
    addTearDown(() => directory.delete(recursive: true));
    var refreshes = 0;
    final coordinator = RepositoryRefreshCoordinator(
      root: directory.path,
      debounce: const Duration(milliseconds: 5),
      fallbackInterval: const Duration(hours: 1),
      onRefresh: () async {
        refreshes++;
      },
    )..start();
    addTearDown(coordinator.dispose);

    expect(coordinator.isWatching, isTrue);
    await File('${directory.path}/changed.txt').writeAsString('changed');
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(refreshes, greaterThanOrEqualTo(1));
  });
}
