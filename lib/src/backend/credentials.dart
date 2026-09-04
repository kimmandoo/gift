// ignore_for_file: prefer_initializing_formals
import 'dart:io';

import 'error.dart';

/// The provider label is metadata used for account matching and UI display.
/// Host equality remains the final authority, so self-hosted installations do
/// not need a provider-specific URL convention.
enum GitCredentialProvider { github, gitlab, generic }

enum GitCredentialKind { httpsToken, sshKey, sshAgent }

enum GitRemoteTransport { https, ssh, other }

class GitCredentialAccount {
  const GitCredentialAccount({
    required this.id,
    required this.provider,
    required this.host,
    required this.accountName,
    required this.kind,
    this.username,
    this.sshKeyPath,
    this.isDefault = false,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final GitCredentialProvider provider;
  final String host;
  final String accountName;
  final GitCredentialKind kind;
  final String? username;
  final String? sshKeyPath;
  final bool isDefault;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  GitCredentialAccount copyWith({
    String? id,
    GitCredentialProvider? provider,
    String? host,
    String? accountName,
    GitCredentialKind? kind,
    String? username,
    String? sshKeyPath,
    bool? isDefault,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => GitCredentialAccount(
    id: id ?? this.id,
    provider: provider ?? this.provider,
    host: host ?? this.host,
    accountName: accountName ?? this.accountName,
    kind: kind ?? this.kind,
    username: username ?? this.username,
    sshKeyPath: sshKeyPath ?? this.sshKeyPath,
    isDefault: isDefault ?? this.isDefault,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'provider': provider.name,
    'host': host,
    'accountName': accountName,
    'kind': kind.name,
    if (username != null) 'username': username,
    if (sshKeyPath != null) 'sshKeyPath': sshKeyPath,
    'isDefault': isDefault,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
  };

  static GitCredentialAccount? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final provider = _enumFromName<GitCredentialProvider>(
      GitCredentialProvider.values,
      value['provider'],
    );
    final host = value['host'];
    final accountName = value['accountName'];
    final kind = _enumFromName<GitCredentialKind>(
      GitCredentialKind.values,
      value['kind'],
    );
    if (id is! String ||
        provider == null ||
        host is! String ||
        accountName is! String ||
        kind == null) {
      return null;
    }
    return GitCredentialAccount(
      id: id,
      provider: provider,
      host: host,
      accountName: accountName,
      kind: kind,
      username: value['username'] is String
          ? value['username'] as String
          : null,
      sshKeyPath: value['sshKeyPath'] is String
          ? value['sshKeyPath'] as String
          : null,
      isDefault: value['isDefault'] == true,
      createdAt: _dateFromJson(value['createdAt']),
      updatedAt: _dateFromJson(value['updatedAt']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GitCredentialAccount &&
      other.id == id &&
      other.provider == provider &&
      other.host == host &&
      other.accountName == accountName &&
      other.kind == kind &&
      other.username == username &&
      other.sshKeyPath == sshKeyPath &&
      other.isDefault == isDefault &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    provider,
    host,
    accountName,
    kind,
    username,
    sshKeyPath,
    isDefault,
    createdAt,
    updatedAt,
  );
}

abstract interface class GitCredentialStore {
  Future<List<GitCredentialAccount>> listAccounts();

  Future<String?> readSecret(String accountId);

  Future<GitCredentialAccount> saveAccount(
    GitCredentialAccount account, {
    String? secret,
    bool clearSecret = false,
  });

  Future<void> removeAccount(String accountId);

  Future<void> setDefault(String host, String accountId);
}

abstract interface class GitCredentialResolver {
  Future<GitCredentialAuth?> resolve(String remoteUrl, {String? accountId});
}

class GitCredentialTestResult {
  const GitCredentialTestResult({
    required this.host,
    required this.referenceCount,
    required this.summary,
  });

  final String host;
  final int referenceCount;
  final String summary;
}

/// Optional gateway capability used by the account manager. Keeping it out of
/// [GitGateway] means existing local-only test gateways remain valid.
abstract interface class GitCredentialTestGateway {
  Future<GitCredentialTestResult> testCredential(
    String remoteUrl, {
    required String accountId,
  });
}

/// The process runner consumes this object for one invocation only. The
/// secret is held in the child environment and never in argv or a Git config
/// file. [cleanup] removes the temporary askpass helper after Git exits.
class GitCredentialAuth {
  GitCredentialAuth({
    required Map<String, String> environment,
    Iterable<String> sensitiveValues = const <String>[],
    Future<void> Function()? cleanup,
  }) : environment = Map.unmodifiable(environment),
       sensitiveValues = List.unmodifiable(
         sensitiveValues.where((value) => value.isNotEmpty),
       ),
       _cleanup = cleanup;

  final Map<String, String> environment;
  final List<String> sensitiveValues;
  final Future<void> Function()? _cleanup;
  var _cleanedUp = false;

  Future<void> cleanup() async {
    if (_cleanedUp) return;
    _cleanedUp = true;
    await _cleanup?.call();
  }
}

class NoopGitCredentialResolver implements GitCredentialResolver {
  const NoopGitCredentialResolver();

  @override
  Future<GitCredentialAuth?> resolve(
    String remoteUrl, {
    String? accountId,
  }) async => null;
}

/// Resolves the selected account at the last responsible moment. Account
/// metadata is listable, but secrets are read only immediately before Git is
/// started.
class StoreGitCredentialResolver implements GitCredentialResolver {
  const StoreGitCredentialResolver(this.store);

  final GitCredentialStore store;

  @override
  Future<GitCredentialAuth?> resolve(
    String remoteUrl, {
    String? accountId,
  }) async {
    final endpoint = parseGitRemoteEndpoint(remoteUrl);
    if (endpoint == null || endpoint.transport == GitRemoteTransport.other) {
      return null;
    }
    final accounts = await store.listAccounts();
    GitCredentialAccount? selected;
    if (accountId != null) {
      selected = accounts
          .where((account) => account.id == accountId)
          .firstOrNull;
      if (selected == null) {
        throw credentialInputError(
          'That account is no longer available. Choose another account.',
          'credential selector referenced an unknown account',
        );
      }
      if (!_matches(selected, endpoint)) {
        throw credentialInputError(
          'That account belongs to a different host. Choose an account for ${endpoint.host}.',
          'credential selector host did not match the remote host',
        );
      }
    } else {
      final matching = accounts
          .where((account) => _matches(account, endpoint))
          .toList(growable: false);
      selected = matching.where((account) => account.isDefault).firstOrNull;
      selected ??= matching.firstOrNull;
    }
    if (selected == null) return null;

    final secret = selected.kind == GitCredentialKind.sshAgent
        ? null
        : await store.readSecret(selected.id);
    switch ((endpoint.transport, selected.kind)) {
      case (GitRemoteTransport.https, GitCredentialKind.httpsToken):
        if (secret == null || secret.isEmpty) {
          throw credentialInputError(
            'The selected account has no token. Edit it or choose another account.',
            'HTTPS credential secret was absent from secure storage',
          );
        }
        return _createAskpassAuth(
          username: selected.username?.trim().isEmpty == false
              ? selected.username!.trim()
              : 'git',
          secret: secret,
        );
      case (GitRemoteTransport.ssh, GitCredentialKind.sshKey):
        final keyPath = selected.sshKeyPath?.trim() ?? '';
        if (keyPath.isEmpty) {
          throw credentialInputError(
            'The selected SSH account has no private-key path.',
            'SSH key credential metadata was missing its path',
          );
        }
        final askpass = secret == null || secret.isEmpty
            ? null
            : await _createAskpassAuth(username: '', secret: secret);
        return GitCredentialAuth(
          environment: <String, String>{
            ...?askpass?.environment,
            'GIT_SSH_COMMAND':
                'ssh -o IdentitiesOnly=yes -i ${_shellQuote(keyPath)}',
            if (askpass != null) ...{
              'SSH_ASKPASS': askpass.environment['GIT_ASKPASS']!,
              'SSH_ASKPASS_REQUIRE': 'force',
            },
          },
          sensitiveValues: secret == null ? const [] : [secret],
          cleanup: askpass?.cleanup,
        );
      case (GitRemoteTransport.ssh, GitCredentialKind.sshAgent):
        return GitCredentialAuth(environment: const <String, String>{});
      default:
        throw credentialInputError(
          'That credential type cannot authenticate this remote. Choose a compatible account.',
          'credential transport and account kind did not match',
        );
    }
  }

  bool _matches(GitCredentialAccount account, GitRemoteEndpoint endpoint) {
    if (account.host != endpoint.host) return false;
    final provider = providerForGitCredentialHost(endpoint.host);
    if (provider != GitCredentialProvider.generic &&
        account.provider != provider &&
        account.provider != GitCredentialProvider.generic) {
      return false;
    }
    return switch (endpoint.transport) {
      GitRemoteTransport.https => account.kind == GitCredentialKind.httpsToken,
      GitRemoteTransport.ssh =>
        account.kind == GitCredentialKind.sshKey ||
            account.kind == GitCredentialKind.sshAgent,
      GitRemoteTransport.other => false,
    };
  }
}

class InMemoryGitCredentialStore implements GitCredentialStore {
  InMemoryGitCredentialStore({
    Iterable<GitCredentialRecord> records = const [],
  }) {
    for (final record in records) {
      _accounts[record.account.id] = record.account;
      _secrets[record.account.id] = record.secret;
    }
  }

  final Map<String, GitCredentialAccount> _accounts = {};
  final Map<String, String?> _secrets = {};
  @override
  Future<List<GitCredentialAccount>> listAccounts() async =>
      List.unmodifiable(_accounts.values);

  @override
  Future<String?> readSecret(String accountId) async => _secrets[accountId];

  @override
  Future<GitCredentialAccount> saveAccount(
    GitCredentialAccount account, {
    String? secret,
    bool clearSecret = false,
  }) async {
    final normalized = validateGitCredentialAccount(account);
    _replaceAccount(normalized);
    if (clearSecret) {
      _secrets.remove(account.id);
    } else if (secret != null) {
      _secrets[account.id] = secret;
    }
    return normalized;
  }

  @override
  Future<void> removeAccount(String accountId) async {
    _accounts.remove(accountId);
    _secrets.remove(accountId);
  }

  @override
  Future<void> setDefault(String host, String accountId) async {
    final account = _accounts[accountId];
    if (account == null || account.host != normalizeGitCredentialHost(host)) {
      throw credentialInputError(
        'That account does not belong to the selected host.',
        'default credential host did not match account metadata',
      );
    }
    for (final current in _accounts.values.toList(growable: false)) {
      if (current.host == account.host) {
        _accounts[current.id] = current.copyWith(
          isDefault: current.id == accountId,
        );
      }
    }
  }

  void _replaceAccount(GitCredentialAccount account) {
    if (account.isDefault) {
      for (final current in _accounts.values.toList(growable: false)) {
        if (current.host == account.host && current.id != account.id) {
          _accounts[current.id] = current.copyWith(isDefault: false);
        }
      }
    }
    _accounts[account.id] = account;
  }
}

class GitCredentialRecord {
  const GitCredentialRecord({required this.account, this.secret});

  final GitCredentialAccount account;
  final String? secret;
}

class GitRemoteEndpoint {
  const GitRemoteEndpoint({required this.host, required this.transport});

  final String host;
  final GitRemoteTransport transport;
}

GitRemoteEndpoint? parseGitRemoteEndpoint(String remoteUrl) {
  if (remoteUrl.isEmpty ||
      remoteUrl != remoteUrl.trim() ||
      remoteUrl.runes.any((rune) => rune < 0x20 || rune == 0x7f)) {
    return null;
  }
  if (!remoteUrl.contains('://')) {
    final scp = RegExp(r'^(?:[^@/:\s]+@)?([^/:\s]+):.+$').firstMatch(remoteUrl);
    if (scp == null) return null;
    return GitRemoteEndpoint(
      host: normalizeGitCredentialHost(scp.group(1)!),
      transport: GitRemoteTransport.ssh,
    );
  }
  final parsed = Uri.tryParse(remoteUrl);
  if (parsed == null ||
      parsed.host.isEmpty ||
      parsed.query.isNotEmpty ||
      parsed.fragment.isNotEmpty) {
    return null;
  }
  final transport = switch (parsed.scheme.toLowerCase()) {
    'https' => GitRemoteTransport.https,
    'ssh' => GitRemoteTransport.ssh,
    _ => GitRemoteTransport.other,
  };
  return GitRemoteEndpoint(
    host: normalizeGitCredentialHost(parsed.host),
    transport: transport,
  );
}

String normalizeGitCredentialHost(String host) {
  final normalized = host.trim().toLowerCase().replaceFirst(
    RegExp(r'\.+$'),
    '',
  );
  if (normalized.isEmpty ||
      normalized.contains('/') ||
      normalized.contains('\\') ||
      normalized.runes.any((rune) => rune < 0x20 || rune == 0x7f)) {
    throw credentialInputError(
      'Enter a valid remote host.',
      'credential host contained an empty, path, or control value',
    );
  }
  return normalized;
}

GitCredentialProvider providerForGitCredentialHost(String host) {
  final normalized = normalizeGitCredentialHost(host);
  if (normalized == 'github.com' || normalized.startsWith('github.')) {
    return GitCredentialProvider.github;
  }
  if (normalized == 'gitlab.com' || normalized.startsWith('gitlab.')) {
    return GitCredentialProvider.gitlab;
  }
  return GitCredentialProvider.generic;
}

GitCredentialAccount validateGitCredentialAccount(
  GitCredentialAccount account,
) {
  final idPattern = RegExp(r'^[A-Za-z0-9_-]{1,96}$');
  if (!idPattern.hasMatch(account.id)) {
    throw credentialInputError(
      'The account identifier is invalid. Try saving it again.',
      'credential account ID was not a bounded opaque identifier',
    );
  }
  final host = normalizeGitCredentialHost(account.host);
  final expectedProvider = providerForGitCredentialHost(host);
  if (expectedProvider != GitCredentialProvider.generic &&
      account.provider != expectedProvider &&
      account.provider != GitCredentialProvider.generic) {
    throw credentialInputError(
      'Choose the provider that matches this host.',
      'credential provider metadata did not match the known host',
    );
  }
  if (account.accountName.trim().isEmpty ||
      account.accountName.contains('\n')) {
    throw credentialInputError(
      'Enter an account name.',
      'credential account name was empty or multiline',
    );
  }
  if (account.kind == GitCredentialKind.sshKey &&
      (account.sshKeyPath == null || account.sshKeyPath!.trim().isEmpty)) {
    throw credentialInputError(
      'Choose an SSH private-key path.',
      'SSH key credential did not include a path',
    );
  }
  return account.copyWith(host: host);
}

GitError credentialInputError(String message, String diagnostic) => GitError(
  category: GitErrorCategory.parseFailure,
  userMessage: message,
  diagnostic: diagnostic,
  retryable: false,
);

Future<GitCredentialAuth> _createAskpassAuth({
  required String username,
  required String secret,
}) async {
  final directory = await Directory.systemTemp.createTemp('gift-askpass-');
  final extension = Platform.isWindows ? '.cmd' : '.sh';
  final helper = File('${directory.path}/askpass$extension');
  try {
    if (Platform.isWindows) {
      await helper.writeAsString(
        '@echo off\r\n'
        'powershell.exe -NoLogo -NoProfile -NonInteractive '
        '-ExecutionPolicy Bypass -File "%~dp0askpass.ps1" "%~1"\r\n',
      );
      await File('${directory.path}/askpass.ps1').writeAsString(
        r'''$prompt = if ($args.Length -gt 0) { $args[0] } else { '' }
if ($prompt -match '(?i)username') { [Console]::WriteLine($env:GIFT_ASKPASS_USERNAME) } else { [Console]::WriteLine($env:GIFT_ASKPASS_TOKEN) }
''',
      );
    } else {
      await helper.writeAsString(r'''#!/bin/sh
case "$1" in
  *[Uu]sername*) printf '%s\n' "$GIFT_ASKPASS_USERNAME" ;;
  *) printf '%s\n' "$GIFT_ASKPASS_TOKEN" ;;
esac
''');
      final chmod = await Process.run('chmod', [
        '700',
        helper.path,
      ], runInShell: false);
      if (chmod.exitCode != 0) {
        throw StateError('chmod exited with ${chmod.exitCode}');
      }
    }
  } on Object catch (error, stackTrace) {
    try {
      await directory.delete(recursive: true);
    } on Object {
      // Cleanup is best effort after helper preparation fails.
    }
    Error.throwWithStackTrace(
      GitError(
        category: GitErrorCategory.processSpawnFailed,
        userMessage: 'Git authentication helper could not be prepared.',
        diagnostic: 'askpass helper setup failed: $error',
        retryable: true,
      ),
      stackTrace,
    );
  }
  return GitCredentialAuth(
    environment: {
      'GIT_ASKPASS': helper.path,
      'GIT_TERMINAL_PROMPT': '0',
      'GIFT_ASKPASS_USERNAME': username,
      'GIFT_ASKPASS_TOKEN': secret,
    },
    sensitiveValues: [secret],
    cleanup: () async {
      try {
        await directory.delete(recursive: true);
      } on Object {
        // Helper cleanup must not replace Git's result.
      }
    },
  );
}

String _shellQuote(String value) => "'${value.replaceAll("'", "'\\''")}'";

T? _enumFromName<T extends Enum>(List<T> values, Object? raw) {
  if (raw is! String) return null;
  for (final value in values) {
    if (value.name == raw) return value;
  }
  return null;
}

DateTime? _dateFromJson(Object? raw) =>
    raw is String ? DateTime.tryParse(raw) : null;
