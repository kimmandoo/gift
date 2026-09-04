import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:gift/src/backend/credentials.dart';

/// Persists only repository-to-account choices. Secrets remain owned by the
/// credential store and are never copied into this mapping.
class RepositoryCredentialStore {
  RepositoryCredentialStore(this.preferences);

  RepositoryCredentialStore.inMemory() : preferences = null;

  static const storageKey = 'gift.repository-credentials.v1';

  final SharedPreferences? preferences;
  final Map<String, Map<String, String>> _memory = {};

  String? accountIdFor(String repositoryRoot, String host) {
    final normalizedHost = normalizeGitCredentialHost(host);
    return _read()[repositoryRoot]?[normalizedHost];
  }

  Future<void> setAccountId(
    String repositoryRoot,
    String host,
    String? accountId,
  ) async {
    if (repositoryRoot.trim().isEmpty) {
      throw ArgumentError.value(repositoryRoot, 'repositoryRoot');
    }
    final normalizedRoot = repositoryRoot.trim();
    final normalizedHost = normalizeGitCredentialHost(host);
    final mappings = _read();
    final hosts = mappings.putIfAbsent(normalizedRoot, () => {});
    if (accountId == null || accountId.trim().isEmpty) {
      hosts.remove(normalizedHost);
    } else {
      hosts[normalizedHost] = accountId.trim();
    }
    if (hosts.isEmpty) mappings.remove(normalizedRoot);
    await _write(mappings);
  }

  Map<String, String> accountsFor(String repositoryRoot) =>
      Map.unmodifiable(_read()[repositoryRoot] ?? const <String, String>{});

  Map<String, Map<String, String>> _read() {
    final prefs = preferences;
    if (prefs == null) return _copy(_memory);
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final result = <String, Map<String, String>>{};
      for (final entry in decoded.entries) {
        if (entry.key is! String || entry.value is! Map) continue;
        final hosts = <String, String>{};
        for (final hostEntry in (entry.value as Map).entries) {
          if (hostEntry.key is String && hostEntry.value is String) {
            hosts[hostEntry.key as String] = hostEntry.value as String;
          }
        }
        if (hosts.isNotEmpty) result[entry.key as String] = hosts;
      }
      return result;
    } on Object {
      return {};
    }
  }

  Future<void> _write(Map<String, Map<String, String>> mappings) async {
    _memory
      ..clear()
      ..addAll(_copy(mappings));
    final prefs = preferences;
    if (prefs != null) {
      await prefs.setString(storageKey, jsonEncode(mappings));
    }
  }

  Map<String, Map<String, String>> _copy(
    Map<String, Map<String, String>> source,
  ) => {
    for (final entry in source.entries) entry.key: {...entry.value},
  };
}
