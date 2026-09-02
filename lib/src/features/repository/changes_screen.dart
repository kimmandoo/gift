import 'dart:async';

import 'package:branchline/src/backend/commit.dart';
import 'package:branchline/src/backend/branch.dart';
import 'package:branchline/src/backend/domain.dart';
import 'package:branchline/src/backend/diff.dart';
import 'package:branchline/src/backend/error.dart';
import 'package:branchline/src/backend/git_gateway.dart';
import 'package:branchline/src/backend/remote.dart';
import 'package:branchline/src/backend/status.dart';
import 'package:branchline/src/features/repository/changes_controller.dart';
import 'package:branchline/src/features/repository/branch_dialog.dart';
import 'package:branchline/src/features/repository/history_screen.dart';
import 'package:branchline/src/features/repository/remote_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shows the repository's current changes grouped by their Git facets.
class ChangesScreen extends StatelessWidget {
  const ChangesScreen({
    super.key,
    required this.gateway,
    required this.repository,
    this.controller,
    this.onBack,
    this.autoInitialize = true,
  });

  final GitGateway gateway;
  final RepositoryOpened repository;
  final ChangesController? controller;
  final VoidCallback? onBack;
  final bool autoInitialize;

  @override
  Widget build(BuildContext context) {
    // A local scope keeps this screen usable from tests and from future
    // navigation shells that do not already have a ProviderScope.
    return ProviderScope(
      child: _ChangesScreenBody(
        gateway: gateway,
        repository: repository,
        controller: controller,
        onBack: onBack,
        autoInitialize: autoInitialize,
      ),
    );
  }
}

class _ChangesScreenBody extends ConsumerStatefulWidget {
  const _ChangesScreenBody({
    required this.gateway,
    required this.repository,
    this.controller,
    this.onBack,
    required this.autoInitialize,
  });

  final GitGateway gateway;
  final RepositoryOpened repository;
  final ChangesController? controller;
  final VoidCallback? onBack;
  final bool autoInitialize;

  @override
  ConsumerState<_ChangesScreenBody> createState() => _ChangesScreenBodyState();
}

class _ChangesScreenBodyState extends ConsumerState<_ChangesScreenBody> {
  ChangesController? _manualController;
  late final ChangesControllerArgs _providerArgs;
  late final TextEditingController _commitMessageController;

  @override
  void initState() {
    super.initState();
    _commitMessageController = TextEditingController();
    _providerArgs = ChangesControllerArgs(
      gateway: widget.gateway,
      repositoryId: widget.repository.repositoryId,
    );
    final providedController = widget.controller;
    if (providedController != null) {
      _manualController = providedController;
      _manualController!.addListener(_onChanged);
      if (widget.autoInitialize) _manualController!.start();
    } else if (widget.autoInitialize) {
      Future<void>.microtask(() {
        if (mounted) ref.read(changesControllerProvider(_providerArgs)).start();
      });
    }
  }

