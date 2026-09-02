import 'package:gitflu/src/backend/domain.dart';
import 'package:gitflu/src/backend/error.dart';
import 'package:gitflu/src/backend/executor.dart';
import 'package:gitflu/src/backend/git_gateway.dart';
import 'package:gitflu/src/backend/remote.dart';
import 'package:flutter/material.dart';

/// Shows remotes and keeps one cancellable synchronization operation visible.
class RemoteDialog extends StatefulWidget {
  const RemoteDialog({
    super.key,
    required this.gateway,
    required this.repository,
  });

  final GitGateway gateway;
  final RepositoryOpened repository;

  @override
  State<RemoteDialog> createState() => _RemoteDialogState();
}

class _RemoteDialogState extends State<RemoteDialog> {
  List<GitRemote>? _remotes;
  GitError? _error;
  GitRemoteOperation? _runningOperation;
  String? _runningRemote;
  GitCancellationToken? _cancellationToken;

  @override
  void initState() {
    super.initState();
    _loadRemotes();
  }

  @override
  Widget build(BuildContext context) {
    final busy = _runningOperation != null;
    final width = (MediaQuery.sizeOf(context).width - 64).clamp(240.0, 440.0);
    return AlertDialog(
      title: const Text('Remote operations'),
      content: SizedBox(
        width: width,
        height: 360,
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
    return ListView.builder(
      itemCount: remotes.length,
      itemBuilder: (context, index) {
        final remote = remotes[index];
        final disabled = _runningOperation != null;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  remote.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (remote.fetchUrl case final url?)
                  Text(
                    'fetch: ${redactRemote(url)}',
                    overflow: TextOverflow.ellipsis,
                  ),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      key: ValueKey('fetch:${remote.name}'),
                      onPressed: disabled
                          ? null
                          : () => _run(remote.name, GitRemoteOperation.fetch),
                      child: const Text('Fetch'),
                    ),
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
                          : () => _run(remote.name, GitRemoteOperation.push),
                      child: const Text('Push'),
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

  Future<void> _run(String remote, GitRemoteOperation operation) async {
    final token = GitCancellationToken();
    setState(() {
      _runningRemote = remote;
      _runningOperation = operation;
      _cancellationToken = token;
      _error = null;
    });
    try {
      final result = switch (operation) {
        GitRemoteOperation.fetch => await widget.gateway.fetch(
          widget.repository.repositoryId,
          remote,
          cancellationToken: token,
        ),
        GitRemoteOperation.pull => await widget.gateway.pull(
          widget.repository.repositoryId,
          remote,
          cancellationToken: token,
        ),
        GitRemoteOperation.push => await widget.gateway.push(
          widget.repository.repositoryId,
          remote,
          cancellationToken: token,
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
