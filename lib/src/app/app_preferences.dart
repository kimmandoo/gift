import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _minimumUiScale = 0.8;
const _maximumUiScale = 1.6;
const _minimumRefreshSeconds = 1;
const _maximumRefreshSeconds = 300;

/// Versioned, validated application preferences.
class GiftPreferences {
  const GiftPreferences({
    required this.uiScale,
    required this.reducedMotion,
    required this.highContrast,
    required this.colorSafeGraph,
    required this.shortcuts,
    required this.defaultBranch,
    required this.defaultRemote,
    required this.refreshInterval,
    required this.themeMode,
  });

  static const storageKey = 'gift.preferences';
  static const currentVersion = 1;
  static const legacyThemeModeKey = 'theme_mode';

  static const defaultShortcutBindings = <String, String>{
    'refresh': 'ctrl+r',
    'history': 'ctrl+h',
    'commit': 'ctrl+enter',
    'fileHistory': 'ctrl+shift+h',
    'focusSearch': 'ctrl+f',
    'cancel': 'escape',
    'nextCommit': 'arrowdown',
    'previousCommit': 'arrowup',
    'nextTab': 'ctrl+tab',
    'previousTab': 'ctrl+shift+tab',
    'branch': 'ctrl+shift+b',
    'remote': 'ctrl+shift+r',
    'commandPalette': 'ctrl+k',
  };

  static const defaults = GiftPreferences(
    uiScale: 1,
    reducedMotion: false,
    highContrast: false,
    colorSafeGraph: true,
    shortcuts: defaultShortcutBindings,
    defaultBranch: null,
    defaultRemote: null,
    refreshInterval: Duration(seconds: 30),
    themeMode: ThemeMode.dark,
  );

  final double uiScale;
  final bool reducedMotion;
  final bool highContrast;
  final bool colorSafeGraph;
  final Map<String, String> shortcuts;
  final String? defaultBranch;
  final String? defaultRemote;
  final Duration refreshInterval;
  final ThemeMode themeMode;

  GiftPreferences copyWith({
    double? uiScale,
    bool? reducedMotion,
    bool? highContrast,
    bool? colorSafeGraph,
    Map<String, String>? shortcuts,
    String? defaultBranch,
    bool clearDefaultBranch = false,
    String? defaultRemote,
    bool clearDefaultRemote = false,
    Duration? refreshInterval,
    ThemeMode? themeMode,
  }) {
    return GiftPreferences._validated(
      uiScale: uiScale ?? this.uiScale,
      reducedMotion: reducedMotion ?? this.reducedMotion,
      highContrast: highContrast ?? this.highContrast,
      colorSafeGraph: colorSafeGraph ?? this.colorSafeGraph,
      shortcuts: shortcuts ?? this.shortcuts,
      defaultBranch: clearDefaultBranch
          ? null
          : defaultBranch ?? this.defaultBranch,
      defaultRemote: clearDefaultRemote
          ? null
          : defaultRemote ?? this.defaultRemote,
      refreshInterval: refreshInterval ?? this.refreshInterval,
      themeMode: themeMode ?? this.themeMode,
    );
  }

  String shortcut(String id) => shortcuts[id] ?? '';

  /// Returns canonical binding values that are assigned to more than one id.
  Map<String, Set<String>> get shortcutConflicts {
    final idsByBinding = <String, Set<String>>{};
    for (final entry in shortcuts.entries) {
      final value = _canonicalShortcut(entry.value);
      if (value.isEmpty) continue;
      idsByBinding.putIfAbsent(value, () => <String>{}).add(entry.key);
    }
    return Map.unmodifiable({
      for (final entry in idsByBinding.entries)
        if (entry.value.length > 1) entry.key: Set.unmodifiable(entry.value),
    });
  }

  Map<String, Object?> toJson() => {
    'version': currentVersion,
    'uiScale': uiScale,
    'reducedMotion': reducedMotion,
    'highContrast': highContrast,
    'colorSafeGraph': colorSafeGraph,
    'shortcuts': shortcuts,
    'defaultBranch': defaultBranch,
    'defaultRemote': defaultRemote,
    'refreshIntervalSeconds': refreshInterval.inSeconds,
    'themeMode': themeMode.name,
  };

  Future<bool> save(SharedPreferences storage) async {
    final written = await storage.setString(storageKey, jsonEncode(toJson()));
    if (written) {
      // Keep the legacy theme key readable for older desktop builds while
      // the versioned payload becomes the source of truth.
      await storage.setString(legacyThemeModeKey, themeMode.name);
    }
    return written;
  }

