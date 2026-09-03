import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gift/src/backend/error.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:gift/src/backend/history.dart';
import 'package:gift/src/backend/reset.dart';
import 'package:gift/src/backend/domain.dart';

/// A preview-first dialog for history-changing operations.
class ResetDialog extends StatefulWidget {
  const ResetDialog({
    super.key,
    required this.gateway,
    required this.repository,
  });

  final GitGateway gateway;
  final RepositoryOpened repository;

  @override
  State<ResetDialog> createState() => _ResetDialogState();
}

class _ResetDialogState extends State<ResetDialog> {
  late final TextEditingController _targetController;
  late final TextEditingController _revisionsController;
  var _targetHistoryLoading = false;
  var _targetHistoryError = false;
  var _targetEditedByUser = false;
  var _advancedTargetExpanded = false;
  String? _selectedTarget;
  List<GitCommit> _recentTargetCommits = const [];
  var _action = GitHistoryRollbackAction.reset;
  var _mode = GitResetMode.mixed;
  var _confirmHardReset = false;
  var _isBusy = false;
  GitHistoryRollbackPreview? _preview;
  GitHistoryRollbackResult? _result;
  GitError? _error;

  @override
  void initState() {
    super.initState();
    _targetController = TextEditingController(text: 'HEAD^');
    _revisionsController = TextEditingController();
    unawaited(_loadRecentTargetCommits());
  }

