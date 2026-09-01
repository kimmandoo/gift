import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BranchlineApp extends ConsumerWidget {
  const BranchlineApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Branchline',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: null,
            child: const Text('Open Repository'),
          ),
        ),
      ),
    );
  }
}
