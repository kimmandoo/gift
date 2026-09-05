import 'dart:async';

import 'package:gift/src/backend/credentials.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/error.dart';
import 'package:gift/src/backend/executor.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:gift/src/backend/remote.dart';
import 'package:gift/src/backend/push.dart';
import 'package:gift/src/features/repository/push_dialog.dart';
import 'package:gift/src/app/repository_credential_store.dart';
import 'package:gift/src/features/repository/object_dialog.dart';
import 'package:flutter/material.dart';

/// Shows remotes and keeps one cancellable synchronization operation visible.
class RemoteDialog extends StatefulWidget {
  const RemoteDialog({
    super.key,
    required this.gateway,
    required this.repository,
    this.credentialStore,
    this.repositoryCredentialStore,
    this.initialOperation,
    this.preferredRemote,
  });

  final GitGateway gateway;
  final RepositoryOpened repository;
  final GitRemoteOperation? initialOperation;
  final String? preferredRemote;
  final GitCredentialStore? credentialStore;
  final RepositoryCredentialStore? repositoryCredentialStore;
  @override
  State<RemoteDialog> createState() => _RemoteDialogState();
}

class _RemoteDialogState extends State<RemoteDialog> {
  List<GitRemote>? _remotes;
  GitError? _error;
  GitRemoteOperation? _runningOperation;
  String? _runningRemote;
  List<GitCredentialAccount>? _accounts;
  final Map<String, String> _selectedByHost = {};
  GitCancellationToken? _cancellationToken;

  @override
  void initState() {
    super.initState();
    _loadRemotes();
    unawaited(_loadAccounts());
  }

