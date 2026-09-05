import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/executor.dart';
import 'package:gift/src/backend/credentials.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:gift/src/backend/setup.dart';
import 'package:gift/src/features/repository/repository_setup_dialog.dart';

import '../../helpers/git_patch_gateway_stub.dart';

void main() {
  testWidgets('keeps clone, initialize, and root mapping controls usable', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final gateway = _SetupGateway();
    await tester.pumpWidget(
      MaterialApp(home: RepositorySetupDialog(gateway: gateway)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Repository setup'), findsOneWidget);
    expect(find.text('Source URL or local path'), findsOneWidget);
    expect(find.text('Clone submodules recursively'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Roots'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('roots-path')),
      Directory.current.path,
    );
    await tester.tap(find.byKey(const Key('discover-roots')));
    await tester.pumpAndSettle();
    expect(gateway.discovered, isTrue);
    expect(find.text('Selected folder'), findsOneWidget);
    expect(find.text('1 Git root found'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('exposes editable browse-assisted absolute folder fields', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: RepositorySetupDialog(gateway: _SetupGateway())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Initialize'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('init-path-browse')), findsOneWidget);
    expect(
      tester
          .element(find.byKey(const Key('init-path')))
          .findAncestorWidgetOfExactType<Tooltip>(),
      isNull,
    );

    await tester.enterText(find.byKey(const Key('init-path')), 'relative/path');
    await tester.pump();
    expect(find.text('Enter an absolute folder path.'), findsOneWidget);
  });
  testWidgets('uses the injected native folder picker and remembers purpose', (
    tester,
  ) async {
    String? pickedInitialDirectory;
    await tester.pumpWidget(
      MaterialApp(
        home: RepositorySetupDialog(
          gateway: _SetupGateway(),
          selectDirectory: ({String? initialDirectory}) async {
            pickedInitialDirectory = initialDirectory;
            return Directory.current.path;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Initialize'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('init-path-browse')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('init-path')))
          .controller!
          .text,
      Directory.current.path,
    );
    expect(pickedInitialDirectory, isNull);
    await tester.tap(find.byKey(const Key('init-path-browse')));
    await tester.pumpAndSettle();
    expect(pickedInitialDirectory, Directory.current.path);
  });
  testWidgets('shows a compact account selector for a clone remote', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final store = InMemoryGitCredentialStore(
      records: [
        GitCredentialRecord(
          account: const GitCredentialAccount(
            id: 'clone-work',
            provider: GitCredentialProvider.generic,
            host: 'example.test',
            accountName: 'Clone work',
            kind: GitCredentialKind.httpsToken,
          ),
          secret: 'clone-token',
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: RepositorySetupDialog(
          gateway: _SetupGateway(),
          credentialStore: store,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('clone-source')),
      'https://example.test/team/repo.git',
    );
    await tester.pumpAndSettle();

    final source = tester.getRect(find.byKey(const Key('clone-source')));
    final account = tester.getRect(find.byKey(const Key('clone-credential')));
    expect(account.top, greaterThanOrEqualTo(source.bottom + 8));
    expect(find.text('Clone account'), findsOneWidget);
    expect(find.text('example.test · default account'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('clone-credential')));
    await tester.pump();
    await tester.tap(find.text('Clone work').last);
    await tester.pumpAndSettle();

    expect((await store.listAccounts()).single.isDefault, isTrue);
  });
}

class _SetupGateway with GitPatchGatewayStub implements GitGateway {
  var discovered = false;

  @override
  Future<GitRootDiscoverySnapshot> discoverRepositoryRoots(String path) async {
    discovered = true;
    return GitRootDiscoverySnapshot(
      path: '/workspace',
      roots: [GitDiscoveredRoot(path: '/workspace', relativePath: '')],
      fingerprint: 'roots',
    );
  }

  @override
  Future<GitRepositorySetupResult> cloneRepository(
    GitCloneRequest request, {
    GitCancellationToken? cancellationToken,
  }) => throw UnimplementedError();

  @override
  Future<GitRepositorySetupResult> initRepository(
    GitInitRequest request, {
    GitCancellationToken? cancellationToken,
  }) => throw UnimplementedError();

  @override
  Future<GitUnshallowResult> unshallowRepository(
    RepositoryId repositoryId, {
    GitCancellationToken? cancellationToken,
  }) => throw UnimplementedError();
}
