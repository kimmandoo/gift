import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/error.dart';
import 'package:gift/src/backend/executor.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:gift/src/backend/recovery.dart';

/// Presents bounded reflog entries beside the process-local Git operation
/// history. Recovery creates a new branch only after a fresh preview is
/// reviewed; the current branch is never moved by this dialog.
class RecoveryDialog extends StatefulWidget {
  const RecoveryDialog({
    super.key,
    required this.gateway,
    required this.repository,
  });

  final GitGateway gateway;
  final RepositoryOpened repository;

  @override
  State<RecoveryDialog> createState() => _RecoveryDialogState();
}

class _RecoveryDialogState extends State<RecoveryDialog> {
  final _branchController = TextEditingController(text: 'recovery/branch');
  GitReflogSnapshot? _reflog;
  List<GitOperationRecord> _operations = const [];
  GitRecoveryBranchPreview? _preview;
  GitError? _error;
  String? _message;
  var _isLoading = true;
  var _isBusy = false;

  @override
  void initState() {
    super.initState();
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
    final compact = size.width < 560;
    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 32,
        vertical: 20,
      ),
      title: Row(
        children: [
          const Expanded(child: Text('Recovery diagnostics')),
          if (_isBusy)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
      content: SizedBox(
        width: (size.width - (compact ? 24 : 64)).clamp(280.0, 800.0),
        height: (size.height - 150).clamp(300.0, 620.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error case final error?) _errorBanner(error),
            if (_message case final message?)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  message,
                  key: const Key('recovery-message'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            _recoveryForm(context),
            const SizedBox(height: 10),
            Expanded(child: _content(context)),
          ],
        ),
      ),
      actionsOverflowButtonSpacing: 4,
      actions: [
        TextButton(
          key: const Key('refresh-recovery'),
          onPressed: _isBusy ? null : _load,
          child: const Text('Refresh'),
        ),
        TextButton(
          key: const Key('close-recovery-dialog'),
          onPressed: _isBusy ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _errorBanner(GitError error) => Container(
    key: const Key('recovery-error'),
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(8),
    color: Theme.of(context).colorScheme.errorContainer,
    child: Text(error.userMessage),
  );

  Widget _recoveryForm(BuildContext context) {
    final preview = _preview;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('recovery-branch-name'),
              controller: _branchController,
              enabled: !_isBusy,
              decoration: const InputDecoration(
                labelText: 'New recovery branch',
                hintText: 'recovery/old-head',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (preview case final selected?) ...[
              const SizedBox(height: 8),
              Text(
                'Create ${selected.request.branchName} at ${selected.entry.oid.substring(0, 8)}…? ',
                key: const Key('recovery-preview'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  key: const Key('create-recovery-branch'),
                  onPressed: _isBusy ? null : _create,
                  child: const Text('Create branch'),
                ),
              ),
            ] else
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  key: const Key('review-recovery-branch'),
                  onPressed: _isBusy ? null : _reviewSelected,
                  child: const Text('Review selected entry'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    final entries = _reflog?.entries ?? const <GitReflogEntry>[];
    return ListView(
      key: const Key('recovery-scroll'),
      children: [
        Text('Reflog', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        if (entries.isEmpty) const Text('No recovery entries are available.'),
        for (final entry in entries) _reflogTile(context, entry),
        const SizedBox(height: 12),
        Text(
          'Recent Git operations',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 6),
        if (_operations.isEmpty)
          const Text('No operations were recorded for this root.'),
        for (var index = 0; index < _operations.length; index++) ...[
          _operationTile(_operations[index]),
          if (index < _operations.length - 1) const SizedBox(height: 6),
        ],
        const SizedBox(height: 8),
        Text(
          'Operation records omit stdin and redact credential-like values. They are kept only for this app process.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _reflogTile(BuildContext context, GitReflogEntry entry) {
    return Card(
      key: ValueKey('reflog:${entry.oid}:${entry.selector}'),
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
        title: Text(
          '${entry.selector} · ${entry.message}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${entry.oid.substring(0, 8)} · ${entry.actor ?? 'unknown actor'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: TextButton(
          key: ValueKey('recover-reflog:${entry.oid}'),
          onPressed: _isBusy ? null : () => _selectEntry(entry),
          child: const Text('Select'),
        ),
      ),
    );
  }

  Widget _operationTile(GitOperationRecord operation) => ListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    leading: Icon(
      operation.succeeded ? Icons.check_circle_outline : Icons.error_outline,
      color: operation.succeeded
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.error,
    ),
    title: Text(
      operation.command,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
    subtitle: Text(
      '${operation.kind.name} · ${operation.duration.inMilliseconds} ms'
      '${operation.diagnostic.isEmpty ? '' : ' · ${operation.diagnostic}'}',
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
  );

  void _selectEntry(GitReflogEntry entry) {
    setState(() {
      _selectedEntry = entry;
      _preview = null;
      _message = 'Selected ${entry.selector}.';
    });
  }

  GitReflogEntry? _selectedEntry;

  Future<void> _reviewSelected() async {
    final entry = _selectedEntry ?? _reflog?.entries.firstOrNull;
    final reflog = _reflog;
    if (entry == null || reflog == null) return;
    await _run(() async {
      final preview = await widget.gateway.previewRecoveryBranch(
        widget.repository.repositoryId,
        GitRecoveryBranchRequest(
          branchName: _branchController.text.trim(),
          oid: entry.oid,
          reflogFingerprint: reflog.fingerprint,
        ),
      );
      if (mounted) setState(() => _preview = preview);
    });
  }

  Future<void> _create() async {
    final preview = _preview;
    if (preview == null) return;
    await _run(() async {
      final result = await widget.gateway.createRecoveryBranch(
        widget.repository.repositoryId,
        preview,
      );
      if (mounted) {
        setState(() {
          _preview = null;
          _message = result.summary;
          _reflog = result.reflog;
        });
      }
    });
  }

  Future<void> _load() async {
    if (_isBusy) return;
    setState(() {
      _isLoading = true;
      _error = null;
      _message = null;
    });
    try {
      final reflog = await widget.gateway.getReflog(
        widget.repository.repositoryId,
      );
      final operations = await widget.gateway.getOperationRecords(
        widget.repository.repositoryId,
      );
      if (!mounted) return;
      setState(() {
        _reflog = reflog;
        _operations = operations;
        _isLoading = false;
        _selectedEntry ??= reflog.entries.firstOrNull;
      });
    } on GitError catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _isLoading = false;
      });
    }
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_isBusy) return;
    setState(() {
      _isBusy = true;
      _error = null;
      _message = null;
    });
    try {
      await operation();
    } on GitError catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }
}