  @override
  void dispose() {
    _commitMessageController.dispose();
    _manualController?.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller =
        _manualController ??
        ref.watch(changesControllerProvider(_providerArgs))!;
    final state = controller.state;
    final snapshot = state.snapshot;
    return Scaffold(
      appBar: AppBar(
        leading: widget.onBack == null
            ? null
            : IconButton(
                tooltip: 'Back to repositories',
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back),
              ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Changes'),
            Text(
              widget.repository.root,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        actions: [
          IconButton(
            key: const Key('open-remotes'),
            tooltip: 'Open remote operations',
            onPressed: () => unawaited(_openRemotes(context)),
            icon: const Icon(Icons.cloud_outlined),
          ),
          IconButton(
            key: const Key('open-branches'),
            tooltip: 'Open branches',
            onPressed: () => unawaited(_openBranches(context)),
            icon: const Icon(Icons.call_split),
          ),
          IconButton(
            key: const Key('open-history'),
            tooltip: 'Open history',
            onPressed: () => unawaited(_openHistory(context)),
            icon: const Icon(Icons.history),
          ),
          IconButton(
            tooltip: 'Refresh changes',
            onPressed: state.isRefreshing ? null : controller.refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (snapshot != null) ...[
              _summary(context, snapshot),
              if (state.error case final error?) _errorBanner(context, error),
            ],
            if (state.isLoading) const LinearProgressIndicator(),
            if (state.commitResult case final result?)
              _commitSuccess(context, result),
            if (state.commitError case final error?) _commitError(error),
            if (snapshot != null && snapshot.staged.isNotEmpty)
              _commitPanel(context, controller, state),
            Expanded(
              child: snapshot == null && state.error != null
                  ? _errorState(state.error!)
                  : snapshot == null
                  ? const Center(child: CircularProgressIndicator())
                  : _changesLayout(context, snapshot, state),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summary(BuildContext context, GitStatusSnapshot snapshot) {
    final branch = snapshot.branch.head ?? 'Detached HEAD';
    final sync = snapshot.branch.hasUpstream
        ? '↑${snapshot.branch.ahead} ↓${snapshot.branch.behind}'
        : 'no upstream';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          const Icon(Icons.account_tree_outlined, size: 18),
          const SizedBox(width: 8),
          Text(branch, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 12),
          Text(sync),
          const Spacer(),
          Text('${snapshot.changes.length} changes'),
          const SizedBox(width: 12),
          Text('generation ${snapshot.generation}'),
        ],
      ),
    );
  }

  Widget _commitPanel(
    BuildContext context,
    ChangesController controller,
    ChangesState state,
  ) {
    final canSubmit =
        controller.canCommit &&
        !state.isMutating &&
        _commitMessageController.text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextField(
                  key: const Key('commit-message'),
                  controller: _commitMessageController,
                  enabled: !state.isMutating,
                  minLines: 1,
                  maxLines: 3,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    labelText: 'Commit staged changes',
                    border: OutlineInputBorder(),
                    hintText: 'Describe the staged changes',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                key: const Key('commit-staged'),
                onPressed: canSubmit
                    ? () => unawaited(_submitCommit(controller))
                    : null,
                icon: state.isCommitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check, size: 18),
                label: const Text('Commit'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _commitSuccess(BuildContext context, GitCommitResult result) {
    final shortOid = result.commitOid.length > 7
        ? result.commitOid.substring(0, 7)
        : result.commitOid;
    return Container(
      key: const Key('commit-success'),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: Text('Committed $shortOid.'),
    );
  }

  Widget _commitError(GitError error) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Text(
        error.userMessage,
        key: const Key('commit-error'),
        style: const TextStyle(color: Colors.red),
      ),
    );
  }

  Future<void> _submitCommit(ChangesController controller) async {
    final message = _commitMessageController.text;
    if (message.trim().isEmpty) return;
    await controller.commit(message);
    if (!mounted || controller.state.commitResult == null) return;
    _commitMessageController.clear();
    setState(() {});
  }

  Widget _changesLayout(
    BuildContext context,
    GitStatusSnapshot snapshot,
    ChangesState state,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final listWidth = constraints.maxWidth < 720 ? 260.0 : 340.0;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: listWidth,
              child: _groupedChanges(context, snapshot, state),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: _details(context, snapshot, state)),
          ],
        );
      },
    );
  }

  Widget _groupedChanges(
    BuildContext context,
    GitStatusSnapshot snapshot,
    ChangesState state,
  ) {
    if (snapshot.isClean) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text('Working tree is clean.'),
        ),
      );
    }

    final sections =
        <({String title, GitChangeGroup group, List<GitChange> changes})>[
          (
            title: 'Conflicts',
            group: GitChangeGroup.conflicts,
            changes: snapshot.conflicts,
          ),
          (
            title: 'Staged',
            group: GitChangeGroup.staged,
            changes: snapshot.staged,
          ),
          (
            title: 'Unstaged',
            group: GitChangeGroup.unstaged,
            changes: snapshot.unstaged,
          ),
          (
            title: 'Untracked',
            group: GitChangeGroup.untracked,
            changes: snapshot.untracked,
          ),
        ];

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final section in sections)
          if (section.changes.isNotEmpty) ...[
            _sectionHeader(context, section.title, section.changes.length),
            for (final change in section.changes)
              _changeTile(context, change, section.group, state),
          ],
      ],
    );
  }

  Widget _sectionHeader(BuildContext context, String title, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 4),
      child: Text(
        '$title ($count)',
        style: Theme.of(context).textTheme.labelLarge
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _changeTile(
    BuildContext context,
    GitChange change,
    GitChangeGroup group,
    ChangesState state,
  ) {
    final selected = state.selectedPath == change.path;
    return ListTile(
      key: ValueKey('${group.name}:${change.path}'),
      dense: true,
      selected: selected,
      leading: _statusBadge(context, change),
      title: Text(change.path, overflow: TextOverflow.ellipsis),
      subtitle: change.originalPath == null
          ? null
          : Text(
              'from ${change.originalPath}',
              overflow: TextOverflow.ellipsis,
            ),
      onTap: () => unawaited(_activeController.selectChange(change)),
    );
  }

  Widget _statusBadge(BuildContext context, GitChange change) {
    final color = change.isConflicted
        ? Theme.of(context).colorScheme.error
        : change.isUntracked
        ? Theme.of(context).colorScheme.tertiary
        : Theme.of(context).colorScheme.primary;
    return Container(
      width: 28,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color),
      ),
      child: Text(
        change.shortStatus,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _details(
    BuildContext context,
    GitStatusSnapshot snapshot,
    ChangesState state,
  ) {
    final selectedPath = state.selectedPath;
    if (selectedPath == null) {
      return const Center(child: Text('Select a change to inspect it.'));
    }
    GitChange? selected;
    for (final change in snapshot.changes) {
      if (change.path == selectedPath) {
        selected = change;
        break;
      }
    }
    if (selected == null) {
      return const Center(child: Text('That change is no longer present.'));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(selected.path, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 10),
          Text('Status ${selected.shortStatus}'),
          const SizedBox(height: 6),
          Text(_groupText(selected)),
          if (selected.originalPath case final originalPath?) ...[
            const SizedBox(height: 6),
            Text('Original path: $originalPath'),
          ],
          if (selected.isStaged || selected.isUnstaged) ...[
            const SizedBox(height: 16),
            _scopeSelector(context, selected, state),
          ],
          if (_activeController.canStageSelected ||
              _activeController.canUnstageSelected ||
              _activeController.canDiscardSelected) ...[
            const SizedBox(height: 16),
            _mutationActions(context, state),
          ],
          if (state.mutationError case final error?) ...[
            const SizedBox(height: 10),
            Text(
              error.userMessage,
              key: const Key('mutation-error'),
              style: TextStyle(color: Colors.red),
            ),
          ],
          if (state.discardError case final error?) ...[
            const SizedBox(height: 10),
            Text(
              error.userMessage,
              key: const Key('discard-error'),
              style: TextStyle(color: Colors.red),
            ),
          ],
          if (state.isDiscardPreparing || state.isMutating)
            const LinearProgressIndicator(),
          const SizedBox(height: 16),
          if (state.isDiffLoading) const LinearProgressIndicator(),
          if (state.diffError case final error?) ...[
            const SizedBox(height: 12),
            Text(
              error.userMessage,
              key: const Key('diff-error'),
              style: TextStyle(color: Colors.red),
            ),
          ],
          const SizedBox(height: 12),
          Expanded(child: _diffBody(context, state)),
        ],
      ),
    );
  }

  Widget _mutationActions(BuildContext context, ChangesState state) {
    final controller = _activeController;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (controller.canStageSelected)
          FilledButton.icon(
            key: const Key('stage-selected'),
            onPressed: state.isMutating || state.isDiscardPreparing
                ? null
                : controller.stageSelected,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Stage'),
          ),
        if (controller.canUnstageSelected)
          OutlinedButton.icon(
            key: const Key('unstage-selected'),
            onPressed: state.isMutating || state.isDiscardPreparing
                ? null
                : controller.unstageSelected,
            icon: const Icon(Icons.remove, size: 18),
            label: const Text('Unstage'),
          ),
        if (controller.canDiscardSelected)
          OutlinedButton.icon(
            key: const Key('discard-selected'),
            onPressed: state.isMutating || state.isDiscardPreparing
                ? null
                : () => unawaited(_showDiscardDialog(context, controller)),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Discard'),
          ),
      ],
    );
  }

  Future<void> _showDiscardDialog(
    BuildContext context,
    ChangesController controller,
  ) async {
    final preview = await controller.prepareDiscard();
    if (!context.mounted || preview == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: Text(
          'Discard the working-tree changes in ${preview.path}? '
          'Staged changes will be kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-discard'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    if (confirmed == true) {
      await controller.confirmDiscard(preview);
    } else {
      controller.cancelDiscardPreview();
    }
  }

  Future<void> _openHistory(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HistoryScreen(
          gateway: widget.gateway,
          repository: widget.repository,
        ),
      ),
    );
  }

  Future<void> _openBranches(BuildContext context) async {
    final result = await showDialog<GitBranchActionResult>(
      context: context,
      builder: (_) =>
          BranchDialog(gateway: widget.gateway, repository: widget.repository),
    );
    if (!context.mounted || result == null) return;
    await _activeController.refresh();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Switched to ${result.branchName}.')),
    );
  }

  Future<void> _openRemotes(BuildContext context) async {
    final result = await showDialog<GitRemoteOperationResult>(
      context: context,
      builder: (_) =>
          RemoteDialog(gateway: widget.gateway, repository: widget.repository),
    );
    if (!context.mounted || result == null) return;
    await _activeController.refresh();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${_remoteOperationLabel(result.operation)} ${result.remote} complete.',
        ),
      ),
    );
  }

  Widget _scopeSelector(
    BuildContext context,
    GitChange selected,
    ChangesState state,
  ) {
    return SegmentedButton<GitDiffScope>(
      segments: const [
        ButtonSegment(
          value: GitDiffScope.workingTree,
          label: Text('Working tree'),
        ),
        ButtonSegment(value: GitDiffScope.staged, label: Text('Staged')),
      ],
      selected: {state.diffScope},
      onSelectionChanged: (scopes) {
        final scope = scopes.firstOrNull;
        if (scope == null) return;
        unawaited(
          _activeController.loadDiff(
            selected.path,
            originalPath: selected.originalPath,
            scope: scope,
          ),
        );
      },
    );
  }

  Widget _diffBody(BuildContext context, ChangesState state) {
    if (state.isDiffLoading && state.diff == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.diffError != null && state.diff == null) {
      return const Center(child: Text('The diff could not be loaded.'));
    }
    final diff = state.diff;
    if (diff == null) {
      return const Center(child: Text('Select a change to inspect its diff.'));
    }
    if (diff.isBinary) {
      return const Center(
        child: Text('Binary file changes are not shown as text.'),
      );
    }
    if (diff.isEmpty) {
      return const Center(child: Text('No changes in this scope.'));
    }

    return ListView.builder(
      key: const Key('diff-lines'),
      itemCount: diff.lines.length,
      itemBuilder: (context, index) =>
          _diffLine(context, diff.lines[index], index),
    );
  }

  Widget _diffLine(BuildContext context, GitDiffLine line, int index) {
    final colors = Theme.of(context).colorScheme;
    final background = switch (line.kind) {
      GitDiffLineKind.addition => colors.tertiaryContainer,
      GitDiffLineKind.deletion => colors.errorContainer,
      GitDiffLineKind.hunkHeader => colors.primaryContainer,
      _ => Colors.transparent,
    };
    final foreground = switch (line.kind) {
      GitDiffLineKind.addition => colors.onTertiaryContainer,
      GitDiffLineKind.deletion => colors.onErrorContainer,
      GitDiffLineKind.hunkHeader => colors.onPrimaryContainer,
      _ => colors.onSurface,
    };
    return Container(
      key: ValueKey('diff-line-$index'),
      color: background,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _lineNumber(line.oldLineNumber),
          _lineNumber(line.newLineNumber),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableText(
              line.text,
              style: TextStyle(
                color: foreground,
                fontFamily: 'monospace',
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lineNumber(int? number) {
    return SizedBox(
      width: 42,
      child: Text(
        number?.toString() ?? '',
        textAlign: TextAlign.right,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
      ),
    );
  }

  String _groupText(GitChange change) {
    if (change.isConflicted) return 'This path needs conflict resolution.';
    if (change.isUntracked) return 'This path is not tracked by Git yet.';
    if (change.isStaged && change.isUnstaged) {
      return 'This path has both staged and unstaged changes.';
    }
    if (change.isStaged) return 'This path is ready for the next commit.';
    return 'This path has working-tree changes.';
  }

  Widget _errorState(GitError error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(error.userMessage, key: const Key('changes-error')),
      ),
    );
  }

  Widget _errorBanner(BuildContext context, GitError error) {
    return Container(
      key: const Key('changes-refresh-error'),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: Theme.of(context).colorScheme.errorContainer,
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(error.userMessage)),
        ],
      ),
    );
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  ChangesController get _activeController =>
      _manualController ?? ref.read(changesControllerProvider(_providerArgs));
}

String _remoteOperationLabel(GitRemoteOperation operation) =>
    switch (operation) {
      GitRemoteOperation.fetch => 'Fetch',
      GitRemoteOperation.pull => 'Pull',
      GitRemoteOperation.push => 'Push',
    };
