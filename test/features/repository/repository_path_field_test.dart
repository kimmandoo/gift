import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:gift/src/backend/repository_paths.dart';
import 'package:gift/src/features/repository/repository_path_field.dart';

import '../../helpers/git_patch_gateway_stub.dart';

void main() {
  testWidgets('searches, browses, normalizes, and rejects traversal', (
    tester,
  ) async {
    const repository = RepositoryOpened(
      repositoryId: RepositoryId(value: 'path-field-repository'),
      root: '/workspace/project',
    );
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepositoryPathField(
            gateway: _PathGateway(),
            repository: repository,
            controller: controller,
            fieldKey: const Key('repository-path-field'),
            browseKey: const Key('repository-path-browse'),
            mode: RepositoryPathMode.file,
            label: 'Path',
            hint: 'src/main.dart',
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('repository-path-browse')));
    await tester.pump();
    expect(
      find.byKey(const Key('repository-path-suggestion:lib/main.dart')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const Key('repository-path-field')),
      r'lib\main',
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      find.byKey(const Key('repository-path-suggestion:lib/main.dart')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const Key('repository-path-suggestion:lib/main.dart')),
    );
    expect(controller.text, 'lib/main.dart');

    await tester.enterText(
      find.byKey(const Key('repository-path-field')),
      '../outside',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(find.text('Enter a safe repository-relative path.'), findsOneWidget);
  });
}

class _PathGateway with GitPatchGatewayStub implements GitGateway {
  @override
  Future<GitRepositoryPathSnapshot> getRepositoryPaths(
    RepositoryId repositoryId, {
    int maxEntries = 2000,
  }) async {
    return GitRepositoryPathSnapshot(
      paths: const [
        GitRepositoryPath(path: 'lib', kind: GitRepositoryPathKind.directory),
        GitRepositoryPath(
          path: 'lib/main.dart',
          kind: GitRepositoryPathKind.file,
        ),
        GitRepositoryPath(path: 'README.md', kind: GitRepositoryPathKind.file),
      ],
      fingerprint: 'paths-1',
    );
  }
}
