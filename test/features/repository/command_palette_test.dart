import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gift/src/features/repository/command_palette.dart';

void main() {
  final actions = [
    CommandPaletteAction(
      id: 'history',
      label: 'Open history',
      icon: Icons.history,
      keywords: const ['log', 'commits'],
      onInvoke: () {},
    ),
    CommandPaletteAction(
      id: 'refresh',
      label: 'Refresh changes',
      icon: Icons.refresh,
      onInvoke: () {},
    ),
  ];

  test('matches every query token across labels and keywords', () {
    expect(
      filterCommandPaletteActions(
        actions,
        '  COMMITS history ',
      ).map((action) => action.id),
      ['history'],
    );
    expect(filterCommandPaletteActions(actions, 'missing'), isEmpty);
  });

  testWidgets('invokes the selected action from the dialog', (tester) async {
    var invoked = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showCommandPalette(
              context,
              actions: [
                CommandPaletteAction(
                  id: 'refresh',
                  label: 'Refresh changes',
                  icon: Icons.refresh,
                  onInvoke: () => invoked = true,
                ),
              ],
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('command-palette-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('command-palette-refresh')));
    await tester.pumpAndSettle();

    expect(invoked, isTrue);
  });
}
