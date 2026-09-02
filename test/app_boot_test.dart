import 'package:branchline/src/app/branchline_app.dart';
import 'package:branchline/src/app/pixel_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('boots into the repository welcome screen', (tester) async {
    await tester.pumpWidget(const BranchlineApp());
    expect(find.text('Open Repository'), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  test('uses the documented pixel theme tokens', () {
    final theme = buildPixelTheme();

    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, pixelCanvas);
    expect(theme.colorScheme.primary, pixelMint);
    expect(theme.colorScheme.error, pixelCoral);
    expect(theme.cardTheme.elevation, 0);
  });
}
