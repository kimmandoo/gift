import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/features/repository/context_actions.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'secondary click, keyboard, and overflow expose one bounded action menu',
    (tester) async {
      addTearDown(tester.view.reset);
      tester.view.physicalSize = const Size(320, 240);
      tester.view.devicePixelRatio = 1;
      final repository = const RepositoryOpened(
        repositoryId: RepositoryId(value: 'actions-repository'),
        root: '/workspace/project',
      );
      final snapshot = ContextActionSnapshot(
        repository: repository,
        target: ContextActionTarget.change(path: 'src/app.dart'),
        fingerprint: 'status-a',
      );
      final focusNode = FocusNode(debugLabel: 'change-action-target');
      addTearDown(focusNode.dispose);
      final invoked = <ContextActionId>[];
      final actions = _actions(snapshot);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topRight,
              child: ContextActionMenu(
                focusNode: focusNode,
                snapshot: snapshot,
                actions: actions,
                onAction: (action) => invoked.add(action.id),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      key: Key('change-action-target'),
                      width: 40,
                      height: 40,
                    ),
                    ContextActionMenuButton(
                      key: const Key('change-action-overflow'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      final target = find.byKey(const Key('change-action-target'));
      final gesture = await tester.startGesture(
        tester.getCenter(target),
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('Inspect'), findsOneWidget);
      expect(find.text('Stage'), findsOneWidget);
      expect(find.text('Discard'), findsOneWidget);
      expect(find.text('Git is already running.'), findsOneWidget);
      expect(tester.getRect(find.text('Stage')).right, lessThanOrEqualTo(320));
      await tester.tap(find.text('Stage'));
      await tester.pumpAndSettle();
      expect(focusNode.hasFocus, isTrue);

      await tester.tapAt(tester.getCenter(target));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.f10);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.f10);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(find.text('Stage'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Stage'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pumpAndSettle();
      expect(find.text('Stage'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('change-action-overflow')));
      await tester.pumpAndSettle();
      expect(find.text('Stage'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(invoked, [ContextActionId.stage]);
    },
  );

  testWidgets('a refreshed snapshot dismisses the old action invocation', (
    tester,
  ) async {
    final repository = const RepositoryOpened(
      repositoryId: RepositoryId(value: 'stale-actions-repository'),
      root: '/workspace/project',
    );
    final first = ContextActionSnapshot(
      repository: repository,
      target: ContextActionTarget.change(path: 'src/app.dart'),
      fingerprint: 'status-a',
    );
    final second = ContextActionSnapshot(
      repository: repository,
      target: ContextActionTarget.change(path: 'src/app.dart'),
      fingerprint: 'status-b',
    );
    final current = ValueNotifier(first);
    addTearDown(current.dispose);
    final focusNode = FocusNode(debugLabel: 'stale-change-action-target');
    addTearDown(focusNode.dispose);
    var invocations = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<ContextActionSnapshot>(
          valueListenable: current,
          builder: (context, snapshot, _) => ContextActionMenu(
            focusNode: focusNode,
            snapshot: snapshot,
            actions: _actions(snapshot),
            onAction: (_) => invocations++,
            child: const SizedBox(
              key: Key('stale-change-action-target'),
              width: 100,
              height: 40,
            ),
          ),
        ),
      ),
    );

    final target = find.byKey(const Key('stale-change-action-target'));
    final gesture = await tester.startGesture(
      tester.getCenter(target),
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();
    current.value = second;
    await tester.pump();
    await tester.tap(find.text('Stage'));
    await tester.pumpAndSettle();

    expect(invocations, 0);
    expect(focusNode.hasFocus, isTrue);
    expect(find.text('Stage'), findsNothing);
  });
}

List<ContextActionDescriptor> _actions(ContextActionSnapshot snapshot) => [
  ContextActionDescriptor(
    id: ContextActionId.inspect,
    label: 'Inspect',
    icon: Icons.visibility_outlined,
    group: ContextActionGroup.inspect,
    route: ContextActionRoute.inspect,
    snapshot: snapshot,
  ),
  ContextActionDescriptor(
    id: ContextActionId.stage,
    label: 'Stage',
    icon: Icons.add,
    group: ContextActionGroup.workflow,
    route: ContextActionRoute.stage,
    snapshot: snapshot,
  ),
  ContextActionDescriptor(
    id: ContextActionId.discard,
    label: 'Discard',
    icon: Icons.delete_outline,
    group: ContextActionGroup.destructive,
    route: ContextActionRoute.discard,
    snapshot: snapshot,
    enabled: false,
    disabledReason: 'Git is already running.',
  ),
];
