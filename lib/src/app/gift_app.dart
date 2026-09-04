import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gift/src/app/app_preferences.dart';
import 'package:gift/src/app/pixel_theme.dart';
import 'package:gift/src/backend/dart_git_gateway.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:gift/src/app/secure_credential_store.dart';
import 'package:gift/src/backend/credentials.dart';
import 'package:gift/src/features/repository/recent_repository_store.dart';
import 'package:gift/src/features/repository/welcome_screen.dart';
import 'package:gift/src/features/repository/workspace_controller.dart';
import 'package:gift/src/features/repository/workspace_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GiftApp extends StatefulWidget {
  const GiftApp({
    super.key,
    this.gateway,
    this.recentStore,
    this.workspaceController,
    this.preferences,
    this.autoInitialize = false,
    this.credentialStore,
  });

  static const themeModeKey = 'theme_mode';

  final GitGateway? gateway;
  final RecentRepositoryStore? recentStore;
  final WorkspaceController? workspaceController;
  final SharedPreferences? preferences;
  final GitCredentialStore? credentialStore;
  final bool autoInitialize;

  @override
  State<GiftApp> createState() => _GiftAppState();
}

class _GiftAppState extends State<GiftApp> {
  late GiftPreferences _preferences;
  late final GitGateway _gateway;
  late final RecentRepositoryStore _recentStore;
  late final GitCredentialStore _credentialStore;
  late final WorkspaceController _workspaceController;
  late final bool _ownsWorkspaceController;

  @override
  void initState() {
    super.initState();
    final loaded = widget.preferences == null
        ? const GiftPreferencesLoadResult(preferences: GiftPreferences.defaults)
        : GiftPreferences.load(widget.preferences!);
    _preferences = loaded.preferences;
    if (widget.preferences != null && loaded.needsRewrite) {
      unawaited(_preferences.save(widget.preferences!));
    }
    _credentialStore =
        widget.credentialStore ??
        (widget.preferences == null
            ? InMemoryGitCredentialStore()
            : SecureGitCredentialStore(preferences: widget.preferences!));
    _gateway =
        widget.gateway ??
        DartGitGateway(
          credentialResolver: StoreGitCredentialResolver(_credentialStore),
        );
    _recentStore =
        widget.recentStore ??
        (widget.preferences == null
            ? RecentRepositoryStore.inMemory()
            : RecentRepositoryStore(widget.preferences!));
    _ownsWorkspaceController = widget.workspaceController == null;
    _workspaceController =
        widget.workspaceController ??
        WorkspaceController(
          gateway: _gateway,
          store: widget.preferences == null
              ? WorkspaceStore.inMemory()
              : WorkspaceStore(widget.preferences!),
          recentStore: _recentStore,
          changesPollInterval: _preferences.refreshInterval,
        );
  }

  @override
  void dispose() {
    if (_ownsWorkspaceController) _workspaceController.dispose();
    super.dispose();
  }

  Future<void> _updatePreferences(GiftPreferences next) async {
    if (!mounted) return;
    setState(() => _preferences = next);
    if (widget.preferences != null) {
      await next.save(widget.preferences!);
    }
  }

  Future<void> _toggleTheme() {
    final next = _preferences.themeMode == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    return _updatePreferences(_preferences.copyWith(themeMode: next));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'gift',
      debugShowCheckedModeBanner: false,
      locale: const Locale('en'),
      supportedLocales: const [Locale('en')],
      theme: buildPixelTheme(
        brightness: Brightness.light,
        uiScale: _preferences.uiScale,
        highContrast: _preferences.highContrast,
        colorSafeGraph: _preferences.colorSafeGraph,
      ),
      darkTheme: buildPixelTheme(
        uiScale: _preferences.uiScale,
        highContrast: _preferences.highContrast,
        colorSafeGraph: _preferences.colorSafeGraph,
      ),
      themeMode: _preferences.themeMode,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        final baseTextScale = media.textScaler.scale(1);
        return MediaQuery(
          data: media.copyWith(
            textScaler: TextScaler.linear(baseTextScale),
            disableAnimations: _preferences.reducedMotion,
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: AppPreferencesScope(
        preferences: _preferences,
        update: _updatePreferences,
        child: PixelThemeScope(
          mode: _preferences.themeMode,
          toggle: _toggleTheme,
          child: WelcomeScreen(
            gateway: _gateway,
            recentStore: _recentStore,
            credentialStore: _credentialStore,
            workspaceController: _workspaceController,
            preferences: widget.preferences,
            autoInitialize: widget.autoInitialize,
          ),
        ),
      ),
    );
  }
}
