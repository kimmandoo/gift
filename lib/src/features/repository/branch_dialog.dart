import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gift/src/app/pixel_theme.dart';

import 'package:gift/src/backend/branch.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/error.dart';
import 'package:gift/src/backend/executor.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:gift/src/backend/remote_branch.dart';
import 'package:gift/src/features/repository/comparison_dialog.dart';

/// A small branch popup that keeps branch work separate from the Changes list.
class BranchDialog extends StatefulWidget {
  const BranchDialog({
    super.key,
    required this.gateway,
    required this.repository,
  });

  final GitGateway gateway;
  final RepositoryOpened repository;

  @override
  State<BranchDialog> createState() => _BranchDialogState();
}

class _BranchDialogState extends State<BranchDialog> {
  final _nameController = TextEditingController();
  final _operationSourceController = TextEditingController();
  final _operationTargetController = TextEditingController();
  List<GitBranch>? _branches;
  GitRemoteBranchSnapshot? _remoteSnapshot;
  GitBranchOperationPreview? _operationPreview;
  GitBranchOperationResult? _operationResult;
  GitCancellationToken? _operationCancellation;
  var _operation = GitBranchOperation.merge;
  var _forceDelete = false;
  var _isOperationLoading = false;
  var _advancedVisible = false;
  GitError? _error;
  var _isLoading = true;
  var _isMutating = false;

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _operationSourceController.dispose();
    _operationTargetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 480;
    final width = (size.width - 80).clamp(0.0, 380.0);
    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 16 : 40,
        vertical: 24,
      ),
      title: const Text('Branches'),
      actionsOverflowButtonSpacing: 4,
      content: SizedBox(
        width: width,
        height: (size.height - 180).clamp(220.0, 420.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final nameField = TextField(
                  key: const Key('new-branch-name'),
                  controller: _nameController,
                  enabled: !_isMutating,
                  decoration: const InputDecoration(
                    labelText: 'New branch name',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _createBranch(),
                );
                final createButton = IconButton(
                  key: const Key('create-branch'),
                  tooltip: 'Create branch',
                  onPressed: _isMutating || _nameController.text.trim().isEmpty
                      ? null
                      : _createBranch,
                  icon: const Icon(Icons.add),
                );
                if (constraints.maxWidth < 320) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      nameField,
                      Align(
                        alignment: Alignment.centerRight,
                        child: createButton,
                      ),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: nameField),
                    const SizedBox(width: 8),
                    createButton,
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            if (_isLoading) const LinearProgressIndicator(),
            if (_error case final error?) ...[
              Text(error.userMessage, key: const Key('branch-error')),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _isMutating ? null : _loadBranches,
                child: const Text('Retry'),
              ),
            ],
            if (_advancedVisible)
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(top: 8),
                  child: _advancedOperations(),
                ),
              )
            else
              Expanded(child: _branchList(context)),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('advanced-branch-operations'),
          onPressed: _isMutating
              ? null
              : () => setState(() => _advancedVisible = !_advancedVisible),
          child: Text(_advancedVisible ? 'Branches' : 'Advanced'),
        ),
        TextButton(
          onPressed: _isMutating ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _branchList(BuildContext context) {
    final branches = _branches;
    if (_isLoading && branches == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final remoteBranches = _remoteSnapshot?.branches
        .where((branch) => !branch.isSymbolicHead)
        .toList(growable: false);
    if (branches == null) return const SizedBox.shrink();
    if (branches.isEmpty && remoteBranches?.isNotEmpty != true) {
      return const Center(child: Text('No local branches yet.'));
    }
    return SingleChildScrollView(
      child: Column(
        children: [
          for (final branch in branches)
            ListTile(
              key: ValueKey('branch:${branch.name}'),
              leading: Icon(
                branch.isCurrent
                    ? Icons.radio_button_checked
                    : Icons.call_split,
              ),
              title: Text(branch.name),
              subtitle: Text(
                branch.isCurrent
                    ? 'Current branch'
                    : branch.hasUpstream
                    ? 'Tracks ${branch.upstream}'
                    : 'Local branch',
              ),
              trailing: branch.isCurrent
                  ? const Text('HEAD')
                  : PopupMenuButton<String>(
                      key: ValueKey('branch-actions:${branch.name}'),
                      tooltip: 'Branch actions',
                      onSelected: (action) =>
                          _prepareQuickOperation(action, branch.name),
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'rename', child: Text('Rename')),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
              onTap: branch.isCurrent || _isMutating
                  ? null
                  : () => _switchBranch(branch.name),
            ),
          if (remoteBranches?.isNotEmpty == true) ...[
            const Divider(),
            const ListTile(
              dense: true,
              leading: Icon(Icons.cloud_outlined),
              title: Text('Remote branches'),
            ),
            for (final branch in remoteBranches!)
              ListTile(
                key: ValueKey('remote-branch:${branch.name}'),
                leading: const Icon(Icons.cloud_queue_outlined),
                title: Text(branch.name),
                subtitle: Text(
                  branch.localTrackingBranch == null
                      ? 'Remote-tracking branch'
                      : 'Tracked by ${branch.localTrackingBranch}',
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: PopupMenuButton<String>(
                  key: ValueKey('remote-actions:${branch.name}'),
                  tooltip: 'Remote branch actions',
                  onSelected: (action) {
                    if (action == 'checkout') {
                      unawaited(_checkoutRemoteBranch(branch));
                    } else if (action == 'compare') {
                      unawaited(_compareRemoteBranch(branch));
                    } else {
                      unawaited(_deleteRemoteBranch(branch));
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'checkout',
                      child: Text('Checkout as local branch'),
                    ),
                    PopupMenuItem(
                      value: 'compare',
                      child: Text('Compare with current'),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete remote branch'),
                    ),
                  ],
                ),
                onTap: _isMutating ? null : () => _checkoutRemoteBranch(branch),
              ),
          ],
        ],
      ),
    );
  }

  Widget _advancedOperations() {
    final preview = _operationPreview;
    final result = _operationResult;
    final compact = MediaQuery.sizeOf(context).width < 360;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<GitBranchOperation>(
          key: const Key('advanced-branch-operation'),
          initialValue: _operation,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Operation',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final operation in GitBranchOperation.values)
              DropdownMenuItem(
                value: operation,
                child: pixelDropdownText(_operationLabel(operation)),
              ),
          ],
          onChanged: _isMutating
              ? null
              : (value) {
                  if (value == null) return;
                  setState(() {
                    _operation = value;
                    _operationPreview = null;
                    _operationResult = null;
                  });
                },
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('advanced-branch-source'),
          controller: _operationSourceController,
          enabled: !_isMutating,
          decoration: InputDecoration(
            labelText: _operation == GitBranchOperation.cherryPick
                ? 'Source commit or ref'
                : 'Source branch',
            border: const OutlineInputBorder(),
          ),
        ),
        if (_operation != GitBranchOperation.delete) ...[
          const SizedBox(height: 8),
          TextField(
            key: const Key('advanced-branch-target'),
            controller: _operationTargetController,
            enabled: !_isMutating,
            decoration: InputDecoration(
              labelText: _operation == GitBranchOperation.rebase
                  ? 'New base branch'
                  : 'Target branch (defaults to current)',
              border: const OutlineInputBorder(),
            ),
          ),
        ],
        if (_operation == GitBranchOperation.delete)
          CheckboxListTile(
            key: const Key('force-delete-branch'),
            dense: compact,
            contentPadding: EdgeInsets.zero,
            value: _forceDelete,
            onChanged: _isMutating
                ? null
                : (value) => setState(() => _forceDelete = value ?? false),
            title: const Text('Force delete unmerged branch'),
          ),
        const SizedBox(height: 4),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 4,
          children: [
            OutlinedButton(
              key: const Key('preview-branch-operation'),
              onPressed: _isMutating ? null : _previewOperation,
              child: const Text('Preview'),
            ),
            if (preview?.canExecute == true)
              FilledButton(
                key: const Key('execute-branch-operation'),
                onPressed: _isMutating ? null : _executeOperation,
                child: const Text('Confirm'),
              ),
            if (_isOperationLoading)
              TextButton(
                key: const Key('cancel-branch-operation'),
                onPressed: _cancelOperation,
                child: const Text('Cancel'),
              ),
          ],
        ),
        if (preview != null) ...[
          const SizedBox(height: 8),
          Text(
            _previewSummary(preview),
            key: const Key('branch-operation-preview'),
          ),
        ],
        if (result != null) ...[
          const SizedBox(height: 8),
          Text(result.summary, key: const Key('branch-operation-result')),
          if (result.recoveryActions.isNotEmpty)
            Wrap(
              spacing: 8,
              children: [
                for (final phase in result.recoveryActions)
                  OutlinedButton(
                    key: ValueKey('branch-recovery:${phase.name}'),
                    onPressed: _isMutating ? null : () => _runRecovery(phase),
                    child: Text(_phaseLabel(phase)),
                  ),
              ],
            ),
        ],
      ],
    );
  }

  void _prepareQuickOperation(String action, String branch) {
    setState(() {
      _operation = action == 'rename'
          ? GitBranchOperation.rename
          : GitBranchOperation.delete;
      _operationSourceController.text = branch;
      _operationTargetController.clear();
      _forceDelete = false;
      _operationPreview = null;
      _operationResult = null;
      _advancedVisible = true;
    });
  }

  Future<void> _previewOperation() async {
    if (_isMutating) return;
    final source = _operationSourceController.text.trim();
    final target = _operationTargetController.text.trim();
    setState(() {
      _isMutating = true;
      _isOperationLoading = true;
      _operationPreview = null;
      _operationResult = null;
      _error = null;
    });
    try {
      final preview = await widget.gateway.previewBranchOperation(
        widget.repository.repositoryId,
        GitBranchOperationRequest(
          operation: _operation,
          source: source.isEmpty ? null : source,
          target: target.isEmpty ? null : target,
          force: _forceDelete,
        ),
      );
      if (!mounted) return;
      setState(() => _operationPreview = preview);
    } on GitError catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) {
        setState(() {
          _isMutating = false;
          _isOperationLoading = false;
        });
      }
    }
  }

  Future<void> _executeOperation() async {
    final preview = _operationPreview;
    if (_isMutating || preview == null || !preview.canExecute) return;
    await _runAdvancedAction(
      GitBranchOperationRequest(
        operation: preview.request.operation,
        source: preview.request.source,
        target: preview.request.target,
        force: preview.request.force,
        confirmationToken: preview.token,
      ),
    );
  }

  Future<void> _runRecovery(GitBranchOperationPhase phase) async {
    if (_isMutating) return;
    await _runAdvancedAction(
      GitBranchOperationRequest(
        operation: _operationResult?.request.operation ?? _operation,
        source: _operationSourceController.text.trim(),
        target: _operationTargetController.text.trim(),
        phase: phase,
      ),
    );
  }

  Future<void> _runAdvancedAction(GitBranchOperationRequest request) async {
    setState(() {
      _isMutating = true;
      _isOperationLoading = true;
      _error = null;
    });
    final cancellation = GitCancellationToken();
    _operationCancellation = cancellation;
    try {
      final result = await widget.gateway.executeBranchOperation(
        widget.repository.repositoryId,
        request,
        cancellationToken: cancellation,
      );
      if (!mounted) return;
      setState(() {
        _operationResult = result;
        if (result.state == GitBranchOperationState.completed ||
            result.state == GitBranchOperationState.aborted) {
          _operationPreview = null;
        }
      });
      await _loadBranches();
    } on GitError catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      _operationCancellation = null;
      if (mounted) {
        setState(() {
          _isMutating = false;
          _isOperationLoading = false;
        });
      }
    }
  }

  void _cancelOperation() {
    _operationCancellation?.cancel();
  }

  String _previewSummary(GitBranchOperationPreview preview) {
    final source = preview.request.source ?? '(current branch)';
    final target =
        preview.request.target ?? preview.currentBranch ?? '(detached)';
    final state =
        preview.blockingMessage ??
        'Ready; confirmation expires ${preview.expiresAt?.toLocal()}.';
    return '${_operationLabel(preview.request.operation)}: $source → $target\n'
        'Expected commits: ${preview.expectedCommits}; '
        'ahead ${preview.ahead}, behind ${preview.behind}; '
        'merge-base ${preview.mergeBase ?? 'none'}.\n$state';
  }

  String _operationLabel(GitBranchOperation operation) => switch (operation) {
    GitBranchOperation.rename => 'Rename',
    GitBranchOperation.delete => 'Delete',
    GitBranchOperation.merge => 'Merge',
    GitBranchOperation.rebase => 'Rebase',
    GitBranchOperation.cherryPick => 'Cherry-pick',
  };

  String _phaseLabel(GitBranchOperationPhase phase) => switch (phase) {
    GitBranchOperationPhase.continueOperation => 'Continue',
    GitBranchOperationPhase.skip => 'Skip',
    GitBranchOperationPhase.abort => 'Abort',
    GitBranchOperationPhase.start => 'Start',
  };

  Future<void> _loadBranches() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final branches = await widget.gateway.getBranches(
        widget.repository.repositoryId,
      );
      if (!mounted) return;
      setState(() {
        _branches = branches;
        _isLoading = false;
      });
      unawaited(_loadRemoteBranches());
    } on GitError catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadRemoteBranches() async {
    try {
      final snapshot = await widget.gateway.getRemoteBranchSnapshot(
        widget.repository.repositoryId,
      );
      if (!mounted) return;
      setState(() => _remoteSnapshot = snapshot);
    } on Object {
      // Older/focused test gateways and repositories without remote refs keep
      // the local branch browser usable when the optional remote read fails.
    }
  }

  Future<void> _createBranch() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _isMutating) return;
    await _runAction(
      () => widget.gateway.createBranch(widget.repository.repositoryId, name),
    );
  }

  Future<void> _switchBranch(String name) async {
    if (_isMutating) return;
    await _runAction(
      () => widget.gateway.switchBranch(widget.repository.repositoryId, name),
    );
  }

  Future<void> _checkoutRemoteBranch(GitRemoteBranch branch) async {
    if (_isMutating) return;
    await _runAction(
      () => widget.gateway.checkoutRemoteBranch(
        widget.repository.repositoryId,
        branch,
      ),
    );
  }

  Future<void> _compareRemoteBranch(GitRemoteBranch branch) async {
    await showDialog<void>(
      context: context,
      builder: (_) => ComparisonDialog(
        gateway: widget.gateway,
        repository: widget.repository,
        initialLeft: branch.name,
        initialRight: _remoteSnapshot?.currentBranch ?? 'HEAD',
      ),
    );
  }

  Future<void> _deleteRemoteBranch(GitRemoteBranch branch) async {
    if (_isMutating) return;
    setState(() {
      _isMutating = true;
      _error = null;
    });
    try {
      final preview = await widget.gateway.previewRemoteBranchDelete(
        widget.repository.repositoryId,
        branch,
      );
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Delete remote branch?'),
          content: Text(
            'Delete ${branch.name} from ${branch.remote}? '
            'This cannot be undone from Git.',
          ),
          actions: [
            TextButton(
              key: const Key('cancel-delete-remote-branch'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('confirm-delete-remote-branch'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
      final result = await widget.gateway.deleteRemoteBranch(
        widget.repository.repositoryId,
        preview,
      );
      if (mounted) Navigator.of(context).pop(result);
    } on GitError catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _isMutating = false);
    }
  }

  Future<void> _runAction(
    Future<GitBranchActionResult> Function() action,
  ) async {
    setState(() {
      _isMutating = true;
      _error = null;
    });
    try {
      final result = await action();
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } on GitError catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _isMutating = false);
    }
  }
}
