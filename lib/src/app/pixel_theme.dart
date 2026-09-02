import 'package:flutter/material.dart';

const pixelFontFamily = 'Pixelify Sans';
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
const pixelLightMuted = Color(0xFF5E6B70);
const pixelLightMint = Color(0xFF087F5B);
const pixelLightSky = Color(0xFF1769AA);
const pixelLightAmber = Color(0xFF9A6700);
const pixelLightCoral = Color(0xFFB42318);

ThemeData buildPixelTheme({Brightness brightness = Brightness.dark}) {
  final dark = brightness == Brightness.dark;
  final canvas = dark ? pixelCanvas : pixelLightCanvas;
  final panel = dark ? pixelPanel : pixelLightPanel;
  final raised = dark ? pixelPanelRaised : pixelLightRaised;
  final ink = dark ? pixelInk : pixelLightInk;
  final muted = dark ? pixelMuted : pixelLightMuted;
  final primary = dark ? pixelMint : pixelLightMint;
  final secondary = dark ? pixelSky : pixelLightSky;
  final tertiary = dark ? pixelAmber : pixelLightAmber;
  final error = dark ? pixelCoral : pixelLightCoral;
  final scheme = ColorScheme.fromSeed(
    seedColor: primary,
    brightness: brightness,
    surface: panel,
    primary: primary,
    secondary: secondary,
    tertiary: tertiary,
    error: error,
    onSurface: ink,
  ).copyWith(surfaceContainerHighest: raised);
  final border = BorderSide(color: muted.withValues(alpha: 0.55));
  final square = RoundedRectangleBorder(
    borderRadius: BorderRadius.zero,
    side: border,
  );
  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.zero,
    borderSide: border,
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
    bodyLarge: const TextStyle(fontSize: 16, height: 1.35),
    bodyMedium: const TextStyle(fontSize: 15, height: 1.35),
    bodySmall: const TextStyle(fontSize: 13, height: 1.3),
    labelLarge: const TextStyle(fontSize: 13, height: 1.2),
    labelSmall: const TextStyle(fontSize: 12, height: 1.2),
    titleMedium: const TextStyle(fontSize: 16, height: 1.25),
    titleLarge: const TextStyle(fontSize: 18, height: 1.25),
    headlineSmall: const TextStyle(fontSize: 22, height: 1.2),
  );
  return base.copyWith(
    textTheme: textTheme.apply(fontFamily: pixelFontFamily),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: pixelFontFamily),
    dividerTheme: DividerThemeData(color: border.color, thickness: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: panel,
      foregroundColor: ink,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: pixelFontFamily,
        color: ink,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    ),
    cardTheme: CardThemeData(
      color: panel,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: square,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: panel,
      elevation: 0,
      shape: square,
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
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        side: BorderSide(color: primary, width: 2),
        minimumSize: const Size(48, 44),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primary,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        side: BorderSide(color: primary),
        minimumSize: const Size(48, 44),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: primary),
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
