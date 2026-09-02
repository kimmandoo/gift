import 'package:flutter/material.dart';

const pixelFontFamily = 'Jersey 15';
const pixelCanvas = Color(0xFF0D1117);
const pixelPanel = Color(0xFF151B23);
const pixelPanelRaised = Color(0xFF202938);
const pixelInk = Color(0xFFF5F7E9);
const pixelMuted = Color(0xFF9AA8A8);
const pixelMint = Color(0xFF63E6BE);
const pixelAmber = Color(0xFFFFCC66);
const pixelCoral = Color(0xFFFF7B72);
const pixelSky = Color(0xFF79C0FF);
const pixelLightCanvas = Color(0xFFF5F1E8);
const pixelLightPanel = Color(0xFFFFFCF5);
const pixelLightRaised = Color(0xFFE9E3D7);
const pixelLightInk = Color(0xFF17212B);
const pixelLightMuted = Color(0xFF526067);
const pixelLightMint = Color(0xFF056B4A);
const pixelLightSky = Color(0xFF145A90);
const pixelLightAmber = Color(0xFF7A4F00);
const pixelLightCoral = Color(0xFF9F1C16);
const pixelPrimaryContainer = Color(0xFF164A3A);
const pixelOnPrimaryContainer = Color(0xFFB8F7DF);
const pixelSecondaryContainer = Color(0xFF143A55);
const pixelOnSecondaryContainer = Color(0xFFC2E7FF);
const pixelTertiaryContainer = Color(0xFF4A390B);
const pixelOnTertiaryContainer = Color(0xFFFFE8A3);
const pixelErrorContainer = Color(0xFF5A201C);
const pixelOnErrorContainer = Color(0xFFFFDAD6);
const pixelLightPrimaryContainer = Color(0xFFB7E4D3);
const pixelLightOnPrimaryContainer = Color(0xFF063B2B);
const pixelLightSecondaryContainer = Color(0xFFC5E5FF);
const pixelLightOnSecondaryContainer = Color(0xFF043451);
const pixelLightTertiaryContainer = Color(0xFFFFE6A6);
const pixelLightOnTertiaryContainer = Color(0xFF2B2100);
const pixelLightErrorContainer = Color(0xFFFFDAD6);
const pixelLightOnErrorContainer = Color(0xFF410002);

// Keep the desktop type scale in one place so every screen stays readable as
// the pixel UI grows. Jersey 15 keeps the pixel silhouette while using
// heavier, simpler glyphs than the first-pass display font.
const pixelBodyLargeSize = 16.0;
const pixelBodyMediumSize = 15.0;
const pixelBodySmallSize = 13.0;
const pixelLabelLargeSize = 13.0;
const pixelLabelSmallSize = 12.0;
const pixelTitleMediumSize = 16.0;
const pixelTitleLargeSize = 18.0;
const pixelHeadlineSmallSize = 22.0;
const pixelHeadlineMediumSize = 24.0;

