import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gift/src/app/error_dialog.dart';
import 'package:gift/src/app/pixel_theme.dart';

import 'package:gift/src/backend/credentials.dart';
import 'package:gift/src/backend/branch.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/error.dart';
import 'package:gift/src/backend/executor.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:gift/src/backend/remote_branch.dart';
import 'package:gift/src/backend/push.dart';
import 'package:gift/src/features/repository/comparison_dialog.dart';
import 'package:gift/src/features/repository/context_actions.dart';
import 'package:gift/src/features/repository/history_screen.dart';
import 'package:gift/src/features/repository/hosting_dialog.dart';
import 'package:flutter/services.dart';
import 'package:gift/src/features/repository/object_dialog.dart';
import 'package:gift/src/features/repository/push_dialog.dart';
import 'package:gift/src/app/repository_credential_store.dart';

/// A small branch popup that keeps branch work separate from the Changes list.
class BranchDialog extends StatefulWidget {
  const BranchDialog({
    super.key,
    required this.gateway,
    required this.repository,
    this.preferredBranch,
    this.preferredRemote,
    this.credentialStore,
    this.repositoryCredentialStore,
    this.initialOperation,
    this.initialOperationSource,
    this.initialOperationTarget,
    this.initialCreateCommitOid,
  });

  final GitGateway gateway;
  final RepositoryOpened repository;
  final String? preferredBranch;
  final String? preferredRemote;
  final GitCredentialStore? credentialStore;
  final RepositoryCredentialStore? repositoryCredentialStore;
  final GitBranchOperation? initialOperation;
  final String? initialOperationSource;
  final String? initialOperationTarget;
  final String? initialCreateCommitOid;

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
  String? _fetchStatus;
  var _isLoading = true;
  var _isMutating = false;
  var _remoteLoadGeneration = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialOperation case final operation?) {
      _operation = operation;
      _advancedVisible = true;
    }
    _operationSourceController.text = widget.initialOperationSource ?? '';
    _operationTargetController.text = widget.initialOperationTarget ?? '';
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
    final veryCompact = size.width < 360;
    final width = (size.width - 80).clamp(0.0, 380.0);
    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 16 : 40,
        vertical: 24,
      ),
      title: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('Branches'),
          if (veryCompact)
            Tooltip(
              message: 'Fetch remote branches',
              child: Semantics(
                button: true,
                label: 'Fetch remote branches',
                child: InkWell(
                  key: const Key('fetch-remote-branches'),
                  onTap: _isMutating ? null : _fetchRemoteBranches,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.cloud_download_outlined, size: 20),
                  ),
                ),
              ),
            )
          else
            OutlinedButton.icon(
              key: const Key('fetch-remote-branches'),
              onPressed: _isMutating ? null : _fetchRemoteBranches,
              icon: const Icon(Icons.cloud_download_outlined),
              label: const Text('Fetch remotes'),
            ),
        ],
      ),
      actionsOverflowButtonSpacing: 8,
      content: SizedBox(
        width: width,
        height: (size.height - 180).clamp(220.0, 420.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('new-branch-name'),
              controller: _nameController,
              enabled: !_isMutating,
              decoration: InputDecoration(
                labelText: 'New branch name',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  key: const Key('create-branch'),
                  tooltip: 'Create branch',
                  onPressed: _isMutating || _nameController.text.trim().isEmpty
                      ? null
                      : _createBranch,
                  icon: const Icon(Icons.add),
                ),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _createBranch(),
            ),
            if (widget.initialCreateCommitOid case final commitOid?)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Starting commit: $commitOid',
                  key: const Key('branch-create-target'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const SizedBox(height: 12),
            if (_isLoading) const LinearProgressIndicator(),
            if (_isMutating)
              const LinearProgressIndicator(
                key: Key('branch-operation-progress'),
                value: 0.5,
              ),
            if (_error case final error?) ...[
              Text(error.userMessage, key: const Key('branch-error')),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _isMutating ? null : _loadBranches,
                child: const Text('Retry'),
              ),
            ],
            if (_fetchStatus case final status?)
              Text(
                status,
                key: const Key('remote-fetch-status'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
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
        if (_operationCancellation != null)
          TextButton(
            key: const Key('cancel-remote-fetch'),
            onPressed: _operationCancellation!.cancel,
            child: const Text('Cancel fetch'),
          ),
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
    final visibleBranches = branches ?? const <GitBranch>[];
    final orderedBranches = [...visibleBranches]
      ..sort((left, right) {
        final preferred = widget.preferredBranch;
        if (preferred == null) return 0;
        if (left.name == preferred) return -1;
        if (right.name == preferred) return 1;
        return 0;
      });
    final visibleRemoteBranches =
        _remoteSnapshot?.branches
            .where((branch) => !branch.isSymbolicHead)
            .toList(growable: false) ??
        const <GitRemoteBranch>[];
    if (orderedBranches.isEmpty && _remoteSnapshot == null) {
      return const Center(child: Text('No local branches yet.'));
    }
    return SingleChildScrollView(
      child: Column(
        children: [
          for (final branch in orderedBranches) _localBranchTile(branch),
          if (_remoteSnapshot != null) ...[
            const Divider(),
            const ListTile(
              dense: true,
              leading: Icon(Icons.cloud_outlined),
              title: Text('Remote branches'),
            ),
            if (visibleRemoteBranches.isEmpty)
              const ListTile(
                dense: true,
                title: Text(
                  'No remote branches cached. Fetch remote branches to update.',
                ),
              ),
            for (final branch in visibleRemoteBranches)
              _remoteBranchTile(branch),
          ],
        ],
      ),
    );
  }

  Widget _localBranchTile(GitBranch branch) {
    final snapshot = _branchActionSnapshot(branch);
    return ContextActionMenu(
      key: ValueKey('branch-action-menu:${branch.name}'),
      snapshot: snapshot,
      actions: _localBranchActions(branch, snapshot),
      onAction: _handleBranchAction,
      child: ListTile(
        key: ValueKey('branch:${branch.name}'),
        leading: Icon(
          branch.isCurrent ? Icons.radio_button_checked : Icons.call_split,
        ),
        title: Text(branch.name),
        subtitle: Text(
          branch.isCurrent
              ? branch.hasUpstream
                    ? 'Current · tracks ${branch.upstream}'
                    : 'Current · not linked to a remote'
              : branch.hasUpstream
              ? 'Tracks ${branch.upstream}'
              : 'Local branch',
        ),
        trailing: _branchActionButton(branch),
        onTap: branch.isCurrent || _isMutating
            ? null
            : () => _switchBranch(branch.name),
      ),
    );
  }

  Widget _branchActionButton(GitBranch branch) {
    final button = ContextActionMenuButton(
      key: ValueKey('branch-actions:${branch.name}'),
    );
    return branch.isCurrent
        ? KeyedSubtree(key: const Key('push-current-branch'), child: button)
        : button;
  }

  Widget _remoteBranchTile(GitRemoteBranch branch) {
    final snapshot = _remoteBranchActionSnapshot(branch);
    return ContextActionMenu(
      key: ValueKey('remote-action-menu:${branch.name}'),
      snapshot: snapshot,
      actions: _remoteBranchActions(branch, snapshot),
      onAction: _handleBranchAction,
      child: ListTile(
        key: ValueKey('remote-branch:${branch.name}'),
        leading: const Icon(Icons.cloud_queue_outlined),
        title: Text(branch.name),
        subtitle: Text(
          branch.localTrackingBranch == null
              ? 'Remote-tracking branch'
              : 'Tracked by ${branch.localTrackingBranch}',
          overflow: TextOverflow.ellipsis,
        ),
        trailing: ContextActionMenuButton(
          key: ValueKey('remote-actions:${branch.name}'),
        ),
        onTap: _isMutating ? null : () => _checkoutRemoteBranch(branch),
      ),
    );
  }

  ContextActionSnapshot _branchActionSnapshot(GitBranch branch) =>
      ContextActionSnapshot(
        repository: widget.repository,
        target: ContextActionTarget.branch(
          name: branch.name,
          label: branch.name,
        ),
        fingerprint: _branchSnapshotFingerprint(),
      );

  ContextActionSnapshot _remoteBranchActionSnapshot(
    GitRemoteBranch branch,
  ) => ContextActionSnapshot(
    repository: widget.repository,
    target: ContextActionTarget.remote(name: branch.name, label: branch.name),
    fingerprint:
        '${_remoteSnapshot?.fingerprint ?? ''}:${branch.remote}:'
        '${branch.branch}:${branch.oid}:${branch.localTrackingBranch ?? ''}:'
        '${branch.isSymbolicHead}:${_remoteSnapshot?.currentBranch ?? ''}',
  );

  String _branchSnapshotFingerprint() =>
      '${_branches?.map((branch) => '${branch.name}:${branch.oid ?? ''}:'
              '${branch.upstream ?? ''}:${branch.isCurrent}').join('|') ?? ''}:'
      '${_remoteSnapshot?.fingerprint ?? ''}:${_remoteSnapshot?.currentBranch ?? ''}';

  String? _currentBranchName() =>
      _branches?.where((branch) => branch.isCurrent).firstOrNull?.name ??
      _remoteSnapshot?.currentBranch;

  List<ContextActionDescriptor> _localBranchActions(
    GitBranch branch,
    ContextActionSnapshot snapshot,
  ) {
    final current = _currentBranchName();
    final busyReason = _isMutating
        ? 'A branch operation is already running.'
        : null;
    final isCurrent = branch.isCurrent || branch.name == current;
    ContextActionDescriptor action({
      required ContextActionId id,
      required String label,
      required IconData icon,
      required ContextActionGroup group,
      required ContextActionRoute route,
      bool enabled = true,
      String? disabledReason,
    }) => ContextActionDescriptor(
      id: id,
      label: label,
      icon: icon,
      group: group,
      route: route,
      snapshot: snapshot,
      enabled: enabled && busyReason == null,
      disabledReason: busyReason ?? disabledReason,
    );
    return [
      action(
        id: ContextActionId.checkoutBranch,
        label: 'Checkout',
        icon: Icons.login,
        group: ContextActionGroup.workflow,
        route: ContextActionRoute.checkoutBranch,
        enabled: !isCurrent,
        disabledReason: isCurrent ? 'This branch is already current.' : null,
      ),
      action(
        id: ContextActionId.mergeBranch,
        label: 'Merge into current',
        icon: Icons.merge,
        group: ContextActionGroup.workflow,
        route: ContextActionRoute.mergeBranch,
        enabled: !isCurrent && current != null,
        disabledReason: isCurrent
            ? 'A branch cannot merge into itself.'
            : current == null
            ? 'Detached HEAD has no current branch target.'
            : null,
      ),
      action(
        id: ContextActionId.rebaseBranch,
        label: 'Rebase current onto this branch',
        icon: Icons.call_merge,
        group: ContextActionGroup.workflow,
        route: ContextActionRoute.rebaseBranch,
        enabled: !isCurrent && current != null,
        disabledReason: isCurrent
            ? 'A branch cannot rebase onto itself.'
            : current == null
            ? 'Detached HEAD has no current branch target.'
            : null,
      ),
      action(
        id: ContextActionId.compareBranch,
        label: 'Compare with current',
        icon: Icons.compare_arrows,
        group: ContextActionGroup.inspect,
        route: ContextActionRoute.compareBranch,
        enabled: !isCurrent && current != null,
        disabledReason: isCurrent
            ? 'This branch is already current.'
            : current == null
            ? 'Detached HEAD has no current branch target.'
            : null,
      ),
      action(
        id: ContextActionId.renameBranch,
        label: 'Rename',
        icon: Icons.drive_file_rename_outline,
        group: ContextActionGroup.workflow,
        route: ContextActionRoute.renameBranch,
      ),
      action(
        id: ContextActionId.deleteBranch,
        label: 'Delete',
        icon: Icons.delete_outline,
        group: ContextActionGroup.destructive,
        route: ContextActionRoute.deleteBranch,
        enabled: !isCurrent,
        disabledReason: isCurrent
            ? 'The current branch cannot be deleted.'
            : null,
      ),
      action(
        id: ContextActionId.pushBranch,
        label: 'Push',
        icon: Icons.cloud_upload_outlined,
        group: ContextActionGroup.workflow,
        route: ContextActionRoute.pushBranch,
        enabled: current != null,
        disabledReason: current == null
            ? 'Detached HEAD has no branch to publish.'
            : null,
      ),
      action(
        id: ContextActionId.upstream,
        label: 'Set/change upstream',
        icon: Icons.link,
        group: ContextActionGroup.workflow,
        route: ContextActionRoute.upstream,
        enabled: current != null,
        disabledReason: current == null
            ? 'Detached HEAD has no upstream branch.'
            : null,
      ),
      action(
        id: ContextActionId.copyBranchName,
        label: 'Copy branch name',
        icon: Icons.content_copy,
        group: ContextActionGroup.inspect,
        route: ContextActionRoute.copyBranchName,
      ),
      action(
        id: ContextActionId.copyBranchRef,
        label: 'Copy full ref',
        icon: Icons.copy_all,
        group: ContextActionGroup.inspect,
        route: ContextActionRoute.copyBranchRef,
      ),
    ];
  }

  List<ContextActionDescriptor> _remoteBranchActions(
    GitRemoteBranch branch,
    ContextActionSnapshot snapshot,
  ) {
    final busyReason = _isMutating
        ? 'A branch operation is already running.'
        : null;
    final current = _currentBranchName();
    final symbolic = branch.isSymbolicHead;
    ContextActionDescriptor action({
      required ContextActionId id,
      required String label,
      required IconData icon,
      required ContextActionRoute route,
      bool enabled = true,
      String? disabledReason,
    }) => ContextActionDescriptor(
      id: id,
      label: label,
      icon: icon,
      group: route == ContextActionRoute.deleteRemote
          ? ContextActionGroup.destructive
          : ContextActionGroup.workflow,
      route: route,
      snapshot: snapshot,
      enabled: enabled && busyReason == null,
      disabledReason: busyReason ?? disabledReason,
    );
    return [
      action(
        id: ContextActionId.checkoutRemote,
        label: 'Checkout as local branch',
        icon: Icons.login,
        route: ContextActionRoute.checkoutRemote,
        enabled: !symbolic && branch.localTrackingBranch == null,
        disabledReason: symbolic
            ? 'Symbolic remote HEAD is not a branch.'
            : branch.localTrackingBranch != null
            ? 'A local branch already tracks this ref.'
            : null,
      ),
      action(
        id: ContextActionId.compareRemote,
        label: 'Compare with current',
        icon: Icons.compare_arrows,
        route: ContextActionRoute.compareRemote,
        enabled: !symbolic && current != null,
        disabledReason: symbolic
            ? 'Symbolic remote HEAD has no independent tip.'
            : current == null
            ? 'Detached HEAD has no current branch target.'
            : null,
      ),
      action(
        id: ContextActionId.cherryPickRemote,
        label: 'Cherry-pick selected commit',
        icon: Icons.call_split,
        route: ContextActionRoute.cherryPickRemote,
        enabled: !symbolic,
        disabledReason: symbolic
            ? 'Symbolic remote HEAD has no commit row.'
            : null,
      ),
      action(
        id: ContextActionId.deleteRemote,
        label: 'Delete remote branch',
        icon: Icons.delete_outline,
        route: ContextActionRoute.deleteRemote,
        enabled: !symbolic,
        disabledReason: symbolic
            ? 'Symbolic remote HEAD cannot be deleted.'
            : null,
      ),
      action(
        id: ContextActionId.copyBranchName,
        label: 'Copy name',
        icon: Icons.content_copy,
        route: ContextActionRoute.copyBranchName,
      ),
      action(
        id: ContextActionId.copyBranchRef,
        label: 'Copy ref',
        icon: Icons.copy_all,
        route: ContextActionRoute.copyBranchRef,
      ),
      action(
        id: ContextActionId.hostLink,
        label: 'Open host link',
        icon: Icons.open_in_browser,
        route: ContextActionRoute.hostLink,
      ),
    ];
  }

  Future<void> _handleBranchAction(ContextActionDescriptor action) async {
    if (action.snapshot.repository != widget.repository) return;
    if (action.snapshot.target.kind == ContextActionTargetKind.branch) {
      final branch = _branches
          ?.where((value) => value.name == action.snapshot.target.identity)
          .firstOrNull;
      if (branch == null || _branchActionSnapshot(branch) != action.snapshot) {
        return;
      }
      switch (action.route) {
        case ContextActionRoute.checkoutBranch:
          await _switchBranch(branch.name);
        case ContextActionRoute.mergeBranch:
          _prepareQuickOperation('merge', branch.name);
        case ContextActionRoute.rebaseBranch:
          _prepareQuickOperation('rebase', branch.name);
        case ContextActionRoute.compareBranch:
          await _compareLocalBranch(branch);
        case ContextActionRoute.renameBranch:
          _prepareQuickOperation('rename', branch.name);
        case ContextActionRoute.deleteBranch:
          _prepareQuickOperation('delete', branch.name);
        case ContextActionRoute.pushBranch:
          await _openBranchPush(branch);
        case ContextActionRoute.upstream:
          await _openBranchUpstream(branch);
        case ContextActionRoute.copyBranchName:
          await _copyBranchValue(branch.name, fullRef: false, remote: false);
        case ContextActionRoute.copyBranchRef:
          await _copyBranchValue(branch.name, fullRef: true, remote: false);
        default:
          return;
      }
      return;
    }
    if (action.snapshot.target.kind != ContextActionTargetKind.remote) return;
    final branch = _remoteSnapshot?.branches
        .where((value) => value.name == action.snapshot.target.identity)
        .firstOrNull;
    if (branch == null ||
        _remoteBranchActionSnapshot(branch) != action.snapshot) {
      return;
    }
    switch (action.route) {
      case ContextActionRoute.checkoutRemote:
        await _checkoutRemoteBranch(branch);
      case ContextActionRoute.compareRemote:
        await _compareRemoteBranch(branch);
      case ContextActionRoute.cherryPickRemote:
        await _openRemoteHistory(branch);
      case ContextActionRoute.deleteRemote:
        await _deleteRemoteBranch(branch);
      case ContextActionRoute.copyBranchName:
        await _copyBranchValue(branch.name, fullRef: false, remote: true);
      case ContextActionRoute.copyBranchRef:
        await _copyBranchValue(branch.name, fullRef: true, remote: true);
      case ContextActionRoute.hostLink:
        await _openRemoteHost(branch);
      default:
        return;
    }
  }

  Future<void> _compareLocalBranch(GitBranch branch) async {
    final current = _currentBranchName();
    if (current == null || current == branch.name) return;
    await showDialog<void>(
      context: context,
      builder: (_) => ComparisonDialog(
        gateway: widget.gateway,
        repository: widget.repository,
        initialLeft: branch.name,
        initialRight: current,
      ),
    );
  }

  Future<void> _openBranchPush(GitBranch branch) async {
    await showDialog<GitPushResult>(
      context: context,
      builder: (_) => PushDialog(
        gateway: widget.gateway,
        repository: widget.repository,
        initialBranch: branch.name,
        preferredRemote: widget.preferredRemote,
        credentialStore: widget.credentialStore,
        repositoryCredentialStore: widget.repositoryCredentialStore,
      ),
    );
    if (mounted) await _loadBranches();
  }

  Future<void> _openBranchUpstream(GitBranch branch) async {
    await showDialog<void>(
      context: context,
      builder: (_) => ObjectDialog(
        gateway: widget.gateway,
        repository: widget.repository,
        initialTabIndex: 3,
        initialBranch: branch.name,
      ),
    );
    if (mounted) await _loadBranches();
  }

  Future<void> _copyBranchValue(
    String name, {
    required bool fullRef,
    required bool remote,
  }) async {
    final value = fullRef
        ? name.startsWith('refs/')
              ? name
              : '${remote ? 'refs/remotes' : 'refs/heads'}/$name'
        : name;
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) {
      _showActionMessage(fullRef ? 'Full ref copied.' : 'Branch name copied.');
    }
  }

  Future<void> _openRemoteHistory(GitRemoteBranch branch) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HistoryScreen(
          gateway: widget.gateway,
          repository: widget.repository,
          initialRef: branch.name,
        ),
      ),
    );
  }

  Future<void> _openRemoteHost(GitRemoteBranch branch) async {
    await showDialog<void>(
      context: context,
      builder: (_) => HostingDialog(
        gateway: widget.gateway,
        repository: widget.repository,
        initialRemote: branch.remote,
      ),
    );
  }

  void _showActionMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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
            labelText:
                _operation == GitBranchOperation.cherryPick ||
                    _operation == GitBranchOperation.merge
                ? 'Source branch or commit'
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
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
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
    final operation = switch (action) {
      'rename' => GitBranchOperation.rename,
      'delete' => GitBranchOperation.delete,
      'merge' => GitBranchOperation.merge,
      'rebase' => GitBranchOperation.rebase,
      _ => GitBranchOperation.merge,
    };
    final current = _currentBranchName();
    setState(() {
      _operation = operation;
      _operationSourceController.text = operation == GitBranchOperation.rebase
          ? current ?? ''
          : branch;
      _operationTargetController.text = switch (operation) {
        GitBranchOperation.merge => current ?? '',
        GitBranchOperation.rebase => branch,
        _ => '',
      };
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
      if (mounted) {
        setState(() => _error = error);
        await _showErrorPopup(error.userMessage);
      }
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
      if (mounted) {
        setState(() => _error = error);
        await _showErrorPopup(error.userMessage);
      }
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
        if (_operationTargetController.text.trim().isEmpty &&
            _operation != GitBranchOperation.rename &&
            _operation != GitBranchOperation.delete) {
          _operationTargetController.text =
              branches.where((branch) => branch.isCurrent).firstOrNull?.name ??
              '';
        }
      });
      await _loadRemoteBranches();
    } on GitError catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _isLoading = false;
      });
      await _showErrorPopup(error.userMessage);
    }
  }

  Future<void> _loadRemoteBranches() async {
    final generation = ++_remoteLoadGeneration;
    try {
      final snapshot = await widget.gateway.getRemoteBranchSnapshot(
        widget.repository.repositoryId,
      );
      if (!mounted || generation != _remoteLoadGeneration) return;
      setState(() => _remoteSnapshot = snapshot);
    } on GitError catch (error) {
      if (!mounted || generation != _remoteLoadGeneration) return;
      setState(() => _error = error);
      await _showErrorPopup(error.userMessage);
    } on Object {
      // Older/focused test gateways and repositories without remote refs keep
      // the local branch browser usable when the optional remote read fails.
    }
  }

  Future<void> _fetchRemoteBranches() async {
    if (_isMutating) return;
    setState(() {
      _isMutating = true;
      _error = null;
      _fetchStatus = 'Fetching remote branches…';
    });
    final cancellation = GitCancellationToken();
    _operationCancellation = cancellation;
    try {
      final remotes = await widget.gateway.getRemotes(
        widget.repository.repositoryId,
      );
      final credentialGateway = widget.gateway is GitCredentialRemoteGateway
          ? widget.gateway as GitCredentialRemoteGateway
          : null;
      for (final remote in remotes) {
        final endpoint = remote.fetchUrl == null
            ? null
            : parseGitRemoteEndpoint(remote.fetchUrl!);
        final credentialId = endpoint == null
            ? null
            : widget.repositoryCredentialStore?.accountIdFor(
                widget.repository.root,
                endpoint.host,
              );
        if (credentialGateway == null) {
          await widget.gateway.fetch(
            widget.repository.repositoryId,
            remote.name,
            cancellationToken: cancellation,
          );
        } else {
          await credentialGateway.fetchWithCredential(
            widget.repository.repositoryId,
            remote.name,
            cancellationToken: cancellation,
            credentialId: credentialId,
          );
        }
      }
      await _loadBranches();
      if (mounted) {
        setState(() {
          _fetchStatus = remotes.isEmpty
              ? 'No remotes are configured.'
              : 'Fetched ${remotes.map((remote) => remote.name).join(', ')}. '
                    'Remote branches updated.';
        });
      }
    } on GitError catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _fetchStatus = null;
        });
        await _showErrorPopup(error.userMessage);
      }
    } finally {
      _operationCancellation = null;
      if (mounted) setState(() => _isMutating = false);
    }
  }

  Future<void> _createBranch() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _isMutating) return;
    final commitOid = widget.initialCreateCommitOid;
    await _runAction(
      commitOid == null
          ? () => widget.gateway.createBranch(
              widget.repository.repositoryId,
              name,
            )
          : () => widget.gateway.createBranchAtCommit(
              widget.repository.repositoryId,
              name,
              commitOid,
            ),
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
      if (mounted) {
        setState(() => _error = error);
        await _showErrorPopup(error.userMessage);
      }
    } finally {
      if (mounted) setState(() => _isMutating = false);
    }
  }

  Future<void> _showErrorPopup(String message) async {
    if (!mounted) return;
    await showGiftErrorDialog(context, message);
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
      await _showErrorPopup(error.userMessage);
    } finally {
      if (mounted) setState(() => _isMutating = false);
    }
  }
}
