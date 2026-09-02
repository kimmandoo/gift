import 'package:flutter/material.dart';
import 'package:gitflu/src/app/pixel_theme.dart';
import 'package:gitflu/src/backend/dart_git_gateway.dart';
import 'package:gitflu/src/backend/git_gateway.dart';
import 'package:gitflu/src/features/repository/recent_repository_store.dart';
import 'package:gitflu/src/features/repository/welcome_screen.dart';
import 'package:gitflu/src/features/repository/workspace_controller.dart';
import 'package:gitflu/src/features/repository/workspace_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GitfluApp extends StatefulWidget {
  const GitfluApp({
    super.key,
    this.gateway,
    this.recentStore,
    this.workspaceController,
    this.preferences,
    this.autoInitialize = false,
  });

  static const themeModeKey = 'theme_mode';

  final GitGateway? gateway;
  final RecentRepositoryStore? recentStore;
  final WorkspaceController? workspaceController;
  final SharedPreferences? preferences;
  final bool autoInitialize;

  @override
  State<GitfluApp> createState() => _GitfluAppState();
}

class _GitfluAppState extends State<GitfluApp> {
  late ThemeMode _themeMode;
  late final GitGateway _gateway;
  late final RecentRepositoryStore _recentStore;
  late final WorkspaceController _workspaceController;
  late final bool _ownsWorkspaceController;

  @override
  void initState() {
    super.initState();
    _themeMode =
        widget.preferences?.getString(GitfluApp.themeModeKey) == 'light'
        ? ThemeMode.light
        : ThemeMode.dark;
    _gateway = widget.gateway ?? DartGitGateway();
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
        );
  }

  @override
  void dispose() {
    if (_ownsWorkspaceController) _workspaceController.dispose();
    super.dispose();
  }

  Future<void> _toggleTheme() async {
    final next = _themeMode == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    setState(() => _themeMode = next);
    await widget.preferences?.setString(
      GitfluApp.themeModeKey,
      next == ThemeMode.light ? 'light' : 'dark',
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'gitflu',
      debugShowCheckedModeBanner: false,
      theme: buildPixelTheme(brightness: Brightness.light),
      darkTheme: buildPixelTheme(),
      themeMode: _themeMode,
      home: PixelThemeScope(
        mode: _themeMode,
        toggle: _toggleTheme,
        child: WelcomeScreen(
          gateway: _gateway,
          recentStore: _recentStore,
          workspaceController: _workspaceController,
          preferences: widget.preferences,
          autoInitialize: widget.autoInitialize,
        ),
      ),
    );
  }
}
