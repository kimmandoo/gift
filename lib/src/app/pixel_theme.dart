import 'package:flutter/material.dart';

const pixelFontFamily = 'Atkinson Hyperlegible Next';
const pixelDisplayFontFamily = 'Jersey 15';
const pixelCanvas = Color(0xFF0D1117);
const pixelPanel = Color(0xFF151B23);
const pixelPanelRaised = Color(0xFF202938);
const pixelInk = Color(0xFFF5F7E9);
const pixelMuted = Color(0xFFB4BFC0);
const pixelMint = Color(0xFF63E6BE);
const pixelAmber = Color(0xFFFFCC66);
const pixelCoral = Color(0xFFFF7B72);
const pixelSky = Color(0xFF79C0FF);
const pixelLightCanvas = Color(0xFFF5F1E8);
const pixelLightPanel = Color(0xFFFFFCF5);
const pixelLightRaised = Color(0xFFE9E3D7);
const pixelLightInk = Color(0xFF17212B);
const pixelLightMuted = Color(0xFF46545C);
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

// Body copy uses a highly legible UI face while headings retain the pixel-game
// silhouette. Keeping both scales here prevents one-off sizes from pushing
// buttons, list rows, and status strips out of alignment.
const pixelBodyLargeSize = 15.0;
const pixelBodyMediumSize = 14.0;
const pixelBodySmallSize = 12.5;
const pixelLabelLargeSize = 12.5;
const pixelLabelSmallSize = 11.5;
const pixelTitleMediumSize = 15.0;
const pixelTitleLargeSize = 17.0;
const pixelHeadlineSmallSize = 20.0;
const pixelHeadlineMediumSize = 22.0;

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
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.05,
  );
  final buttonShape = const RoundedRectangleBorder(
    borderRadius: BorderRadius.zero,
  );
  final filledButtonStyle = ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return muted.withValues(alpha: 0.2);
      }
      if (states.contains(WidgetState.pressed)) {
        return primary.withValues(alpha: 0.72);
      }
      if (states.contains(WidgetState.hovered)) {
        return primary.withValues(alpha: 0.88);
      }
      return primary;
    }),
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return muted.withValues(alpha: 0.62);
      }
      return dark ? pixelCanvas : pixelLightPanel;
    }),
    side: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return BorderSide(color: muted.withValues(alpha: 0.35));
      }
      return BorderSide(color: primary, width: 2);
    }),
    textStyle: const WidgetStatePropertyAll(buttonTextStyle),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    ),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    shape: WidgetStatePropertyAll(buttonShape),
    minimumSize: const WidgetStatePropertyAll(Size(40, 36)),
  );
  final outlinedButtonStyle = ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return Colors.transparent;
      }
      if (states.contains(WidgetState.pressed)) {
        return primary.withValues(alpha: 0.2);
      }
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused)) {
        return dark ? pixelPrimaryContainer : pixelLightPrimaryContainer;
      }
      return Colors.transparent;
    }),
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return muted.withValues(alpha: 0.62);
      }
      return primary;
    }),
    side: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return BorderSide(color: muted.withValues(alpha: 0.35));
      }
      if (states.contains(WidgetState.focused) ||
          states.contains(WidgetState.pressed)) {
        return BorderSide(color: primary, width: 2);
      }
      return BorderSide(color: primary);
    }),
    textStyle: const WidgetStatePropertyAll(buttonTextStyle),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    ),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    shape: WidgetStatePropertyAll(buttonShape),
    minimumSize: const WidgetStatePropertyAll(Size(40, 36)),
  );
  final textButtonStyle = ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.pressed)) {
        return primary.withValues(alpha: 0.2);
      }
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused)) {
        return dark ? pixelPrimaryContainer : pixelLightPrimaryContainer;
      }
      return Colors.transparent;
    }),
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return muted.withValues(alpha: 0.62);
      }
      return primary;
    }),
    textStyle: const WidgetStatePropertyAll(buttonTextStyle),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    ),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    shape: WidgetStatePropertyAll(buttonShape),
    minimumSize: const WidgetStatePropertyAll(Size(40, 36)),
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
    bodyLarge: TextStyle(
      color: ink,
      fontSize: pixelBodyLargeSize,
      height: 1.42,
      letterSpacing: 0,
      fontWeight: FontWeight.w500,
    ),
    bodyMedium: TextStyle(
      color: ink,
      fontSize: pixelBodyMediumSize,
      height: 1.4,
      letterSpacing: 0,
      fontWeight: FontWeight.w500,
    ),
    bodySmall: TextStyle(
      color: muted,
      fontSize: pixelBodySmallSize,
      height: 1.38,
      letterSpacing: 0,
      fontWeight: FontWeight.w500,
    ),
    labelLarge: TextStyle(
      color: ink,
      fontSize: pixelLabelLargeSize,
      height: 1.2,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.05,
    ),
    labelSmall: TextStyle(
      color: muted,
      fontSize: pixelLabelSmallSize,
      height: 1.25,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.05,
    ),
    titleMedium: TextStyle(
      color: ink,
      fontSize: pixelTitleMediumSize,
      height: 1.28,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
    ),
    titleLarge: TextStyle(
      color: ink,
      fontSize: pixelTitleLargeSize,
      height: 1.28,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
    ),
    headlineSmall: TextStyle(
      color: ink,
      fontFamily: pixelDisplayFontFamily,
      fontSize: pixelHeadlineSmallSize,
      height: 1.15,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.2,
    ),
    headlineMedium: TextStyle(
      color: ink,
      fontFamily: pixelDisplayFontFamily,
      fontSize: pixelHeadlineMediumSize,
      height: 1.15,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.2,
    ),
  );
  final resolvedTextTheme = textTheme
      .apply(fontFamily: pixelFontFamily)
      .copyWith(
        headlineSmall: textTheme.headlineSmall,
        headlineMedium: textTheme.headlineMedium,
      );
  return base.copyWith(
    textTheme: resolvedTextTheme,
    primaryTextTheme: base.primaryTextTheme.apply(
      fontFamily: pixelFontFamily,
      bodyColor: ink,
      displayColor: ink,
    ),
    dividerTheme: DividerThemeData(color: border.color, thickness: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: panel,
      foregroundColor: ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: pixelDisplayFontFamily,
        color: ink,
        fontSize: pixelTitleLargeSize,
        height: 1.15,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.2,
      ),
      toolbarHeight: 52,
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
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      actionsPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      titleTextStyle: TextStyle(
        color: ink,
        fontFamily: pixelDisplayFontFamily,
        fontSize: pixelHeadlineSmallSize,
        height: 1.15,
      ),
      contentTextStyle: resolvedTextTheme.bodyMedium,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: panel,
      surfaceTintColor: Colors.transparent,
      shape: square,
      textStyle: resolvedTextTheme.bodyMedium?.copyWith(color: ink),
      labelTextStyle: WidgetStatePropertyAll(
        resolvedTextTheme.bodyMedium?.copyWith(color: ink),
      ),
      menuPadding: const EdgeInsets.symmetric(vertical: 8),
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
      floatingLabelStyle: TextStyle(
        color: primary,
        fontSize: pixelLabelLargeSize,
        height: 1.55,
        fontWeight: FontWeight.w600,
      ),
      hintStyle: TextStyle(color: muted),
      helperStyle: TextStyle(color: muted, height: 1.45),
      errorStyle: TextStyle(color: scheme.error, height: 1.45),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(style: filledButtonStyle),
    outlinedButtonTheme: OutlinedButtonThemeData(style: outlinedButtonStyle),
    textButtonTheme: TextButtonThemeData(style: textButtonStyle),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) {
            return primary.withValues(alpha: 0.2);
          }
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return dark ? pixelPrimaryContainer : pixelLightPrimaryContainer;
          }
          return Colors.transparent;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return muted.withValues(alpha: 0.5);
          }
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return primary;
          }
          return muted;
        }),
        side: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return BorderSide(color: muted.withValues(alpha: 0.25));
          }
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return BorderSide(color: primary);
          }
          return BorderSide(color: muted.withValues(alpha: 0.45));
        }),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: WidgetStatePropertyAll(buttonShape),
        minimumSize: const WidgetStatePropertyAll(Size(36, 36)),
        maximumSize: const WidgetStatePropertyAll(Size(40, 40)),
      ),
    ),
    listTileTheme: ListTileThemeData(
      selectedTileColor: raised,
      selectedColor: ink,
      iconColor: muted,
      textColor: ink,
      titleTextStyle: resolvedTextTheme.bodyMedium?.copyWith(
        color: ink,
        fontWeight: FontWeight.w600,
      ),
      subtitleTextStyle: resolvedTextTheme.bodySmall?.copyWith(color: muted),
      minTileHeight: 48,
      minVerticalPadding: 6,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      dense: true,
    ),
    tooltipTheme: TooltipThemeData(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      margin: const EdgeInsets.all(8),
      waitDuration: const Duration(milliseconds: 450),
      showDuration: const Duration(seconds: 4),
      verticalOffset: 8,
      preferBelow: false,
      textAlign: TextAlign.center,
      constraints: const BoxConstraints(maxWidth: 260),
      textStyle: resolvedTextTheme.labelLarge?.copyWith(color: ink),
      decoration: BoxDecoration(
        color: raised,
        border: Border.all(color: primary),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: panel,
      selectedColor: dark ? pixelPrimaryContainer : pixelLightPrimaryContainer,
      checkmarkColor: dark
          ? pixelOnPrimaryContainer
          : pixelLightOnPrimaryContainer,
      labelStyle: resolvedTextTheme.labelLarge,
      side: border,
      shape: buttonShape,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return dark ? pixelPrimaryContainer : pixelLightPrimaryContainer;
          }
          if (states.contains(WidgetState.pressed)) {
            return primary.withValues(alpha: 0.16);
          }
          return Colors.transparent;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return dark
                ? pixelOnPrimaryContainer
                : pixelLightOnPrimaryContainer;
          }
          return ink;
        }),
        side: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected) ||
              states.contains(WidgetState.focused)) {
            return BorderSide(color: primary, width: 2);
          }
          return border;
        }),
        shape: WidgetStatePropertyAll(buttonShape),
        textStyle: const WidgetStatePropertyAll(buttonTextStyle),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: primary,
      selectionColor: primary.withValues(alpha: 0.28),
      selectionHandleColor: primary,
    ),
    focusColor: primary.withValues(alpha: 0.24),
    visualDensity: VisualDensity.compact,
  );
}

/// Keeps long option labels readable inside the fixed-width pixel controls.
Widget pixelDropdownText(String text) =>
    Text(text, maxLines: 1, overflow: TextOverflow.ellipsis);

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
