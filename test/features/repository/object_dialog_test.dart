import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/objects.dart';
import 'package:gift/src/backend/remote.dart';
import 'package:gift/src/backend/status.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:gift/src/features/repository/object_dialog.dart';

import '../../helpers/git_patch_gateway_stub.dart';

void main() {
  testWidgets('shows responsive stash, tag, remote, and upstream tabs', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(380, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    const repository = RepositoryOpened(
      repositoryId: RepositoryId(value: 'objects-repository'),
      root: '/workspace/project',
    );
    final gateway = _ObjectGateway(repository.repositoryId);

    await tester.pumpWidget(
      MaterialApp(
        home: ObjectDialog(gateway: gateway, repository: repository),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Git objects'), findsOneWidget);
    expect(find.text('No stashes found.'), findsOneWidget);
    expect(find.text('No tags found.'), findsNothing);
    expect(tester.takeException(), isNull);
    expect(
      tester.getTopLeft(find.byKey(const Key('create-stash'))).dy,
      greaterThan(tester.getTopLeft(find.byKey(const Key('stash-message'))).dy),
    );

    await tester.tap(find.text('Tags'));
    await tester.pumpAndSettle();
    expect(find.text('No tags found.'), findsOneWidget);

    await tester.tap(find.text('Remotes'));
    await tester.pumpAndSettle();
    expect(find.text('origin'), findsOneWidget);
    expect(
      find.text('fetch: https://***@example.test/repo.git'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

class _ObjectGateway with GitPatchGatewayStub implements GitGateway {
  _ObjectGateway(this.repositoryId);

  final RepositoryId repositoryId;

  @override
  Future<GitStashSnapshot> getStashes(RepositoryId id) async =>
      GitStashSnapshot(
        repositoryId: id,
        entries: const [],
        fingerprint: 'stashes',
      );

  @override
  Future<GitTagSnapshot> getTags(RepositoryId id) async =>
      GitTagSnapshot(repositoryId: id, tags: const [], fingerprint: 'tags');

  @override
  Future<List<GitRemote>> getRemotes(RepositoryId id) async => [
    const GitRemote(
      name: 'origin',
      fetchUrl: 'https://alice:secret@example.test/repo.git',
    ),
  ];

  @override
  Future<GitUpstreamSnapshot> getUpstream(RepositoryId id) async =>
      const GitUpstreamSnapshot(
        repositoryId: RepositoryId(value: 'objects-repository'),
        branch: 'main',
        remote: 'origin',
        remoteBranch: 'main',
      );

  @override
  Future<GitStatusSnapshot> getStatus(RepositoryId id) =>
      throw UnimplementedError();
}
