// ignore_for_file: prefer_initializing_formals
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:gift/src/backend/credentials.dart';
import 'package:gift/src/backend/error.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class SecureValueStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

class FlutterSecureValueStore implements SecureValueStore {
  FlutterSecureValueStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Stores the account index without secrets in SharedPreferences and stores
/// each secret under a separate platform-backed secure-storage key.
class SecureGitCredentialStore implements GitCredentialStore {
  SecureGitCredentialStore({
    required SharedPreferences preferences,
    SecureValueStore? secureStore,
  }) : _preferences = preferences,
       _secureStore = secureStore ?? FlutterSecureValueStore();

  static const _indexKey = 'gift.credentials.index.v1';
  static const _secretPrefix = 'gift.credentials.secret.v1.';

  final SharedPreferences _preferences;
  final SecureValueStore _secureStore;

  @override
  Future<List<GitCredentialAccount>> listAccounts() async {
    final raw = _preferences.getString(_indexKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) throw const FormatException('index is not a list');
      final accounts = <GitCredentialAccount>[];
      for (final item in decoded) {
        final account = GitCredentialAccount.fromJson(item);
        if (account == null) continue;
        try {
          accounts.add(validateGitCredentialAccount(account));
        } on GitError {
          // Ignore one corrupt account instead of making all local Git
          // workflows unavailable. The next save rewrites the clean index.
        }
      }
      return List.unmodifiable(accounts);
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(
        _storageError(
          'Saved Git accounts could not be read. You can add them again.',
          'credential metadata index was invalid: $error',
        ),
        stackTrace,
      );
    }
  }

  @override
  Future<String?> readSecret(String accountId) async {
    _validateAccountId(accountId);
    try {
      return await _secureStore.read('$_secretPrefix$accountId');
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(
        _storageError(
          'The secure credential store could not be opened.',
          'credential secret read failed: $error',
        ),
        stackTrace,
      );
    }
  }

  @override
  Future<GitCredentialAccount> saveAccount(
    GitCredentialAccount account, {
    String? secret,
    bool clearSecret = false,
  }) async {
    final normalized = validateGitCredentialAccount(account);
    final accounts = [...await listAccounts()];
    final index = accounts.indexWhere(
      (candidate) => candidate.id == account.id,
    );
    if (index == -1) {
      accounts.add(normalized);
    } else {
      accounts[index] = normalized;
    }
    if (normalized.isDefault) {
      for (var i = 0; i < accounts.length; i++) {
        final current = accounts[i];
        if (current.host == normalized.host && current.id != normalized.id) {
          accounts[i] = current.copyWith(isDefault: false);
        }
      }
    }
    try {
      if (clearSecret) {
        await _secureStore.delete('$_secretPrefix${normalized.id}');
      } else if (secret != null) {
        if (secret.isEmpty && normalized.kind == GitCredentialKind.httpsToken) {
          throw credentialInputError(
            'Enter a personal access token.',
            'empty HTTPS credential secret was rejected',
          );
        }
        await _secureStore.write('$_secretPrefix${normalized.id}', secret);
      }
      final saved = await _preferences.setString(
        _indexKey,
        jsonEncode(accounts.map((candidate) => candidate.toJson()).toList()),
      );
      if (!saved) {
        throw StateError('SharedPreferences rejected the credential index');
      }
    } on GitError {
      rethrow;
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(
        _storageError(
          'The Git account could not be saved securely.',
          'credential save failed: $error',
        ),
        stackTrace,
      );
    }
    return normalized;
  }

  @override
  Future<void> removeAccount(String accountId) async {
    _validateAccountId(accountId);
    final accounts = [...await listAccounts()]
      ..removeWhere((account) => account.id == accountId);
    try {
      await _secureStore.delete('$_secretPrefix$accountId');
      final saved = await _preferences.setString(
        _indexKey,
        jsonEncode(accounts.map((account) => account.toJson()).toList()),
      );
      if (!saved) throw StateError('SharedPreferences rejected the index');
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(
        _storageError(
          'The Git account could not be removed securely.',
          'credential removal failed: $error',
        ),
        stackTrace,
      );
    }
  }

  @override
  Future<void> setDefault(String host, String accountId) async {
    final normalizedHost = normalizeGitCredentialHost(host);
    final accounts = [...await listAccounts()];
    final selected = accounts
        .where((account) => account.id == accountId)
        .firstOrNull;
    if (selected == null || selected.host != normalizedHost) {
      throw credentialInputError(
        'That account does not belong to the selected host.',
        'default credential host did not match account metadata',
      );
    }
    for (var i = 0; i < accounts.length; i++) {
      final account = accounts[i];
      if (account.host == normalizedHost) {
        accounts[i] = account.copyWith(isDefault: account.id == accountId);
      }
    }
    try {
      final saved = await _preferences.setString(
        _indexKey,
        jsonEncode(accounts.map((account) => account.toJson()).toList()),
      );
      if (!saved) throw StateError('SharedPreferences rejected the index');
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(
        _storageError(
          'The default Git account could not be updated.',
          'credential default update failed: $error',
        ),
        stackTrace,
      );
    }
  }

  void _validateAccountId(String accountId) {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,96}$').hasMatch(accountId)) {
      throw credentialInputError(
        'That Git account is invalid. Choose another account.',
        'credential ID was not a bounded secure-storage key suffix',
      );
    }
  }
}

GitError _storageError(String message, String diagnostic) => GitError(
  category: GitErrorCategory.permissionDenied,
  userMessage: message,
  diagnostic: diagnostic,
  retryable: true,
);
