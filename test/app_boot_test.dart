import 'package:gitflu/src/app/gitflu_app.dart';
import 'package:gitflu/src/app/pixel_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('boots into the repository welcome screen', (tester) async {
    await tester.pumpWidget(const GitfluApp());
    expect(find.text('Open Repository'), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  test('uses the documented pixel theme tokens', () {
    final theme = buildPixelTheme();
    final light = buildPixelTheme(brightness: Brightness.light);

    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, pixelCanvas);
    expect(theme.colorScheme.primary, pixelMint);
    expect(theme.colorScheme.error, pixelCoral);
    expect(theme.cardTheme.elevation, 0);
    expect(theme.textTheme.bodyMedium?.fontFamily, pixelFontFamily);
    expect(light.brightness, Brightness.light);
    expect(light.scaffoldBackgroundColor, pixelLightCanvas);
  });

  testWidgets('switches and persists the light theme', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(GitfluApp(preferences: preferences));

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
    await tester.tap(find.byKey(const Key('theme-toggle')));
    await tester.pumpAndSettle();

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.light,
    );
    expect(preferences.getString(GitfluApp.themeModeKey), 'light');
  });

  testWidgets('welcome screen does not overflow in a compact window', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;

    await tester.pumpWidget(const GitfluApp());
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Open Repository'), findsOneWidget);
  });
}
