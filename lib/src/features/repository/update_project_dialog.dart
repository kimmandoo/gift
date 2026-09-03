import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gift/src/app/pixel_theme.dart';
import 'package:gift/src/backend/error.dart';
import 'package:gift/src/backend/executor.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:gift/src/backend/remote_branch.dart';
import 'package:gift/src/backend/domain.dart';

/// Reviews and applies the current branch's tracked remote update.
class UpdateProjectDialog extends StatefulWidget {
  const UpdateProjectDialog({
    super.key,
    required this.gateway,
    required this.repository,
  });

  final GitGateway gateway;
  final RepositoryOpened repository;

  @override
  State<UpdateProjectDialog> createState() => _UpdateProjectDialogState();
}

class _UpdateProjectDialogState extends State<UpdateProjectDialog> {
  GitUpdateStrategy _strategy = GitUpdateStrategy.merge;
  GitUpdateLocalChanges _localChanges = GitUpdateLocalChanges.reject;
  GitUpdateProjectPreview? _preview;
  GitUpdateProjectResult? _result;
  GitError? _error;
  GitCancellationToken? _cancellation;
  var _busy = false;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 520;
    final preview = _preview;
    return AlertDialog(
      key: const Key('update-project-dialog'),
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 16 : 40,
        vertical: 24,
      ),
      title: const Text('Update project'),
      content: SizedBox(
        width: (size.width - (compact ? 32 : 80)).clamp(280.0, 560.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<GitUpdateStrategy>(
                key: const Key('update-strategy'),
                initialValue: _strategy,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Strategy',
                  helperText:
                      'Choose how incoming commits become local history.',
                ),
                items: [
                  for (final strategy in GitUpdateStrategy.values)
                    DropdownMenuItem(
                      value: strategy,
                      child: pixelDropdownText(_strategyLabel(strategy)),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() {
                          _strategy = value;
                          _preview = null;
                          _result = null;
                        });
                      },
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<GitUpdateLocalChanges>(
                key: const Key('update-local-changes'),
                initialValue: _localChanges,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Local changes',
                  helperText:
                      'Dirty worktrees are never changed without a choice.',
                ),
                items: [
                  DropdownMenuItem(
                    value: GitUpdateLocalChanges.reject,
                    child: pixelDropdownText('Require a clean worktree'),
                  ),
                  DropdownMenuItem(
                    value: GitUpdateLocalChanges.stash,
                    child: pixelDropdownText('Stash and restore after update'),
                  ),
                ],
                onChanged: _busy
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() {
                          _localChanges = value;
                          _preview = null;
                          _result = null;
                        });
                      },
              ),
              if (_error case final error?) ...[
                const SizedBox(height: 8),
                Text(error.userMessage, key: const Key('update-project-error')),
              ],
              if (preview != null) ...[
                const SizedBox(height: 12),
                Card(
                  key: const Key('update-project-preview'),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_previewSummary(preview)),
                  ),
                ),
              ],
              if (_result case final result?) ...[
                const SizedBox(height: 8),
                Text(result.summary, key: const Key('update-project-result')),
                if (result.recoveryActions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final phase in result.recoveryActions)
                          OutlinedButton(
                            key: ValueKey('update-recovery:${phase.name}'),
                            onPressed: _busy ? null : () => _recover(phase),
                            child: Text(_phaseLabel(phase)),
                          ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      actionsOverflowButtonSpacing: 4,
      actions: [
        if (_busy)
          TextButton(
            key: const Key('cancel-update-project'),
            onPressed: _cancellation?.cancel,
            child: const Text('Cancel'),
          ),
        if (!_busy && preview?.canExecute != true)
          OutlinedButton(
            key: const Key('preview-update-project'),
            onPressed: _previewUpdate,
            child: const Text('Preview'),
          ),
        if (!_busy && preview?.canExecute == true)
          FilledButton(
            key: const Key('execute-update-project'),
            style: pixelProminentButtonStyle,
            onPressed: _executeUpdate,
            child: Text(
              preview!.request.strategy == GitUpdateStrategy.resetToRemote
                  ? 'Reset to remote'
                  : 'Update project',
            ),
          ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Future<void> _previewUpdate() async {
    setState(() {
      _busy = true;
      _error = null;
      _preview = null;
      _result = null;
    });
    try {
      final preview = await widget.gateway.previewUpdateProject(
        widget.repository.repositoryId,
        GitUpdateProjectRequest(
          strategy: _strategy,
          localChanges: _localChanges,
        ),
      );
      if (!mounted) return;
      setState(() => _preview = preview);
    } on GitError catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _executeUpdate() async {
    final preview = _preview;
    if (preview == null || !preview.canExecute || _busy) return;
    await _run(
      GitUpdateProjectRequest(
        strategy: preview.request.strategy,
        localChanges: preview.request.localChanges,
        confirmationToken: preview.token,
      ),
    );
  }

  Future<void> _recover(GitUpdatePhase phase) async {
    if (_busy) return;
    await _run(GitUpdateProjectRequest(strategy: _strategy, phase: phase));
  }

  Future<void> _run(GitUpdateProjectRequest request) async {
    final cancellation = GitCancellationToken();
    setState(() {
      _busy = true;
      _error = null;
      _cancellation = cancellation;
    });
    try {
      final result = await widget.gateway.executeUpdateProject(
        widget.repository.repositoryId,
        request,
        cancellationToken: cancellation,
      );
      if (!mounted) return;
      if (result.state == GitUpdateState.completed ||
          result.state == GitUpdateState.aborted ||
          result.state == GitUpdateState.cancelled) {
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

  String _previewSummary(GitUpdateProjectPreview preview) {
    final local = preview.dirtyWorktree ? 'dirty' : 'clean';
    final warning = preview.requiresConfirmation
        ? '\nWarning: local commits will be discarded.'
        : '';
    return '${_strategyLabel(preview.request.strategy)} ${preview.branch} from '
        '${preview.upstream}\n'
        'Incoming ${preview.incoming} · outgoing ${preview.outgoing} · '
        'worktree $local$warning'
        '${preview.blockingMessage == null ? '' : '\n${preview.blockingMessage}'}';
  }

  String _strategyLabel(GitUpdateStrategy strategy) => switch (strategy) {
    GitUpdateStrategy.merge => 'Merge',
    GitUpdateStrategy.rebase => 'Rebase',
    GitUpdateStrategy.resetToRemote => 'Reset to remote',
  };

  String _phaseLabel(GitUpdatePhase phase) => switch (phase) {
    GitUpdatePhase.start => 'Start',
    GitUpdatePhase.continueOperation => 'Continue',
    GitUpdatePhase.abort => 'Abort',
  };
}
