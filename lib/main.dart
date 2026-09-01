import 'package:branchline/src/app/branchline_app.dart';
import 'package:branchline/src/rust/generated/frb_generated.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  runApp(const ProviderScope(child: BranchlineApp()));
}
