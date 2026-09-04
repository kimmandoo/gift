import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:gift/src/backend/credentials.dart';
import 'package:gift/src/backend/error.dart';

class CredentialsDialog extends StatefulWidget {
  const CredentialsDialog({super.key, required this.store, this.tester});

  final GitCredentialStore store;
  final GitCredentialTestGateway? tester;

  @override
  State<CredentialsDialog> createState() => _CredentialsDialogState();
}

class _CredentialsDialogState extends State<CredentialsDialog> {
  final _hostController = TextEditingController();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController(text: 'git');
  final _secretController = TextEditingController();
  final _keyPathController = TextEditingController();
  final _testUrlController = TextEditingController();
  final _searchController = TextEditingController();

  List<GitCredentialAccount>? _accounts;
  String? _editingId;
  GitCredentialProvider _provider = GitCredentialProvider.generic;
  GitCredentialKind _kind = GitCredentialKind.httpsToken;
  var _isDefault = false;
  var _showForm = true;
  var _busy = false;
  String? _error;
  String? _message;

  bool get _isEditing => _editingId != null;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _hostController.dispose();
    _nameController.dispose();
    _usernameController.dispose();
    _secretController.dispose();
    _keyPathController.dispose();
    _testUrlController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final accounts = _accounts;
    final visibleAccounts = accounts == null
        ? const <GitCredentialAccount>[]
        : _visibleAccounts(accounts);
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.key_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 10),
          const Expanded(child: Text('Git accounts')),
          if (accounts != null)
            Text(
              '${accounts.length} saved',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
      content: SizedBox(
        width: (size.width - 48).clamp(300.0, 700.0),
        height: (size.height - 160).clamp(360.0, 640.0),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _securityCard(),
            const SizedBox(height: 12),
            if (_error case final error?) _messageBanner(error, isError: true),
            if (_message case final message?)
              _messageBanner(message, isError: false),
            if (accounts == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (accounts.isEmpty)
              _emptyState()
            else ...[
              _accountToolbar(accounts.length),
              const SizedBox(height: 12),
              if (visibleAccounts.isEmpty)
                _noSearchResults()
              else
                for (final entry in _groupAccounts(
                  visibleAccounts,
                ).entries) ...[
                  _hostHeader(entry.key, entry.value.length),
                  for (final account in entry.value) _accountTile(account),
                  const SizedBox(height: 10),
                ],
            ],
            if (_showForm) ...[
              if (accounts?.isNotEmpty ?? false) const SizedBox(height: 4),
              _formCard(),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        if (_showForm && (accounts?.isNotEmpty ?? false))
          TextButton(
            key: const Key('credential-cancel'),
            onPressed: _busy ? null : _closeForm,
            child: const Text('Cancel'),
          ),
        if (_showForm)
          OutlinedButton(
            key: const Key('credential-test'),
            onPressed: _busy ? null : () => _save(testAfterSave: true),
            child: const Text('Save and test'),
          ),
        if (_showForm)
          FilledButton(
            key: const Key('credential-save'),
            onPressed: _busy ? null : _save,
            child: Text(_isEditing ? 'Save changes' : 'Save account'),
          ),
      ],
    );
  }

  Widget _securityCard() {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lock_outline, color: scheme.onSecondaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Secrets stay in the platform secure store. Private-key files '
                'stay at their original path and are never copied.',
                style: TextStyle(color: scheme.onSecondaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _messageBanner(String text, {required bool isError}) {
    final scheme = Theme.of(context).colorScheme;
    final background = isError
        ? scheme.errorContainer
        : scheme.primaryContainer;
    final foreground = isError
        ? scheme.onErrorContainer
        : scheme.onPrimaryContainer;
    return Container(
      key: Key(isError ? 'credential-error' : 'credential-message'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      color: background,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            size: 18,
            color: foreground,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: foreground)),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() => Card(
    color: Theme.of(context).colorScheme.surfaceContainerHigh,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.account_circle_outlined,
            color: Theme.of(context).colorScheme.primary,
            size: 30,
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Add your first Git account'),
                SizedBox(height: 4),
                Text(
                  'The form below connects private remotes without putting '
                  'tokens in Git configuration or command arguments.',
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _accountToolbar(int count) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              'Saved accounts',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          Text('$count total', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      const SizedBox(height: 8),
      TextField(
        key: const Key('credential-search'),
        controller: _searchController,
        enabled: !_busy,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: 'Search accounts',
          hintText: 'Name, host, provider, or credential type',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(
                  key: const Key('credential-clear-search'),
                  tooltip: 'Clear account search',
                  onPressed: _busy
                      ? null
                      : () {
                          _searchController.clear();
                          setState(() {});
                        },
                  icon: const Icon(Icons.clear),
                ),
          isDense: true,
        ),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton.icon(
          key: const Key('credential-new'),
          onPressed: _busy ? null : _openNew,
          icon: const Icon(Icons.add),
          label: const Text('Add account'),
        ),
      ),
    ],
  );

  Widget _noSearchResults() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const Icon(Icons.search_off_outlined),
          const SizedBox(height: 8),
          const Text('No matching accounts'),
          const SizedBox(height: 4),
          const Text('Try a different name, host, or credential type.'),
          const SizedBox(height: 8),
          TextButton(
            key: const Key('credential-clear-search-empty'),
            onPressed: _busy
                ? null
                : () {
                    _searchController.clear();
                    setState(() {});
                  },
            child: const Text('Show all accounts'),
          ),
        ],
      ),
    ),
  );

  Widget _hostHeader(String host, int count) => Padding(
    padding: const EdgeInsets.only(bottom: 6, left: 2),
    child: Row(
      children: [
        Icon(
          Icons.dns_outlined,
          size: 18,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(host, style: Theme.of(context).textTheme.titleSmall),
        ),
        Text(
          '$count ${count == 1 ? 'account' : 'accounts'}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );

  Widget _accountTile(GitCredentialAccount account) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: ValueKey('credential-account:${account.id}'),
      color: account.id == _editingId ? scheme.primaryContainer : null,
      child: ListTile(
        onTap: _busy ? null : () => _edit(account),
        leading: Icon(
          _kindIcon(account.kind),
          color: account.id == _editingId
              ? scheme.onPrimaryContainer
              : scheme.primary,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(account.accountName, overflow: TextOverflow.ellipsis),
            ),
            if (account.isDefault)
              const Chip(
                label: Text('Default'),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        subtitle: Text(
          '${_providerLabel(account.provider)} · ${_kindShortLabel(account.kind)}',
          overflow: TextOverflow.ellipsis,
        ),
        trailing: PopupMenuButton<_AccountAction>(
          key: ValueKey('credential-actions:${account.id}'),
          tooltip: 'Account actions',
          onSelected: (action) {
            switch (action) {
              case _AccountAction.setDefault:
                unawaited(_setDefault(account));
              case _AccountAction.edit:
                _edit(account);
              case _AccountAction.remove:
                unawaited(_remove(account));
            }
          },
          itemBuilder: (context) => [
            if (!account.isDefault)
              PopupMenuItem(
                key: ValueKey('credential-default:${account.id}'),
                value: _AccountAction.setDefault,
                child: const _AccountMenuLabel(
                  icon: Icons.star_border,
                  label: 'Use as default',
                ),
              ),
            PopupMenuItem(
              key: ValueKey('credential-edit:${account.id}'),
              value: _AccountAction.edit,
              child: const _AccountMenuLabel(
                icon: Icons.edit_outlined,
                label: 'Edit account',
              ),
            ),
            PopupMenuItem(
              key: ValueKey('credential-remove:${account.id}'),
              value: _AccountAction.remove,
              child: const _AccountMenuLabel(
                icon: Icons.delete_outline,
                label: 'Revoke local access',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _formCard() => Card(
    key: const Key('credential-editor'),
    color: Theme.of(context).colorScheme.surfaceContainerHigh,
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isEditing ? 'Edit account' : 'Add account',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 2),
          Text(
            _isEditing
                ? 'Update connection details without replacing the saved secret.'
                : 'Save one account per host, then choose it for private remotes.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final host = TextField(
                key: const Key('credential-host'),
                controller: _hostController,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'Host',
                  hintText: 'github.com or git.example.com',
                  helperText: 'The host part of the remote URL.',
                  isDense: true,
                ),
                onChanged: (_) => setState(_clearFeedback),
              );
              final name = TextField(
                key: const Key('credential-account-name'),
                controller: _nameController,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'Account name',
                  hintText: 'Work GitHub',
                  helperText: 'A label only you will see.',
                  isDense: true,
                ),
                onChanged: (_) => setState(_clearFeedback),
              );
              if (constraints.maxWidth >= 500) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: host),
                    const SizedBox(width: 10),
                    Expanded(child: name),
                  ],
                );
              }
              return Column(children: [host, const SizedBox(height: 10), name]);
            },
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<GitCredentialProvider>(
            key: const Key('credential-provider'),
            initialValue: _provider,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Provider',
              helperText: 'Detected hosts can still use Generic host.',
              isDense: true,
            ),
            items: GitCredentialProvider.values
                .map(
                  (provider) => DropdownMenuItem(
                    value: provider,
                    child: Text(_providerLabel(provider)),
                  ),
                )
                .toList(),
            onChanged: _busy
                ? null
                : (value) {
                    if (value != null) {
                      setState(() {
                        _provider = value;
                        _clearFeedback();
                      });
                    }
                  },
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<GitCredentialKind>(
            key: const Key('credential-kind'),
            initialValue: _kind,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Credential type',
              helperText:
                  'Use HTTPS tokens for HTTPS remotes and SSH for SSH remotes.',
              isDense: true,
            ),
            items: GitCredentialKind.values
                .map(
                  (kind) => DropdownMenuItem(
                    value: kind,
                    child: Text(_kindLabel(kind)),
                  ),
                )
                .toList(),
            onChanged: _busy
                ? null
                : (value) {
                    if (value != null) {
                      setState(() {
                        _kind = value;
                        _clearFeedback();
                      });
                    }
                  },
          ),
          if (_kind == GitCredentialKind.httpsToken) ...[
            const SizedBox(height: 10),
            TextField(
              key: const Key('credential-username'),
              controller: _usernameController,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'HTTPS username',
                hintText: 'git',
                helperText:
                    'Usually git for GitHub, GitLab, and hosted services.',
                isDense: true,
              ),
              onChanged: (_) => _clearFeedback(),
            ),
          ],
          if (_kind == GitCredentialKind.sshKey) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('credential-key-path'),
                    controller: _keyPathController,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      labelText: 'SSH private-key path',
                      hintText: '~/.ssh/id_ed25519',
                      helperText:
                          'The key stays on disk and is never imported.',
                      isDense: true,
                    ),
                    onChanged: (_) => _clearFeedback(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  key: const Key('credential-browse-key'),
                  tooltip: 'Browse for private key',
                  onPressed: _busy ? null : _pickKey,
                  icon: const Icon(Icons.folder_open_outlined),
                ),
              ],
            ),
          ],
          if (_kind != GitCredentialKind.sshAgent) ...[
            const SizedBox(height: 10),
            TextField(
              key: const Key('credential-secret'),
              controller: _secretController,
              enabled: !_busy,
              obscureText: true,
              decoration: InputDecoration(
                labelText: _kind == GitCredentialKind.httpsToken
                    ? 'Personal access token'
                    : 'SSH passphrase (optional)',
                hintText: _isEditing
                    ? 'Leave blank to keep the saved secret'
                    : 'Paste the secret; it will not be shown again',
                helperText: _isEditing
                    ? 'Enter a new value only when you want to replace it.'
                    : 'Stored only in the platform secure store.',
                suffixIcon: const Icon(Icons.lock_outline),
                isDense: true,
              ),
              onChanged: (_) => _clearFeedback(),
            ),
          ],
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            key: const Key('credential-default'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Use as default for this host'),
            subtitle: const Text(
              'Git operations use this account automatically when the host matches.',
            ),
            value: _isDefault,
            onChanged: _busy
                ? null
                : (value) => setState(() {
                    _isDefault = value;
                    _clearFeedback();
                  }),
          ),
          const Divider(height: 20),
          Text(
            'Connection test',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 2),
          Text(
            'Optional: save first, then verify access with a private remote URL.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('credential-test-url'),
            controller: _testUrlController,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'Remote URL to test',
              hintText: 'https://github.com/org/private-repo.git',
              isDense: true,
            ),
            onChanged: (_) => _clearFeedback(),
          ),
        ],
      ),
    ),
  );
  List<GitCredentialAccount> _visibleAccounts(
    List<GitCredentialAccount> accounts,
  ) {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return accounts;
    return accounts
        .where(
          (account) => [
            account.accountName,
            account.host,
            _providerLabel(account.provider),
            _kindLabel(account.kind),
          ].any((value) => value.toLowerCase().contains(query)),
        )
        .toList(growable: false);
  }

  Map<String, List<GitCredentialAccount>> _groupAccounts(
    List<GitCredentialAccount> accounts,
  ) {
    final groups = <String, List<GitCredentialAccount>>{};
    for (final account in accounts) {
      groups.putIfAbsent(account.host, () => []).add(account);
    }
    return groups;
  }

  IconData _kindIcon(GitCredentialKind kind) => switch (kind) {
    GitCredentialKind.httpsToken => Icons.http_outlined,
    GitCredentialKind.sshKey => Icons.vpn_key_outlined,
    GitCredentialKind.sshAgent => Icons.memory_outlined,
  };

  void _openNew() {
    _resetForm();
  }

  void _closeForm() {
    setState(() {
      _showForm = false;
      _editingId = null;
      _clearFeedback();
    });
  }

  Future<void> _pickKey() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'SSH private key', extensions: ['pem', 'key']),
      ],
    );
    if (file != null && mounted) {
      setState(() => _keyPathController.text = file.path);
    }
  }

  Future<void> _load() async {
    try {
      final accounts = await widget.store.listAccounts();
      if (mounted) {
        setState(() {
          _accounts = accounts;
          if (_editingId == null) _showForm = accounts.isEmpty;
        });
      }
    } on GitError catch (error) {
      if (mounted) setState(() => _error = error.userMessage);
    } on Object {
      if (mounted) setState(() => _error = 'Accounts could not be loaded.');
    }
  }

  void _resetForm() {
    setState(() {
      _showForm = true;
      _editingId = null;
      _hostController.clear();
      _nameController.clear();
      _usernameController.text = 'git';
      _secretController.clear();
      _keyPathController.clear();
      _testUrlController.clear();
      _provider = GitCredentialProvider.generic;
      _kind = GitCredentialKind.httpsToken;
      _isDefault = false;
      _clearFeedback();
    });
  }

  void _edit(GitCredentialAccount account) {
    setState(() {
      _showForm = true;
      _editingId = account.id;
      _hostController.text = account.host;
      _nameController.text = account.accountName;
      _usernameController.text = account.username ?? 'git';
      _secretController.clear();
      _keyPathController.text = account.sshKeyPath ?? '';
      _testUrlController.clear();
      _provider = account.provider;
      _kind = account.kind;
      _isDefault = account.isDefault;
      _clearFeedback();
    });
  }

  Future<void> _save({bool testAfterSave = false}) async {
    final host = _hostController.text.trim();
    final name = _nameController.text.trim();
    if (host.isEmpty || name.isEmpty) {
      setState(() => _error = 'Enter a host and account name.');
      return;
    }
    final secret = _secretController.text;
    if (_editingId == null &&
        _kind == GitCredentialKind.httpsToken &&
        secret.isEmpty) {
      setState(() => _error = 'Enter a personal access token.');
      return;
    }
    final now = DateTime.now();
    final current = _accounts
        ?.where((account) => account.id == _editingId)
        .firstOrNull;
    final account = GitCredentialAccount(
      id: _editingId ?? _newAccountId(),
      provider: _provider,
      host: host,
      accountName: name,
      kind: _kind,
      username: _kind == GitCredentialKind.httpsToken
          ? (_usernameController.text.trim().isEmpty
                ? 'git'
                : _usernameController.text.trim())
          : null,
      sshKeyPath: _kind == GitCredentialKind.sshKey
          ? _keyPathController.text.trim()
          : null,
      isDefault: _isDefault,
      createdAt: current?.createdAt ?? now,
      updatedAt: now,
    );
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final saved = await widget.store.saveAccount(
        account,
        secret: secret.isEmpty ? null : secret,
      );
      if (_isDefault) await widget.store.setDefault(saved.host, saved.id);
      await _load();
      if (!mounted) return;
      if (testAfterSave) {
        setState(() => _message = 'Saved ${saved.accountName} securely.');
        await _test(saved);
      } else {
        setState(() {
          _showForm = false;
          _editingId = null;
          _message = 'Saved ${saved.accountName} securely.';
        });
      }
    } on GitError catch (error) {
      if (mounted) setState(() => _error = error.userMessage);
    } on Object {
      if (mounted) setState(() => _error = 'The account could not be saved.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _test(GitCredentialAccount account) async {
    final url = _testUrlController.text.trim();
    if (url.isEmpty) {
      if (mounted) {
        setState(
          () => _message =
              'Saved securely. Enter a remote URL to test the connection.',
        );
      }
      return;
    }
    final tester = widget.tester;
    if (tester == null) {
      if (mounted) {
        setState(
          () => _message = 'Saved securely; connection testing is unavailable in this gateway.',
        );
      }
      return;
    }
    try {
      final result = await tester.testCredential(url, accountId: account.id);
      if (mounted) setState(() => _message = result.summary);
    } on GitError catch (error) {
      if (mounted) setState(() => _error = error.userMessage);
    } on Object {
      if (mounted) setState(() => _error = 'The connection test failed.');
    }
  }

  Future<void> _setDefault(GitCredentialAccount account) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.store.setDefault(account.host, account.id);
      await _load();
      if (mounted) {
        setState(
          () => _message =
              '${account.accountName} is now the default for ${account.host}.',
        );
      }
    } on GitError catch (error) {
      if (mounted) setState(() => _error = error.userMessage);
    } on Object {
      if (mounted) {
        setState(() => _error = 'The default account could not be changed.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(GitCredentialAccount account) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revoke Git account?'),
        content: Text(
          'Revoke ${account.accountName} and delete its secure secret? '
          'Future operations will use another matching account or ambient Git authentication.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (remove != true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.store.removeAccount(account.id);
      await _load();
      if (_editingId == account.id) {
        if (_accounts?.isNotEmpty ?? false) {
          _closeForm();
        } else {
          _resetForm();
        }
      }
      if (mounted) setState(() => _message = 'Revoked ${account.accountName}.');
    } on GitError catch (error) {
      if (mounted) setState(() => _error = error.userMessage);
    } on Object {
      if (mounted) setState(() => _error = 'The account could not be removed.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _clearFeedback() {
    _error = null;
    _message = null;
  }

  String _newAccountId() =>
      'account-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
}

String _providerLabel(GitCredentialProvider provider) => switch (provider) {
  GitCredentialProvider.github => 'GitHub',
  GitCredentialProvider.gitlab => 'GitLab',
  GitCredentialProvider.generic => 'Generic host',
};

String _kindShortLabel(GitCredentialKind kind) => switch (kind) {
  GitCredentialKind.httpsToken => 'HTTPS token',
  GitCredentialKind.sshKey => 'SSH key',
  GitCredentialKind.sshAgent => 'SSH agent',
};

enum _AccountAction { setDefault, edit, remove }

class _AccountMenuLabel extends StatelessWidget {
  const _AccountMenuLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [Icon(icon, size: 18), const SizedBox(width: 10), Text(label)],
  );
}

String _kindLabel(GitCredentialKind kind) => switch (kind) {
  GitCredentialKind.httpsToken => 'HTTPS personal access token',
  GitCredentialKind.sshKey => 'SSH private-key path',
  GitCredentialKind.sshAgent => 'SSH agent',
};
