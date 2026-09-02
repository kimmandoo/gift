import 'dart:async';

import 'package:gift/src/features/settings/git_settings_controller.dart';
import 'package:gift/src/features/settings/git_settings_dialog.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/branch.dart';
import 'package:gift/src/backend/commit.dart';
import 'package:gift/src/backend/executor.dart';
import 'package:gift/src/backend/discard.dart';
import 'package:gift/src/backend/diff.dart';
import 'package:gift/src/backend/error.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:gift/src/backend/history.dart';
import 'package:gift/src/backend/remote.dart';
import 'package:gift/src/backend/status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/git_patch_gateway_stub.dart';

import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('selects a valid executable and persists its path', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final preferences = await SharedPreferences.getInstance();
    final gateway = FakeSettingsGateway(
      installation: const GitInstallation(
        executablePath: '/custom/git',
        version: '2.51.0',
      ),
    );
    final controller = GitSettingsController(
      gateway: gateway,
      preferences: preferences,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: GitSettingsDialog(
          controller: controller,
          selectExecutable: () async => '/custom/git',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Choose Git executable'));
    await tester.pumpAndSettle();

    expect(gateway.configuredPaths, ['/custom/git']);
    expect(preferences.getString(GitSettingsController.pathKey), '/custom/git');
    expect(find.text('/custom/git'), findsOneWidget);
  });

  testWidgets('persists the validated canonical executable path', (
    tester,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final gateway = FakeSettingsGateway(
      installation: const GitInstallation(
        executablePath: '/canonical/git',
        version: '2.51.0',
      ),
    );
    final controller = GitSettingsController(
      gateway: gateway,
      preferences: preferences,
    );

    await controller.configurePath('../linked-git');

    expect(
      preferences.getString(GitSettingsController.pathKey),
      '/canonical/git',
    );
    controller.dispose();
  });

  testWidgets('ignores an async result after disposal', (tester) async {
    final preferences = await SharedPreferences.getInstance();
    final completer = Completer<GitInstallation>();
    final gateway = DeferredSettingsGateway(completer.future);
    final controller = GitSettingsController(
      gateway: gateway,
      preferences: preferences,
    );
    final future = controller.initialize();

    controller.dispose();
    completer.complete(
      const GitInstallation(executablePath: '/late/git', version: '2.51.0'),
    );

    await future;
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'rejects an unsupported Git version and keeps settings retryable',
    (tester) async {
      final preferences = await SharedPreferences.getInstance();
      final gateway = FakeSettingsGateway(
        installationError: const GitError(
          category: GitErrorCategory.unsupportedGitVersion,
          userMessage: 'Git 2.35 or newer is required.',
          diagnostic: 'detected Git 2.34.9',
          retryable: false,
        ),
      );
      final controller = GitSettingsController(
        gateway: gateway,
        preferences: preferences,
      );

      await tester.pumpWidget(
        MaterialApp(home: GitSettingsDialog(controller: controller)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Git 2.35 or newer is required.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(preferences.getString(GitSettingsController.pathKey), isNull);
    },
  );

  testWidgets('validates a persisted explicit path before enabling settings', (
    tester,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(GitSettingsController.pathKey, '/saved/git');
    final gateway = FakeSettingsGateway(
      installation: const GitInstallation(
        executablePath: '/saved/git',
        version: '2.51.0',
      ),
    );
    final controller = GitSettingsController(
      gateway: gateway,
      preferences: preferences,
    );

    await tester.pumpWidget(
      MaterialApp(home: GitSettingsDialog(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(gateway.configuredPaths, ['/saved/git']);
    expect(find.text('Version 2.51.0'), findsOneWidget);
  });

  testWidgets('retries Git discovery after a startup failure', (tester) async {
    final preferences = await SharedPreferences.getInstance();
    final gateway = FakeSettingsGateway(
      installation: const GitInstallation(
        executablePath: '/usr/bin/git',
        version: '2.51.0',
      ),
      installationError: const GitError(
        category: GitErrorCategory.gitNotFound,
        userMessage: 'Git could not be found.',
        diagnostic: 'PATH did not contain Git',
        retryable: true,
      ),
    );
    final controller = GitSettingsController(
      gateway: gateway,
      preferences: preferences,
    );

    await tester.pumpWidget(
      MaterialApp(home: GitSettingsDialog(controller: controller)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Git could not be found.'), findsOneWidget);

    gateway.installationError = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('/usr/bin/git'), findsOneWidget);
    expect(find.text('Version 2.51.0'), findsOneWidget);
  });
}

class FakeSettingsGateway with GitPatchGatewayStub implements GitGateway {
  FakeSettingsGateway({this.installation, this.installationError});

  final GitInstallation? installation;
  GitError? installationError;
  final List<String> configuredPaths = <String>[];

  @override
  Future<GitInstallation> configureGitPath(String path) async {
    configuredPaths.add(path);
    if (installationError != null) throw installationError!;
    return installation!;
  }

  @override
  Future<GitInstallation> getGitInstallation() async {
    if (installationError != null) throw installationError!;
    return installation!;
  }

  @override
  Future<RepositoryOpened> openRepository(String path) {
    throw UnimplementedError();
  }

  @override
  Future<GitStatusSnapshot> getStatus(RepositoryId repositoryId) {
    throw UnimplementedError();
  }

  @override
  Future<GitHistoryPage> getHistory(
    RepositoryId repositoryId, {
    int limit = 50,
    int offset = 0,
  }) {
    throw UnimplementedError();
  }

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
  }) {
    throw UnimplementedError();
  }

  @override
  Future<GitStatusSnapshot> stage(RepositoryId repositoryId, String path) {
    throw UnimplementedError();
  }

  @override
  Future<GitStatusSnapshot> unstage(RepositoryId repositoryId, String path) {
    throw UnimplementedError();
  }

  @override
  Future<GitCommitResult> commit(RepositoryId repositoryId, String message) {
    throw UnimplementedError();
  }

  @override
  Future<DiscardPreview> createDiscardPreview(
    RepositoryId repositoryId,
    String path,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<GitStatusSnapshot> discard(
    RepositoryId repositoryId,
    DiscardPreview preview,
  ) {
    throw UnimplementedError();
  }
}

class DeferredSettingsGateway extends FakeSettingsGateway {
  DeferredSettingsGateway(this.result);

  final Future<GitInstallation> result;

  @override
  Future<GitInstallation> getGitInstallation() => result;
}
