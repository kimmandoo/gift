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

  test('uses a restrained pixel button hierarchy', () {
    final theme = buildPixelTheme();
    final filled = theme.filledButtonTheme.style!;
    final outlined = theme.outlinedButtonTheme.style!;
    final icon = theme.iconButtonTheme.style!;

    expect(
      (filled.shape!.resolve(const {})! as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(4),
    );
    expect(filled.backgroundColor!.resolve(const {}), pixelMint);
    expect(
      pixelProminentButtonStyle.textStyle!.resolve(const {})!.fontFamily,
      pixelDisplayFontFamily,
    );
    expect(outlined.backgroundColor!.resolve(const {}), Colors.transparent);
    expect(outlined.foregroundColor!.resolve(const {}), pixelInk);
    expect(icon.backgroundColor!.resolve(const {}), Colors.transparent);
    expect(icon.side, isNull);
  });
}
