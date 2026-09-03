import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/error.dart';
import 'package:gift/src/backend/executor.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:gift/src/backend/history.dart';
import 'package:gift/src/backend/interactive_rebase.dart';
import 'package:gift/src/backend/status.dart';

/// A compact, keyboard-friendly editor for a reviewed interactive rebase.
///
/// The dialog builds the plan from the captured History page. It never asks
/// the user to type a shell command or a raw todo file; the backend owns the
/// final command and revalidates the selected range before execution.
class InteractiveRebaseDialog extends StatefulWidget {
  const InteractiveRebaseDialog({
    super.key,
    required this.gateway,
    required this.repository,
  });

  final GitGateway gateway;
  final RepositoryOpened repository;

  @override
  State<InteractiveRebaseDialog> createState() =>
      _InteractiveRebaseDialogState();
}

class _InteractiveRebaseDialogState extends State<InteractiveRebaseDialog> {
  GitHistoryPage? _history;
  GitBranchStatus? _status;
  List<GitInteractiveRebaseEntry> _entries = const [];
  GitInteractiveRebasePreview? _preview;
  GitInteractiveRebaseResult? _result;
  GitError? _error;
  int? _upstreamIndex;
  var _root = false;
  var _autosquash = false;
  var _updateRefs = false;
  var _isLoading = true;
  var _isMutating = false;
  GitCancellationToken? _cancellationToken;

