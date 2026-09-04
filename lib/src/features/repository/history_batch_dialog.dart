import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/error.dart';
import 'package:gift/src/backend/executor.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:gift/src/backend/history_batch.dart';

class HistoryBatchDialog extends StatefulWidget {
  const HistoryBatchDialog({
    super.key,
    required this.gateway,
    required this.repository,
    required this.action,
    required this.revisions,
  });

  final GitGateway gateway;
  final RepositoryOpened repository;
  final GitHistoryBatchAction action;
  final List<String> revisions;

  @override
  State<HistoryBatchDialog> createState() => _HistoryBatchDialogState();
}

class _HistoryBatchDialogState extends State<HistoryBatchDialog> {
  GitHistoryBatchPreview? _preview;
  GitHistoryBatchResult? _result;
  GitError? _error;
  GitCancellationToken? _cancellationToken;
  var _loading = true;
  var _executing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPreview());
  }

  Future<void> _loadPreview() async {
    try {
      final preview = await widget.gateway.previewHistoryBatch(
        widget.repository.repositoryId,
        GitHistoryBatchRequest(
          action: widget.action,
          revisions: widget.revisions,
        ),
      );
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _loading = false;
        _error = null;
      });
    } on GitError catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  Future<void> _execute() async {
    final preview = _preview;
    if (preview == null || !preview.canExecute || _executing) return;
    final cancellation = GitCancellationToken();
    setState(() {
      _executing = true;
      _cancellationToken = cancellation;
      _error = null;
    });
    try {
      final result = await widget.gateway.executeHistoryBatch(
        widget.repository.repositoryId,
        preview,
        cancellationToken: cancellation,
      );
      if (!mounted) return;
      setState(() {
        _executing = false;
        _cancellationToken = null;
        _result = result;
      });
    } on GitError catch (error) {
      if (!mounted) return;
      setState(() {
        _executing = false;
        _cancellationToken = null;
        _error = error;
      });
    }
  }

  Future<void> _recover(GitHistoryBatchRecoveryAction action) async {
    final result = _result;
    final preview = _preview;
    final token = result?.continuationToken;
    final currentOid = result?.currentOid;
    if (result == null ||
        preview == null ||
        token == null ||
        currentOid == null) {
      return;
    }
    final request = GitHistoryBatchRecoveryRequest(
      action: result.request.action,
      revisions: result.request.revisions,
      executionOids: preview.executionOids,
      completedOids: result.completedOids,
      skippedOids: result.skippedOids,
      currentOid: currentOid,
      remainingOids: result.remainingOids
          .where((oid) => oid != currentOid)
          .toList(growable: false),
      targetBranch: preview.targetBranch!,
      mainlines: result.request.mainlines,
      selectionFingerprint: result.selectionFingerprint,
      recoveryAction: action,
      continuationToken: token,
    );
    setState(() {
      _executing = true;
      _error = null;
    });
    try {
      final recovered = await widget.gateway.recoverHistoryBatch(
        widget.repository.repositoryId,
        request,
      );
      if (!mounted) return;
      setState(() {
        _executing = false;
        _result = recovered;
      });
    } on GitError catch (error) {
      if (!mounted) return;
      setState(() {
        _executing = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return AlertDialog(
      title: Text('${widget.action.label} selected commits'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              : _error != null && _preview == null
              ? Text(_error!.userMessage)
              : _body(context, result),
        ),
      ),
      actions: [
        if (_executing)
          TextButton(
            key: const Key('batch-cancel'),
            onPressed: () => _cancellationToken?.cancel(),
            child: const Text('Cancel'),
          ),
        TextButton(
          key: const Key('batch-close'),
          onPressed: _executing
              ? null
              : () => Navigator.of(context).pop(result),
          child: const Text('Close'),
        ),
        if (_preview?.canExecute == true && result == null)
          FilledButton(
            key: const Key('batch-execute'),
            onPressed: _executing ? null : _execute,
            child: Text(widget.action.label),
          ),
      ],
    );
  }

  Widget _body(BuildContext context, GitHistoryBatchResult? result) {
    final preview = _preview!;
    final theme = Theme.of(context);
    final progress = result == null
        ? null
        : GitHistoryBatchProgress.fromResult(result);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (preview.blockingMessage case final message?)
          _notice(context, message, theme.colorScheme.errorContainer),
        if (_error case final error?)
          _notice(context, error.userMessage, theme.colorScheme.errorContainer),
        Text(
          'Target branch: ${preview.targetBranch ?? '(detached)'}',
          key: const Key('batch-target-branch'),
        ),
        const SizedBox(height: 6),
        Text(
          'Execution: ${_directionLabel(preview.executionDirection)}',
          key: const Key('batch-execution-direction'),
        ),
        const SizedBox(height: 6),
        Text('Impacted paths: ${preview.impactedPaths.length}'),
        if (preview.impactedPaths.isNotEmpty)
          Text(
            preview.impactedPaths.join(', '),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        if (preview.duplicateOids.isNotEmpty)
          Text('Duplicates: ${preview.duplicateOids.length}'),
        if (preview.containedOids.isNotEmpty)
          Text('Already contained: ${preview.containedOids.length}'),
        if (preview.mergeMainlineRequired.isNotEmpty)
          Text('Merge commits need a mainline parent.'),
        const SizedBox(height: 12),
        Text(
          result == null
              ? 'Reviewed commit order'
              : 'Progress: ${progress!.completedOids.length} completed · ${progress.remainingOids.length} remaining',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 6),
        for (final oid in preview.executionOids)
          Text(
            _progressLabel(oid, result),
            key: ValueKey('batch-preview-oid:$oid'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        if (result != null) ...[
          const SizedBox(height: 12),
          Text(result.summary),
          for (final action in result.recoveryActions)
            OutlinedButton(
              key: ValueKey('batch-recovery:${action.name}'),
              onPressed: _executing ? null : () => _recover(action),
              child: Text(_recoveryLabel(action)),
            ),
        ],
      ],
    );
  }

  Widget _notice(BuildContext context, String text, Color color) => Container(
    color: color,
    padding: const EdgeInsets.all(10),
    child: Text(text),
  );

  String _progressLabel(String oid, GitHistoryBatchResult? result) {
    if (result == null) return oid;
    if (result.completedOids.contains(oid)) return 'Completed · $oid';
    if (result.skippedOids.contains(oid)) return 'Skipped · $oid';
    if (result.currentOid == oid) return 'Current · $oid';
    return 'Remaining · $oid';
  }

  String _directionLabel(GitHistoryBatchExecutionDirection direction) =>
      switch (direction) {
        GitHistoryBatchExecutionDirection.oldestToNewest => 'oldest → newest',
        GitHistoryBatchExecutionDirection.newestToOldest => 'newest → oldest',
      };

  String _recoveryLabel(
    GitHistoryBatchRecoveryAction action,
  ) => switch (action) {
    GitHistoryBatchRecoveryAction.continueCurrent => 'Continue current commit',
    GitHistoryBatchRecoveryAction.skipCurrent => 'Skip current commit',
    GitHistoryBatchRecoveryAction.abortCurrent => 'Abort current operation',
    GitHistoryBatchRecoveryAction.continueRemaining =>
      'Continue remaining commits',
    GitHistoryBatchRecoveryAction.abortRemaining => 'Stop remaining commits',
  };
}
