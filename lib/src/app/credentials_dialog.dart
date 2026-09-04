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

  List<GitCredentialAccount>? _accounts;
  String? _editingId;
  GitCredentialProvider _provider = GitCredentialProvider.generic;
  GitCredentialKind _kind = GitCredentialKind.httpsToken;
  var _isDefault = false;
  var _busy = false;
  String? _error;
  String? _message;

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final accounts = _accounts;
    return AlertDialog(
      title: const Text('Git accounts'),
      content: SizedBox(
        width: (size.width - 48).clamp(300.0, 700.0),
        height: (size.height - 160).clamp(360.0, 640.0),
        child: ListView(
          children: [
            const Text(
              'Tokens and SSH passphrases stay in the platform secure store. '
              'Private-key files stay at their selected path and are never copied.',
            ),
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
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No accounts configured. Local Git remains available.',
                ),
              )
            else
              for (final account in accounts) _accountTile(account),
            const Divider(height: 28),
            Text(
              _editingId == null ? 'Add account' : 'Edit account',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('credential-host'),
              controller: _hostController,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Host',
                hintText: 'github.com or git.example.com',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => _clearFeedback(),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('credential-account-name'),
              controller: _nameController,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Account name',
                hintText: 'Work GitHub',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<GitCredentialProvider>(
              key: const Key('credential-provider'),
              initialValue: _provider,
              decoration: const InputDecoration(
                labelText: 'Provider',
                border: OutlineInputBorder(),
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
                      if (value != null) setState(() => _provider = value);
                    },
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<GitCredentialKind>(
              key: const Key('credential-kind'),
              initialValue: _kind,
              decoration: const InputDecoration(
                labelText: 'Credential type',
                border: OutlineInputBorder(),
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
                      if (value != null) setState(() => _kind = value);
                    },
            ),
            if (_kind == GitCredentialKind.httpsToken) ...[
              const SizedBox(height: 8),
              TextField(
                key: const Key('credential-username'),
                controller: _usernameController,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'HTTPS username',
                  hintText: 'git',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
            if (_kind == GitCredentialKind.sshKey) ...[
              const SizedBox(height: 8),
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
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
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
              const SizedBox(height: 8),
            ],
            if (_kind != GitCredentialKind.sshAgent)
              TextField(
                key: const Key('credential-secret'),
                controller: _secretController,
                enabled: !_busy,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: _kind == GitCredentialKind.httpsToken
                      ? 'Personal access token'
                      : 'SSH passphrase (optional)',
                  hintText: _editingId == null
                      ? null
                      : 'Leave blank to keep the saved secret',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              key: const Key('credential-default'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Use as default for this host'),
              value: _isDefault,
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _isDefault = value),
            ),
            TextField(
              key: const Key('credential-test-url'),
              controller: _testUrlController,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Connection-test remote URL (optional)',
                hintText: 'https://github.com/org/private-repo.git',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('credential-new'),
          onPressed: _busy ? null : _resetForm,
          child: const Text('New account'),
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        OutlinedButton(
          key: const Key('credential-test'),
          onPressed: _busy ? null : () => _save(testAfterSave: true),
          child: const Text('Save and test'),
        ),
        FilledButton(
          key: const Key('credential-save'),
          onPressed: _busy ? null : _save,
          child: const Text('Save account'),
        ),
      ],
    );
  }

  Widget _messageBanner(String text, {required bool isError}) => Container(
    key: Key(isError ? 'credential-error' : 'credential-message'),
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(8),
    color: isError
        ? Theme.of(context).colorScheme.errorContainer
        : Theme.of(context).colorScheme.primaryContainer,
    child: Text(text),
  );

  Widget _accountTile(GitCredentialAccount account) => Card(
    key: ValueKey('credential-account:${account.id}'),
    child: ListTile(
      title: Text(account.accountName),
      subtitle: Text(
        '${account.host} · ${_providerLabel(account.provider)} · ${_kindLabel(account.kind)}',
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Wrap(
        spacing: 2,
        children: [
          if (account.isDefault)
            const Chip(
              label: Text('Default'),
              visualDensity: VisualDensity.compact,
            )
          else
            IconButton(
              key: ValueKey('credential-default:${account.id}'),
              tooltip: 'Use as default',
              onPressed: _busy ? null : () => _setDefault(account),
              icon: const Icon(Icons.star_border),
            ),
          IconButton(
            key: ValueKey('credential-edit:${account.id}'),
            tooltip: 'Edit account',
            onPressed: _busy ? null : () => _edit(account),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            key: ValueKey('credential-remove:${account.id}'),
            tooltip: 'Revoke local access',
            onPressed: _busy ? null : () => _remove(account),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    ),
  );
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
      if (mounted) setState(() => _accounts = accounts);
    } on GitError catch (error) {
      if (mounted) setState(() => _error = error.userMessage);
    } on Object {
      if (mounted) setState(() => _error = 'Accounts could not be loaded.');
    }
  }

  void _resetForm() {
    setState(() {
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
      setState(() => _message = 'Saved ${saved.accountName} securely.');
      if (testAfterSave) await _test(saved);
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
          'Revoke ${account.accountName} and delete its secure secret?',
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
      if (_editingId == account.id) _resetForm();
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

String _kindLabel(GitCredentialKind kind) => switch (kind) {
  GitCredentialKind.httpsToken => 'HTTPS personal access token',
  GitCredentialKind.sshKey => 'SSH private-key path',
  GitCredentialKind.sshAgent => 'SSH agent',
};
