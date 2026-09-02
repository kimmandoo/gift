import 'package:flutter/material.dart';

import 'pixel_theme.dart';

import 'package:gitflu/src/features/repository/recent_repository_store.dart';
import 'package:gitflu/src/features/repository/welcome_screen.dart';
import 'package:gitflu/src/backend/dart_git_gateway.dart';
import 'package:gitflu/src/backend/git_gateway.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GitfluApp extends StatelessWidget {
  const GitfluApp({
    super.key,
    this.gateway,
    this.recentStore,
    this.preferences,
    this.autoInitialize = false,
  });

  final GitGateway? gateway;
  final RecentRepositoryStore? recentStore;
  final SharedPreferences? preferences;
  final bool autoInitialize;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'gitflu',
      theme: buildPixelTheme(),
      home: WelcomeScreen(
        gateway: gateway ?? DartGitGateway(),
        recentStore: recentStore ?? RecentRepositoryStore.inMemory(),
        preferences: preferences,
        autoInitialize: autoInitialize,
      ),
    );
  }
}
