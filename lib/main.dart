import 'package:branchline/src/app/branchline_app.dart';
import 'package:branchline/src/features/repository/recent_repository_store.dart';
import 'package:branchline/src/rust/frb_git_gateway.dart';
import 'package:branchline/src/rust/generated/frb_generated.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  final preferences = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      child: BranchlineApp(
        gateway: const FrbGitGateway(),
        recentStore: RecentRepositoryStore(preferences),
        preferences: preferences,
        autoInitialize: true,
      ),
    ),
  );
}
