import 'package:gitshiba/src/app/gitshiba_app.dart';
import 'package:gitshiba/src/app/pixel_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('boots into the repository welcome screen', (tester) async {
    await tester.pumpWidget(const GitshibaApp());
    expect(find.text('Open Repository'), findsOneWidget);
    expect(find.byKey(const Key('welcome-logo')), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  testWidgets('keeps the welcome action compact and aligned with the logo', (
    tester,
  ) async {
    await tester.pumpWidget(const GitshibaApp());

    final action = find.widgetWithText(FilledButton, 'Open Repository');
    expect(tester.getSize(action).height, lessThanOrEqualTo(44));
    expect(
      tester.getTopLeft(find.byKey(const Key('welcome-logo'))).dx,
      closeTo(tester.getTopLeft(find.text('Open a Git repository')).dx, 1),
    );
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
    expect(theme.textTheme.headlineMedium?.fontFamily, pixelDisplayFontFamily);
    expect(theme.textTheme.bodyLarge?.fontSize, pixelBodyLargeSize);
    expect(theme.textTheme.bodyMedium?.fontSize, pixelBodyMediumSize);
    expect(theme.textTheme.bodySmall?.fontSize, pixelBodySmallSize);
    expect(theme.textTheme.labelSmall?.fontSize, pixelLabelSmallSize);
    expect(theme.textTheme.titleLarge?.fontSize, pixelTitleLargeSize);
    expect(theme.textTheme.headlineSmall?.fontSize, pixelHeadlineSmallSize);
    expect(theme.textTheme.headlineMedium?.fontSize, pixelHeadlineMediumSize);
    expect(theme.appBarTheme.titleTextStyle?.fontSize, pixelTitleLargeSize);
    expect(
      theme.filledButtonTheme.style?.minimumSize?.resolve({}),
      const Size(40, 36),
    );
    expect(
      theme.outlinedButtonTheme.style?.minimumSize?.resolve({}),
      const Size(40, 36),
    );
    expect(theme.colorScheme.surfaceContainerHighest, pixelPanelRaised);
    expect(light.brightness, Brightness.light);
    expect(light.scaffoldBackgroundColor, pixelLightCanvas);
    expect(light.colorScheme.surfaceContainerHighest, pixelLightRaised);
    for (final scheme in [theme.colorScheme, light.colorScheme]) {
      expect(
        contrast(scheme.onSurface, scheme.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(scheme.onSurfaceVariant, scheme.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(scheme.onPrimary, scheme.primary),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(scheme.onSecondary, scheme.secondary),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(scheme.onTertiary, scheme.tertiary),
        greaterThanOrEqualTo(4.5),
      );
      expect(contrast(scheme.onError, scheme.error), greaterThanOrEqualTo(4.5));
      expect(
        contrast(scheme.onPrimaryContainer, scheme.primaryContainer),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(scheme.onSecondaryContainer, scheme.secondaryContainer),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(scheme.onTertiaryContainer, scheme.tertiaryContainer),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(scheme.onErrorContainer, scheme.errorContainer),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(scheme.primary, scheme.surfaceContainerHighest),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(scheme.secondary, scheme.surfaceContainerHighest),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(scheme.tertiary, scheme.surfaceContainerHighest),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(scheme.error, scheme.surfaceContainerHighest),
        greaterThanOrEqualTo(4.5),
      );
    }
    expect(theme.textTheme.bodyMedium?.color, theme.colorScheme.onSurface);
    expect(
      theme.textTheme.bodySmall?.color,
      theme.colorScheme.onSurfaceVariant,
    );
    expect(light.textTheme.bodyMedium?.color, light.colorScheme.onSurface);
    expect(
      light.textTheme.bodySmall?.color,
      light.colorScheme.onSurfaceVariant,
    );
  });

  testWidgets('switches and persists the light theme', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(GitshibaApp(preferences: preferences));

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
    expect(preferences.getString(GitshibaApp.themeModeKey), 'light');
  });

  testWidgets('welcome screen does not overflow in a compact window', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(const GitshibaApp());
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Open Repository'), findsOneWidget);
  });
}

double contrast(Color foreground, Color background) {
  final foregroundLuminance = foreground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final darker = foregroundLuminance > backgroundLuminance
      ? backgroundLuminance
      : foregroundLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}
