import 'package:flutter/material.dart';

const pixelFontFamily = 'Atkinson Hyperlegible Next';
const pixelDisplayFontFamily = 'Jersey 15';
const pixelKoreanFontFamily = 'Noto Sans KR';
const pixelFontFallbackFamilies = <String>[
  pixelKoreanFontFamily,
  'Malgun Gothic',
  'Segoe UI',
];

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

ThemeData buildPixelTheme({
  Brightness brightness = Brightness.dark,
  double uiScale = 1,
  bool highContrast = false,
  bool colorSafeGraph = true,
}) {
  final dark = brightness == Brightness.dark;
  final canvas = dark ? pixelCanvas : pixelLightCanvas;
  final panel = dark ? pixelPanel : pixelLightPanel;
  final raised = dark ? pixelPanelRaised : pixelLightRaised;
  final ink = dark ? pixelInk : pixelLightInk;
  final muted = dark ? pixelMuted : pixelLightMuted;
  final primary = dark ? pixelMint : pixelLightMint;
  final scale = uiScale.clamp(0.8, 1.6).toDouble();
  final baseScheme = dark
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
  final scheme = colorSafeGraph
      ? baseScheme.copyWith(
          secondary: dark ? const Color(0xFF56B4E9) : const Color(0xFF005A8D),
          tertiary: dark ? const Color(0xFFE69F00) : const Color(0xFF8C5C00),
        )
      : baseScheme;
  final border = BorderSide(
    color: muted.withValues(alpha: highContrast ? 0.9 : 0.55),
    width: highContrast ? 1.5 : 1,
  );
  final square = RoundedRectangleBorder(
    borderRadius: BorderRadius.zero,
    side: border,
  );
  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.zero,
    borderSide: border,
  );
  final buttonTextStyle = TextStyle(
    fontFamily: pixelFontFamily,
    fontFamilyFallback: pixelFontFallbackFamilies,
    fontSize: pixelLabelLargeSize * scale,
    height: 1.28,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.05,
  );

  const buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.zero);
  const labeledButtonPadding = EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 8,
  );
  const textButtonPadding = EdgeInsets.symmetric(horizontal: 12, vertical: 8);
  final filledButtonStyle = ButtonStyle(
    animationDuration: Duration.zero,
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return panel;
      return primary;
    }),
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return muted.withValues(alpha: 0.58);
      }
      return scheme.onPrimary;
    }),
    overlayColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.pressed)) {
        return ink.withValues(alpha: 0.18);
      }
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused)) {
        return Colors.white.withValues(alpha: dark ? 0.1 : 0.16);
      }
      return Colors.transparent;
    }),
    textStyle: WidgetStatePropertyAll(buttonTextStyle),
    iconSize: const WidgetStatePropertyAll(18),
    padding: const WidgetStatePropertyAll(labeledButtonPadding),
    side: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return BorderSide(color: muted.withValues(alpha: 0.24));
      }
      return BorderSide(
        color: scheme.onPrimary.withValues(
          alpha:
              states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused) ||
                  states.contains(WidgetState.pressed)
              ? 0.82
              : 0.55,
        ),
      );
    }),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    shape: WidgetStatePropertyAll(buttonShape),
    minimumSize: const WidgetStatePropertyAll(Size(40, 40)),
    elevation: const WidgetStatePropertyAll(0),
  );
  final outlinedButtonStyle = ButtonStyle(
    animationDuration: Duration.zero,
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return Colors.transparent;
      if (states.contains(WidgetState.pressed)) {
        return primary.withValues(alpha: 0.12);
      }
      return raised.withValues(alpha: dark ? 0.5 : 0.38);
    }),
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return muted.withValues(alpha: 0.58);
      }
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused) ||
          states.contains(WidgetState.pressed)) {
        return primary;
      }
      return ink;
    }),
    overlayColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.pressed)) {
        return primary.withValues(alpha: 0.14);
      }
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused)) {
        return primary.withValues(alpha: 0.08);
      }
      return Colors.transparent;
    }),
    side: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return BorderSide(color: muted.withValues(alpha: 0.24));
      }
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused) ||
          states.contains(WidgetState.pressed)) {
        return BorderSide(color: primary);
      }
      return border;
    }),
    textStyle: WidgetStatePropertyAll(buttonTextStyle),
    iconSize: const WidgetStatePropertyAll(18),
    padding: const WidgetStatePropertyAll(labeledButtonPadding),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    shape: WidgetStatePropertyAll(buttonShape),
    minimumSize: const WidgetStatePropertyAll(Size(40, 40)),
    elevation: const WidgetStatePropertyAll(0),
  );
  final textButtonStyle = ButtonStyle(
    animationDuration: Duration.zero,
    backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return muted.withValues(alpha: 0.58);
      }
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused) ||
          states.contains(WidgetState.pressed)) {
        return primary;
      }
      return ink;
    }),
    overlayColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.pressed)) {
        return primary.withValues(alpha: 0.12);
      }
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused)) {
        return primary.withValues(alpha: 0.07);
      }
      return Colors.transparent;
    }),
    textStyle: WidgetStatePropertyAll(buttonTextStyle),
    iconSize: const WidgetStatePropertyAll(18),
    padding: const WidgetStatePropertyAll(textButtonPadding),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    shape: WidgetStatePropertyAll(buttonShape),
    minimumSize: const WidgetStatePropertyAll(Size(40, 40)),
    elevation: const WidgetStatePropertyAll(0),
  );
  final base = ThemeData(
    colorScheme: scheme,
    brightness: brightness,
    useMaterial3: true,
    fontFamily: pixelFontFamily,
    fontFamilyFallback: pixelFontFallbackFamilies,
    scaffoldBackgroundColor: canvas,
    canvasColor: canvas,
  );

  final textTheme = base.textTheme.copyWith(
    bodyLarge: TextStyle(
      color: ink,
      fontSize: pixelBodyLargeSize * scale,
      height: 1.42,
      letterSpacing: 0,
      fontWeight: FontWeight.w500,
    ),
    bodyMedium: TextStyle(
      color: ink,
      fontSize: pixelBodyMediumSize * scale,
      height: 1.4,
      letterSpacing: 0,
      fontWeight: FontWeight.w500,
    ),
    bodySmall: TextStyle(
      color: muted,
      fontSize: pixelBodySmallSize * scale,
      height: 1.38,
      letterSpacing: 0,
      fontWeight: FontWeight.w500,
    ),
    labelLarge: TextStyle(
      color: ink,
      fontSize: pixelLabelLargeSize * scale,
      height: 1.3,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.05,
    ),
    labelSmall: TextStyle(
      color: muted,
      fontSize: pixelLabelSmallSize * scale,
      height: 1.35,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.05,
    ),
    titleMedium: TextStyle(
      color: ink,
      fontSize: pixelTitleMediumSize * scale,
      height: 1.28,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
    ),
    titleLarge: TextStyle(
      color: ink,
      fontSize: pixelTitleLargeSize * scale,
      height: 1.28,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
    ),
    headlineSmall: TextStyle(
      color: ink,
      fontFamily: pixelDisplayFontFamily,
      fontSize: pixelHeadlineSmallSize * scale,
      height: 1.15,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.2,
    ),
    headlineMedium: TextStyle(
      color: ink,
      fontFamily: pixelDisplayFontFamily,
      fontSize: pixelHeadlineMediumSize * scale,
      height: 1.15,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.2,
    ),
  );
  final resolvedTextTheme = textTheme
      .apply(
        fontFamily: pixelFontFamily,
        fontFamilyFallback: pixelFontFallbackFamilies,
      )
      .copyWith(
        headlineSmall: textTheme.headlineSmall?.copyWith(
          fontFamilyFallback: pixelFontFallbackFamilies,
        ),
        headlineMedium: textTheme.headlineMedium?.copyWith(
          fontFamilyFallback: pixelFontFallbackFamilies,
        ),
      );

  return base.copyWith(
    textTheme: resolvedTextTheme,
    primaryTextTheme: base.primaryTextTheme.apply(
      fontFamily: pixelFontFamily,
      fontFamilyFallback: pixelFontFallbackFamilies,
      bodyColor: ink,
      displayColor: ink,
    ),

    dividerTheme: DividerThemeData(
      color: border.color,
      thickness: highContrast ? 1.5 : 1,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: panel,
      foregroundColor: ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: pixelDisplayFontFamily,
        fontFamilyFallback: pixelFontFallbackFamilies,
        color: ink,
        fontSize: pixelHeadlineSmallSize * scale,
        height: 1.15,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.2,
      ),

      toolbarHeight: 52,
      actionsPadding: const EdgeInsets.only(right: 8),
    ),
    cardTheme: CardThemeData(
      color: panel,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: square,
    ),
    checkboxTheme: CheckboxThemeData(
      checkColor: WidgetStatePropertyAll(scheme.onPrimary),
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return muted.withValues(alpha: 0.18);
        }
        if (states.contains(WidgetState.selected) ||
            states.contains(WidgetState.pressed) ||
            states.contains(WidgetState.focused)) {
          return primary;
        }
        return Colors.transparent;
      }),
      side: border,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: panel,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: square,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      actionsPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      titleTextStyle: TextStyle(
        color: ink,
        fontFamily: pixelDisplayFontFamily,
        fontFamilyFallback: pixelFontFallbackFamilies,
        fontSize: pixelHeadlineSmallSize * scale,
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
      contentTextStyle: TextStyle(
        color: ink,
        fontFamily: pixelFontFamily,
        fontFamilyFallback: pixelFontFallbackFamilies,
      ),
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
      labelStyle: TextStyle(
        color: muted,
        fontFamilyFallback: pixelFontFallbackFamilies,
      ),
      floatingLabelStyle: TextStyle(
        color: primary,
        fontFamilyFallback: pixelFontFallbackFamilies,
        fontSize: pixelLabelLargeSize * scale,
        height: 1.55,
        fontWeight: FontWeight.w600,
      ),
      hintStyle: TextStyle(
        color: muted,
        fontFamilyFallback: pixelFontFallbackFamilies,
      ),
      helperStyle: TextStyle(
        color: muted,
        fontFamilyFallback: pixelFontFallbackFamilies,
        height: 1.45,
      ),
      errorStyle: TextStyle(
        color: scheme.error,
        fontFamilyFallback: pixelFontFallbackFamilies,
        height: 1.45,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(style: filledButtonStyle),
    outlinedButtonTheme: OutlinedButtonThemeData(style: outlinedButtonStyle),
    textButtonTheme: TextButtonThemeData(style: textButtonStyle),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        animationDuration: Duration.zero,
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return Colors.transparent;
          }
          if (states.contains(WidgetState.pressed)) {
            return scheme.primaryContainer;
          }
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return raised;
          }
          return raised.withValues(alpha: dark ? 0.32 : 0.22);
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return muted.withValues(alpha: 0.42);
          }
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused) ||
              states.contains(WidgetState.pressed)) {
            return primary;
          }
          return muted;
        }),
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) {
            return primary.withValues(alpha: 0.14);
          }
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return primary.withValues(alpha: 0.08);
          }
          return Colors.transparent;
        }),
        side: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused) ||
              states.contains(WidgetState.pressed)) {
            return BorderSide(color: primary);
          }
          return const BorderSide(color: Colors.transparent);
        }),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: WidgetStatePropertyAll(buttonShape),
        minimumSize: const WidgetStatePropertyAll(Size(40, 40)),
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
      minTileHeight: 44,
      minVerticalPadding: 4,
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
      checkmarkColor: primary,
      labelStyle: resolvedTextTheme.labelLarge,
      side: border,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        animationDuration: Duration.zero,
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return dark ? pixelPrimaryContainer : pixelLightPrimaryContainer;
          }
          if (states.contains(WidgetState.pressed)) {
            return primary.withValues(alpha: 0.12);
          }
          return Colors.transparent;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected) ||
              states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return primary;
          }
          return ink;
        }),
        side: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected) ||
              states.contains(WidgetState.focused)) {
            return BorderSide(color: primary);
          }
          return border;
        }),
        shape: WidgetStatePropertyAll(buttonShape),
        textStyle: WidgetStatePropertyAll(buttonTextStyle),
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

class PixelToolbarIconButton extends StatelessWidget {
  const PixelToolbarIconButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    required this.icon,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final Widget icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: IconButton(tooltip: tooltip, onPressed: onPressed, icon: icon),
    );
  }
}

class PixelThemeToggle extends StatelessWidget {
  const PixelThemeToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = PixelThemeScope.maybeOf(context);
    if (scope == null) return const SizedBox.shrink();
    final dark = scope.mode == ThemeMode.dark;
    return PixelToolbarIconButton(
      key: const Key('theme-toggle'),
      tooltip: dark ? 'Use light theme' : 'Use dark theme',
      onPressed: scope.toggle,
      icon: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
    );
  }
}
