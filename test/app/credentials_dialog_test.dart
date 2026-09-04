import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gift/src/app/credentials_dialog.dart';
import 'package:gift/src/backend/credentials.dart';

void main() {
  testWidgets('adds an HTTPS Git account without exposing its token', (
    tester,
  ) async {
    final store = InMemoryGitCredentialStore();
    await tester.pumpWidget(MaterialApp(home: CredentialsDialog(store: store)));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('credential-host')),
      'github.com',
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('credential-account-name')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.byKey(const Key('credential-account-name')),
      'Personal GitHub',
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('credential-secret')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.byKey(const Key('credential-secret')),
      'private-token',
    );
    await tester.tap(find.byKey(const Key('credential-save')));
    await tester.pumpAndSettle();

    expect(find.text('Personal GitHub'), findsOneWidget);
    expect(find.text('private-token'), findsNothing);
    expect((await store.listAccounts()).single.host, 'github.com');
    expect(
      await store.readSecret((await store.listAccounts()).single.id),
      'private-token',
    );
  });
}
