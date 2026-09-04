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

  testWidgets('creates a browser OAuth account without storing a token', (
    tester,
  ) async {
    final store = InMemoryGitCredentialStore();
    await tester.pumpWidget(
      MaterialApp(
        home: CredentialsDialog(
          store: store,
          oauthGateway: _FakeOAuthGateway(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('oauth-github')));
    await tester.pumpAndSettle();

    final saved = (await store.listAccounts()).single;
    expect(saved.provider, GitCredentialProvider.github);
    expect(saved.kind, GitCredentialKind.webOAuth);
    expect(await store.readSecret(saved.id), isNull);
    expect(find.text('Signed in with GitHub in your browser.'), findsOneWidget);
  });

  testWidgets('searches accounts and keeps add flow out of the list', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(720, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = InMemoryGitCredentialStore(
      records: [
        GitCredentialRecord(
          account: GitCredentialAccount(
            id: 'work',
            provider: GitCredentialProvider.github,
            host: 'github.com',
            accountName: 'Work GitHub',
            kind: GitCredentialKind.httpsToken,
            username: 'git',
            isDefault: true,
          ),
          secret: 'work-token',
        ),
        GitCredentialRecord(
          account: GitCredentialAccount(
            id: 'personal',
            provider: GitCredentialProvider.gitlab,
            host: 'gitlab.com',
            accountName: 'Personal GitLab',
            kind: GitCredentialKind.httpsToken,
            username: 'git',
          ),
          secret: 'personal-token',
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp(home: CredentialsDialog(store: store)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('credential-editor')), findsNothing);
    expect(find.text('2 saved'), findsOneWidget);
    expect(find.text('Work GitHub'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Personal GitLab'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Personal GitLab'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('credential-search')),
      'gitlab',
    );
    await tester.pump();
    expect(find.text('Personal GitLab'), findsOneWidget);
    expect(find.text('Work GitHub'), findsNothing);

    await tester.scrollUntilVisible(
      find.byKey(const Key('credential-new')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('credential-new')));
    await tester.pump();
    expect(find.byKey(const Key('credential-editor')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('credential-editor')),
        matching: find.text('Add account'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('credential-cancel')));
    await tester.pump();
    expect(find.byKey(const Key('credential-editor')), findsNothing);
  });

  testWidgets('opens a compact editor from an account row', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = InMemoryGitCredentialStore(
      records: [
        GitCredentialRecord(
          account: GitCredentialAccount(
            id: 'work',
            provider: GitCredentialProvider.github,
            host: 'github.com',
            accountName: 'Work GitHub',
            kind: GitCredentialKind.httpsToken,
            username: 'git',
          ),
          secret: 'work-token',
        ),
      ],
    );
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.2)),
        child: MaterialApp(home: CredentialsDialog(store: store)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Work GitHub'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('credential-actions:work')), findsOneWidget);
    final accountTile = tester.widget<ListTile>(
      find.ancestor(
        of: find.text('Work GitHub'),
        matching: find.byType(ListTile),
      ),
    );
    accountTile.onTap!();
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const Key('credential-editor')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('credential-editor')), findsOneWidget);
    expect(find.text('Edit account'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FakeOAuthGateway implements GitCredentialOAuthGateway {
  @override
  Future<GitCredentialOAuthResult> loginWithBrowser(
    GitCredentialProvider provider,
  ) async => GitCredentialOAuthResult(
    provider: provider,
    host: provider == GitCredentialProvider.github
        ? 'github.com'
        : 'gitlab.com',
    accountName: '${provider.name} browser account',
  );
}
