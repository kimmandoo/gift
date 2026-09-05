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

  test('configures a bundled Korean font fallback', () {
    final theme = buildPixelTheme();

    expect(
      theme.textTheme.bodyMedium?.fontFamilyFallback,
      contains(pixelKoreanFontFamily),
    );
    expect(
      theme.textTheme.headlineMedium?.fontFamilyFallback,
      contains(pixelKoreanFontFamily),
    );
  });
}