ThemeData buildPixelTheme({Brightness brightness = Brightness.dark}) {
  final dark = brightness == Brightness.dark;
  final canvas = dark ? pixelCanvas : pixelLightCanvas;
  final panel = dark ? pixelPanel : pixelLightPanel;
  final raised = dark ? pixelPanelRaised : pixelLightRaised;
  final ink = dark ? pixelInk : pixelLightInk;
  final muted = dark ? pixelMuted : pixelLightMuted;
  final primary = dark ? pixelMint : pixelLightMint;
  final scheme = dark
      ? const ColorScheme.dark(
          surface: pixelPanel,
          onSurface: pixelInk,
          surfaceDim: pixelCanvas,
          surfaceBright: pixelPanelRaised,
          surfaceContainerLowest: pixelCanvas,
          surfaceContainerLow: pixelPanel,
          surfaceContainer: pixelPanel,
          surfaceContainerHigh: pixelPanelRaised,
          surfaceContainerHighest: pixelPanelRaised,
          surfaceTint: Colors.transparent,
          primary: pixelMint,
          onPrimary: pixelCanvas,
          primaryContainer: pixelPrimaryContainer,
          onPrimaryContainer: pixelOnPrimaryContainer,
          secondary: pixelSky,
          onSecondary: pixelCanvas,
          secondaryContainer: pixelSecondaryContainer,
          onSecondaryContainer: pixelOnSecondaryContainer,
          tertiary: pixelAmber,
          onTertiary: pixelCanvas,
          tertiaryContainer: pixelTertiaryContainer,
          onTertiaryContainer: pixelOnTertiaryContainer,
          error: pixelCoral,
          onError: pixelCanvas,
          errorContainer: pixelErrorContainer,
          onErrorContainer: pixelOnErrorContainer,
          outline: pixelMuted,
          onSurfaceVariant: pixelMuted,
        )
      : const ColorScheme.light(
          surface: pixelLightPanel,
          onSurface: pixelLightInk,
          surfaceDim: pixelLightRaised,
          surfaceBright: pixelLightPanel,
          surfaceContainerLowest: pixelLightPanel,
          surfaceContainerLow: pixelLightPanel,
          surfaceContainer: pixelLightPanel,
          surfaceContainerHigh: pixelLightRaised,
          surfaceContainerHighest: pixelLightRaised,
          surfaceTint: Colors.transparent,
          primary: pixelLightMint,
          onPrimary: pixelLightPanel,
          primaryContainer: pixelLightPrimaryContainer,
          onPrimaryContainer: pixelLightOnPrimaryContainer,
          secondary: pixelLightSky,
          onSecondary: pixelLightPanel,
          secondaryContainer: pixelLightSecondaryContainer,
          onSecondaryContainer: pixelLightOnSecondaryContainer,
          tertiary: pixelLightAmber,
          onTertiary: pixelLightPanel,
          tertiaryContainer: pixelLightTertiaryContainer,
          onTertiaryContainer: pixelLightOnTertiaryContainer,
          error: pixelLightCoral,
          onError: pixelLightPanel,
          errorContainer: pixelLightErrorContainer,
          onErrorContainer: pixelLightOnErrorContainer,
          outline: pixelLightMuted,
          onSurfaceVariant: pixelLightMuted,
        );
  final border = BorderSide(color: muted.withValues(alpha: 0.55));
  final square = RoundedRectangleBorder(
    borderRadius: BorderRadius.zero,
    side: border,
  );
  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.zero,
    borderSide: border,
  );
  const buttonTextStyle = TextStyle(
    fontFamily: pixelFontFamily,
    fontSize: pixelLabelLargeSize,
    height: 1.25,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.15,
  );
  final base = ThemeData(
    colorScheme: scheme,
    brightness: brightness,
    useMaterial3: true,
    fontFamily: pixelFontFamily,
    scaffoldBackgroundColor: canvas,
    canvasColor: canvas,
  );
  final textTheme = base.textTheme.copyWith(
    bodyLarge: const TextStyle(
      fontSize: pixelBodyLargeSize,
      height: 1.4,
      letterSpacing: 0.1,
      fontWeight: FontWeight.w500,
    ),
    bodyMedium: const TextStyle(
      fontSize: pixelBodyMediumSize,
      height: 1.4,
      letterSpacing: 0.1,
      fontWeight: FontWeight.w500,
    ),
    bodySmall: const TextStyle(
      fontSize: pixelBodySmallSize,
      height: 1.35,
      letterSpacing: 0.1,
      fontWeight: FontWeight.w500,
    ),
    labelLarge: const TextStyle(
      fontSize: pixelLabelLargeSize,
      height: 1.25,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.15,
    ),
    labelSmall: const TextStyle(
      fontSize: pixelLabelSmallSize,
      height: 1.25,
      letterSpacing: 0.1,
    ),
    titleMedium: const TextStyle(
      fontSize: pixelTitleMediumSize,
      height: 1.3,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
    ),
    titleLarge: const TextStyle(
      fontSize: pixelTitleLargeSize,
      height: 1.3,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
    ),
    headlineSmall: const TextStyle(
      fontSize: pixelHeadlineSmallSize,
      height: 1.25,
      fontWeight: FontWeight.w600,
    ),
    headlineMedium: const TextStyle(
      fontSize: pixelHeadlineMediumSize,
      height: 1.25,
      fontWeight: FontWeight.w600,
    ),
  );
  return base.copyWith(
    textTheme: textTheme.apply(fontFamily: pixelFontFamily),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: pixelFontFamily),
    dividerTheme: DividerThemeData(color: border.color, thickness: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: panel,
      foregroundColor: ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: pixelFontFamily,
        color: ink,
        fontSize: pixelTitleLargeSize,
        height: 1.3,
        fontWeight: FontWeight.bold,
      ),
    ),
    cardTheme: CardThemeData(
      color: panel,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: square,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: panel,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: square,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: raised,
      contentTextStyle: TextStyle(color: ink, fontFamily: pixelFontFamily),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: canvas,
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: primary, width: 2),
      ),
      labelStyle: TextStyle(color: muted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: dark ? pixelCanvas : pixelLightPanel,
        textStyle: buttonTextStyle,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        side: BorderSide(color: primary, width: 2),
        minimumSize: const Size(44, 40),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primary,
        textStyle: buttonTextStyle,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        side: BorderSide(color: primary),
        minimumSize: const Size(44, 40),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primary,
        textStyle: buttonTextStyle,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        minimumSize: const Size(44, 40),
      ),
    ),
    listTileTheme: ListTileThemeData(
      selectedTileColor: raised,
      selectedColor: ink,
      iconColor: muted,
    ),
    focusColor: primary.withValues(alpha: 0.24),
    visualDensity: VisualDensity.standard,
  );
}

class PixelThemeScope extends InheritedWidget {
  const PixelThemeScope({
    super.key,
    required this.mode,
    required this.toggle,
    required super.child,
  });

  final ThemeMode mode;
  final VoidCallback toggle;

  static PixelThemeScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PixelThemeScope>()!;

  static PixelThemeScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PixelThemeScope>();

  @override
  bool updateShouldNotify(PixelThemeScope oldWidget) => oldWidget.mode != mode;
}

class PixelThemeToggle extends StatelessWidget {
  const PixelThemeToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = PixelThemeScope.maybeOf(context);
    if (scope == null) return const SizedBox.shrink();
    final dark = scope.mode == ThemeMode.dark;
    return IconButton(
      key: const Key('theme-toggle'),
      tooltip: dark ? 'Use light theme' : 'Use dark theme',
      onPressed: scope.toggle,
      icon: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
    );
  }
}
