import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gift/src/app/gift_app.dart';

import 'package:gift/src/app/pixel_theme.dart';

void main() {
  testWidgets('uses the GIFT product identity', (tester) async {
    await tester.pumpWidget(const GiftApp());

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.title, 'gift');
    expect(find.text('GIFT'), findsOneWidget);
    expect(find.bySemanticsLabel('GIFT pixel mascot'), findsOneWidget);
  });

  test('uses square pixel button states', () {
    final theme = buildPixelTheme();
    final filled = theme.filledButtonTheme.style!;
    final outlined = theme.outlinedButtonTheme.style!;
    final icon = theme.iconButtonTheme.style!;

    expect(
      (filled.shape!.resolve(const {})! as RoundedRectangleBorder).borderRadius,
      BorderRadius.zero,
    );
    expect(filled.backgroundColor!.resolve(const {}), pixelMint);
    expect(outlined.backgroundColor!.resolve(const {}), Colors.transparent);
    expect(icon.side!.resolve(const {})!.color, isNot(pixelMuted));
  });
}
