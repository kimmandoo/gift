import 'package:branchline/src/features/settings/git_settings_controller.dart';
import 'package:branchline/src/features/settings/git_settings_dialog.dart';
import 'package:branchline/src/backend/domain.dart';
import 'package:branchline/src/backend/error.dart';
import 'package:branchline/src/backend/git_gateway.dart';
import 'package:branchline/src/backend/status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('selects a valid executable and persists its path', (
    tester,
  ) async {
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

class FakeSettingsGateway implements GitGateway {
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
}
