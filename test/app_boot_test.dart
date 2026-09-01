import 'package:branchline/src/app/branchline_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('boots into the repository welcome screen', (tester) async {
    await tester.pumpWidget(const BranchlineApp());
    expect(find.text('Open Repository'), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
