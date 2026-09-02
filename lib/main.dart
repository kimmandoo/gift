import 'package:gitflu/src/app/gitflu_app.dart';
import 'package:gitflu/src/backend/dart_git_gateway.dart';
import 'package:gitflu/src/features/repository/recent_repository_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  // SharedPreferences and file selectors need Flutter's platform bindings
  // before they are used.
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();

  // Keep one gateway for the app. The gateway is the only object the UI needs
  // to know about; Git process details stay inside the Dart backend.
  final gateway = DartGitGateway();
  runApp(
    ProviderScope(
      child: GitfluApp(
        gateway: gateway,
        recentStore: RecentRepositoryStore(preferences),
        preferences: preferences,
        autoInitialize: true,
      ),
    ),
  );
}
