import 'package:flutter/material.dart';

/// Shared visual tokens from the product's original pixel-game direction.
const pixelCanvas = Color(0xFF11161C);
const pixelPanel = Color(0xFF1A222C);
const pixelPanelRaised = Color(0xFF222D39);
const pixelInk = Color(0xFFF2F4E8);
const pixelMuted = Color(0xFFAAB5B2);
const pixelMint = Color(0xFF79E2B8);
const pixelAmber = Color(0xFFF4C95D);
const pixelCoral = Color(0xFFF47C7C);
const pixelSky = Color(0xFF79BDE8);

/// Builds a flat, high-contrast dark theme with crisp square surfaces.
ThemeData buildPixelTheme() {
  final scheme = const ColorScheme.dark(
    surface: pixelPanel,
    surfaceContainerHighest: pixelPanelRaised,
    primary: pixelMint,
    onPrimary: pixelCanvas,
    secondary: pixelSky,
    onSecondary: pixelCanvas,
    tertiary: pixelAmber,
    onTertiary: pixelCanvas,
    error: pixelCoral,
    onError: pixelCanvas,
    onSurface: pixelInk,
  );
  final border = BorderSide(color: pixelMuted.withValues(alpha: 0.35));
  return ThemeData(
    colorScheme: scheme,
    brightness: Brightness.dark,
    useMaterial3: true,
    scaffoldBackgroundColor: pixelCanvas,
    canvasColor: pixelCanvas,
    dividerTheme: DividerThemeData(color: border.color, thickness: 1),
    appBarTheme: const AppBarTheme(
      backgroundColor: pixelPanel,
      foregroundColor: pixelInk,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: pixelPanel,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: border,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: pixelCanvas,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: border,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: border,
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: pixelMint, width: 2),
      ),
      labelStyle: const TextStyle(color: pixelMuted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: pixelMint,
        foregroundColor: pixelCanvas,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        side: const BorderSide(color: pixelMint),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: pixelMint,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        side: const BorderSide(color: pixelMint),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: pixelMint),
    ),
    listTileTheme: const ListTileThemeData(
      selectedTileColor: pixelPanelRaised,
      selectedColor: pixelInk,
      iconColor: pixelMuted,
    ),
    focusColor: pixelMint.withValues(alpha: 0.24),
  );
}