  static GiftPreferencesLoadResult load(SharedPreferences storage) {
    final legacyTheme = _themeModeFromValue(
      storage.getString(legacyThemeModeKey),
    );
    final encoded = storage.getString(storageKey);
    if (encoded == null) {
      return GiftPreferencesLoadResult(
        preferences: defaults.copyWith(
          themeMode: legacyTheme ?? defaults.themeMode,
        ),
        migratedLegacyData: legacyTheme != null,
        needsRewrite: legacyTheme != null,
      );
    }

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) {
        throw const FormatException('preference root was not an object');
      }
      final version = decoded['version'];
      if (version is! int || version > currentVersion || version < 1) {
        throw const FormatException('unsupported preference version');
      }
      var recovered = false;
      final uiScale = _doubleInRange(decoded['uiScale']);
      if (uiScale == null && decoded.containsKey('uiScale')) recovered = true;
      final refreshSeconds = _intInRange(decoded['refreshIntervalSeconds']);
      if (refreshSeconds == null &&
          decoded.containsKey('refreshIntervalSeconds')) {
        recovered = true;
      }
      final shortcuts = _readShortcuts(decoded['shortcuts']);
      if (shortcuts == null && decoded.containsKey('shortcuts')) {
        recovered = true;
      }
      final theme = _themeModeFromValue(decoded['themeMode']);
      if (theme == null && decoded.containsKey('themeMode')) recovered = true;
      final usesLegacyTheme = theme == null && legacyTheme != null;
      final branch = _optionalText(decoded['defaultBranch']);
      final remote = _optionalText(decoded['defaultRemote']);
      if (decoded.containsKey('defaultBranch') &&
          decoded['defaultBranch'] != null &&
          branch == null) {
        recovered = true;
      }
      if (decoded.containsKey('defaultRemote') &&
          decoded['defaultRemote'] != null &&
          remote == null) {
        recovered = true;
      }
      for (final key in const [
        'reducedMotion',
        'highContrast',
        'colorSafeGraph',
      ]) {
        if (decoded.containsKey(key) && decoded[key] is! bool) recovered = true;
      }
      return GiftPreferencesLoadResult(
        preferences: GiftPreferences._validated(
          uiScale: uiScale ?? defaults.uiScale,
          reducedMotion: decoded['reducedMotion'] is bool
              ? decoded['reducedMotion'] as bool
              : defaults.reducedMotion,
          highContrast: decoded['highContrast'] is bool
              ? decoded['highContrast'] as bool
              : defaults.highContrast,
          colorSafeGraph: decoded['colorSafeGraph'] is bool
              ? decoded['colorSafeGraph'] as bool
              : defaults.colorSafeGraph,
          shortcuts: shortcuts ?? defaults.shortcuts,
          defaultBranch: branch,
          defaultRemote: remote,
          refreshInterval: Duration(
            seconds: refreshSeconds ?? defaults.refreshInterval.inSeconds,
          ),
          themeMode: theme ?? legacyTheme ?? defaults.themeMode,
        ),
        recoveredCorruptData: recovered,
        migratedLegacyData: usesLegacyTheme,
        needsRewrite: recovered || version != currentVersion || usesLegacyTheme,
      );
    } on Object {
      return GiftPreferencesLoadResult(
        preferences: defaults.copyWith(
          themeMode: legacyTheme ?? defaults.themeMode,
        ),
        recoveredCorruptData: true,
        migratedLegacyData: legacyTheme != null,
        needsRewrite: true,
      );
    }
  }

  GiftPreferences._validated({
    required double uiScale,
    required this.reducedMotion,
    required this.highContrast,
    required this.colorSafeGraph,
    required Map<String, String> shortcuts,
    required String? defaultBranch,
    required String? defaultRemote,
    required Duration refreshInterval,
    required this.themeMode,
  }) : uiScale = uiScale.clamp(_minimumUiScale, _maximumUiScale).toDouble(),
       shortcuts = Map.unmodifiable({
         ...defaultShortcutBindings,
         for (final entry in shortcuts.entries)
           entry.key: _canonicalShortcut(entry.value),
       }),
       defaultBranch = _normalizeText(defaultBranch),
       defaultRemote = _normalizeText(defaultRemote),
       refreshInterval = Duration(
         seconds: refreshInterval.inSeconds.clamp(
           _minimumRefreshSeconds,
           _maximumRefreshSeconds,
         ),
       );

  static double? _doubleInRange(Object? value) {
    if (value is! num) return null;
    final number = value.toDouble();
    return number >= _minimumUiScale && number <= _maximumUiScale
        ? number
        : null;
  }

  static int? _intInRange(Object? value) {
    if (value is! num || value % 1 != 0) return null;
    final number = value.toInt();
    return number >= _minimumRefreshSeconds && number <= _maximumRefreshSeconds
        ? number
        : null;
  }

  static Map<String, String>? _readShortcuts(Object? value) {
    if (value is! Map) return null;
    final result = <String, String>{};
    for (final entry in value.entries) {
      if (entry.key is! String || entry.value is! String) return null;
      result[entry.key as String] = entry.value as String;
    }
    return result;
  }

  static ThemeMode? _themeModeFromValue(Object? value) => switch (value) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    'system' => ThemeMode.system,
    _ => null,
  };

  static String? _optionalText(Object? value) {
    if (value == null) return null;
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  static String? _normalizeText(String? value) => _optionalText(value);
}

