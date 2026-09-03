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
import 'package:gift/src/features/repository/update_project_dialog.dart';

/// Reviews a bounded push scope before publishing it to a remote.
class PushDialog extends StatefulWidget {
  const PushDialog({
    super.key,
    required this.gateway,
    required this.repository,
    this.initialRemote,
  });

  final GitGateway gateway;
  final RepositoryOpened repository;
  final String? initialRemote;

  @override
  State<PushDialog> createState() => _PushDialogState();
}

class _PushDialogState extends State<PushDialog> {
  final _branchController = TextEditingController();
  GitPushTarget _target = GitPushTarget.currentBranch;
  List<GitRemote>? _remotes;
  List<GitCommit> _commits = const [];
  String? _remote;
  String? _selectedCommit;
  String? _expectedRemoteOid;
  GitPushPreview? _preview;
  GitPushResult? _result;
  GitError? _error;
  GitCancellationToken? _cancellation;
  var _forceWithLease = false;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
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
              const SizedBox(height: 14),
              _remoteField(),
              const SizedBox(height: 8),
              DropdownButtonFormField<GitPushTarget>(
                key: const Key('push-target'),
                initialValue: _target,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Publish scope',
                  helperText:
                      'Only the reviewed branch, commit, or tags are sent.',
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
                          _preview = null;
                          _result = null;
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
                    labelText: 'Target branch',
                    helperText: 'Defaults to the current local branch.',
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
                    helperText:
                        'The selected commit becomes the remote branch tip.',
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
              CheckboxListTile(
                key: const Key('push-force-with-lease'),
                value: _forceWithLease,
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Force-with-lease'),
                subtitle: const Text(
                  'Replace history only after the reviewed remote tip matches.',
                ),
                onChanged: _busy
                    ? null
                    : (value) => setState(() {
                        _forceWithLease = value ?? false;
                        _preview = null;
                        _result = null;
                      }),
              ),
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
      actionsOverflowButtonSpacing: 4,
      actions: [
        if (_busy)
          TextButton(
            key: const Key('cancel-push'),
            onPressed: _cancellation?.cancel,
            child: const Text('Cancel'),
          ),
        if (!_busy && preview?.canExecute != true)
          OutlinedButton(
            key: const Key('preview-push'),
            onPressed: _remotes == null ? null : _previewPush,
            child: const Text('Review changes'),
          ),
        if (!_busy && preview?.canExecute == true)
          FilledButton(
            style: pixelProminentButtonStyle,
            key: const Key('execute-push'),
            onPressed: _executePush,
            child: Text(
              _forceWithLease
                  ? 'Force push to ${preview!.remote}'
                  : 'Push to ${preview!.remote}',
            ),
          ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _pushGuidance() => Card(
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
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Nothing is pushed yet',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 4),
                Text(
                  'Choose what to publish, then select Review changes. '
                  'The app checks commits, files, and the remote tip. '
                  'Only the final Push button sends data.',
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

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
      onChanged: _busy
          ? null
          : (value) {
              setState(() {
                _remote = value;
                _invalidateReview(clearRemoteTip: true);
              });
            },
    );
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
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'The final Push button confirms this reviewed remote tip.',
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
                  runSpacing: 4,
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

  Future<void> _load() async {
    try {
      final remotes = await widget.gateway.getRemotes(
        widget.repository.repositoryId,
      );
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
      setState(() {
        _remotes = remotes;
        _remote = remotes.isEmpty
            ? null
            : remotes.any((remote) => remote.name == widget.initialRemote)
            ? widget.initialRemote
            : remotes.first.name;
        _commits = history?.commits ?? const [];
        if (_branchController.text.isEmpty && status.branch.head != null) {
          _branchController.text = status.branch.head!;
        }
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
          branch: _branchController.text.trim().isEmpty
              ? null
              : _branchController.text.trim(),
          commitOid: _selectedCommit,
          forceWithLease: _forceWithLease,
          expectedRemoteOid: _forceWithLease ? _expectedRemoteOid : null,
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
    if (_forceWithLease) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirm force-with-lease'),
          content: Text(
            'Replace ${preview.targetBranch} only if remote tip '
            '${_shortOid(preview.remoteHead ?? 'missing')} is unchanged?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
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