  @override
  Widget build(BuildContext context) {
    final busy = _runningOperation != null;
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 480;
    final width = (size.width - 80).clamp(0.0, 440.0);
    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 16 : 40,
        vertical: 24,
      ),
      title: Text(
        widget.initialOperation == GitRemoteOperation.push
            ? 'Push to remote'
            : 'Remote operations',
      ),
      actionsOverflowButtonSpacing: 8,
      content: SizedBox(
        width: width,
        height: (size.height - 180).clamp(220.0, 360.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (busy) ...[
              const LinearProgressIndicator(key: Key('remote-progress')),
              const SizedBox(height: 8),
              Text(
                '${_operationLabel(_runningOperation!)} $_runningRemote…',
                key: const Key('remote-running'),
              ),
            ],
            if (_error case final error?) ...[
              Text(error.userMessage, key: const Key('remote-error')),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: busy ? null : _loadRemotes,
                child: const Text('Retry'),
              ),
            ],
            Expanded(child: _remoteList(context)),
          ],
        ),
      ),
      actions: [
        if (busy)
          TextButton(
            key: const Key('cancel-remote'),
            onPressed: _cancellationToken?.cancel,
            child: const Text('Cancel operation'),
          ),
        if (!busy)
          OutlinedButton(
            key: const Key('manage-remotes'),
            onPressed: _manageRemotes,
            child: const Text('Remote setup'),
          ),
        TextButton(
          onPressed: busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _remoteList(BuildContext context) {
    final remotes = _remotes;
    if (remotes == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (remotes.isEmpty) {
      return const Center(child: Text('No remotes are configured.'));
    }
    final orderedRemotes = [...remotes]
      ..sort((left, right) {
        final preferred = widget.preferredRemote;
        if (preferred == null) return 0;
        if (left.name == preferred) return -1;
        if (right.name == preferred) return 1;
        return 0;
      });
    return ListView.separated(
      itemCount: orderedRemotes.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final remote = orderedRemotes[index];
        final disabled = _runningOperation != null;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  remote.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (remote.fetchUrl case final url?)
                  Text(
                    'fetch: ${redactRemote(url)}',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                _credentialSelector(remote),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (widget.initialOperation != GitRemoteOperation.push)
                      OutlinedButton(
                        key: ValueKey('fetch:${remote.name}'),
                        onPressed: disabled
                            ? null
                            : () => _run(remote.name, GitRemoteOperation.fetch),
                        child: const Text('Fetch'),
                      ),
                    if (widget.initialOperation != GitRemoteOperation.push)
                      OutlinedButton(
                        key: ValueKey('pull:${remote.name}'),
                        onPressed: disabled
                            ? null
                            : () => _run(remote.name, GitRemoteOperation.pull),
                        child: const Text('Pull'),
                      ),
                    FilledButton(
                      key: ValueKey('push:${remote.name}'),
                      onPressed: disabled
                          ? null
                          : () => _openPushReview(context, remote.name),
                      child: const Text('Review push'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _manageRemotes() async {
    await showDialog<void>(
      context: context,
      builder: (_) => ObjectDialog(
        gateway: widget.gateway,
        repository: widget.repository,
        initialTabIndex: 2,
      ),
    );
    if (!mounted) return;
    await _loadRemotes();
  }

  Future<void> _openPushReview(BuildContext context, String remote) async {
    final result = await showDialog<GitPushResult>(
      context: context,
      builder: (_) => PushDialog(
        gateway: widget.gateway,
        repository: widget.repository,
        initialRemote: remote,
        credentialStore: widget.credentialStore,
        repositoryCredentialStore: widget.repositoryCredentialStore,
      ),
    );
    if (!context.mounted || result == null) return;
    Navigator.of(context).pop(result);
  }

  Widget _credentialSelector(GitRemote remote) {
    final store = widget.credentialStore;
    final disabled = _runningOperation != null;
    final url = widget.initialOperation == GitRemoteOperation.push
        ? remote.pushUrl ?? remote.fetchUrl
        : remote.fetchUrl ?? remote.pushUrl;
    final endpoint = url == null ? null : parseGitRemoteEndpoint(url);
    if (store == null ||
        endpoint == null ||
        endpoint.transport == GitRemoteTransport.other) {
      return const SizedBox.shrink();
    }
    final accounts = _matchingAccounts(endpoint);
    if (_accounts == null) {
      return const LinearProgressIndicator(
        key: Key('credential-selector-loading'),
      );
    }
    if (accounts.isEmpty) {
      return Text(
        'No matching account for ${endpoint.host}; Git will use public or ambient authentication.',
        key: ValueKey('credential-selector-empty:${remote.name}'),
      );
    }
    final selected =
        widget.repositoryCredentialStore?.accountIdFor(
          widget.repository.root,
          endpoint.host,
        ) ??
        _selectedByHost[endpoint.host] ??
        accounts.where((account) => account.isDefault).firstOrNull?.id ??
        '';
    final values = <String>['', ...accounts.map((account) => account.id)];
    return DropdownButtonFormField<String>(
      key: ValueKey('credential-selector:${remote.name}'),
      initialValue: values.contains(selected) ? selected : '',
      decoration: InputDecoration(
        labelText: widget.repositoryCredentialStore == null
            ? 'Account for ${endpoint.host}'
            : 'Account for ${endpoint.host} in this repository',
        isDense: true,
      ),
      items: [
        const DropdownMenuItem(
          value: '',
          child: Text('Automatic / no account'),
        ),
        for (final account in accounts)
          DropdownMenuItem(
            value: account.id,
            child: Text(account.accountName, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: disabled
          ? null
          : (value) {
              if (value == null) return;
              unawaited(_selectAccount(endpoint.host, value));
            },
    );
  }

  List<GitCredentialAccount> _matchingAccounts(GitRemoteEndpoint endpoint) {
    final accounts = _accounts;
    if (accounts == null) return const [];
    return accounts
        .where(
          (account) =>
              account.host == endpoint.host &&
              (endpoint.transport == GitRemoteTransport.https
                  ? account.kind == GitCredentialKind.httpsToken ||
                        account.kind == GitCredentialKind.webOAuth
                  : account.kind == GitCredentialKind.sshKey ||
                        account.kind == GitCredentialKind.sshAgent),
        )
        .toList(growable: false);
  }

  Future<void> _loadAccounts() async {
    final store = widget.credentialStore;
    if (store == null) return;
    try {
      final accounts = await store.listAccounts();
      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        _selectedByHost
          ..clear()
          ..addEntries(
            accounts
                .where((account) => account.isDefault)
                .map((account) => MapEntry(account.host, account.id)),
          );
      });
    } on Object {
      if (mounted) setState(() => _accounts = const []);
    }
  }

  Future<void> _selectAccount(String host, String accountId) async {
    final store = widget.credentialStore;
    if (store == null) return;
    try {
      final repositoryStore = widget.repositoryCredentialStore;
      if (repositoryStore != null) {
        await repositoryStore.setAccountId(
          widget.repository.root,
          host,
          accountId.isEmpty ? null : accountId,
        );
      } else if (accountId.isNotEmpty) {
        await store.setDefault(host, accountId);
      }
      if (mounted) {
        setState(() {
          if (accountId.isEmpty) {
            _selectedByHost.remove(host);
          } else {
            _selectedByHost[host] = accountId;
          }
        });
      }
    } on GitError catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _loadRemotes() async {
    setState(() {
      _remotes = null;
      _error = null;
    });
    try {
      final remotes = await widget.gateway.getRemotes(
        widget.repository.repositoryId,
      );
      if (!mounted) return;
      setState(() => _remotes = remotes);
    } on GitError catch (error) {
      if (!mounted) return;
      setState(() {
        _remotes = const [];
        _error = error;
      });
    }
  }

  String? _credentialIdForRemote(String remoteName) {
    final remote = _remotes
        ?.where((candidate) => candidate.name == remoteName)
        .firstOrNull;
    final url = widget.initialOperation == GitRemoteOperation.push
        ? remote?.pushUrl ?? remote?.fetchUrl
        : remote?.fetchUrl ?? remote?.pushUrl;
    final endpoint = url == null ? null : parseGitRemoteEndpoint(url);
    if (endpoint == null) return null;
    return widget.repositoryCredentialStore?.accountIdFor(
          widget.repository.root,
          endpoint.host,
        ) ??
        _selectedByHost[endpoint.host];
  }

  Future<void> _run(String remote, GitRemoteOperation operation) async {
    final token = GitCancellationToken();
    setState(() {
      _runningRemote = remote;
      _runningOperation = operation;
      _cancellationToken = token;
      _error = null;
    });
    try {
      final credentialGateway = widget.gateway is GitCredentialRemoteGateway
          ? widget.gateway as GitCredentialRemoteGateway
          : null;
      final credentialId = _credentialIdForRemote(remote);
      final result = switch (operation) {
        GitRemoteOperation.fetch =>
          credentialGateway == null
              ? await widget.gateway.fetch(
                  widget.repository.repositoryId,
                  remote,
                  cancellationToken: token,
                )
              : await credentialGateway.fetchWithCredential(
                  widget.repository.repositoryId,
                  remote,
                  cancellationToken: token,
                  credentialId: credentialId,
                ),
        GitRemoteOperation.pull =>
          credentialGateway == null
              ? await widget.gateway.pull(
                  widget.repository.repositoryId,
                  remote,
                  cancellationToken: token,
                )
              : await credentialGateway.pullWithCredential(
                  widget.repository.repositoryId,
                  remote,
                  cancellationToken: token,
                  credentialId: credentialId,
                ),
        GitRemoteOperation.push => throw StateError(
          'Push must be opened through the review dialog.',
        ),
      };
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } on GitError catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) {
        setState(() {
          _runningRemote = null;
          _runningOperation = null;
          _cancellationToken = null;
        });
      }
    }
  }
}

String _operationLabel(GitRemoteOperation operation) => switch (operation) {
  GitRemoteOperation.fetch => 'Fetching',
  GitRemoteOperation.pull => 'Pulling',
  GitRemoteOperation.push => 'Pushing',
};
