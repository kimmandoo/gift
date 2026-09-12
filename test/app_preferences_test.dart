import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gift/src/app/app_preferences.dart';
import 'package:gift/src/app/preferences_dialog.dart';
import 'package:gift/src/backend/error.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('migrates legacy theme and recovers malformed versioned data', () async {
    SharedPreferences.setMockInitialValues({
      'theme_mode': 'light',
      GiftPreferences.storageKey: '{not-json',
    });
    final storage = await SharedPreferences.getInstance();

    final result = GiftPreferences.load(storage);

    expect(result.preferences.themeMode, ThemeMode.light);
    expect(result.preferences.uiScale, 1.0);
    expect(result.recoveredCorruptData, isTrue);
    expect(result.needsRewrite, isTrue);
    await result.preferences.save(storage);
    final encoded = storage.getString(GiftPreferences.storageKey);
    expect(encoded, isNotNull);
    expect(jsonDecode(encoded!)['version'], GiftPreferences.currentVersion);
  });
  test('canonicalizes shortcut conflicts without losing defaults', () {
    final preferences = GiftPreferences.defaults.copyWith(
      shortcuts: const {'refresh': 'CTRL+R', 'history': 'ctrl+r'},
    );
    expect(preferences.shortcut('refresh'), 'ctrl+r');
    expect(preferences.shortcutConflicts, {
      'ctrl+r': {'refresh', 'history'},
    });
  });

  test('formats shortcut bindings for visible hints', () {
    expect(formatShortcut('ctrl+shift+p'), 'Ctrl+Shift+P');
    expect(formatShortcut('escape'), 'Esc');
    expect(formatShortcut(''), 'Unassigned');
  });

  test('round trips accessibility and repository preferences', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = await SharedPreferences.getInstance();
    final preferences = GiftPreferences.defaults.copyWith(
      uiScale: 1.4,
      reducedMotion: true,
      highContrast: true,
      colorSafeGraph: false,
      defaultBranch: 'develop',
      defaultRemote: 'upstream',
      refreshInterval: const Duration(seconds: 60),
      themeMode: ThemeMode.light,
    );

    expect(await preferences.save(storage), isTrue);
    final loaded = GiftPreferences.load(storage);

    expect(loaded.preferences.uiScale, 1.4);
    expect(loaded.preferences.reducedMotion, isTrue);
    expect(loaded.preferences.highContrast, isTrue);
    expect(loaded.preferences.colorSafeGraph, isFalse);
    expect(loaded.preferences.defaultBranch, 'develop');
    expect(loaded.preferences.defaultRemote, 'upstream');
    expect(loaded.preferences.refreshInterval, const Duration(seconds: 60));
    expect(loaded.preferences.themeMode, ThemeMode.light);
    expect(loaded.needsRewrite, isFalse);
  });
  testWidgets('applies accessibility settings and validates shortcut input', (
    tester,
  ) async {
    GiftPreferences? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => PreferencesDialog(
                  preferences: GiftPreferences.defaults,
                  onSave: (value) async => saved = value,
                ),
              ),
              child: const Text('Open preferences'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open preferences'));
    await tester.pumpAndSettle();
    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel(RegExp('UI scale')), findsAtLeastNWidgets(1));
    expect(
      find.bySemanticsLabel(RegExp('Reduce motion')),
      findsAtLeastNWidgets(1),
    );
    semantics.dispose();
    await tester.tap(find.byKey(const Key('preference-reduced-motion')));
    await tester.tap(find.byKey(const Key('preference-high-contrast')));
    await tester.drag(find.byType(ListView), const Offset(0, -420));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const Key('preference-shortcut-refresh')),
          )
          .controller
          ?.text,
      formatShortcut(GiftPreferences.defaults.shortcut('refresh')),
    );
    await tester.enterText(
      find.byKey(const Key('preference-shortcut-refresh')),
      'ctrl+alt+r',
    );
    await tester.tap(find.byKey(const Key('save-preferences')));
    await tester.pumpAndSettle();

    expect(saved?.reducedMotion, isTrue);
    expect(saved?.highContrast, isTrue);
    expect(saved?.shortcut('refresh'), 'ctrl+alt+r');
    expect(find.text('Open preferences'), findsOneWidget);
  });

  testWidgets('keeps preference fields separated in a compact dialog', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => PreferencesDialog(
                  preferences: GiftPreferences.defaults,
                  onSave: (_) async {},
                ),
              ),
              child: const Text('Open preferences'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open preferences'));
    await tester.pumpAndSettle();

    final list = find.byType(Scrollable);
    await tester.scrollUntilVisible(
      find.byKey(const Key('preference-default-remote')),
      200,
      scrollable: list,
    );
    final branchRect = tester.getRect(
      find.byKey(const Key('preference-default-branch')),
    );
    final remoteRect = tester.getRect(
      find.byKey(const Key('preference-default-remote')),
    );
    expect(remoteRect.top - branchRect.bottom, greaterThanOrEqualTo(12));
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows preference save failures in a modal error popup', (
    tester,
  ) async {
    const failure = GitError(
      category: GitErrorCategory.permissionDenied,
      userMessage: 'Preferences could not be written.',
      diagnostic: 'test save failure',
      retryable: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => PreferencesDialog(
                  preferences: GiftPreferences.defaults,
                  onSave: (_) async => throw failure,
                ),
              ),
              child: const Text('Open preferences'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open preferences'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-preferences')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('error-popup')), findsOneWidget);
    expect(find.text(failure.userMessage), findsOneWidget);
    await tester.tap(find.byKey(const Key('dismiss-error-popup')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('save-preferences')), findsOneWidget);
  });
}