  @override
  void initState() {
    super.initState();
    unawaited(_loadHistory());
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 520;
    final width = (size.width - (compact ? 32 : 80)).clamp(280.0, 720.0);
    final height = (size.height - 180).clamp(260.0, 620.0);
    return AlertDialog(
      key: const Key('interactive-rebase-dialog'),
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 16 : 40,
        vertical: 24,
      ),
      title: const Text('Interactive rebase'),
      content: SizedBox(
        width: width,
        height: height,
        child: _isLoading && _history == null
            ? const Center(
                child: CircularProgressIndicator(
                  key: Key('rebase-history-loading'),
                ),
              )
            : _content(context, compact),
      ),
      actionsOverflowButtonSpacing: 4,
      actions: [
        if (_history != null) _actionButtons(context),
        TextButton(
          onPressed: _isMutating ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _content(BuildContext context, bool compact) {
    final history = _history;
    if (history == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error case final error?)
            Text(error.userMessage, key: const Key('rebase-error')),
          const Spacer(),
          OutlinedButton(
            onPressed: _isMutating ? null : _loadHistory,
            child: const Text('Retry'),
          ),
        ],
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_isLoading) const LinearProgressIndicator(),
          if (_error case final error?) ...[
            Text(error.userMessage, key: const Key('rebase-error')),
            const SizedBox(height: 8),
          ],
          _rangeControls(context, history, compact),
          const SizedBox(height: 12),
          _planSection(context, compact),
          if (_preview case final preview?) ...[
            const SizedBox(height: 12),
            _previewSummary(context, preview),
          ],
          if (_result case final result?) ...[
            const SizedBox(height: 12),
            _resultSummary(context, result),
          ],
        ],
      ),
    );
  }

  Widget _rangeControls(
    BuildContext context,
    GitHistoryPage history,
    bool compact,
  ) {
    final canChooseUpstream = history.commits.length > 1;
    final upstreamItems = [
      for (var index = 1; index < history.commits.length; index++)
        DropdownMenuItem(
          value: index,
          child: Text(
            '${history.commits[index].shortOid} · ${history.commits[index].subject}',
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Current branch: ${_status?.head ?? '(detached)'}',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          key: const Key('rebase-upstream'),
          initialValue: _root ? null : _upstreamIndex,
          decoration: const InputDecoration(
            labelText: 'Rebase commits after',
            helperText: 'The selected commit stays as the upstream base.',
            border: OutlineInputBorder(),
          ),
          items: upstreamItems,
          onChanged: _isMutating || _root || !canChooseUpstream
              ? null
              : (value) {
                  if (value == null) return;
                  setState(() {
                    _root = false;
                    _upstreamIndex = value;
                    _entries = _entriesForRange(history, value, root: false);
                    _clearReview();
                  });
                },
        ),
        CheckboxListTile(
          key: const Key('rebase-root'),
          dense: compact,
          contentPadding: EdgeInsets.zero,
          value: _root,
          onChanged: _isMutating || history.hasMore
              ? null
              : (value) {
                  setState(() {
                    _root = value ?? false;
                    _entries = _entriesForRange(
                      history,
                      _upstreamIndex,
                      root: _root,
                    );
                    _clearReview();
                  });
                },
          title: const Text('Rebase from root'),
          subtitle: Text(
            history.hasMore
                ? 'Load the complete history before using root rebase.'
                : 'Include every commit reachable from HEAD.',
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            FilterChip(
              key: const Key('rebase-autosquash'),
              label: const Text('Autosquash'),
              selected: _autosquash,
              onSelected: _isMutating
                  ? null
                  : (value) => setState(() {
                      _autosquash = value;
                      _clearReview();
                    }),
            ),
            FilterChip(
              key: const Key('rebase-update-refs'),
              label: const Text('Update refs'),
              selected: _updateRefs,
              onSelected: _isMutating
                  ? null
                  : (value) => setState(() {
                      _updateRefs = value;
                      _clearReview();
                    }),
            ),
          ],
        ),
      ],
    );
  }

  Widget _planSection(BuildContext context, bool compact) {
    if (_entries.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text('Select an upstream commit to build the rebase plan.'),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Plan (${_entries.length} commit${_entries.length == 1 ? '' : 's'})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Rows run from oldest to newest. Reorder before previewing.',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 8),
            for (var index = 0; index < _entries.length; index++)
              _planRow(context, index, compact),
          ],
        ),
      ),
    );
  }

  Widget _planRow(BuildContext context, int index, bool compact) {
    final entry = _entries[index];
    return Container(
      key: ValueKey('rebase-entry:${entry.originalOid}'),
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text('${index + 1}', textAlign: TextAlign.right),
          ),
          const SizedBox(width: 6),
          DropdownButton<GitInteractiveRebaseAction>(
            key: ValueKey('rebase-action:${entry.originalOid}'),
            value: entry.action,
            isDense: true,
            onChanged: _isMutating
                ? null
                : (action) {
                    if (action == null) return;
                    setState(() {
                      _entries = [
                        for (
                          var itemIndex = 0;
                          itemIndex < _entries.length;
                          itemIndex++
                        )
                          itemIndex == index
                              ? _entries[itemIndex].copyWith(action: action)
                              : _entries[itemIndex],
                      ];
                      _clearReview();
                    });
                  },
            items: [
              for (final action in GitInteractiveRebaseAction.values)
                DropdownMenuItem(value: action, child: Text(action.label)),
            ],
          ),
          const SizedBox(width: 6),
          if (entry.action == GitInteractiveRebaseAction.reword)
            Expanded(
              child: TextFormField(
                key: ValueKey('rebase-subject:${entry.originalOid}'),
                initialValue: entry.subject,
                maxLines: 1,
                onChanged: _isMutating
                    ? null
                    : (subject) {
                        setState(() {
                          _entries = [
                            for (
                              var itemIndex = 0;
                              itemIndex < _entries.length;
                              itemIndex++
                            )
                              itemIndex == index
                                  ? _entries[itemIndex].copyWith(
                                      subject: subject,
                                    )
                                  : _entries[itemIndex],
                          ];
                          _clearReview();
                        });
                      },
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'New commit subject',
                  prefixText: '${entry.shortOid} · ',
                  border: const OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: compact ? 6 : 8,
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: Text(
                '${entry.shortOid} · ${entry.subject}',
                maxLines: compact ? 2 : 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          IconButton(
            key: ValueKey('rebase-up:${entry.originalOid}'),
            tooltip: 'Move up',
            visualDensity: VisualDensity.compact,
            onPressed: _isMutating || index == 0
                ? null
                : () => _moveEntry(index, index - 1),
            icon: const Icon(Icons.arrow_upward, size: 17),
          ),
          IconButton(
            key: ValueKey('rebase-down:${entry.originalOid}'),
            tooltip: 'Move down',
            visualDensity: VisualDensity.compact,
            onPressed: _isMutating || index == _entries.length - 1
                ? null
                : () => _moveEntry(index, index + 1),
            icon: const Icon(Icons.arrow_downward, size: 17),
          ),
        ],
      ),
    );
  }

  Widget _actionButtons(BuildContext context) {
    final preview = _preview;
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 4,
      children: [
        if (_isMutating)
          TextButton(
            key: const Key('cancel-interactive-rebase'),
            onPressed: _cancelMutation,
            child: const Text('Cancel'),
          ),
        OutlinedButton(
          key: const Key('preview-interactive-rebase'),
          onPressed: _isMutating ? null : _previewPlan,
          child: const Text('Preview'),
        ),
        if (preview?.canExecute == true)
          FilledButton(
            key: const Key('execute-interactive-rebase'),
            onPressed: _isMutating ? null : _executePlan,
            child: const Text('Start rebase'),
          ),
      ],
    );
  }

  Widget _previewSummary(
    BuildContext context,
    GitInteractiveRebasePreview preview,
  ) {
    final state = preview.blockingMessage ?? 'Ready for confirmation.';
    return Card(
      key: const Key('interactive-rebase-preview'),
      color: preview.canExecute
          ? Theme.of(context).colorScheme.tertiaryContainer
          : Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Branch: ${preview.currentBranch ?? '(detached)'} · '
              '${preview.selectedCommitCount} commit(s) · '
              '${preview.mergeCommitCount} merge commit(s)\n$state',
              style: TextStyle(
                color: preview.canExecute
                    ? Theme.of(context).colorScheme.onTertiaryContainer
                    : Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
            if (preview.optionLimitations.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Option notes:\n${preview.optionLimitations.map((note) => '• $note').join('\n')}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _resultSummary(
    BuildContext context,
    GitInteractiveRebaseResult result,
  ) {
    return Card(
      key: const Key('interactive-rebase-result'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(result.summary),
            if (result.pauseReason case final reason?) ...[
              const SizedBox(height: 4),
              Text(
                'Stop reason: ${_pauseReasonLabel(reason)}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
            if (result.recoveryRefs.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Recovery refs: ${result.recoveryRefs.join(', ')}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
            if (result.originalCommitOids.isNotEmpty ||
                result.rewrittenCommitOids.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Rewritten commits: ${result.rewrittenCommitOids.length}/'
                '${result.originalCommitOids.length}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
            if (result.recoveryActions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final action in result.recoveryActions)
                    OutlinedButton(
                      key: ValueKey(
                        'interactive-rebase-recovery:${action.name}',
                      ),
                      onPressed:
                          _isMutating || result.recoveryFingerprint == null
                          ? null
                          : () => _recover(action, result.recoveryFingerprint!),
                      child: Text(_recoveryLabel(action)),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<GitInteractiveRebaseEntry> _entriesForRange(
    GitHistoryPage history,
    int? upstreamIndex, {
    required bool root,
  }) {
    final commits = root
        ? history.commits
        : upstreamIndex == null
        ? const <GitCommit>[]
        : history.commits.take(upstreamIndex).toList(growable: false);
    final oldestFirst = commits.reversed.toList(growable: false);
    return [
      for (var index = 0; index < oldestFirst.length; index++)
        GitInteractiveRebaseEntry(
          originalOid: oldestFirst[index].oid,
          subject: oldestFirst[index].subject,
          action: GitInteractiveRebaseAction.pick,
          originalIndex: index,
        ),
    ];
  }

  GitInteractiveRebasePlan? _plan() {
    final history = _history;
    if (history == null || _entries.isEmpty) return null;
    return GitInteractiveRebasePlan(
      repositoryId: widget.repository.repositoryId,
      upstreamRevision: _root || _upstreamIndex == null
          ? null
          : history.commits[_upstreamIndex!].oid,
      entries: _entries,
      options: GitInteractiveRebaseOptions(
        autosquash: _autosquash,
        root: _root,
        updateRefs: _updateRefs,
      ),
    );
  }

  void _moveEntry(int fromIndex, int toIndex) {
    setState(() {
      final moved = [..._entries];
      final entry = moved.removeAt(fromIndex);
      moved.insert(toIndex, entry);
      _entries = moved;
      _clearReview();
    });
  }

  void _clearReview() {
    _preview = null;
    _result = null;
    _error = null;
  }

  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final history = await widget.gateway.getHistory(
        widget.repository.repositoryId,
        limit: 50,
      );
      final status = await widget.gateway.getStatus(
        widget.repository.repositoryId,
      );
      if (!mounted) return;
      final upstreamIndex = history.commits.length > 1 ? 1 : null;
      setState(() {
        _history = history;
        _status = status.branch;
        _upstreamIndex = upstreamIndex;
        _entries = _entriesForRange(history, upstreamIndex, root: false);
        _isLoading = false;
      });
    } on GitError catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _isLoading = false;
      });
    }
  }

  Future<void> _previewPlan() async {
    final plan = _plan();
    if (_isMutating || plan == null) return;
    setState(() {
      _isMutating = true;
      _preview = null;
      _result = null;
      _error = null;
    });
    try {
      final preview = await widget.gateway.previewInteractiveRebase(
        widget.repository.repositoryId,
        plan,
      );
      if (mounted) setState(() => _preview = preview);
    } on GitError catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _isMutating = false);
    }
  }

  Future<void> _executePlan() async {
    final preview = _preview;
    if (_isMutating || preview == null || !preview.canExecute) return;
    final cancellationToken = GitCancellationToken();
    setState(() {
      _isMutating = true;
      _error = null;
      _cancellationToken = cancellationToken;
    });
    try {
      final result = await widget.gateway.executeInteractiveRebase(
        widget.repository.repositoryId,
        preview,
        cancellationToken: cancellationToken,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _preview = null;
      });
      if (result.state == GitInteractiveRebaseExecutionState.completed ||
          result.state == GitInteractiveRebaseExecutionState.aborted) {
        if (mounted) Navigator.of(context).pop(result);
      }
    } on GitError catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) {
        setState(() {
          _isMutating = false;
          if (identical(_cancellationToken, cancellationToken)) {
            _cancellationToken = null;
          }
        });
      }
    }
  }

  Future<void> _recover(
    GitInteractiveRebaseRecoveryAction action,
    String fingerprint,
  ) async {
    if (_isMutating) return;
    final previousResult = _result;
    final cancellationToken = GitCancellationToken();
    setState(() {
      _isMutating = true;
      _error = null;
      _cancellationToken = cancellationToken;
    });
    try {
      final result = await widget.gateway.recoverInteractiveRebase(
        widget.repository.repositoryId,
        GitInteractiveRebaseRecoveryRequest(
          action: action,
          fingerprint: fingerprint,
          originalCommitOids: previousResult?.originalCommitOids ?? const [],
          recoveryRefs: previousResult?.recoveryRefs ?? const [],
        ),
        cancellationToken: cancellationToken,
      );
      if (!mounted) return;
      setState(() => _result = result);
      if (result.state == GitInteractiveRebaseExecutionState.completed ||
          result.state == GitInteractiveRebaseExecutionState.aborted) {
        if (mounted) Navigator.of(context).pop(result);
      }
    } on GitError catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) {
        setState(() {
          _isMutating = false;
          if (identical(_cancellationToken, cancellationToken)) {
            _cancellationToken = null;
          }
        });
      }
    }
  }

  void _cancelMutation() => _cancellationToken?.cancel();

  String _recoveryLabel(GitInteractiveRebaseRecoveryAction action) =>
      switch (action) {
        GitInteractiveRebaseRecoveryAction.continueOperation => 'Continue',
        GitInteractiveRebaseRecoveryAction.skip => 'Skip',
        GitInteractiveRebaseRecoveryAction.abort => 'Abort',
      };

  String _pauseReasonLabel(GitInteractiveRebasePauseReason reason) =>
      switch (reason) {
        GitInteractiveRebasePauseReason.edit => 'edit requested',
        GitInteractiveRebasePauseReason.conflict => 'unresolved conflict',
        GitInteractiveRebasePauseReason.hookRejected => 'hook rejected',
        GitInteractiveRebasePauseReason.cancelled => 'cancelled',
      };
}
