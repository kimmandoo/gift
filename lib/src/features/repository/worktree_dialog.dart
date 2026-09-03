import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/error.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:gift/src/backend/worktree.dart';

/// Lists and manages the linked worktrees belonging to one repository.
///
/// Mutating actions always ask the backend for a fresh preview. This keeps the
/// dialog useful even when another worktree or an external Git process changes
/// the repository while it is open.
class WorktreeDialog extends StatefulWidget {
  const WorktreeDialog({
    super.key,
    required this.gateway,
    required this.repository,
  });

  final GitGateway gateway;
  final RepositoryOpened repository;

  @override
  State<WorktreeDialog> createState() => _WorktreeDialogState();
}

class _WorktreeDialogState extends State<WorktreeDialog> {
  final _pathController = TextEditingController();
  final _branchController = TextEditingController();
  final _startPointController = TextEditingController();
  final _lockReasonController = TextEditingController();
  GitWorktreeSnapshot? _snapshot;
  GitError? _error;
  String? _message;
  var _isLoading = true;
  var _isBusy = false;
  var _createBranch = true;
  var _detach = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _pathController.dispose();
    _branchController.dispose();
    _startPointController.dispose();
    _lockReasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 560;
    final width = (size.width - (compact ? 24 : 64)).clamp(280.0, 820.0);
    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 32,
        vertical: 20,
      ),
      title: Row(
        children: [
          const Expanded(child: Text('Worktrees')),
          if (_isBusy)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
      content: SizedBox(
        width: width,
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
                  key: const Key('worktree-message'),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            _createPanel(context),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Expanded(child: _worktreeList(context)),
          ],
        ),
      ),
      actionsOverflowButtonSpacing: 4,
      actions: [
        TextButton(
          key: const Key('refresh-worktrees'),
          onPressed: _isBusy ? null : _load,
          child: const Text('Refresh'),
        ),
        TextButton(
          key: const Key('close-worktree-dialog'),
          onPressed: _isBusy ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _errorBanner(GitError error) {
    return Container(
      key: const Key('worktree-error'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      color: Theme.of(context).colorScheme.errorContainer,
      child: Text(error.userMessage),
    );
  }

  Widget _createPanel(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        key: const Key('add-worktree-expansion'),
        initiallyExpanded: false,
        tilePadding: const EdgeInsets.symmetric(horizontal: 10),
        childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        title: Text(
          'Add worktree',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        children: [
          TextField(
            key: const Key('worktree-path'),
            controller: _pathController,
            enabled: !_isBusy,
            decoration: const InputDecoration(
              labelText: 'Destination path',
              hintText: 'Absolute path or folder below this repository',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (_) => _createWorktree(),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('worktree-branch'),
            controller: _branchController,
            enabled: !_isBusy && !_detach,
            decoration: InputDecoration(
              labelText: _createBranch ? 'New branch name' : 'Existing branch',
              hintText: _detach ? 'Detached worktree' : 'feature/my-task',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (_) => _createWorktree(),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('worktree-start-point'),
            controller: _startPointController,
            enabled: !_isBusy,
            decoration: const InputDecoration(
              labelText: 'Start point (optional)',
              hintText: 'HEAD, branch, or commit',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (_) => _createWorktree(),
          ),
          CheckboxListTile(
            key: const Key('worktree-create-branch'),
            value: _createBranch,
            onChanged: _isBusy || _detach
                ? null
                : (value) => setState(() => _createBranch = value ?? false),
            contentPadding: EdgeInsets.zero,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Create a new branch'),
          ),
          CheckboxListTile(
            key: const Key('worktree-detached'),
            value: _detach,
            onChanged: _isBusy
                ? null
                : (value) => setState(() {
                    _detach = value ?? false;
                    if (_detach) _createBranch = false;
                  }),
            contentPadding: EdgeInsets.zero,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Detached HEAD'),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              key: const Key('create-worktree'),
              onPressed: _isBusy ? null : _createWorktree,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add worktree'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _worktreeList(BuildContext context) {
    if (_isLoading && _snapshot == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final worktrees = _snapshot?.worktrees ?? const <GitWorktree>[];
    if (worktrees.isEmpty) {
      return const Center(child: Text('No worktrees found.'));
    }
    return ListView(
      key: const Key('worktree-list'),
      children: [
        Text(
          '${worktrees.length} ${worktrees.length == 1 ? 'worktree' : 'worktrees'}',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 6),
        for (final worktree in worktrees) _worktreeCard(context, worktree),
      ],
    );
  }

  Widget _worktreeCard(BuildContext context, GitWorktree worktree) {
    final colors = Theme.of(context).colorScheme;
    final title =
        worktree.branch ??
        (worktree.isPrunable ? 'Missing worktree' : 'Detached HEAD');
    final stateLabels = <String>[
      if (worktree.isMain) 'Main',
      if (worktree.isCurrent) 'Current',
      if (worktree.isLocked) 'Locked',
      if (worktree.isPrunable) 'Prunable',
      if (worktree.isDirty) 'Dirty (${worktree.dirtyPaths.length})',
    ];
    return Card(
      key: ValueKey('worktree:${worktree.path}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  worktree.isPrunable
                      ? Icons.link_off
                      : worktree.isCurrent
                      ? Icons.radio_button_checked
                      : Icons.account_tree_outlined,
                  size: 18,
                  color: worktree.isPrunable ? colors.error : colors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      SelectableText(
                        worktree.path,
                        maxLines: 2,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (worktree.head case final head?)
                        Text(
                          'HEAD ${_shortOid(head)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (stateLabels.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final label in stateLabels)
                    Chip(
                      label: Text(label),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                    ),
                ],
              ),
            ],
            if (worktree.lockReason case final reason? when reason.isNotEmpty)
              Text(
                'Lock reason: $reason',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (worktree.pruneReason case final reason? when reason.isNotEmpty)
              Text(
                'Prune reason: $reason',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              alignment: WrapAlignment.end,
              children: [
                if (!worktree.isPrunable && !worktree.isCurrent)
                  OutlinedButton.icon(
                    key: ValueKey('open-worktree:${worktree.path}'),
                    onPressed: _isBusy ? null : () => _openWorktree(worktree),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('Open'),
                  ),
                if (worktree.isPrunable)
                  OutlinedButton.icon(
                    key: ValueKey('prune-worktree:${worktree.path}'),
                    onPressed: _isBusy
                        ? null
                        : () => _runAction(worktree, GitWorktreeAction.prune),
                    icon: const Icon(
                      Icons.cleaning_services_outlined,
                      size: 16,
                    ),
                    label: const Text('Prune'),
                  )
                else ...[
                  if (worktree.isLocked)
                    OutlinedButton.icon(
                      key: ValueKey('unlock-worktree:${worktree.path}'),
                      onPressed: _isBusy
                          ? null
                          : () =>
                                _runAction(worktree, GitWorktreeAction.unlock),
                      icon: const Icon(Icons.lock_open_outlined, size: 16),
                      label: const Text('Unlock'),
                    )
                  else
                    OutlinedButton.icon(
                      key: ValueKey('lock-worktree:${worktree.path}'),
                      onPressed: _isBusy
                          ? null
                          : () => _runAction(worktree, GitWorktreeAction.lock),
                      icon: const Icon(Icons.lock_outline, size: 16),
                      label: const Text('Lock'),
                    ),
                  if (!worktree.isMain && !worktree.isCurrent)
                    OutlinedButton.icon(
                      key: ValueKey('remove-worktree:${worktree.path}'),
                      onPressed: _isBusy
                          ? null
                          : () =>
                                _runAction(worktree, GitWorktreeAction.remove),
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: const Text('Remove'),
                    ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _load() async {
    if (_isBusy) return;
    setState(() {
      _isLoading = true;
      _error = null;
      _message = null;
    });
    try {
      final snapshot = await widget.gateway.getWorktrees(
        widget.repository.repositoryId,
      );
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
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

  Future<void> _createWorktree() async {
    final path = _pathController.text.trim();
    final branch = _branchController.text.trim();
    final startPoint = _startPointController.text.trim();
    if (path.isEmpty || (!_detach && branch.isEmpty)) {
      setState(
        () => _error = const GitError(
          category: GitErrorCategory.parseFailure,
          userMessage: 'Enter a destination and branch name.',
          diagnostic: 'worktree form was incomplete',
          retryable: false,
        ),
      );
      return;
    }
    await _busy(() async {
      final result = await widget.gateway.createWorktree(
        widget.repository.repositoryId,
        GitWorktreeCreateRequest(
          path: path,
          branch: _detach ? null : branch,
          startPoint: startPoint.isEmpty ? null : startPoint,
          createBranch: _detach ? false : _createBranch,
          detach: _detach,
        ),
      );
      if (!mounted) return;
      setState(() {
        _snapshot = result.snapshot;
        _message = result.summary;
        _pathController.clear();
        _startPointController.clear();
      });
    });
  }

  Future<void> _openWorktree(GitWorktree worktree) async {
    await _busy(() async {
      final opened = await widget.gateway.openWorktree(
        widget.repository.repositoryId,
        worktree,
      );
      if (!mounted) return;
      Navigator.of(context).pop(opened);
    });
  }

  Future<void> _runAction(
    GitWorktree worktree,
    GitWorktreeAction action, {
    bool confirmDirty = false,
  }) async {
    if (action == GitWorktreeAction.lock &&
        _lockReasonController.text.trim().isEmpty) {
      final reason = await _askLockReason();
      if (!mounted || reason == null) return;
      _lockReasonController.text = reason;
    }
    if (_isBusy) return;
    setState(() {
      _isBusy = true;
      _error = null;
      _message = null;
    });
    try {
      final request = GitWorktreeActionRequest(
        action: action,
        path: worktree.path,
        confirmDirty: confirmDirty,
        lockReason: action == GitWorktreeAction.lock
            ? _lockReasonController.text.trim()
            : null,
      );
      final preview = await widget.gateway.previewWorktreeAction(
        widget.repository.repositoryId,
        request,
      );
      if (!preview.canExecute) {
        if (action == GitWorktreeAction.remove &&
            preview.requiresConfirmation &&
            !confirmDirty) {
          final confirmed = await _confirmDirtyRemoval(preview);
          if (confirmed == true && mounted) {
            final confirmedRequest = GitWorktreeActionRequest(
              action: action,
              path: worktree.path,
              confirmDirty: true,
            );
            final confirmedPreview = await widget.gateway.previewWorktreeAction(
              widget.repository.repositoryId,
              confirmedRequest,
            );
            if (!confirmedPreview.canExecute) {
              throw GitError(
                category: GitErrorCategory.worktreeOperationNotAllowed,
                userMessage:
                    confirmedPreview.blockingMessage ??
                    'Review this worktree action again.',
                diagnostic: 'dirty worktree confirmation became stale',
                retryable: false,
              );
            }
            final result = await widget.gateway.executeWorktreeAction(
              widget.repository.repositoryId,
              confirmedPreview.request,
            );
            if (!mounted) return;
            setState(() {
              _snapshot = result.snapshot;
              _message = result.summary;
            });
          }
          return;
        }
        throw GitError(
          category: GitErrorCategory.worktreeOperationNotAllowed,
          userMessage:
              preview.blockingMessage ?? 'Review this worktree action again.',
          diagnostic: 'worktree action was blocked by its fresh preview',
          retryable: false,
        );
      }
      final result = await widget.gateway.executeWorktreeAction(
        widget.repository.repositoryId,
        preview.request,
      );
      if (!mounted) return;
      setState(() {
        _snapshot = result.snapshot;
        _message = result.summary;
        if (action == GitWorktreeAction.lock) {
          _lockReasonController.clear();
        }
      });
    } on GitError catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<String?> _askLockReason() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Lock worktree'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Reason (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Lock'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  Future<bool?> _confirmDirtyRemoval(GitWorktreeActionPreview preview) {
    final paths = preview.dirtyPaths;
    final pathText = paths.isEmpty
        ? 'Git reported local changes.'
        : paths.take(5).join(', ') + (paths.length > 5 ? '…' : '');
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove dirty worktree?'),
        content: Text(
          'This permanently removes the worktree and its local changes. '
          'Affected paths: $pathText',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-remove-dirty-worktree'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  Future<void> _busy(Future<void> Function() operation) async {
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

String _shortOid(String oid) => oid.length <= 8 ? oid : oid.substring(0, 8);
