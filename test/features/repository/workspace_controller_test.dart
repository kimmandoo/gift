import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/git_patch_gateway_stub.dart';

import 'package:gitshiba/src/app/pixel_theme.dart';
import 'package:gitshiba/src/app/gitshiba_app.dart';
import 'package:gitshiba/src/backend/branch.dart';
import 'package:gitshiba/src/backend/commit.dart';
import 'package:gitshiba/src/backend/discard.dart';
import 'package:gitshiba/src/backend/diff.dart';
import 'package:gitshiba/src/backend/domain.dart';
import 'package:gitshiba/src/backend/error.dart';
import 'package:gitshiba/src/backend/executor.dart';
import 'package:gitshiba/src/backend/git_gateway.dart';
import 'package:gitshiba/src/backend/history.dart';
import 'package:gitshiba/src/backend/remote.dart';
import 'package:gitshiba/src/backend/status.dart';
import 'package:gitshiba/src/features/repository/workspace_controller.dart';
import 'package:gitshiba/src/features/repository/workspace_screen.dart';
import 'package:gitshiba/src/features/repository/workspace_store.dart';
import 'package:gitshiba/src/features/repository/recent_repository_store.dart';

void main() {
  test(
    'restores tab order and active path without persisting session IDs',
    () async {
      final gateway = WorkspaceGateway();
      final store = WorkspaceStore.inMemory();
      final first = WorkspaceController(
        gateway: gateway,
        store: store,
        changesPollInterval: const Duration(hours: 1),
      );

      await first.openPath('/aliases/alpha');
      await first.openPath('/aliases/beta');
      first.select(0);
      await first.reorder(0, 1);
      first.dispose();

      final restored = WorkspaceController(
        gateway: gateway,
        store: store,
        changesPollInterval: const Duration(hours: 1),
      );
      await restored.restore();

      expect(restored.state.tabs.map((tab) => tab.path), [
        '/workspace/beta',
        '/workspace/alpha',
      ]);
      expect(restored.state.activeTab?.path, '/workspace/alpha');
      expect(restored.state.tabs.every((tab) => tab.isAvailable), isTrue);
      expect(
        await store.load(),
        const WorkspaceSnapshot(
          paths: ['/workspace/beta', '/workspace/alpha'],
          activePath: '/workspace/alpha',
        ),
      );
      restored.dispose();
    },
  );

  test('does not add a duplicate canonical repository path', () async {
    final controller = WorkspaceController(
      gateway: WorkspaceGateway(),
      store: WorkspaceStore.inMemory(),
      changesPollInterval: const Duration(hours: 1),
    );

    await controller.openPath('/aliases/alpha');
    await controller.openPath('/workspace/alpha');

    expect(controller.state.tabs, hasLength(1));
    expect(controller.state.activeTab?.path, '/workspace/alpha');
    controller.dispose();
  });

  test('removes duplicate canonical paths while restoring', () async {
    final gateway = WorkspaceGateway();
    final store = WorkspaceStore.inMemory();
    await store.save(
      paths: const ['/aliases/alpha', '/workspace/alpha', '/aliases/beta'],
      activePath: '/workspace/alpha',
    );
    final controller = WorkspaceController(
      gateway: gateway,
      store: store,
      changesPollInterval: const Duration(hours: 1),
    );

    await controller.restore();

    expect(controller.state.tabs.map((tab) => tab.path), [
      '/workspace/alpha',
      '/workspace/beta',
    ]);
    expect(controller.state.activeTab?.path, '/workspace/alpha');
    controller.dispose();
  });

  test('keeps unavailable tabs recoverable', () async {
    final gateway = WorkspaceGateway();
    final store = WorkspaceStore.inMemory();
    await store.save(
      paths: const ['/workspace/missing'],
      activePath: '/workspace/missing',
    );
    final controller = WorkspaceController(
      gateway: gateway,
      store: store,
      changesPollInterval: const Duration(hours: 1),
    );

    await controller.restore();
    expect(controller.state.activeTab?.isAvailable, isFalse);
    expect(
      controller.state.activeTab?.error?.category,
      GitErrorCategory.notRepository,
    );

    await controller.retryUnavailable(0, '/aliases/beta');
    expect(controller.state.activeTab?.isAvailable, isTrue);
    expect(controller.state.activeTab?.path, '/workspace/beta');
    controller.dispose();
  });

  test('keeps a failed new open visible as an unavailable tab', () async {
    final store = WorkspaceStore.inMemory();
    final controller = WorkspaceController(
      gateway: WorkspaceGateway(),
      store: store,
      changesPollInterval: const Duration(hours: 1),
    );

    final opened = await controller.openPath('/workspace/missing');

    expect(opened, isNull);
    expect(controller.state.tabs, hasLength(1));
    expect(controller.state.activeTab?.isAvailable, isFalse);
    expect(controller.state.activeTab?.path, '/workspace/missing');
    expect(
      await store.load(),
      const WorkspaceSnapshot(
        paths: ['/workspace/missing'],
        activePath: '/workspace/missing',
      ),
    );
    controller.dispose();
  });

  test(
    'gives each open repository an independent Changes controller',
    () async {
      final controller = WorkspaceController(
        gateway: WorkspaceGateway(),
        store: WorkspaceStore.inMemory(),
        changesPollInterval: const Duration(hours: 1),
      );

      await controller.openPath('/aliases/alpha');
      await controller.openPath('/aliases/beta');

      expect(
        controller.state.tabs[0].changesController,
        isNot(same(controller.state.tabs[1].changesController)),
      );
      expect(
        controller.state.tabs[0].repository?.repositoryId,
        isNot(controller.state.tabs[1].repository?.repositoryId),
      );
      expect(
        controller.state.tabs[0].historyController,
        isNot(same(controller.state.tabs[1].historyController)),
      );
      controller.dispose();
    },
  );

  test('routes a tab mutation through that tab repository ID', () async {
    final gateway = WorkspaceGateway();
    final controller = WorkspaceController(
      gateway: gateway,
      store: WorkspaceStore.inMemory(),
      changesPollInterval: const Duration(hours: 1),
    );
    await controller.openPath('/aliases/alpha');
    await controller.openPath('/aliases/beta');

    final alphaChanges = controller.state.tabs[0].changesController!;
    await alphaChanges.refresh();
    alphaChanges.selectPath('README.md');
    await alphaChanges.stageSelected();

    expect(
      gateway.stagedRepositoryId,
      controller.state.tabs[0].repository?.repositoryId,
    );
    expect(
      gateway.stagedRepositoryId,
      isNot(controller.state.tabs[1].repository?.repositoryId),
    );
    controller.dispose();
  });

  testWidgets('keeps compact repository tabs visible and keyboard navigable', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final controller = WorkspaceController(
      gateway: WorkspaceGateway(),
      store: WorkspaceStore.inMemory(),
      changesPollInterval: const Duration(hours: 1),
    );
    await controller.openPath('/aliases/alpha');
    await controller.openPath('/aliases/beta');

    await tester.pumpWidget(
      MaterialApp(
        theme: buildPixelTheme(brightness: Brightness.light),
        home: WorkspaceScreen(
          controller: controller,
          onOpenRepository: (_) async {},
          onWorkspaceEmpty: () {},
          autoInitialize: false,
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('workspace-tab-bar')), findsOneWidget);
    expect(find.text('alpha'), findsOneWidget);
    expect(find.text('beta'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(
      find.byKey(const ValueKey('workspace-tab:/workspace/alpha')),
    );
    await tester.pump();
    expect(controller.state.activeTab?.path, '/workspace/alpha');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(controller.state.activeTab?.path, '/workspace/beta');

    await tester.tap(
      find.byKey(const ValueKey('workspace-close:/workspace/beta')),
    );
    await tester.pump();
    expect(controller.state.tabs, hasLength(1));
    expect(controller.state.activeTab?.path, '/workspace/alpha');
    controller.dispose();
  });

  testWidgets('restores workspace tabs through the app entry point', (
    tester,
  ) async {
    final store = WorkspaceStore.inMemory();
    await store.save(
      paths: const ['/aliases/alpha', '/aliases/beta'],
      activePath: '/aliases/beta',
    );
    final gateway = WorkspaceGateway();
    final controller = WorkspaceController(
      gateway: gateway,
      store: store,
      changesPollInterval: const Duration(hours: 1),
    );

    await tester.pumpWidget(
      GitshibaApp(
        gateway: gateway,
        recentStore: RecentRepositoryStore.inMemory(),
        workspaceController: controller,
        autoInitialize: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('workspace-tab-bar')), findsOneWidget);
    expect(controller.state.activeTab?.path, '/workspace/beta');
    expect(tester.takeException(), isNull);
    controller.dispose();
  });
}

class WorkspaceGateway with GitPatchGatewayStub implements GitGateway {
  RepositoryId? stagedRepositoryId;

  final Map<String, RepositoryOpened> _repositories = {
    '/aliases/alpha': const RepositoryOpened(
      repositoryId: RepositoryId(value: 'alpha-id'),
      root: '/workspace/alpha',
    ),
    '/aliases/beta': const RepositoryOpened(
      repositoryId: RepositoryId(value: 'beta-id'),
      root: '/workspace/beta',
    ),
    '/workspace/alpha': const RepositoryOpened(
      repositoryId: RepositoryId(value: 'alpha-reopened-id'),
      root: '/workspace/alpha',
    ),
    '/workspace/beta': const RepositoryOpened(
      repositoryId: RepositoryId(value: 'beta-reopened-id'),
      root: '/workspace/beta',
    ),
  };

  @override
  Future<GitInstallation> getGitInstallation() async =>
      const GitInstallation(executablePath: '/usr/bin/git', version: '2.51.0');

  @override
  Future<RepositoryOpened> openRepository(String path) async {
    final repository = _repositories[path];
    if (repository != null) return repository;
    throw const GitError(
      category: GitErrorCategory.notRepository,
      userMessage: 'The selected folder is not a Git repository.',
      diagnostic: 'workspace test path is unavailable',
      retryable: false,
    );
  }

  @override
  Future<GitInstallation> configureGitPath(String path) =>
      throw UnimplementedError();

  @override
  Future<GitStatusSnapshot> getStatus(RepositoryId repositoryId) async =>
      GitStatusSnapshot(
        repositoryId: repositoryId,
        root: '/workspace/${repositoryId.value}',
        branch: const GitBranchStatus(head: 'main'),
        changes: const [
          GitChange(
            type: GitChangeType.tracked,
            path: 'README.md',
            indexStatus: '.',
            worktreeStatus: 'M',
            submoduleStatus: 'N...',
          ),
        ],
        contentHash: repositoryId.value,
        generation: 1,
      );

  @override
  Future<GitHistoryPage> getHistory(
    RepositoryId repositoryId, {
    int limit = 50,
    int offset = 0,
  }) => throw UnimplementedError();

  @override
  Future<List<GitBranch>> getBranches(RepositoryId repositoryId) =>
      throw UnimplementedError();

  @override
  Future<GitBranchActionResult> createBranch(
    RepositoryId repositoryId,
    String name,
  ) => throw UnimplementedError();

  @override
  Future<GitBranchActionResult> switchBranch(
    RepositoryId repositoryId,
    String name,
  ) => throw UnimplementedError();

  @override
  Future<List<GitRemote>> getRemotes(RepositoryId repositoryId) =>
      throw UnimplementedError();

  @override
  Future<GitRemoteOperationResult> fetch(
    RepositoryId repositoryId,
    String remote, {
    GitCancellationToken? cancellationToken,
  }) => throw UnimplementedError();

  @override
  Future<GitRemoteOperationResult> pull(
    RepositoryId repositoryId,
    String remote, {
    GitCancellationToken? cancellationToken,
  }) => throw UnimplementedError();

  @override
  Future<GitRemoteOperationResult> push(
    RepositoryId repositoryId,
    String remote, {
    GitCancellationToken? cancellationToken,
  }) => throw UnimplementedError();

  @override
  Future<GitDiffSnapshot> getDiff(
    RepositoryId repositoryId,
    String path, {
    GitDiffScope scope = GitDiffScope.workingTree,
    String? originalPath,
  }) async => GitDiffSnapshot(
    repositoryId: repositoryId,
    path: path,
    scope: scope,
    lines: const [],
    contentHash: 'workspace-test-diff',
  );

  @override
  Future<GitStatusSnapshot> stage(
    RepositoryId repositoryId,
    String path,
  ) async {
    stagedRepositoryId = repositoryId;
    return getStatus(repositoryId);
  }

  @override
  Future<GitStatusSnapshot> unstage(RepositoryId repositoryId, String path) =>
      throw UnimplementedError();

  @override
  Future<GitCommitResult> commit(RepositoryId repositoryId, String message) =>
      throw UnimplementedError();

  @override
  Future<DiscardPreview> createDiscardPreview(
    RepositoryId repositoryId,
    String path,
  ) => throw UnimplementedError();

  @override
  Future<GitStatusSnapshot> discard(
    RepositoryId repositoryId,
    DiscardPreview preview,
  ) => throw UnimplementedError();
}
