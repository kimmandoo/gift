import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gift/src/app/secure_credential_store.dart';
import 'package:gift/src/app/repository_credential_store.dart';
import 'package:gift/src/backend/executor.dart';
import 'package:gift/src/backend/repository_service.dart';
import 'package:gift/src/backend/error.dart';
import 'package:gift/src/backend/credentials.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('parses HTTPS, SCP-style SSH, and rejects unsafe remotes', () {
    final https = parseGitRemoteEndpoint('https://GitHub.com/org/repo.git');
    expect(https?.host, 'github.com');
    expect(https?.transport, GitRemoteTransport.https);
    final ssh = parseGitRemoteEndpoint('git@gitlab.com:team/repo.git');
    expect(ssh?.host, 'gitlab.com');
    expect(ssh?.transport, GitRemoteTransport.ssh);
    expect(
      parseGitRemoteEndpoint('https://github.com/org/repo.git?token=x'),
      isNull,
    );
    expect(
      parseGitRemoteEndpoint('https://github.com/org/repo.git#fragment'),
      isNull,
    );
    expect(parseGitRemoteEndpoint('https://github.com/org/repo.git\n'), isNull);
  });

  test('resolves the explicit or host default HTTPS account', () async {
    final first = account(
      id: 'first',
      host: 'github.com',
      accountName: 'First',
      isDefault: false,
    );
    final second = account(
      id: 'second',
      host: 'github.com',
      accountName: 'Second',
      isDefault: true,
    );
    final store = InMemoryGitCredentialStore(
      records: [
        GitCredentialRecord(account: first, secret: 'first-token'),
        GitCredentialRecord(account: second, secret: 'second-token'),
      ],
    );
    final resolver = StoreGitCredentialResolver(store);

    final automatic = await resolver.resolve('https://github.com/org/repo.git');
    expect(automatic, isNotNull);
    expect(automatic!.environment['GIFT_ASKPASS_TOKEN'], 'second-token');

    final explicit = await resolver.resolve(
      'https://github.com/org/repo.git',
      accountId: 'first',
    );
    expect(explicit!.environment['GIFT_ASKPASS_TOKEN'], 'first-token');

    await expectLater(
      resolver.resolve('https://gitlab.com/org/repo.git', accountId: 'first'),
      throwsA(isA<GitError>()),
    );
    await automatic.cleanup();
    await explicit.cleanup();
  });

  test(
    'injects SSH key path and passphrase without writing key material',
    () async {
      final store = InMemoryGitCredentialStore(
        records: [
          GitCredentialRecord(
            account: account(
              id: 'ssh',
              host: 'git.example.com',
              accountName: 'SSH work',
              kind: GitCredentialKind.sshKey,
              sshKeyPath: '/tmp/private key',
            ),
            secret: 'key-passphrase',
          ),
        ],
      );
      final auth = await StoreGitCredentialResolver(store)
          .resolve('git@git.example.com:team/repo.git');

      expect(auth, isNotNull);
      expect(
        auth!.environment['GIT_SSH_COMMAND'],
        contains("'/tmp/private key'"),
      );
      expect(auth.environment['SSH_ASKPASS_REQUIRE'], 'force');
      expect(auth.sensitiveValues, contains('key-passphrase'));
      await auth.cleanup();
    },
  );

  test('stores only credential metadata in preferences', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final secure = _FakeSecureValueStore();
    final store = SecureGitCredentialStore(
      preferences: preferences,
      secureStore: secure,
    );
    final saved = await store.saveAccount(
      account(
        id: 'secure',
        host: 'git.example.com',
        accountName: 'Secure work',
      ),
      secret: 'super-secret-token',
    );

    final rawIndex = preferences.getString('gift.credentials.index.v1');
    expect(rawIndex, isNotNull);
    expect(rawIndex, isNot(contains('super-secret-token')));
    expect(
      secure.values['gift.credentials.secret.v1.secure'],
      'super-secret-token',
    );
    expect((await store.listAccounts()).single, saved);

    await store.removeAccount('secure');
    expect(secure.values, isEmpty);
    expect(await store.listAccounts(), isEmpty);
  });

  test('stores repository-specific account choices without secrets', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final store = RepositoryCredentialStore(preferences);

    await store.setAccountId('C:/work/app', 'GitHub.com', 'work');

    expect(store.accountIdFor('C:/work/app', 'github.com'), 'work');
    expect(store.accountIdFor('C:/other/app', 'github.com'), isNull);
    expect(
      preferences.getString(RepositoryCredentialStore.storageKey),
      isNot(contains('token')),
    );
    await store.setAccountId('C:/work/app', 'github.com', null);
    expect(store.accountIdFor('C:/work/app', 'github.com'), isNull);
  });

  test('resolves browser OAuth accounts without a token', () async {
    final store = InMemoryGitCredentialStore(
      records: [
        GitCredentialRecord(
          account: account(
            id: 'browser',
            host: 'github.com',
            accountName: 'GitHub browser',
            kind: GitCredentialKind.webOAuth,
          ),
        ),
      ],
    );

    final auth = await StoreGitCredentialResolver(store)
        .resolve('https://github.com/org/repo.git', accountId: 'browser');

    expect(auth, isNotNull);
    expect(auth!.environment, isEmpty);
    await auth.cleanup();
  });

  test(
    'starts provider browser sign-in through Git Credential Manager',
    () async {
      final runner = _RecordingRunner();
      final result = await RepositoryService(
        gitPath: 'git',
        state: AppState(),
        runner: runner,
      ).loginWithBrowser(GitCredentialProvider.github);

      expect(result.host, 'github.com');
      expect(runner.invocations.single.args, [
        'credential-manager',
        'github',
        'login',
      ]);
      expect(
        runner.invocations.single.environment?['GCM_INTERACTIVE'],
        'Always',
      );
    },
  );

  test('cleans askpass helpers after use', () async {
    final auth = await StoreGitCredentialResolver(
      InMemoryGitCredentialStore(
        records: [
          GitCredentialRecord(
            account: GitCredentialAccount(
              id: 'cleanup',
              provider: GitCredentialProvider.generic,
              host: 'git.example.com',
              accountName: 'Cleanup',
              kind: GitCredentialKind.httpsToken,
            ),
            secret: 'cleanup-token',
          ),
        ],
      ),
    ).resolve('https://git.example.com/team/repo.git');
    final helper = auth!.environment['GIT_ASKPASS']!;
    expect(File(helper).existsSync(), isTrue);
    await auth.cleanup();
    expect(File(helper).existsSync(), isFalse);
  });
  test('injects credentials into private remote connection tests', () async {
    final runner = _RecordingRunner();
    final service = RepositoryService(
      gitPath: 'git',
      state: AppState(),
      runner: runner,
      credentialResolver: StoreGitCredentialResolver(
        InMemoryGitCredentialStore(
          records: [
            GitCredentialRecord(
              account: account(
                id: 'private',
                host: 'github.com',
                accountName: 'Private GitHub',
              ),
              secret: 'private-token',
            ),
          ],
        ),
      ),
    );

    final result = await service.testCredential(
      'https://github.com/org/private.git',
      accountId: 'private',
    );

    expect(result.referenceCount, 2);
    expect(runner.invocations, hasLength(1));
    final invocation = runner.invocations.single;
    expect(invocation.args, isNot(contains('private-token')));
    expect(invocation.environment?['GIFT_ASKPASS_TOKEN'], 'private-token');
  });
}

GitCredentialAccount account({
  required String id,
  required String host,
  required String accountName,
  GitCredentialKind kind = GitCredentialKind.httpsToken,
  String? sshKeyPath,
  bool isDefault = false,
}) => GitCredentialAccount(
  id: id,
  provider: providerForGitCredentialHost(host),
  host: host,
  accountName: accountName,
  kind: kind,
  username: kind == GitCredentialKind.httpsToken ? 'git' : null,
  sshKeyPath: sshKeyPath,
  isDefault: isDefault,
);

class _RecordingRunner extends ProcessGitRunner {
  final invocations = <GitInvocation>[];

  @override
  Future<ProcessOutput> run(GitInvocation invocation) async {
    invocations.add(invocation);
    await invocation.cleanup?.call();
    return ProcessOutput(
      stdout: utf8.encode(
        'a1b2c3 refs/heads/main\n'
        'd4e5f6 refs/tags/v1\n',
      ),
      stderr: const [],
      exitCode: 0,
    );
  }
}

class _FakeSecureValueStore implements SecureValueStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}