class GiftPreferencesLoadResult {
  const GiftPreferencesLoadResult({
    required this.preferences,
    this.recoveredCorruptData = false,
    this.migratedLegacyData = false,
    this.needsRewrite = false,
  });

  final GiftPreferences preferences;
  final bool recoveredCorruptData;
  final bool migratedLegacyData;
  final bool needsRewrite;
}

String _canonicalShortcut(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');

/// Formats a stored shortcut binding for visible keyboard hints.
String formatShortcut(String value) {
  final tokens = _canonicalShortcut(value).split('+');
  if (tokens.length == 1 && tokens.single.isEmpty) return 'Unassigned';
  return tokens
      .map(
        (token) => switch (token) {
          'ctrl' || 'control' => 'Ctrl',
          'shift' => 'Shift',
          'alt' || 'option' => 'Alt',
          'meta' || 'cmd' || 'command' => 'Cmd',
          'enter' || 'return' => 'Enter',
          'escape' || 'esc' => 'Esc',
          'tab' => 'Tab',
          'arrowup' => 'Arrow Up',
          'arrowdown' => 'Arrow Down',
          'arrowleft' => 'Arrow Left',
          'arrowright' => 'Arrow Right',
          'space' => 'Space',
          'backspace' => 'Backspace',
          'delete' => 'Delete',
          _ => token.length == 1 ? token.toUpperCase() : token,
        },
      )
      .join('+');
}

/// Parses the canonical shortcut strings accepted by GiftPreferences.
ShortcutActivator? shortcutActivator(String value) {
  final tokens = _canonicalShortcut(value).split('+');
  if (tokens.isEmpty || tokens.last.isEmpty) return null;
  var control = false;
  var shift = false;
  var alt = false;
  var meta = false;
  for (final token in tokens.take(tokens.length - 1)) {
    switch (token) {
      case 'ctrl':
      case 'control':
        control = true;
      case 'shift':
        shift = true;
      case 'alt':
      case 'option':
        alt = true;
      case 'meta':
      case 'cmd':
      case 'command':
        meta = true;
      default:
        return null;
    }
  }
  final key = _shortcutKey(tokens.last);
  return key == null
      ? null
      : SingleActivator(
          key,
          control: control,
          shift: shift,
          alt: alt,
          meta: meta,
        );
}

LogicalKeyboardKey? _shortcutKey(String token) {
  final named = <String, LogicalKeyboardKey>{
    'enter': LogicalKeyboardKey.enter,
    'return': LogicalKeyboardKey.enter,
    'escape': LogicalKeyboardKey.escape,
    'esc': LogicalKeyboardKey.escape,
    'tab': LogicalKeyboardKey.tab,
    'arrowup': LogicalKeyboardKey.arrowUp,
    'arrowdown': LogicalKeyboardKey.arrowDown,
    'arrowleft': LogicalKeyboardKey.arrowLeft,
    'arrowright': LogicalKeyboardKey.arrowRight,
    'space': LogicalKeyboardKey.space,
    'backspace': LogicalKeyboardKey.backspace,
    'delete': LogicalKeyboardKey.delete,
  };
  final namedKey = named[token];
  if (namedKey != null) return namedKey;
  if (token.length != 1) return null;
  final character = token.codeUnitAt(0);
  if (character < 0x61 || character > 0x7a) return null;
  return LogicalKeyboardKey(LogicalKeyboardKey.keyA.keyId + character - 0x61);
}

class AppPreferencesScope extends InheritedWidget {
  const AppPreferencesScope({
    super.key,
    required this.preferences,
    required this.update,
    required super.child,
  });

  final GiftPreferences preferences;
  final Future<void> Function(GiftPreferences) update;

  static AppPreferencesScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppPreferencesScope>()!;

  static AppPreferencesScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppPreferencesScope>();

  @override
  bool updateShouldNotify(AppPreferencesScope oldWidget) =>
      oldWidget.preferences != preferences;
}
