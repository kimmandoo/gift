import 'package:flutter/material.dart';

import 'pixel_theme.dart';

import 'package:branchline/src/features/repository/recent_repository_store.dart';
import 'package:branchline/src/features/repository/welcome_screen.dart';
import 'package:branchline/src/backend/dart_git_gateway.dart';
import 'package:branchline/src/backend/git_gateway.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BranchlineApp extends StatelessWidget {
  const BranchlineApp({
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
      title: 'Branchline',
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
