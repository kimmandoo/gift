import 'dart:async';

import 'package:gift/src/backend/branch.dart';
import 'package:gift/src/backend/commit.dart';
import 'package:gift/src/backend/discard.dart';
import 'package:gift/src/backend/diff.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/error.dart';
import 'package:gift/src/backend/executor.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:gift/src/backend/history.dart';
import 'package:gift/src/backend/status.dart';
import 'package:gift/src/backend/remote.dart';
import 'package:gift/src/backend/remote_branch.dart';
import 'package:gift/src/features/repository/branch_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/git_patch_gateway_stub.dart';

void main() {
  testWidgets('lists local branches and switches the selected branch', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final repository = const RepositoryOpened(
      repositoryId: RepositoryId(value: 'branch-repository'),
      root: '/workspace/project',
    );
    final gateway = FakeBranchGateway(
      branches: const [
        GitBranch(name: 'feature/demo'),
        GitBranch(name: 'main', isCurrent: true),
      ],
      action: GitBranchActionResult(
        repositoryId: repository.repositoryId,
        branchName: 'feature/demo',
        status: GitStatusSnapshot(
          repositoryId: repository.repositoryId,
          root: repository.root,
          branch: GitBranchStatus(head: 'feature/demo'),
          changes: const [],
          contentHash: 'changed',
          generation: 2,
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BranchDialog(gateway: gateway, repository: repository),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('feature/demo'), findsOneWidget);
    expect(find.text('Current · not linked to a remote'), findsOneWidget);
    expect(find.byKey(const Key('push-current-branch')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('branch:feature/demo')));
    await tester.pumpAndSettle();
    expect(gateway.switchedTo, 'feature/demo');
  });

  testWidgets('previews and confirms an advanced branch operation', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(420, 640);
    tester.view.devicePixelRatio = 1;
    final repository = const RepositoryOpened(
      repositoryId: RepositoryId(value: 'advanced-branch-repository'),
      root: '/workspace/project',
    );
    final status = GitStatusSnapshot(
      repositoryId: repository.repositoryId,
      root: repository.root,
      branch: GitBranchStatus(head: 'main', oid: 'a' * 40),
      changes: const [],
      contentHash: 'clean',
      generation: 1,
    );
    final gateway = FakeBranchGateway(
      branches: const [GitBranch(name: 'main', isCurrent: true)],
      action: GitBranchActionResult(
        repositoryId: repository.repositoryId,
        branchName: 'main',
        status: status,
      ),
      preview: GitBranchOperationPreview(
        repositoryId: repository.repositoryId,
        request: const GitBranchOperationRequest(
          operation: GitBranchOperation.merge,
          source: 'feature',
          target: 'main',
        ),
        currentBranch: 'main',
        ahead: 1,
        behind: 0,
        expectedCommits: 1,
        mergeBase: 'a' * 40,
        dirtyWorktree: false,
        detachedHead: false,
        operationInProgress: null,
        requiresConfirmation: true,
        token: 'preview-token',
        expiresAt: DateTime(2030),
      ),
      operationResult: GitBranchOperationResult(
        repositoryId: repository.repositoryId,
        request: const GitBranchOperationRequest(
          operation: GitBranchOperation.merge,
          source: 'feature',
          target: 'main',
        ),
        state: GitBranchOperationState.completed,
        status: status,
        summary: 'The branch operation completed.',
        recoveryActions: const [],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BranchDialog(gateway: gateway, repository: repository),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('advanced-branch-operations')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('advanced-branch-source')),
      'feature',
    );
    await tester.enterText(
      find.byKey(const Key('advanced-branch-target')),
      'main',
    );
    await tester.tap(find.byKey(const Key('preview-branch-operation')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('branch-operation-preview')), findsOneWidget);
    await tester.tap(find.byKey(const Key('execute-branch-operation')));
    await tester.pumpAndSettle();
    expect(gateway.executed, isTrue);
    expect(find.byKey(const Key('branch-operation-result')), findsOneWidget);
  });

  testWidgets('shows remote branch fetching in the branch browser', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(420, 640);
    tester.view.devicePixelRatio = 1;
    final repository = const RepositoryOpened(
      repositoryId: RepositoryId(value: 'remote-fetch-ui-repository'),
      root: '/workspace/project',
    );
    final status = GitStatusSnapshot(
      repositoryId: repository.repositoryId,
      root: repository.root,
      branch: const GitBranchStatus(head: 'main'),
      changes: const [],
      contentHash: 'remote-fetch-ui',
      generation: 1,
    );
    final gateway = FakeBranchGateway(
      branches: const [GitBranch(name: 'main', isCurrent: true)],
      action: GitBranchActionResult(
        repositoryId: repository.repositoryId,
        branchName: 'main',
        status: status,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BranchDialog(gateway: gateway, repository: repository),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('fetch-remote-branches')), findsOneWidget);

    await tester.tap(find.byKey(const Key('fetch-remote-branches')));
    await tester.pumpAndSettle();

    expect(gateway.fetchCalls, ['origin']);
  });

  testWidgets('shows remote fetch failures in a modal error popup', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(420, 640);
    tester.view.devicePixelRatio = 1;
    final repository = const RepositoryOpened(
      repositoryId: RepositoryId(value: 'remote-fetch-error-repository'),
      root: '/workspace/project',
    );
    final status = GitStatusSnapshot(
      repositoryId: repository.repositoryId,
      root: repository.root,
      branch: const GitBranchStatus(head: 'main'),
      changes: const [],
      contentHash: 'remote-fetch-error',
      generation: 1,
    );
    final gateway = FakeBranchGateway(
      branches: const [GitBranch(name: 'main', isCurrent: true)],
      action: GitBranchActionResult(
        repositoryId: repository.repositoryId,
        branchName: 'main',
        status: status,
      ),
      fetchError: const GitError(
        category: GitErrorCategory.processFailed,
        userMessage: 'Remote fetch failed.',
        diagnostic: 'test fetch failure',
        retryable: true,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BranchDialog(gateway: gateway, repository: repository),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fetch-remote-branches')));
    await tester.pumpAndSettle();

    expect(gateway.fetchCalls, ['origin']);
    expect(find.byKey(const Key('error-popup')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('error-popup')),
        matching: find.text('Remote fetch failed.'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('dismiss-error-popup')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('branch-error')), findsOneWidget);
  });

  testWidgets('fetches and renders remote-only branches from the browser', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(420, 640);
    tester.view.devicePixelRatio = 1;
    final repository = const RepositoryOpened(
      repositoryId: RepositoryId(value: 'remote-only-branch-repository'),
      root: '/workspace/project',
    );
    final status = GitStatusSnapshot(
      repositoryId: repository.repositoryId,
      root: repository.root,
      branch: const GitBranchStatus(head: 'main'),
      changes: const [],
      contentHash: 'remote-only',
      generation: 1,
    );
    final remoteBranch = GitRemoteBranch(
      name: 'origin/remote-only',
      remote: 'origin',
      branch: 'remote-only',
      oid: 'b' * 40,
    );
    final gateway = FakeBranchGateway(
      branches: const [GitBranch(name: 'main', isCurrent: true)],
      action: GitBranchActionResult(
        repositoryId: repository.repositoryId,
        branchName: 'main',
        status: status,
      ),
      remoteSnapshot: GitRemoteBranchSnapshot(
        repositoryId: repository.repositoryId,
        fingerprint: 'before-fetch',
        currentBranch: 'main',
        branches: const [],
      ),
      remoteSnapshotAfterFetch: GitRemoteBranchSnapshot(
        repositoryId: repository.repositoryId,
        fingerprint: 'after-fetch',
        currentBranch: 'main',
        branches: [remoteBranch],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BranchDialog(gateway: gateway, repository: repository),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Fetch remotes'), findsOneWidget);
    await tester.tap(find.byKey(const Key('fetch-remote-branches')));
    await tester.pumpAndSettle();

    expect(gateway.fetchCalls, ['origin']);
    expect(find.text('origin/remote-only'), findsOneWidget);
  });

  testWidgets('keeps a fresh remote snapshot over a stale read', (
    tester,
  ) async {
    final firstSnapshot = Completer<GitRemoteBranchSnapshot>();
    final repository = const RepositoryOpened(
      repositoryId: RepositoryId(value: 'remote-snapshot-race-repository'),
      root: '/workspace/project',
    );
    final status = GitStatusSnapshot(
      repositoryId: repository.repositoryId,
      root: repository.root,
      branch: const GitBranchStatus(head: 'main'),
      changes: const [],
      contentHash: 'remote-race',
      generation: 1,
    );
    final remoteBranch = GitRemoteBranch(
      name: 'origin/remote-only',
      remote: 'origin',
      branch: 'remote-only',
      oid: 'c' * 40,
    );
    final stale = GitRemoteBranchSnapshot(
      repositoryId: repository.repositoryId,
      fingerprint: 'stale',
      currentBranch: 'main',
      branches: const [],
    );
    final fresh = GitRemoteBranchSnapshot(
      repositoryId: repository.repositoryId,
      fingerprint: 'fresh',
      currentBranch: 'main',
      branches: [remoteBranch],
    );
    final gateway = FakeBranchGateway(
      branches: const [GitBranch(name: 'main', isCurrent: true)],
      action: GitBranchActionResult(
        repositoryId: repository.repositoryId,
        branchName: 'main',
        status: status,
      ),
      remoteSnapshot: stale,
      remoteSnapshotAfterFetch: fresh,
      remoteSnapshotReader: (read) =>
          read == 1 ? firstSnapshot.future : Future.value(fresh),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BranchDialog(gateway: gateway, repository: repository),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('fetch-remote-branches')));
    await tester.pumpAndSettle();
    expect(find.text('origin/remote-only'), findsOneWidget);

    firstSnapshot.complete(stale);
    await tester.pumpAndSettle();
    expect(find.text('origin/remote-only'), findsOneWidget);
  });

  testWidgets('shows remote branches as checkout and compare actions', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(420, 640);
    tester.view.devicePixelRatio = 1;
    final repository = const RepositoryOpened(
      repositoryId: RepositoryId(value: 'remote-branch-ui-repository'),
      root: '/workspace/project',
    );
    final status = GitStatusSnapshot(
      repositoryId: repository.repositoryId,
      root: repository.root,
      branch: const GitBranchStatus(head: 'main'),
      changes: const [],
      contentHash: 'remote-ui',
      generation: 1,
    );
    final gateway = FakeBranchGateway(
      branches: const [GitBranch(name: 'main', isCurrent: true)],
      action: GitBranchActionResult(
        repositoryId: repository.repositoryId,
        branchName: 'feature',
        status: status,
      ),
      remoteSnapshot: GitRemoteBranchSnapshot(
        repositoryId: repository.repositoryId,
        fingerprint: 'remote-ui',
        currentBranch: 'main',
        branches: [
          GitRemoteBranch(
            name: 'origin/feature',
            remote: 'origin',
            branch: 'feature',
            oid: 'a' * 40,
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BranchDialog(gateway: gateway, repository: repository),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('origin/feature'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('remote-actions:origin/feature')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Checkout as local branch'), findsOneWidget);
    await tester.tap(find.text('Checkout as local branch'));
    await tester.pumpAndSettle();
    expect(gateway.checkedOutRemote, 'origin/feature');
  });

  testWidgets('previews and confirms deleting a remote branch', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(420, 640);
    tester.view.devicePixelRatio = 1;
    final repository = const RepositoryOpened(
      repositoryId: RepositoryId(value: 'remote-delete-ui-repository'),
      root: '/workspace/project',
    );
    final branch = GitRemoteBranch(
      name: 'origin/old-feature',
      remote: 'origin',
      branch: 'old-feature',
      oid: 'b' * 40,
    );
    final snapshot = GitRemoteBranchSnapshot(
      repositoryId: repository.repositoryId,
      fingerprint: 'remote-delete-ui',
      currentBranch: 'main',
      branches: [branch],
    );
    final status = GitStatusSnapshot(
      repositoryId: repository.repositoryId,
      root: repository.root,
      branch: const GitBranchStatus(head: 'main'),
      changes: const [],
      contentHash: 'remote-delete-ui',
      generation: 1,
    );
    final gateway = FakeBranchGateway(
      branches: const [GitBranch(name: 'main', isCurrent: true)],
      action: GitBranchActionResult(
        repositoryId: repository.repositoryId,
        branchName: 'main',
        status: status,
      ),
      remoteSnapshot: snapshot,
      remoteDeletePreview: GitRemoteBranchDeletePreview(
        repositoryId: repository.repositoryId,
        branch: branch,
        oid: branch.oid,
        fingerprint: snapshot.fingerprint,
        token: 'delete-token',
        expiresAt: DateTime(2030),
      ),
      remoteDeleteResult: GitRemoteBranchActionResult(
        repositoryId: repository.repositoryId,
        branch: branch,
        status: status,
        snapshot: GitRemoteBranchSnapshot(
          repositoryId: repository.repositoryId,
          fingerprint: 'remote-delete-ui-after',
          currentBranch: 'main',
          branches: const [],
        ),
        summary: 'The remote branch was deleted.',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BranchDialog(gateway: gateway, repository: repository),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('remote-actions:origin/old-feature')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete remote branch'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('confirm-delete-remote-branch')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('confirm-delete-remote-branch')));
    await tester.pumpAndSettle();
    expect(gateway.deletedRemote, 'origin/old-feature');
  });
}

class FakeBranchGateway with GitPatchGatewayStub implements GitGateway {
  FakeBranchGateway({
    required this.branches,
    required this.action,
    this.preview,
    this.operationResult,
    this.remoteSnapshot,
    this.remoteSnapshotAfterFetch,
    this.remoteSnapshotReader,
    this.remoteDeletePreview,
    this.remoteDeleteResult,
    this.fetchError,
    this.remotes = const [GitRemote(name: 'origin')],
  });

  final List<GitBranch> branches;
  final GitBranchActionResult action;
  final GitBranchOperationPreview? preview;
  final GitBranchOperationResult? operationResult;
  final GitRemoteBranchSnapshot? remoteSnapshot;
  final GitRemoteBranchSnapshot? remoteSnapshotAfterFetch;
  final Future<GitRemoteBranchSnapshot> Function(int)? remoteSnapshotReader;
  final GitRemoteBranchDeletePreview? remoteDeletePreview;
  final GitRemoteBranchActionResult? remoteDeleteResult;
  final GitError? fetchError;
  final List<GitRemote> remotes;
  String? switchedTo;
  String? checkedOutRemote;
  String? deletedRemote;
  var executed = false;
  final fetchCalls = <String>[];

  @override
  Future<List<GitBranch>> getBranches(RepositoryId repositoryId) async =>
      branches;

  @override
  Future<GitRemoteBranchSnapshot> getRemoteBranchSnapshot(
    RepositoryId repositoryId,
  ) async =>
      remoteSnapshotReader?.call(fetchCalls.length + 1) ??
      (fetchCalls.isEmpty
          ? remoteSnapshot!
          : remoteSnapshotAfterFetch ?? remoteSnapshot!);

  @override
  Future<GitBranchActionResult> checkoutRemoteBranch(
    RepositoryId repositoryId,
    GitRemoteBranch branch, {
    String? localName,
  }) async {
    checkedOutRemote = branch.name;
    return action;
  }

  @override
  Future<GitRemoteBranchDeletePreview> previewRemoteBranchDelete(
    RepositoryId repositoryId,
    GitRemoteBranch branch,
  ) async => remoteDeletePreview!;

  @override
  Future<GitRemoteBranchActionResult> deleteRemoteBranch(
    RepositoryId repositoryId,
    GitRemoteBranchDeletePreview preview,
  ) async {
    deletedRemote = preview.branch.name;
    return remoteDeleteResult!;
  }

  @override
  Future<GitBranchActionResult> switchBranch(
    RepositoryId repositoryId,
    String name,
  ) async {
    switchedTo = name;
    return action;
  }

  @override
  Future<GitBranchOperationPreview> previewBranchOperation(
    RepositoryId repositoryId,
    GitBranchOperationRequest request,
  ) async => preview!;

  @override
  Future<GitBranchOperationResult> executeBranchOperation(
    RepositoryId repositoryId,
    GitBranchOperationRequest request, {
    GitCancellationToken? cancellationToken,
  }) async {
    executed = true;
    return operationResult!;
  }

  @override
  Future<GitInstallation> configureGitPath(String path) =>
      throw UnimplementedError();

  @override
  Future<GitInstallation> getGitInstallation() => throw UnimplementedError();

  @override
  Future<RepositoryOpened> openRepository(String path) =>
      throw UnimplementedError();

  @override
  Future<GitStatusSnapshot> getStatus(RepositoryId repositoryId) =>
      throw UnimplementedError();

  @override
  Future<GitHistoryPage> getHistory(
    RepositoryId repositoryId, {
    int limit = 50,
    int offset = 0,
    GitHistoryQuery? query,
  }) => throw UnimplementedError();

  @override
  Future<GitDiffSnapshot> getDiff(
    RepositoryId repositoryId,
    String path, {
    GitDiffScope scope = GitDiffScope.workingTree,
    String? originalPath,
  }) => throw UnimplementedError();

  @override
  Future<GitStatusSnapshot> stage(RepositoryId repositoryId, String path) =>
      throw UnimplementedError();

  @override
  Future<GitStatusSnapshot> unstage(RepositoryId repositoryId, String path) =>
      throw UnimplementedError();

  @override
  Future<GitCommitResult> commit(
    RepositoryId repositoryId,
    String message, {
    GitCommitOptions options = const GitCommitOptions(),
  }) => throw UnimplementedError();

  @override
  Future<GitBranchActionResult> createBranch(
    RepositoryId repositoryId,
    String name,
  ) => throw UnimplementedError();

  @override
  Future<List<GitRemote>> getRemotes(RepositoryId repositoryId) async =>
      remotes;

  @override
  Future<GitRemoteOperationResult> fetch(
    RepositoryId repositoryId,
    String remote, {
    GitCancellationToken? cancellationToken,
  }) async {
    fetchCalls.add(remote);
    if (fetchError != null) throw fetchError!;
    return GitRemoteOperationResult(
      repositoryId: repositoryId,
      remote: remote,
      operation: GitRemoteOperation.fetch,
      status: action.status,
      summary: 'Fetched $remote.',
    );
  }

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
