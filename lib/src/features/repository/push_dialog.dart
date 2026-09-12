import 'dart:async';

import 'package:gift/src/backend/credentials.dart';
import 'package:gift/src/app/repository_credential_store.dart';
import 'package:flutter/material.dart';
import 'package:gift/src/app/pixel_theme.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/error.dart';
import 'package:gift/src/backend/executor.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:gift/src/backend/history.dart';
import 'package:gift/src/backend/push.dart';
import 'package:gift/src/backend/remote.dart';
import 'package:gift/src/backend/remote_branch.dart';
import 'package:gift/src/backend/status.dart';
import 'package:gift/src/features/repository/update_project_dialog.dart';

/// Reviews a bounded push scope before publishing it to a remote.
class PushDialog extends StatefulWidget {
  const PushDialog({
    super.key,
    required this.gateway,
    required this.repository,
    this.initialRemote,
    this.initialBranch,
    this.credentialStore,
    this.repositoryCredentialStore,
    this.preferredRemote,
  });

  final GitGateway gateway;
  final RepositoryOpened repository;
  final GitCredentialStore? credentialStore;
  final RepositoryCredentialStore? repositoryCredentialStore;
  final String? initialRemote;
  final String? initialBranch;
  final String? preferredRemote;

  @override
  State<PushDialog> createState() => _PushDialogState();
}

