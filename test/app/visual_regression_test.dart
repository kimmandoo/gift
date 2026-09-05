import 'dart:io';

import 'package:gift/src/app/pixel_theme.dart';
import 'package:gift/src/backend/credentials.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:gift/src/backend/history.dart';
import 'package:gift/src/backend/remote.dart';
import 'package:gift/src/backend/status.dart';
import 'package:gift/src/features/repository/push_dialog.dart';
import 'package:gift/src/features/repository/repository_setup_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gift/src/app/gift_app.dart';

import '../helpers/git_patch_gateway_stub.dart';

void main() {
  const fixtures = [
    (
      name: 'compact-dark-large-text',
      size: Size(320, 480),
      brightness: Brightness.dark,
      textScale: 1.2,
    ),
    (
      name: 'compact-light-large-text',
      size: Size(320, 480),
      brightness: Brightness.light,
      textScale: 1.2,
    ),
    (
      name: 'standard-dark',
      size: Size(800, 600),
      brightness: Brightness.dark,
      textScale: 1.0,
    ),
    (
      name: 'standard-light',
      size: Size(800, 600),
      brightness: Brightness.light,
      textScale: 1.0,
    ),
    (
      name: 'wide-dark',
      size: Size(1280, 800),
      brightness: Brightness.dark,
      textScale: 1.0,
    ),
    (
      name: 'wide-light',
      size: Size(1280, 800),
      brightness: Brightness.light,
      textScale: 1.0,
    ),
  ];

  for (final fixture in fixtures) {
    testWidgets('keeps the ${fixture.name} welcome surface bounded', (
      tester,
    ) async {
      addTearDown(tester.view.reset);
      tester.view.physicalSize = fixture.size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = fixture.textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(const GiftApp());
      await tester.pump();
      if (fixture.brightness == Brightness.light) {
        await tester.tap(find.byKey(const Key('theme-toggle')));
        await tester.pumpAndSettle();
      }

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(
        app.themeMode,
        fixture.brightness == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light,
      );
      expect(tester.takeException(), isNull);

      final viewport = Offset.zero & fixture.size;
      final logo = tester.getRect(find.byKey(const Key('welcome-logo')));
      final themeToggle = tester.getRect(find.byKey(const Key('theme-toggle')));
      final preferences = tester.getRect(
        find.byKey(const Key('open-preferences')),
      );
      final open = tester.getRect(
        find.widgetWithText(FilledButton, 'Open Repository'),
      );
      final setup = tester.getRect(find.byKey(const Key('setup-repository')));

      expect(logo, completelyWithin(viewport));
      expect(themeToggle, completelyWithin(viewport));
      expect(preferences, completelyWithin(viewport));
      expect(open, completelyWithin(viewport));
      expect(setup, completelyWithin(viewport));
      expect(open.height, lessThanOrEqualTo(48));
      expect(setup.height, lessThanOrEqualTo(48));

      if (fixture.size.width < 520) {
        expect(setup.top, greaterThanOrEqualTo(open.bottom + 8));
      } else {
        expect(setup.left, greaterThanOrEqualTo(open.right + 8));
        expect(setup.top, closeTo(open.top, 1));
      }
      await expectVisualGolden(tester, '${fixture.name}.png');
    });
  }

  testWidgets('keeps the welcome theme interaction available in compact mode', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(const GiftApp());
    await tester.pump();
    expect(find.byKey(const Key('theme-toggle')), findsOneWidget);
    expect(find.byKey(const Key('open-preferences')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('theme-toggle')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.light,
    );
    expect(tester.takeException(), isNull);
  });
  for (final fixture in const [
    (
      name: 'compact-dark-dialog',
      size: Size(360, 640),
      brightness: Brightness.dark,
      textScale: 1.2,
    ),
    (
      name: 'standard-light-dialog',
      size: Size(800, 700),
      brightness: Brightness.light,
      textScale: 1.0,
    ),
  ]) {
    testWidgets('keeps the ${fixture.name} push dialog bounded', (
      tester,
    ) async {
      addTearDown(tester.view.reset);
      tester.view.physicalSize = fixture.size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = fixture.textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      const repository = RepositoryOpened(
        repositoryId: RepositoryId(value: 'visual-push-repository'),
        root: '/workspace/project',
      );
      final store = InMemoryGitCredentialStore(
        records: [
          GitCredentialRecord(
            account: GitCredentialAccount(
              id: 'visual-account',
              provider: GitCredentialProvider.github,
              host: 'github.com',
              accountName: 'Visual test account',
              kind: GitCredentialKind.httpsToken,
            ),
            secret: 'visual-secret',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: buildPixelTheme(brightness: fixture.brightness),
          home: PushDialog(
            gateway: _VisualGateway(repository),
            repository: repository,
            credentialStore: store,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final viewport = Offset.zero & fixture.size;
      final remote = tester.getRect(find.byKey(const Key('push-remote')));
      final account = tester.getRect(find.byKey(const Key('push-credential')));
      expect(remote, completelyWithin(viewport));
      expect(account, completelyWithin(viewport));
      expect(account.top, greaterThanOrEqualTo(remote.bottom + 8));
      expect(tester.takeException(), isNull);
      await expectVisualGolden(tester, '${fixture.name}-push.png');
    });

    testWidgets('keeps the ${fixture.name} clone dialog bounded', (
      tester,
    ) async {
      addTearDown(tester.view.reset);
      tester.view.physicalSize = fixture.size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = fixture.textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      const repository = RepositoryOpened(
        repositoryId: RepositoryId(value: 'visual-clone-repository'),
        root: '/workspace/project',
      );
      final store = InMemoryGitCredentialStore(
        records: [
          GitCredentialRecord(
            account: GitCredentialAccount(
              id: 'visual-clone-account',
              provider: GitCredentialProvider.github,
              host: 'github.com',
              accountName: 'Visual clone account',
              kind: GitCredentialKind.httpsToken,
            ),
            secret: 'visual-secret',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: buildPixelTheme(brightness: fixture.brightness),
          home: RepositorySetupDialog(
            gateway: _VisualGateway(repository),
            credentialStore: store,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('clone-source')),
        'https://github.com/acme/project.git',
      );
      await tester.pumpAndSettle();

      final viewport = Offset.zero & fixture.size;
      final source = tester.getRect(find.byKey(const Key('clone-source')));
      final account = tester.getRect(find.byKey(const Key('clone-credential')));
      expect(source, completelyWithin(viewport));
      expect(account, completelyWithin(viewport));
      expect(account.top, greaterThanOrEqualTo(source.bottom + 8));
      expect(tester.takeException(), isNull);
      await expectVisualGolden(tester, '${fixture.name}-clone.png');
    });
  }
}

String? get visualGoldenPlatform => switch (Platform.operatingSystem) {
  'windows' => 'windows',
  'linux' => 'linux',
  'macos' => 'macos',
  _ => null,
};

bool get shouldCaptureVisualGoldens {
  final platform = visualGoldenPlatform;
  return platform != null &&
      (Platform.isWindows ||
          Platform.environment['GIFT_CAPTURE_GOLDENS'] == '1');
}

Future<void> expectVisualGolden(WidgetTester tester, String fileName) async {
  final platform = visualGoldenPlatform;
  if (platform == null || !shouldCaptureVisualGoldens) return;
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/$platform/$fileName'),
  );
}

class _VisualGateway with GitPatchGatewayStub implements GitGateway {
  _VisualGateway(this.repository);

  final RepositoryOpened repository;

  @override
  Future<List<GitRemote>> getRemotes(RepositoryId repositoryId) async => const [
    GitRemote(
      name: 'origin',
      fetchUrl: 'https://github.com/acme/project.git',
      pushUrl: 'https://github.com/acme/project.git',
    ),
  ];

  @override
  Future<GitStatusSnapshot> getStatus(RepositoryId repositoryId) async =>
      GitStatusSnapshot(
        repositoryId: repositoryId,
        root: repository.root,
        branch: GitBranchStatus(head: 'main', oid: 'a' * 40),
        changes: const [],
        contentHash: 'visual',
        generation: 1,
      );

  @override
  Future<GitHistoryPage> getHistory(
    RepositoryId repositoryId, {
    int limit = 50,
    int offset = 0,
    GitHistoryQuery? query,
  }) async => GitHistoryPage(
    repositoryId: repositoryId,
    commits: const [],
    offset: offset,
    limit: limit,
    hasMore: false,
  );
}

Matcher completelyWithin(Rect viewport) => predicate<Rect>(
  (rect) =>
      rect.left >= viewport.left &&
      rect.top >= viewport.top &&
      rect.right <= viewport.right &&
      rect.bottom <= viewport.bottom,
  'a rectangle fully inside $viewport',
);
