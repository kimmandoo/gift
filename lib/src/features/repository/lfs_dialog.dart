import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gift/src/backend/error.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/lfs.dart';

class GitLfsDialog extends StatefulWidget {
  const GitLfsDialog({
    required this.gateway,
    required this.repository,
    super.key,
  });

  final GitGateway gateway;
  final RepositoryOpened repository;

  @override
  State<GitLfsDialog> createState() => _GitLfsDialogState();
}

class _GitLfsDialogState extends State<GitLfsDialog> {
  GitLfsSnapshot? _snapshot;
  GitError? _error;
  var _loading = false;
  var _pulling = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (_loading || !mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snapshot = await widget.gateway.getLfsStatus(
        widget.repository.repositoryId,
      );
      if (mounted) setState(() => _snapshot = snapshot);
    } on GitError catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pull() async {
    if (_pulling) return;
    setState(() {
      _pulling = true;
      _error = null;
    });
    try {
      final result = await widget.gateway.pullLfs(
        widget.repository.repositoryId,
      );
      if (mounted) {
        setState(() => _snapshot = result.snapshot);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(result.summary)));
      }
    } on GitError catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _pulling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    return AlertDialog(
      key: const Key('git-lfs-dialog'),
      title: const Text('Git LFS status'),
      content: SizedBox(
        width: (MediaQuery.sizeOf(context).width - 64).clamp(280.0, 560.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_loading) const LinearProgressIndicator(),
              if (_error case final error?)
                Text(
                  error.userMessage,
                  key: const Key('git-lfs-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (snapshot case final value?) ...[
                Text(
                  value.isAvailable
                      ? 'Git LFS available${value.version == null ? '' : ': ${value.version}'}'
                      : 'Git LFS is not installed',
                  key: const Key('git-lfs-installation'),
                ),
                const SizedBox(height: 8),
                Text(
                  '${value.filteredPaths.length} path(s) use the LFS filter.',
                ),
                if (value.diagnostics.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final diagnostic in value.diagnostics)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: const Icon(Icons.warning_amber_outlined),
                      title: Text(diagnostic),
                    ),
                ],
                if (value.files.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final file in value.files)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: Icon(
                        file.state == GitLfsFileState.hydrated
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                      ),
                      title: Text(file.path),
                      subtitle: Text(file.state.name),
                    ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('git-lfs-refresh'),
          onPressed: _loading || _pulling ? null : _load,
          child: const Text('Refresh'),
        ),
        FilledButton.tonal(
          key: const Key('git-lfs-pull'),
          onPressed:
              snapshot?.isAvailable == true &&
                  snapshot!.hasLfsFilters &&
                  !_pulling
              ? _pull
              : null,
          child: _pulling
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Pull LFS objects'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
