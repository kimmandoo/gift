import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/error.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:gift/src/backend/submodule.dart';

/// Shows superproject gitlinks without pretending that a child repository is
/// part of the parent's status. Every action carries an explicit module scope
/// and refreshes both the child map and parent status after Git returns.
class SubmoduleDialog extends StatefulWidget {
  const SubmoduleDialog({
    super.key,
    required this.gateway,
    required this.repository,
    this.onOpenRepository,
  });

  final GitGateway gateway;
  final RepositoryOpened repository;
  final Future<void> Function(RepositoryOpened repository)? onOpenRepository;

  @override
  State<SubmoduleDialog> createState() => _SubmoduleDialogState();
}

class _SubmoduleDialogState extends State<SubmoduleDialog> {
  GitSubmoduleSnapshot? _snapshot;
  GitNestedRootSnapshot? _nestedRoots;
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
          const Expanded(child: Text('Submodules & nested roots')),
          if (_isBusy)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
      content: SizedBox(
        width: (size.width - (compact ? 24 : 64)).clamp(280.0, 760.0),
        height: (size.height - 150).clamp(300.0, 600.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error case final error?) _errorBanner(error),
            if (_message case final message?)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  message,
                  key: const Key('submodule-message'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            _actionBar(context),
            const SizedBox(height: 10),
            Expanded(child: _content(context)),
          ],
        ),
      ),
      actionsOverflowButtonSpacing: 4,
      actions: [
        TextButton(
          key: const Key('refresh-submodules'),
          onPressed: _isBusy ? null : _load,
          child: const Text('Refresh'),
        ),
        TextButton(
          key: const Key('close-submodule-dialog'),
          onPressed: _isBusy ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _errorBanner(GitError error) {
    return Container(
      key: const Key('submodule-error'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      color: Theme.of(context).colorScheme.errorContainer,
      child: Text(error.userMessage),
    );
  }

  Widget _actionBar(BuildContext context) {
    final enabled = !_isBusy && (_snapshot?.modules.isNotEmpty ?? false);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Scope', style: Theme.of(context).textTheme.labelLarge),
            OutlinedButton.icon(
              key: const Key('update-all-submodules'),
              onPressed: enabled
                  ? () => _runAction(
                      const GitSubmoduleActionRequest(
                        action: GitSubmoduleAction.update,
                        recursive: true,
                      ),
                    )
                  : null,
              icon: const Icon(Icons.sync, size: 18),
              label: const Text('Update all recursively'),
            ),
            OutlinedButton(
              key: const Key('sync-all-submodules'),
              onPressed: enabled
                  ? () => _runAction(
                      const GitSubmoduleActionRequest(
                        action: GitSubmoduleAction.sync,
                        recursive: true,
                      ),
                    )
                  : null,
              child: const Text('Sync all'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    if (_isLoading && _snapshot == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final modules = _snapshot?.modules ?? const <GitSubmodule>[];
    final roots = _nestedRoots?.roots ?? const <GitNestedRoot>[];
    if (modules.isEmpty && roots.length <= 1) {
      return const Center(child: Text('No submodules or nested roots found.'));
    }
    return ListView(
      key: const Key('submodule-list'),
      children: [
        if (roots.isNotEmpty) ...[
          Text('Nested roots', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          for (final root in roots) _rootTile(context, root),
          const SizedBox(height: 12),
        ],
        if (modules.isNotEmpty)
          Text('Submodules', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        for (final module in modules) _moduleCard(context, module),
      ],
    );
  }

  Widget _rootTile(BuildContext context, GitNestedRoot root) {
    final label = root.relativePath.isEmpty
        ? 'Superproject'
        : root.relativePath;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        root.kind == GitNestedRootKind.superproject
            ? Icons.account_tree_outlined
            : Icons.folder_special_outlined,
      ),
      title: Text(label, overflow: TextOverflow.ellipsis),
      subtitle: Text(root.path, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }

  Widget _moduleCard(BuildContext context, GitSubmodule module) {
    final colors = Theme.of(context).colorScheme;
    final states = module.states.map(_stateLabel).join(' · ');
    final absolutePath = _absolutePath(module.path);
    return Card(
      key: ValueKey('submodule:${module.path}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    module.path,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    states,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: TextStyle(color: colors.primary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(module.url, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (module.expectedOid != null || module.currentOid != null)
              Text(
                'Expected ${_shortOid(module.expectedOid)} · Current ${_shortOid(module.currentOid)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (module.dirtyPaths.isNotEmpty)
              Text(
                'Dirty: ${module.dirtyPaths.join(', ')}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.error),
              ),
            const SizedBox(height: 6),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 6,
              runSpacing: 4,
              children: [
                if (!module.isInitialized || module.isMissing)
                  OutlinedButton(
                    key: ValueKey('init-submodule:${module.path}'),
                    onPressed: _isBusy
                        ? null
                        : () => _runAction(
                            GitSubmoduleActionRequest(
                              action: GitSubmoduleAction.init,
                              paths: [module.path],
                            ),
                          ),
                    child: const Text('Initialize'),
                  ),
                if (module.isInitialized)
                  OutlinedButton(
                    key: ValueKey('update-submodule:${module.path}'),
                    onPressed: _isBusy
                        ? null
                        : () => _runAction(
                            GitSubmoduleActionRequest(
                              action: GitSubmoduleAction.update,
                              paths: [module.path],
                            ),
                          ),
                    child: const Text('Update'),
                  ),
                OutlinedButton(
                  key: ValueKey('sync-submodule:${module.path}'),
                  onPressed: _isBusy
                      ? null
                      : () => _runAction(
                          GitSubmoduleActionRequest(
                            action: GitSubmoduleAction.sync,
                            paths: [module.path],
                          ),
                        ),
                  child: const Text('Sync URL'),
                ),
                if (module.isInitialized)
                  TextButton(
                    key: ValueKey('deinit-submodule:${module.path}'),
                    onPressed: _isBusy ? null : () => _confirmDeinit(module),
                    child: const Text('Deinitialize'),
                  ),
                if (widget.onOpenRepository != null)
                  TextButton(
                    key: ValueKey('open-submodule:${module.path}'),
                    onPressed: _isBusy || !module.isInitialized
                        ? null
                        : () => _openModule(absolutePath),
                    child: const Text('Open root'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeinit(GitSubmodule module) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deinitialize submodule?'),
        content: Text(
          'Remove the checkout for ${module.path}? The parent gitlink remains.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-deinit-submodule'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Deinitialize'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _runAction(
        GitSubmoduleActionRequest(
          action: GitSubmoduleAction.deinit,
          paths: [module.path],
          force: true,
        ),
      );
    }
  }

  Future<void> _openModule(String path) async {
    await _run(() async {
      final opened = await widget.gateway.openRepository(path);
      if (widget.onOpenRepository != null) {
        await widget.onOpenRepository!(opened);
      }
    });
  }

  Future<void> _runAction(GitSubmoduleActionRequest request) async {
    await _run(() async {
      final result = await widget.gateway.executeSubmoduleAction(
        widget.repository.repositoryId,
        request,
      );
      if (!mounted) return;
      setState(() {
        _snapshot = result.snapshot;
        _message = result.summary;
      });
      await _loadNestedRoots();
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
      final snapshot = await widget.gateway.getSubmodules(
        widget.repository.repositoryId,
      );
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _isLoading = false;
      });
      await _loadNestedRoots();
    } on GitError catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadNestedRoots() async {
    final roots = await widget.gateway.getNestedRoots(
      widget.repository.repositoryId,
    );
    if (mounted) setState(() => _nestedRoots = roots);
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

  String _absolutePath(String relativePath) =>
      '${widget.repository.root}/${relativePath.replaceAll('/', '/')}';
}

String _shortOid(String? oid) => oid == null
    ? 'unknown'
    : oid.length <= 10
    ? oid
    : '${oid.substring(0, 8)}…';

String _stateLabel(GitSubmoduleState state) => switch (state) {
  GitSubmoduleState.initialized => 'Initialized',
  GitSubmoduleState.uninitialized => 'Uninitialized',
  GitSubmoduleState.dirty => 'Dirty',
  GitSubmoduleState.detached => 'Detached',
  GitSubmoduleState.changedCommit => 'Changed commit',
  GitSubmoduleState.conflicted => 'Conflict',
  GitSubmoduleState.missing => 'Missing',
};
