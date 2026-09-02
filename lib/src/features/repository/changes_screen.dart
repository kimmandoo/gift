import 'package:branchline/src/backend/domain.dart';
import 'package:branchline/src/backend/error.dart';
import 'package:branchline/src/backend/git_gateway.dart';
import 'package:branchline/src/backend/status.dart';
import 'package:branchline/src/features/repository/changes_controller.dart';
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

  @override
  void initState() {
    super.initState();
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
      onTap: () => _activeController.selectPath(change.path),
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(selected.path, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Text('Status ${selected.shortStatus}'),
          const SizedBox(height: 8),
          Text(_groupText(selected)),
          if (selected.originalPath case final originalPath?) ...[
            const SizedBox(height: 8),
            Text('Original path: $originalPath'),
          ],
          const SizedBox(height: 24),
          const Text(
            'Diff preview will appear here in the next task.',
            style: TextStyle(fontStyle: FontStyle.italic),
          ),
        ],
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