class _PushDialogState extends State<PushDialog> {
  final _branchController = TextEditingController();
  List<GitCredentialAccount> _accounts = const [];
  String? _credentialId;
  GitPushTarget _target = GitPushTarget.currentBranch;
  List<GitRemote>? _remotes;
  List<GitCommit> _commits = const [];
  String? _remote;
  String? _selectedCommit;
  String? _expectedRemoteOid;
  GitBranchStatus? _branchStatus;
  GitPushPreview? _preview;
  GitPushResult? _result;
  GitError? _error;
  GitCancellationToken? _cancellation;
  GitPushMode _pushMode = GitPushMode.normal;
  var _setUpstream = false;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _branchController.text = widget.initialBranch ?? '';
    unawaited(_load());
  }

  @override
  void dispose() {
    _branchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 520;
    final preview = _preview;
    return AlertDialog(
      key: const Key('push-dialog'),
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 16 : 40,
        vertical: 24,
      ),
      title: const Text('Push to remote'),
      content: SizedBox(
        width: (size.width - (compact ? 32 : 80)).clamp(280.0, 620.0),
        height: (size.height - 190).clamp(260.0, 520.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _pushGuidance(),
              if (_busy && _cancellation != null) ...[
                const SizedBox(height: 12),
                _pushProgressCard(),
              ],
              const SizedBox(height: 14),
              _remoteField(),
              const SizedBox(height: 10),
              _credentialField(),
              const SizedBox(height: 10),
              _trackingCard(),
              const SizedBox(height: 8),
              _advancedOptions(),
              if (_error case final error?) ...[
                const SizedBox(height: 8),
                _messageCard(
                  key: const Key('push-error'),
                  message: error.userMessage,
                ),
              ],
              if (preview != null) ...[
                const SizedBox(height: 12),
                _previewCard(preview),
              ],
              if (_result case final result?) ...[
                const SizedBox(height: 8),
                _resultCard(result),
              ],
            ],
          ),
        ),
      ),
      actionsOverflowButtonSpacing: 8,
      actions: [
        if (_busy)
          TextButton(
            key: const Key('cancel-push'),
            onPressed: _cancellation?.cancel,
            child: const Text('Cancel push'),
          ),
        if (!_busy && preview?.canExecute != true)
          OutlinedButton(
            key: const Key('preview-push'),
            onPressed: _remotes == null ? null : _previewPush,
            child: const Text('Review changes'),
          ),
        if (!_busy && preview?.canExecute == true)
          FilledButton(
            key: const Key('execute-push'),
            onPressed: _executePush,
            child: Text(_pushActionLabel(_pushMode, preview!.remote)),
          ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _pushGuidance() {
    final branch = _branchStatus?.head;
    final upstream = _branchStatus?.upstream;
    final title = branch == null || branch == '(detached)'
        ? 'Review a push destination'
        : upstream == null
        ? 'Publish and link $branch'
        : 'Push $branch to $upstream';
    return Card(
      key: const Key('push-guidance'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline,
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Review shows exactly what will be sent. '
                    'Only the final Push button changes the remote.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pushProgressCard() {
    final preview = _preview;
    final destination = preview == null
        ? (_remote ?? 'remote')
        : preview.targetBranch.isEmpty
        ? '${preview.remote}/all tags'
        : '${preview.remote}/${preview.targetBranch}';
    return Card(
      key: const Key('push-progress'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.cloud_upload_outlined,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Pushing to $destination…',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            const Text(
              'Sending the reviewed changes to the remote. '
              'You can cancel safely while Git is running.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _remoteField() {
    final remotes = _remotes;
    if (remotes == null) {
      return const LinearProgressIndicator(key: Key('push-loading'));
    }
    if (remotes.isEmpty) {
      return _messageCard(
        key: const Key('push-no-remotes'),
        message: 'No remotes are configured.',
      );
    }
    return DropdownButtonFormField<String>(
      key: const Key('push-remote'),
      initialValue: _remote,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Remote'),
      items: [
        for (final remote in remotes)
          DropdownMenuItem(
            value: remote.name,
            child: pixelDropdownText(remote.name),
          ),
      ],
      onChanged: _busy ? null : _selectRemote,
    );
  }

  Widget _trackingCard() {
    final status = _branchStatus;
    final remote = _remote;
    if (status == null || remote == null) return const SizedBox.shrink();
    final branch = status.head;
    final remoteBranch = _branchController.text.trim();
    if (_target == GitPushTarget.allTags) {
      return const Card(
        key: Key('push-destination'),
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text('Destination: all selected tags on the chosen remote'),
        ),
      );
    }
    final destination =
        '$remote/${remoteBranch.isEmpty ? branch ?? '' : remoteBranch}';
    final currentUpstream = status.upstream;
    final canLink =
        _target == GitPushTarget.currentBranch &&
        branch != null &&
        branch != '(detached)' &&
        destination != currentUpstream;
    return Card(
      key: const Key('push-destination'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${branch ?? 'Detached HEAD'} → $destination',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            if (currentUpstream == destination)
              Text('Linked upstream: $currentUpstream')
            else if (_target != GitPushTarget.currentBranch)
              const Text('This advanced push does not change branch tracking.')
            else
              Text(
                currentUpstream == null
                    ? 'This local branch is not linked to a remote branch yet.'
                    : 'Current upstream: $currentUpstream',
              ),
            if (canLink)
              CheckboxListTile(
                key: const Key('push-set-upstream'),
                value: _setUpstream,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text('Use $destination as this branch’s upstream'),
                subtitle: const Text(
                  'Future push, pull, and ahead/behind status will use this link.',
                ),
                onChanged: _busy
                    ? null
                    : (value) => setState(() {
                        _setUpstream = value ?? false;
                        _invalidateReview(clearRemoteTip: true);
                      }),
              ),
          ],
        ),
      ),
    );
  }

  Widget _advancedOptions() {
    return ExpansionTile(
      key: const Key('push-advanced-options'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 4),
      title: const Text('Advanced push options'),
      subtitle: const Text('Different branch, selected commit, tags, or force'),
      children: [
        DropdownButtonFormField<GitPushTarget>(
          key: const Key('push-target'),
          initialValue: _target,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Publish scope',
            helperText: 'The current branch is the safe default.',
          ),
          items: [
            for (final target in GitPushTarget.values)
              DropdownMenuItem(
                value: target,
                child: pixelDropdownText(_targetLabel(target)),
              ),
          ],
          onChanged: _busy
              ? null
              : (value) {
                  if (value == null) return;
                  setState(() {
                    _target = value;
                    _selectedCommit = null;
                    _setUpstream =
                        value == GitPushTarget.currentBranch &&
                        _branchStatus?.upstream == null;
                    _invalidateReview(clearRemoteTip: true);
                  });
                },
        ),
        if (_target != GitPushTarget.allTags) ...[
          const SizedBox(height: 8),
          TextFormField(
            key: const Key('push-target-branch'),
            controller: _branchController,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'Remote branch',
              helperText: 'The branch name that will be created or updated.',
            ),
            onChanged: (_) =>
                setState(() => _invalidateReview(clearRemoteTip: true)),
          ),
        ],
        if (_target == GitPushTarget.selectedCommit) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: const Key('push-selected-commit'),
            initialValue: _selectedCommit,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Push up to commit',
              helperText: 'The selected commit becomes the remote branch tip.',
            ),
            items: [
              for (final commit in _commits)
                DropdownMenuItem(
                  value: commit.oid,
                  child: pixelDropdownText(
                    '${commit.shortOid} ${commit.subject}',
                  ),
                ),
            ],
            onChanged: _busy
                ? null
                : (value) => setState(() {
                    _selectedCommit = value;
                    _preview = null;
                    _result = null;
                  }),
          ),
        ],
        const SizedBox(height: 4),
        DropdownButtonFormField<GitPushMode>(
          key: const Key('push-mode'),
          initialValue: _pushMode,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Push mode',
            helperText: 'Normal push is the safe default.',
          ),
          items: [
            for (final mode in GitPushMode.values)
              DropdownMenuItem(
                value: mode,
                child: pixelDropdownText(_pushModeLabel(mode)),
              ),
          ],
          onChanged: _busy
              ? null
              : (value) {
                  if (value == null) return;
                  setState(() {
                    _pushMode = value;
                    _invalidateReview(clearRemoteTip: true);
                  });
                },
        ),
        if (_pushMode == GitPushMode.force)
          Card(
            key: const Key('push-force-warning'),
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Force push replaces the remote branch without a lease. '
                'Remote-only commits may be lost.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _credentialField() {
    final store = widget.credentialStore;
    final remote = _remotes
        ?.where((candidate) => candidate.name == _remote)
        .firstOrNull;
    final url = remote?.pushUrl ?? remote?.fetchUrl;
    final endpoint = url == null ? null : parseGitRemoteEndpoint(url);
    if (store == null ||
        endpoint == null ||
        endpoint.transport == GitRemoteTransport.other) {
      return const SizedBox.shrink();
    }
    final accounts = _accounts
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
    if (accounts.isEmpty) {
      return Text(
        'No matching account for ${endpoint.host}; public or ambient authentication remains available.',
      );
    }
    final repositorySelection = widget.repositoryCredentialStore?.accountIdFor(
      widget.repository.root,
      endpoint.host,
    );
    final values = <String>['', ...accounts.map((account) => account.id)];
    final selected = values.contains(_credentialId)
        ? _credentialId!
        : values.contains(repositorySelection)
        ? repositorySelection!
        : '';
    return DropdownButtonFormField<String>(
      key: const Key('push-credential'),
      initialValue: selected,
      decoration: InputDecoration(
        labelText: 'Push account',
        helperText: widget.repositoryCredentialStore == null
            ? '${endpoint.host} · default account'
            : '${endpoint.host} · this repository',
        isDense: true,
      ),
      items: [
        const DropdownMenuItem(
          value: '',
          child: SizedBox(
            width: 150,
            child: Text(
              'Automatic / no account',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        for (final account in accounts)
          DropdownMenuItem(
            value: account.id,
            child: SizedBox(
              width: 150,
              child: Text(
                account.accountName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
      ],
      onChanged: _busy
          ? null
          : (value) => unawaited(_selectCredential(endpoint.host, value)),
    );
  }

  Future<void> _selectCredential(String host, String? accountId) async {
    final store = widget.credentialStore;
    if (accountId == null) return;
    try {
      final repositoryStore = widget.repositoryCredentialStore;
      if (repositoryStore != null) {
        await repositoryStore.setAccountId(
          widget.repository.root,
          host,
          accountId.isEmpty ? null : accountId,
        );
      } else if (accountId.isNotEmpty) {
        await store?.setDefault(host, accountId);
      }
      if (mounted) {
        setState(() => _credentialId = accountId.isEmpty ? null : accountId);
      }
    } on GitError catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Widget _previewCard(GitPushPreview preview) {
    final destination = preview.targetBranch.isEmpty
        ? 'all tags'
        : '${preview.remote}/${preview.targetBranch}';
    final canPush = preview.canExecute;
    return Card(
      key: const Key('push-preview'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  canPush ? Icons.check_circle_outline : Icons.block_outlined,
                  size: 20,
                  color: canPush
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    canPush ? 'Ready to push' : 'Push blocked',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              canPush
                  ? 'Nothing has been sent yet. Check this review, then '
                        'choose the Push button.'
                  : 'Nothing has been sent. Resolve the issue below, then '
                        'review the push again.',
            ),
            const SizedBox(height: 10),
            Text('Destination: $destination'),
            if (preview.request.setUpstream)
              Text(
                'After push: ${preview.currentBranch} will track $destination',
              ),
            if (preview.request.target != GitPushTarget.allTags)
              Text(
                'Commits to publish: ${preview.commits.length} commit(s), '
                '${preview.changedPaths.length} file(s)',
              ),
            if (preview.request.target == GitPushTarget.allTags)
              Text(
                'Tags to publish: ${preview.tags.length} tag(s): '
                '${preview.tags.map((tag) => tag.name).join(', ')}',
              ),
            if (preview.remoteHead case final remoteHead?)
              Text('Remote currently at: ${_shortOid(remoteHead)}'),
            Text('Remote will point to: ${_shortOid(preview.targetOid)}'),
            if (preview.request.mode == GitPushMode.force) ...[
              Padding(
                key: const Key('push-force-preview-warning'),
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Force push replaces $destination without a lease. '
                  'Remote-only commits may be lost.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
              if (preview.remoteOnlyCommits.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Remote commits to replace',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                for (final commit in preview.remoteOnlyCommits.take(8))
                  Text('${_shortOid(commit.oid)} ${commit.subject}'),
                if (preview.remoteOnlyCommitsTruncated)
                  const Text('+ more remote commits'),
              ],
              if (!preview.remoteHistoryAvailable)
                const Text('Remote history could not be inspected.'),
            ],
            if (preview.dirtyWorktree)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Working tree has local changes; push does not stage or '
                  'commit them.',
                ),
              ),
            if (preview.commits.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Commits included',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              for (final commit in preview.commits.take(8))
                Text('${_shortOid(commit.oid)} ${commit.subject}'),
              if (preview.commits.length > 8)
                Text('+ ${preview.commits.length - 8} more commits'),
            ],
            if (preview.blockingMessage case final message?) ...[
              const SizedBox(height: 8),
              Text(message, key: const Key('push-preview-blocked')),
            ],
            if (preview.requiresConfirmation && preview.blockingMessage == null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  preview.request.mode == GitPushMode.force
                      ? 'The final Force push button confirms this remote history replacement.'
                      : 'The final Force-with-lease button confirms this reviewed remote tip.',
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _resultCard(GitPushResult result) {
    return Card(
      key: const Key('push-result'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(result.summary, key: const Key('push-result-message')),
            if (result.recoveryActions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final action in result.recoveryActions)
                      OutlinedButton(
                        key: ValueKey('push-recovery:${action.name}'),
                        onPressed: _busy ? null : () => _openRecovery(action),
                        child: Text(_recoveryLabel(action)),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _messageCard({required Key key, required String message}) => Card(
    key: key,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Text(message, overflow: TextOverflow.ellipsis),
    ),
  );

  String? _storedCredentialForRemote(String remoteName) {
    final remote = _remotes
        ?.where((candidate) => candidate.name == remoteName)
        .firstOrNull;
    final url = remote?.pushUrl ?? remote?.fetchUrl;
    final endpoint = url == null ? null : parseGitRemoteEndpoint(url);
    if (endpoint == null) return null;
    return widget.repositoryCredentialStore?.accountIdFor(
      widget.repository.root,
      endpoint.host,
    );
  }

  void _selectRemote(String? remote) {
    if (remote == null) return;
    final status = _branchStatus;
    final tracking = _trackingDestination(status, _remotes ?? const []);
    setState(() {
      _remote = remote;
      _credentialId = _storedCredentialForRemote(remote);
      if (tracking != null && tracking.$1 == remote) {
        _branchController.text = tracking.$2;
        _setUpstream = false;
      } else if (status?.head case final branch?) {
        if (branch != '(detached)') _branchController.text = branch;
        _setUpstream = status?.upstream == null;
      }
      _invalidateReview(clearRemoteTip: true);
    });
  }

  (String, String)? _trackingDestination(
    GitBranchStatus? status,
    List<GitRemote> remotes,
  ) {
    final upstream = status?.upstream;
    if (upstream == null || upstream.isEmpty) return null;
    final names = remotes.map((remote) => remote.name).toList()
      ..sort((left, right) => right.length.compareTo(left.length));
    for (final name in names) {
      final prefix = '$name/';
      if (upstream.startsWith(prefix) && upstream.length > prefix.length) {
        return (name, upstream.substring(prefix.length));
      }
    }
    return null;
  }

  Future<void> _load() async {
    try {
      final remotes = await widget.gateway.getRemotes(
        widget.repository.repositoryId,
      );
      var accounts = const <GitCredentialAccount>[];
      final store = widget.credentialStore;
      if (store != null) {
        try {
          accounts = await store.listAccounts();
        } on Object {
          // Account discovery must not make local push review unavailable.
        }
      }
      final status = await widget.gateway.getStatus(
        widget.repository.repositoryId,
      );
      GitHistoryPage? history;
      try {
        history = await widget.gateway.getHistory(
          widget.repository.repositoryId,
          limit: 50,
        );
      } on GitError {
        // A repository without commits can still review a tag/branch action.
      }
      if (!mounted) return;
      final tracking = _trackingDestination(status.branch, remotes);
      final candidates = [
        tracking?.$1,
        widget.initialRemote,
        widget.preferredRemote,
        'origin',
      ];
      final selectedRemote = candidates
          .whereType<String>()
          .where((name) => remotes.any((remote) => remote.name == name))
          .firstOrNull;
      final selectedBranch = tracking != null && tracking.$1 == selectedRemote
          ? tracking.$2
          : status.branch.head;
      setState(() {
        _accounts = accounts;
        _remotes = remotes;
        _remote = remotes.isEmpty ? null : selectedRemote ?? remotes.first.name;
        _branchStatus = status.branch;
        _setUpstream =
            status.branch.head != null &&
            !status.branch.isDetached &&
            tracking == null;
        _commits = history?.commits ?? const [];
        _branchController.text = widget.initialBranch ?? selectedBranch ?? '';
      });
    } on GitError catch (error) {
      if (!mounted) return;
      setState(() {
        _remotes = const [];
        _error = error;
      });
    }
  }

  Future<void> _previewPush() async {
    final remote = _remote;
    if (remote == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _preview = null;
      _result = null;
    });
    try {
      final preview = await widget.gateway.previewPush(
        widget.repository.repositoryId,
        GitPushRequest(
          remote: remote,
          target: _target,
          mode: _pushMode,
          branch: _branchController.text.trim().isEmpty
              ? null
              : _branchController.text.trim(),
          commitOid: _selectedCommit,
          setUpstream: _setUpstream && _target == GitPushTarget.currentBranch,
          expectedRemoteOid: _pushMode == GitPushMode.forceWithLease
              ? _expectedRemoteOid
              : null,
          credentialId: _credentialId ?? _storedCredentialForRemote(remote),
        ),
      );
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _expectedRemoteOid = preview.remoteHead;
      });
    } on GitError catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _executePush() async {
    final preview = _preview;
    if (preview == null || !preview.canExecute || _busy) return;
    if (preview.request.mode != GitPushMode.normal) {
      final confirmed = await _confirmPush(preview);
      if (confirmed != true || !mounted) return;
    }
    final cancellation = GitCancellationToken();
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
      _cancellation = cancellation;
    });
    try {
      final result = await widget.gateway.executePush(
        widget.repository.repositoryId,
        preview.request.copyWith(confirmationToken: preview.token),
        cancellationToken: cancellation,
      );
      if (!mounted) return;
      if (result.state == GitPushState.completed) {
        Navigator.of(context).pop(result);
      } else {
        setState(() => _result = result);
      }
    } on GitError catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _cancellation = null;
        });
      }
    }
  }

  Future<bool?> _confirmPush(GitPushPreview preview) {
    var typedBranch = '';
    return showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final isForce = preview.request.mode == GitPushMode.force;
          final branchMatches = typedBranch == preview.targetBranch;
          return AlertDialog(
            title: Text(
              isForce ? 'Confirm force push' : 'Confirm force-with-lease',
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    isForce
                        ? 'Replace ${preview.remote}/${preview.targetBranch} '
                              'unconditionally with '
                              '${_shortOid(preview.targetOid)}. '
                              'Remote-only commits may be lost.'
                        : 'Replace ${preview.targetBranch} only if remote tip '
                              '${_shortOid(preview.remoteHead ?? 'missing')} '
                              'is unchanged?',
                  ),
                  if (isForce) ...[
                    const SizedBox(height: 12),
                    Text('Type ${preview.targetBranch} to continue.'),
                    const SizedBox(height: 8),
                    TextField(
                      key: const Key('force-push-confirmation'),
                      autofocus: true,
                      onChanged: (value) {
                        typedBranch = value;
                        setState(() {});
                      },
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: !isForce || branchMatches
                    ? () => Navigator.of(context).pop(true)
                    : null,
                child: Text(isForce ? 'Force push' : 'Confirm'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openRecovery(GitPushRecoveryAction action) async {
    final strategy = switch (action) {
      GitPushRecoveryAction.merge => GitUpdateStrategy.merge,
      GitPushRecoveryAction.rebase => GitUpdateStrategy.rebase,
      GitPushRecoveryAction.retry => null,
    };
    if (strategy == null) {
      setState(() {
        _preview = null;
        _result = null;
      });
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => UpdateProjectDialog(
        gateway: widget.gateway,
        repository: widget.repository,
      ),
    );
  }

  void _invalidateReview({bool clearRemoteTip = false}) {
    _preview = null;
    _result = null;
    if (clearRemoteTip) _expectedRemoteOid = null;
  }
}

String _pushModeLabel(GitPushMode mode) => switch (mode) {
  GitPushMode.normal => 'Normal push',
  GitPushMode.forceWithLease => 'Force-with-lease (recommended)',
  GitPushMode.force => 'Force push (unsafe)',
};

String _pushActionLabel(GitPushMode mode, String remote) => switch (mode) {
  GitPushMode.normal => 'Push to $remote',
  GitPushMode.forceWithLease => 'Force-with-lease to $remote',
  GitPushMode.force => 'Force push to $remote',
};

String _targetLabel(GitPushTarget target) => switch (target) {
  GitPushTarget.currentBranch => 'Current branch',
  GitPushTarget.selectedCommit => 'Up to selected commit',
  GitPushTarget.allTags => 'All local tags (explicit refs)',
};

String _recoveryLabel(GitPushRecoveryAction action) => switch (action) {
  GitPushRecoveryAction.retry => 'Review again',
  GitPushRecoveryAction.merge => 'Review merge',
  GitPushRecoveryAction.rebase => 'Review rebase',
};

String _shortOid(String oid) => oid.length > 8 ? oid.substring(0, 8) : oid;
