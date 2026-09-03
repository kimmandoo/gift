import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/executor.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:gift/src/backend/hosting.dart';
import 'package:gift/src/backend/status.dart';
import 'package:gift/src/features/repository/hosting_dialog.dart';
import 'package:gift/src/app/pixel_theme.dart';

import '../../helpers/git_patch_gateway_stub.dart';

void main() {
  testWidgets('shows compact host links with copy and optional review', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    const repository = RepositoryOpened(
      repositoryId: RepositoryId(value: 'hosting-ui-repository'),
      root: '/workspace/project',
    );
    final gateway = _HostingGateway(repository);
    final copiedUrls = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPixelTheme(),
        home: HostingDialog(
          gateway: gateway,
          repository: repository,
          initialCommitOid: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          initialPath: 'lib/main.dart',
          initialLineStart: 4,
          copyUrl: (url) async => copiedUrls.add(url),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Hosting links'), findsOneWidget);
    expect(find.byKey(const Key('hosting-available')), findsOneWidget);
    await tester.drag(
      find.byKey(const Key('hosting-scroll')),
      const Offset(0, -600),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('build-hosting-links')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('hosting-link-results')), findsOneWidget);
    expect(find.byKey(const Key('hosting-link-commit')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('copy-hosting-commit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('copy-hosting-commit')));
    await tester.pumpAndSettle();
    expect(copiedUrls, hasLength(1));
    await tester.drag(
      find.byKey(const Key('hosting-scroll')),
      const Offset(0, 2000),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('hosting-message')), findsOneWidget);
    await tester.tap(find.byKey(const Key('hosting-review-handoff')));
    await tester.pumpAndSettle();
    expect(find.textContaining('account integration'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _HostingGateway with GitPatchGatewayStub implements GitGateway {
  _HostingGateway(this.repository);

  final RepositoryOpened repository;
  final _hostingRepository = const GitHostingRepository(
    provider: GitHostingProvider.github,
    host: 'github.com',
    owner: 'acme',
    name: 'tools',
    webBase: 'https://github.com/acme/tools',
  );

  @override
  Future<GitHostingSnapshot> getHostingRepository(
    RepositoryId repositoryId, {
    String remote = 'origin',
  }) async => GitHostingSnapshot(
    repositoryId: repositoryId,
    remoteName: remote,
    repository: _hostingRepository,
    sanitizedRemoteUrl: _hostingRepository.webBase,
  );

  @override
  Future<GitHostingLinks> getHostingLinks(
    RepositoryId repositoryId,
    String commitOid, {
    String? remote,
    String? path,
    int? lineStart,
    int? lineEnd,
  }) async => buildGitHostingLinks(
    _hostingRepository,
    commitOid,
    path: path,
    lineStart: lineStart,
    lineEnd: lineEnd,
  );

  @override
  Future<GitHostingReviewCapability> getHostingReviewCapability(
    RepositoryId repositoryId, {
    String remote = 'origin',
  }) async => hostingReviewCapability(_hostingRepository);

  @override
  Future<GitStatusSnapshot> getStatus(RepositoryId repositoryId) async =>
      GitStatusSnapshot(
        repositoryId: repositoryId,
        root: repository.root,
        branch: const GitBranchStatus(head: 'main'),
        changes: const [],
        contentHash: 'status',
        generation: 1,
      );

  @override
  Future<GitInstallation> getGitInstallation() => throw UnimplementedError();

  @override
  Future<List<GitOperationRecord>> getOperationRecords(
    RepositoryId repositoryId, {
    int limit = 100,
  }) => throw UnimplementedError();
}
