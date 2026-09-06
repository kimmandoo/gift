import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/error.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:gift/src/backend/signing.dart';

class GitSigningDialog extends StatefulWidget {
  const GitSigningDialog({
    required this.gateway,
    required this.repository,
    super.key,
  });

  final GitGateway gateway;
  final RepositoryOpened repository;

  @override
  State<GitSigningDialog> createState() => _GitSigningDialogState();
}

class _GitSigningDialogState extends State<GitSigningDialog> {
  GitSigningConfiguration? _configuration;
  GitError? _error;
  var _loading = false;

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
      final configuration = await widget.gateway.getSigningConfiguration(
        widget.repository.repositoryId,
      );
      if (mounted) setState(() => _configuration = configuration);
    } on GitError catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final configuration = _configuration;
    return AlertDialog(
      key: const Key('git-signing-dialog'),
      title: const Text('Commit signing'),
      content: SizedBox(
        width: (MediaQuery.sizeOf(context).width - 64).clamp(280.0, 520.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (_error case final error?)
              Text(
                error.userMessage,
                key: const Key('git-signing-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (configuration case final value?) ...[
              Text(
                value.enabled
                    ? 'Signing is enabled by Git.'
                    : 'Signing is opt-in for commits.',
              ),
              const SizedBox(height: 8),
              Text('Format: ${value.formatLabel}'),
              Text('Signing key: ${value.signingKey ?? 'not configured'}'),
              Text(
                'Program: ${value.program ?? value.sshProgram ?? 'Git default'}',
              ),
              Text(
                'Key status: ${value.agentAvailable ? 'configured' : 'not configured'}',
              ),
              if (value.source.isNotEmpty)
                Text(
                  value.source,
                  key: const Key('git-signing-source'),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('git-signing-refresh'),
          onPressed: _loading ? null : _load,
          child: const Text('Refresh'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
