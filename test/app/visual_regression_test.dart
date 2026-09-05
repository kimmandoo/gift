import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gift/src/app/gift_app.dart';

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
}

Matcher completelyWithin(Rect viewport) => predicate<Rect>(
  (rect) =>
      rect.left >= viewport.left &&
      rect.top >= viewport.top &&
      rect.right <= viewport.right &&
      rect.bottom <= viewport.bottom,
  'a rectangle fully inside $viewport',
);