  @override
  void dispose() {
    _targetController.dispose();
    _revisionsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.history_toggle_off),
          SizedBox(width: 10),
          Expanded(child: Text('Undo, reset, or revert')),
        ],
      ),
      content: SizedBox(
        width: compact ? double.maxFinite : 680,
        child: SingleChildScrollView(
          key: const Key('rollback-dialog-scroll'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Review the exact effect before changing repository history.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<GitHistoryRollbackAction>(
                key: const Key('rollback-action'),
                initialValue: _action,
                decoration: const InputDecoration(labelText: 'Action'),
                items: const [
                  DropdownMenuItem(
                    value: GitHistoryRollbackAction.reset,
                    child: Text('Reset branch to a revision'),
                  ),
                  DropdownMenuItem(
                    value: GitHistoryRollbackAction.undo,
                    child: Text('Undo latest unpushed commit'),
                  ),
                  DropdownMenuItem(
                    value: GitHistoryRollbackAction.revert,
                    child: Text('Revert commit(s) with new commit(s)'),
                  ),
                ],
                onChanged: _isBusy
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() {
                          _action = value;
                          _preview = null;
                          _result = null;
                          _error = null;
                        });
                      },
              ),
              const SizedBox(height: 12),
              if (_action == GitHistoryRollbackAction.reset) ...[
                if (_targetHistoryLoading)
                  const Padding(
                    key: Key('rollback-target-history-loading'),
                    padding: EdgeInsets.only(bottom: 8),
                    child: LinearProgressIndicator(),
                  ),
                if (_recentTargetCommits.isNotEmpty)
                  DropdownButtonFormField<String>(
                    key: const Key('rollback-target-commit'),
                    initialValue: _selectedTarget,
                    decoration: const InputDecoration(
                      labelText: 'Target commit',
                      helperText:
                          'Choose a recent commit instead of typing HEAD^.',
                    ),
                    items: [
                      for (final commit in _recentTargetCommits)
                        DropdownMenuItem(
                          value: commit.oid,
                          child: Text(
                            '${commit.shortOid} · ${commit.subject.isEmpty ? '(no subject)' : commit.subject}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _isBusy
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() {
                              _selectedTarget = value;
                              _targetController.text = value;
                              _targetEditedByUser = true;
                              _preview = null;
                              _result = null;
                              _error = null;
                              _confirmHardReset = false;
                            });
                          },
                  ),
                if (_targetHistoryError)
                  const Text(
                    'Recent commits could not be loaded. Enter a revision below.',
                    key: Key('rollback-target-history-error'),
                  ),
                const SizedBox(height: 8),
                ExpansionTile(
                  key: const Key('rollback-advanced-target'),
                  initiallyExpanded: _advancedTargetExpanded,
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  title: const Text('Advanced revision'),
                  subtitle: const Text(
                    'Use HEAD^, HEAD~1, a branch, or a full commit ID',
                  ),
                  onExpansionChanged: (expanded) {
                    setState(() => _advancedTargetExpanded = expanded);
                  },
                  children: [
                    TextField(
                      key: const Key('rollback-target-revision'),
                      controller: _targetController,
                      enabled: !_isBusy,
                      decoration: const InputDecoration(
                        labelText: 'Revision expression',
                        hintText: 'Only needed for an advanced target',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) {
                        _selectedTarget = null;
                        _targetEditedByUser = true;
                        _clearReview();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<GitResetMode>(
                  key: const Key('rollback-reset-mode'),
                  initialValue: _mode,
                  decoration: const InputDecoration(labelText: 'Reset mode'),
                  items: GitResetMode.values
                      .map(
                        (mode) => DropdownMenuItem(
                          value: mode,
                          child: Text(
                            '${mode.label} — ${_modeDescription(mode)}',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _isBusy
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() {
                            _mode = value;
                            _confirmHardReset = false;
                            _preview = null;
                            _error = null;
                          });
                        },
                ),
              ],
              if (_action == GitHistoryRollbackAction.revert)
                TextField(
                  key: const Key('rollback-revisions'),
                  controller: _revisionsController,
                  enabled: !_isBusy,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Commit(s) to revert',
                    hintText: 'Paste commit IDs or refs, separated by commas',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => _clearReview(),
                ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    key: const Key('preview-rollback'),
                    onPressed: _isBusy
                        ? null
                        : () => unawaited(_previewAction()),
                    icon: _isBusy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.visibility_outlined),
                    label: const Text('Preview effect'),
                  ),
                ],
              ),
              if (_preview?.isDestructive == true &&
                  _preview?.request.mode == GitResetMode.hard)
                CheckboxListTile(
                  key: const Key('confirm-hard-reset'),
                  dense: compact,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _confirmHardReset,
                  onChanged: _isBusy
                      ? null
                      : (selected) => setState(
                          () => _confirmHardReset = selected ?? false,
                        ),
                  title: const Text('I understand this will discard content'),
                ),
              if (_preview case final preview?) ...[
                const SizedBox(height: 14),
                _previewCard(context, preview),
              ],
              if (_error case final error?) ...[
                const SizedBox(height: 12),
                _errorCard(context, error),
              ],
              if (_result case final result?) ...[
                const SizedBox(height: 12),
                _resultCard(context, result),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isBusy ? null : () => Navigator.of(context).pop(_result),
          child: Text(_result == null ? 'Close' : 'Done'),
        ),
        if (_preview case final preview?)
          FilledButton.icon(
            key: const Key('execute-rollback'),
            onPressed: _canExecute(preview) && !_isBusy
                ? () => unawaited(_execute(preview))
                : null,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Run reviewed action'),
          ),
      ],
    );
  }

  bool _canExecute(GitHistoryRollbackPreview preview) {
    if (!preview.canExecute) return false;
    return preview.request.mode != GitResetMode.hard || _confirmHardReset;
  }

  Future<void> _previewAction() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _isBusy = true;
      _preview = null;
      _result = null;
      _error = null;
    });
    try {
      final request = switch (_action) {
        GitHistoryRollbackAction.reset => GitHistoryRollbackRequest(
          action: _action,
          targetRevision: _targetController.text.trim(),
          mode: _mode,
        ),
        GitHistoryRollbackAction.undo => const GitHistoryRollbackRequest(
          action: GitHistoryRollbackAction.undo,
        ),
        GitHistoryRollbackAction.revert => GitHistoryRollbackRequest(
          action: _action,
          revisions: _revisionsController.text
              .split(RegExp(r'[,\s]+'))
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toList(growable: false),
        ),
      };
      final preview = await widget.gateway.previewHistoryRollback(
        widget.repository.repositoryId,
        request,
      );
      if (!mounted) return;
      setState(() => _preview = preview);
    } on GitError catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _execute(GitHistoryRollbackPreview preview) async {
    setState(() {
      _isBusy = true;
      _error = null;
    });
    try {
      final result = await widget.gateway.executeHistoryRollback(
        widget.repository.repositoryId,
        preview,
      );
      if (!mounted) return;
      setState(() => _result = result);
    } on GitError catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _loadRecentTargetCommits() async {
    if (mounted) setState(() => _targetHistoryLoading = true);
    try {
      final page = await widget.gateway.getHistory(
        widget.repository.repositoryId,
        query: const GitHistoryQuery(limit: 30),
      );
      if (!mounted) return;
      final current = page.commits.isEmpty ? null : page.commits.first;
      final commits = current == null
          ? page.commits
          : page.commits.where((commit) => commit.oid != current.oid).toList();
      final preferred = current?.parents.firstWhere(
        (parent) => commits.any((commit) => commit.oid == parent),
        orElse: () => commits.isEmpty ? '' : commits.first.oid,
      );
      setState(() {
        _recentTargetCommits = commits;
        _targetHistoryError = false;
        if (commits.isEmpty && !_targetEditedByUser) {
          _advancedTargetExpanded = true;
        }
        if (!_targetEditedByUser && preferred != null && preferred.isNotEmpty) {
          _selectedTarget = preferred;
          _targetController.text = preferred;
        }
      });
    } on GitError {
      if (mounted) setState(() => _targetHistoryError = true);
    } finally {
      if (mounted) setState(() => _targetHistoryLoading = false);
    }
  }

  void _clearReview() {
    if (_preview == null && _error == null && _result == null) return;
    setState(() {
      _preview = null;
      _result = null;
      _error = null;
      _confirmHardReset = false;
    });
  }

  Widget _previewCard(BuildContext context, GitHistoryRollbackPreview preview) {
    final scheme = Theme.of(context).colorScheme;
    final blocked = preview.blockingMessage != null;
    final impact = preview.impact;
    return Card(
      key: const Key('rollback-preview'),
      color: blocked ? scheme.errorContainer : scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  blocked ? Icons.block : Icons.fact_check_outlined,
                  size: 18,
                  color: blocked ? scheme.onErrorContainer : scheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    blocked ? 'Action blocked' : 'Review before execution',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Text(
                  preview.currentBranch ?? 'detached',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'HEAD  ${_short(preview.currentHead)} → ${_short(preview.targetHead)}',
            ),
            Text('Index  ${_effectLabel(impact.indexEffect)}'),
            Text('Worktree  ${_effectLabel(impact.worktreeEffect)}'),
            Text('Commits moved  ${impact.commitsMoved}'),
            if (impact.preservedPaths.isNotEmpty)
              Text('Preserved paths  ${impact.preservedPaths.join(', ')}'),
            if (impact.potentiallyDiscardedPaths.isNotEmpty)
              Text(
                'Discarded paths  ${impact.potentiallyDiscardedPaths.join(', ')}',
                style: TextStyle(
                  color: scheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (preview.blockingMessage case final message?)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  message,
                  key: const Key('rollback-blocking-message'),
                  style: TextStyle(color: scheme.onErrorContainer),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _errorCard(BuildContext context, GitError error) {
    return Card(
      key: const Key('rollback-error'),
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(error.userMessage),
      ),
    );
  }

  Widget _resultCard(BuildContext context, GitHistoryRollbackResult result) {
    final conflicted = result.state == GitHistoryRollbackState.conflicted;
    return Card(
      key: const Key('rollback-result'),
      color: conflicted
          ? Theme.of(context).colorScheme.errorContainer
          : Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              conflicted
                  ? 'Revert needs conflict recovery'
                  : 'Rollback complete',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(result.summary),
            if (conflicted)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Open Changes → Resolve conflicts, then continue or abort the revert.',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _short(String oid) => oid.length > 8 ? oid.substring(0, 8) : oid;

String _effectLabel(GitRollbackTreeEffect effect) => switch (effect) {
  GitRollbackTreeEffect.preserved => 'preserved',
  GitRollbackTreeEffect.resetToTarget => 'reset to target',
  GitRollbackTreeEffect.unchanged => 'unchanged',
};

String _modeDescription(GitResetMode mode) => switch (mode) {
  GitResetMode.soft => 'keep index and files',
  GitResetMode.mixed => 'reset index, keep files',
  GitResetMode.hard => 'reset index and files',
  GitResetMode.keep => 'keep local files when safe',
};
