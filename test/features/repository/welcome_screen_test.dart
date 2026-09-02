import 'package:branchline/src/features/repository/recent_repository_store.dart';
import 'package:branchline/src/features/repository/welcome_screen.dart';
import 'package:branchline/src/backend/domain.dart';
import 'package:branchline/src/backend/error.dart';
import 'package:branchline/src/backend/git_gateway.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('keeps recent repositories ordered and capped at ten entries', () async {
    final preferences = await SharedPreferences.getInstance();
    final store = RecentRepositoryStore(preferences);

    for (var index = 0; index < 11; index++) {
      await store.add('/repo-$index');
    }
    await store.add('/repo-5');

    final repositories = await store.load();
    expect(repositories, hasLength(10));
    expect(repositories.first.path, '/repo-5');
    expect(
      repositories.any((repository) => repository.path == '/repo-0'),
      isFalse,
    );
  });

  testWidgets('opens a selected folder and stores its canonical root', (
    tester,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final gateway = FakeGitGateway(
      installation: const GitInstallation(
        executablePath: '/usr/bin/git',
        version: '2.51.0',
      ),
      opened: const RepositoryOpened(
        repositoryId: RepositoryId(value: 'opaque-id'),
        root: '/workspace/project',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WelcomeScreen(
          gateway: gateway,
          recentStore: RecentRepositoryStore(preferences),
          selectDirectory: () async => '/workspace/project/src',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Repository'));
    await tester.pumpAndSettle();

    expect(gateway.openedPaths, ['/workspace/project/src']);
    expect(preferences.getStringList(RecentRepositoryStore.pathsKey), [
      '/workspace/project',
    ]);
    expect(find.text('/workspace/project'), findsOneWidget);
  });

  testWidgets('displays and removes a missing recent repository', (
    tester,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(RecentRepositoryStore.pathsKey, [
      '/path/that/is/not/present',
    ]);

    final gateway = FakeGitGateway(
      installation: const GitInstallation(
        executablePath: '/usr/bin/git',
        version: '2.51.0',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: WelcomeScreen(
          gateway: gateway,
          recentStore: RecentRepositoryStore(preferences),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Missing'), findsOneWidget);
    await tester.tap(find.byTooltip('Remove'));
    await tester.pumpAndSettle();

    expect(find.text('/path/that/is/not/present'), findsNothing);
    expect(preferences.getStringList(RecentRepositoryStore.pathsKey), isEmpty);
  });

  testWidgets(
    'presents a not-repository error without calling the bridge directly',
    (tester) async {
      final preferences = await SharedPreferences.getInstance();
      final gateway = FakeGitGateway(
        installation: const GitInstallation(
          executablePath: '/usr/bin/git',
          version: '2.51.0',
        ),
        openError: const GitError(
          category: GitErrorCategory.notRepository,
          userMessage: 'The selected folder is not a Git repository.',
          diagnostic: 'test diagnostic',
          retryable: false,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: WelcomeScreen(
            gateway: gateway,
            recentStore: RecentRepositoryStore(preferences),
            selectDirectory: () async => '/tmp/not-a-repository',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Repository'));
      await tester.pumpAndSettle();

      expect(
        find.text('The selected folder is not a Git repository.'),
        findsOneWidget,
      );
      expect(preferences.getStringList(RecentRepositoryStore.pathsKey), isNull);
    },
  );

  testWidgets('keeps repository actions disabled when Git is not found', (
    tester,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final gateway = FakeGitGateway(
      installationError: const GitError(
        category: GitErrorCategory.gitNotFound,
        userMessage: 'Git could not be found.',
        diagnostic: 'PATH did not contain Git',
        retryable: true,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: WelcomeScreen(
          gateway: gateway,
          recentStore: RecentRepositoryStore(preferences),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    expect(find.text('Git could not be found.'), findsOneWidget);
  });
}

class FakeGitGateway implements GitGateway {
  FakeGitGateway({
    this.installation,
    this.installationError,
    this.opened,
    this.openError,
  });

  final GitInstallation? installation;
  final GitError? installationError;
  final RepositoryOpened? opened;
  final GitError? openError;
  final List<String> openedPaths = <String>[];

  @override
  Future<GitInstallation> configureGitPath(String path) {
    throw UnimplementedError();
  }

  @override
  Future<GitInstallation> getGitInstallation() async {
    if (installationError != null) throw installationError!;
    return installation!;
  }

  @override
  Future<RepositoryOpened> openRepository(String path) async {
    openedPaths.add(path);
    if (openError != null) throw openError!;
    return opened!;
  }
}
