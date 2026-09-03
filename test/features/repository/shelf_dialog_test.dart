import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gift/src/app/pixel_theme.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:gift/src/backend/shelf.dart';
import 'package:gift/src/features/repository/shelf_dialog.dart';

import '../../helpers/git_patch_gateway_stub.dart';

void main() {
  testWidgets('shows shelf semantics and compact changelist controls', (
    tester,
  ) async {
    final repository = const RepositoryOpened(
      repositoryId: RepositoryId(value: 'shelf-ui-repository'),
      root: '/workspace/project',
    );
    final gateway = _ShelfGateway(repository.repositoryId);
    await tester.binding.setSurfaceSize(const Size(420, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPixelTheme(),
        home: ShelfDialog(gateway: gateway, repository: repository),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Shelves are local reusable patches. They do not touch Git stash. Unversioned files are not included in tracked-path shelves.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('changelist-section')), findsOneWidget);
    expect(find.byKey(const Key('shelf-section')), findsOneWidget);
    expect(find.byKey(const Key('import-shelf')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('new-changelist-name')),
      'Later',
    );
    await tester.tap(find.byKey(const Key('create-changelist')));
    await tester.pumpAndSettle();
    expect(gateway.createdNames, ['Later']);
    expect(find.text('Later'), findsOneWidget);
  });
}

class _ShelfGateway with GitPatchGatewayStub implements GitGateway {
  _ShelfGateway(this.repositoryId)
    : changelists = GitChangelistSnapshot(
        repositoryId: repositoryId,
        lists: [
          GitChangelist(
            id: 'default',
            name: 'Changes',
            paths: const [],
            isActive: true,
          ),
        ],
        fingerprint: 'lists',
      ),
      shelves = GitShelfSnapshot(
        repositoryId: repositoryId,
        shelves: const [],
        fingerprint: 'shelves',
      );

  final RepositoryId repositoryId;
  GitChangelistSnapshot changelists;
  final GitShelfSnapshot shelves;
  final createdNames = <String>[];

  @override
  Future<GitChangelistSnapshot> getChangelists(RepositoryId id) async =>
      changelists;

  @override
  Future<GitShelfSnapshot> getShelves(RepositoryId id) async => shelves;

  @override
  Future<GitChangelistSnapshot> createChangelist(
    RepositoryId id,
    String name,
  ) async {
    createdNames.add(name);
    changelists = GitChangelistSnapshot(
      repositoryId: id,
      lists: [
        ...changelists.lists,
        GitChangelist(
          id: 'later',
          name: name,
          paths: const [],
          isActive: false,
        ),
      ],
      fingerprint: 'lists-2',
    );
    return changelists;
  }
}
