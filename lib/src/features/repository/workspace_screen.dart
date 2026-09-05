import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:gift/src/features/repository/context_actions.dart';
import 'package:gift/src/features/repository/folder_path_field.dart';
import 'package:gift/src/features/repository/path_actions.dart';

import 'package:flutter/material.dart';
import 'package:gift/src/features/repository/changes_screen.dart';
import 'package:gift/src/features/repository/workspace_controller.dart';
import 'package:gift/src/app/app_preferences.dart';
import 'package:gift/src/backend/credentials.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/app/repository_credential_store.dart';

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({
    super.key,
    required this.controller,
    required this.onOpenRepository,
    required this.onWorkspaceEmpty,
    this.autoInitialize = true,
    this.credentialStore,
    this.repositoryCredentialStore,
    this.fileManager = const PlatformFileManagerRevealer(),
    this.selectDirectory,
    this.pathHistory,
    this.onOpenRepositoryPath,
  });

  final WorkspaceController controller;
  final Future<void> Function(int? replaceIndex) onOpenRepository;
  final VoidCallback onWorkspaceEmpty;
  final GitCredentialStore? credentialStore;
  final RepositoryCredentialStore? repositoryCredentialStore;
  final FileManagerRevealer fileManager;
  final FolderPathPicker? selectDirectory;
  final FolderPathHistory? pathHistory;
  final Future<void> Function(String path, int? replaceIndex)?
  onOpenRepositoryPath;
  final bool autoInitialize;

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;
    if (state.tabs.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final activeIndex = state.activeIndex.clamp(0, state.tabs.length - 1);
    final preferences =
        AppPreferencesScope.maybeOf(context)?.preferences ??
        GiftPreferences.defaults;
    final bindings = <ShortcutActivator, VoidCallback>{};
    void bind(String id, VoidCallback action) {
      final activator = shortcutActivator(preferences.shortcut(id));
      if (activator != null) bindings[activator] = action;
    }

    bind('nextTab', widget.controller.selectNext);
    bind('previousTab', widget.controller.selectPrevious);
    bind('cancel', () => unawaited(_closeActive()));
    return CallbackShortcuts(
      bindings: bindings,
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _WorkspaceTabBar(
                state: state,
                onSelect: widget.controller.select,
                onClose: _close,
                onReorder: widget.controller.reorder,
                onAdd: () => widget.onOpenRepository(null),
                snapshotFor: _workspaceActionSnapshot,
                actionsFor: _workspaceActions,
                onAction: _handleWorkspaceAction,
              ),
              Expanded(
                child: IndexedStack(
                  index: activeIndex,
                  children: [
                    for (final tab in state.tabs)
                      KeyedSubtree(
                        key: ValueKey('workspace-view:${tab.path}'),
                        child: _tabContent(tab),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  ContextActionSnapshot _workspaceActionSnapshot(WorkspaceTab tab) {
    final repository =
        tab.repository ??
        RepositoryOpened(
          repositoryId: RepositoryId(value: 'workspace:${tab.path}'),
          root: tab.path,
        );
    final membership = widget.controller.state.tabs
        .map(
          (candidate) =>
              '${candidate.path}:${candidate.repository?.root ?? ''}:'
              '${candidate.isAvailable}',
        )
        .join('|');
    return ContextActionSnapshot(
      repository: repository,
      target: ContextActionTarget.repository(
        path: tab.path,
        label: tab.displayName,
      ),
      fingerprint:
          '${widget.controller.state.activeIndex}:$membership:${tab.path}',
    );
  }

  List<ContextActionDescriptor> _workspaceActions(WorkspaceTab tab, int index) {
    final snapshot = _workspaceActionSnapshot(tab);
    final state = widget.controller.state;
    final active = state.activeIndex == index;
    final nested = state.tabs.any(
      (candidate) =>
          candidate.path != tab.path && _isNestedPath(tab.path, candidate.path),
    );
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
      enabled: enabled,
      disabledReason: disabledReason,
    );

    return [
      action(
        id: ContextActionId.activateRepository,
        label: 'Activate',
        icon: Icons.open_in_new,
        group: ContextActionGroup.workflow,
        route: ContextActionRoute.activateRepository,
        enabled: !active,
        disabledReason: active ? 'This repository is already active.' : null,
      ),
      action(
        id: ContextActionId.closeRepository,
        label: 'Close tab',
        icon: Icons.close,
        group: ContextActionGroup.destructive,
        route: ContextActionRoute.closeRepository,
      ),
      action(
        id: ContextActionId.closeOtherRepositories,
        label: 'Close other tabs',
        icon: Icons.tab_unselected,
        group: ContextActionGroup.destructive,
        route: ContextActionRoute.closeOtherRepositories,
        enabled: state.tabs.length > 1,
        disabledReason: state.tabs.length > 1
            ? null
            : 'There are no other open repositories.',
      ),
      action(
        id: ContextActionId.copyRepositoryPath,
        label: 'Copy repository path',
        icon: Icons.content_copy,
        group: ContextActionGroup.inspect,
        route: ContextActionRoute.copyRepositoryPath,
      ),
      action(
        id: ContextActionId.revealRepository,
        label: 'Reveal in file manager',
        icon: Icons.folder_open_outlined,
        group: ContextActionGroup.inspect,
        route: ContextActionRoute.revealRepository,
        enabled: tab.isAvailable && Directory(tab.path).existsSync(),
        disabledReason: tab.isAvailable
            ? 'The repository root is not present on disk.'
            : 'This repository is unavailable.',
      ),
      if (nested)
        action(
          id: ContextActionId.openNestedRepository,
          label: 'Open nested repository',
          icon: Icons.account_tree_outlined,
          group: ContextActionGroup.workflow,
          route: ContextActionRoute.openNestedRepository,
        ),
    ];
  }

  Future<void> _handleWorkspaceAction(ContextActionDescriptor action) async {
    if (action.snapshot.target.kind != ContextActionTargetKind.repository) {
      return;
    }
    final index = widget.controller.state.tabs.indexWhere(
      (tab) => tab.path == action.snapshot.target.identity,
    );
    if (index == -1) return;
    final tab = widget.controller.state.tabs[index];
    if (_workspaceActionSnapshot(tab) != action.snapshot) return;
    switch (action.route) {
      case ContextActionRoute.activateRepository ||
          ContextActionRoute.openNestedRepository:
        widget.controller.select(index);
      case ContextActionRoute.closeRepository:
        await _close(index);
      case ContextActionRoute.closeOtherRepositories:
        await widget.controller.closeOthers(index);
      case ContextActionRoute.copyRepositoryPath:
        await Clipboard.setData(ClipboardData(text: tab.path));
      case ContextActionRoute.revealRepository:
        final result = await widget.fileManager.reveal(tab.path);
        if (!mounted || result.isSuccess || result.message == null) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(result.message!)));
      case ContextActionRoute.openRepository:
      case ContextActionRoute.removeRecentRepository:
      case ContextActionRoute.inspect ||
          ContextActionRoute.stage ||
          ContextActionRoute.unstage ||
          ContextActionRoute.stageSelectedPatch ||
          ContextActionRoute.discard ||
          ContextActionRoute.moveToChangelist ||
          ContextActionRoute.shelve ||
          ContextActionRoute.ignoreLocal ||
          ContextActionRoute.ignoreRepository ||
          ContextActionRoute.fileHistory ||
          ContextActionRoute.blame ||
          ContextActionRoute.compare ||
          ContextActionRoute.compareBranch ||
          ContextActionRoute.copyRelativePath ||
          ContextActionRoute.copyAbsolutePath ||
          ContextActionRoute.reveal ||
          ContextActionRoute.cherryPick ||
          ContextActionRoute.revert ||
          ContextActionRoute.createBranch ||
          ContextActionRoute.createTag ||
          ContextActionRoute.reset ||
          ContextActionRoute.copyFullHash ||
          ContextActionRoute.copyShortHash ||
          ContextActionRoute.checkoutBranch ||
          ContextActionRoute.mergeBranch ||
          ContextActionRoute.rebaseBranch ||
          ContextActionRoute.renameBranch ||
          ContextActionRoute.deleteBranch ||
          ContextActionRoute.pushBranch ||
          ContextActionRoute.upstream ||
          ContextActionRoute.copyBranchName ||
          ContextActionRoute.copyBranchRef ||
          ContextActionRoute.compareRemote ||
          ContextActionRoute.checkoutRemote ||
          ContextActionRoute.deleteRemote ||
          ContextActionRoute.cherryPickRemote ||
          ContextActionRoute.hostLink:
        return;
    }
  }

  bool _isNestedPath(String path, String possibleParent) {
    final child = path.replaceAll('\\', '/').replaceFirst(RegExp(r'/+$'), '');
    final parent = possibleParent
        .replaceAll('\\', '/')
        .replaceFirst(RegExp(r'/+$'), '');
    return child != parent && child.startsWith('$parent/');
  }

  Widget _tabContent(WorkspaceTab tab) {
    if (tab.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (tab.repository case final repository?) {
      return ChangesScreen(
        gateway: widget.controller.gateway,
        repository: repository,
        controller: tab.changesController,
        historyController: tab.historyController,
        onOpenRepository: (opened) async {
          await widget.controller.openPath(opened.root);
        },
        autoInitialize: widget.autoInitialize,
        credentialStore: widget.credentialStore,
        repositoryCredentialStore: widget.repositoryCredentialStore,
        pathHistory: widget.pathHistory,
      );
    }
    final replaceIndex = widget.controller.state.tabs.indexOf(tab);
    return _UnavailableWorkspaceTab(
      tab: tab,
      selectDirectory: widget.selectDirectory,
      pathHistory: widget.pathHistory,
      onReplace: (path) {
        final openPath = widget.onOpenRepositoryPath;
        return openPath == null
            ? widget.onOpenRepository(replaceIndex)
            : openPath(path, replaceIndex);
      },
    );
  }

  Future<void> _close(int index) async {
    await widget.controller.close(index);
    if (mounted && widget.controller.state.tabs.isEmpty) {
      widget.onWorkspaceEmpty();
    }
  }

  Future<void> _closeActive() => _close(widget.controller.state.activeIndex);

  void _onChanged() {
    if (mounted) setState(() {});
  }
}

class _WorkspaceTabBar extends StatelessWidget {
  const _WorkspaceTabBar({
    required this.state,
    required this.onSelect,
    required this.onClose,
    required this.onReorder,
    required this.onAdd,
    required this.snapshotFor,
    required this.actionsFor,
    required this.onAction,
  });

  final WorkspaceState state;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onClose;
  final Future<void> Function(int oldIndex, int newIndex) onReorder;
  final VoidCallback onAdd;
  final ContextActionSnapshot Function(WorkspaceTab tab) snapshotFor;
  final List<ContextActionDescriptor> Function(WorkspaceTab tab, int index)
  actionsFor;
  final ContextActionHandler onAction;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const Key('workspace-tab-bar'),
      height: 48,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.outline)),
      ),
      child: Row(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Two tabs should remain fully actionable at the smallest
                // supported window. Additional tabs can scroll horizontally.
                final tabWidth =
                    ((constraints.maxWidth - 8) / state.tabs.length)
                        .clamp(116.0, 220.0)
                        .toDouble();
                return ReorderableListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                  buildDefaultDragHandles: false,
                  itemCount: state.tabs.length,
                  onReorderItem: (oldIndex, newIndex) {
                    unawaited(onReorder(oldIndex, newIndex));
                  },
                  itemBuilder: (context, index) {
                    final tab = state.tabs[index];
                    final selected = state.activeIndex == index;
                    return ContextActionMenu(
                      key: ValueKey('workspace-menu:${tab.path}'),
                      snapshot: snapshotFor(tab),
                      actions: actionsFor(tab, index),
                      onAction: onAction,
                      child: ReorderableDelayedDragStartListener(
                        key: ValueKey('workspace-tab:${tab.path}'),
                        index: index,
                        child: _WorkspaceTab(
                          width: tabWidth,
                          tab: tab,
                          selected: selected,
                          onSelect: () => onSelect(index),
                          onClose: () => onClose(index),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: IconButton(
              key: const Key('workspace-open-repository'),
              tooltip: 'Open repository',
              onPressed: onAdd,
              icon: const Icon(Icons.add),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceTab extends StatelessWidget {
  const _WorkspaceTab({
    required this.width,
    required this.tab,
    required this.selected,
    required this.onSelect,
    required this.onClose,
  });

  final double width;
  final WorkspaceTab tab;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = selected ? colors.onSurface : colors.onSurfaceVariant;
    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? colors.primary : Colors.transparent,
              width: 4,
            ),
          ),
        ),
        child: Material(
          color: selected ? colors.surfaceContainerHighest : colors.surface,
          child: InkWell(
            onTap: onSelect,
            child: Semantics(
              button: true,
              selected: selected,
              label: tab.isAvailable
                  ? '${tab.displayName} repository tab'
                  : '${tab.displayName} unavailable repository tab',
              child: Padding(
                padding: const EdgeInsets.only(left: 10, right: 4),
                child: Row(
                  children: [
                    Icon(
                      tab.isAvailable
                          ? Icons.account_tree_outlined
                          : Icons.warning_amber_rounded,
                      size: 15,
                      color: tab.isAvailable ? foreground : colors.error,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        tab.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: foreground,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    ContextActionMenuButton(
                      key: ValueKey('workspace-actions:${tab.path}'),
                    ),
                    IconButton(
                      key: ValueKey('workspace-close:${tab.path}'),
                      tooltip: 'Close ${tab.displayName}',
                      onPressed: onClose,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: foreground,
                        side: BorderSide.none,
                        minimumSize: const Size(32, 32),
                        maximumSize: const Size(32, 32),
                        padding: const EdgeInsets.all(8),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.zero,
                        ),
                      ),
                      icon: const Icon(Icons.close, size: 15),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UnavailableWorkspaceTab extends StatefulWidget {
  const _UnavailableWorkspaceTab({
    required this.tab,
    required this.onReplace,
    this.selectDirectory,
    this.pathHistory,
  });

  final WorkspaceTab tab;
  final Future<void> Function(String path) onReplace;
  final FolderPathPicker? selectDirectory;
  final FolderPathHistory? pathHistory;

  @override
  State<_UnavailableWorkspaceTab> createState() =>
      _UnavailableWorkspaceTabState();
}

class _UnavailableWorkspaceTabState extends State<_UnavailableWorkspaceTab> {
  final _pathController = TextEditingController();
  final _fieldKey = GlobalKey<FolderPathFieldState>();

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  Future<void> _replace() async {
    final validation = _fieldKey.currentState?.validateNow();
    if (validation == null || !validation.isValid) return;
    await widget.onReplace(_pathController.text.trim());
  }

  Future<void> _chooseOrReplace() async {
    if (_pathController.text.trim().isEmpty) {
      await _fieldKey.currentState?.browse();
      return;
    }
    await _replace();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.tab.displayName,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                widget.tab.path,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Text(
                widget.tab.error?.userMessage ??
                    'This repository is unavailable.',
              ),
              const SizedBox(height: 16),
              FolderPathField(
                key: _fieldKey,
                fieldKey: const Key('workspace-replacement-path'),
                browseKey: const Key('workspace-replacement-browse'),
                controller: _pathController,
                purpose: FolderPathPurpose.replaceWorkspaceRoot,
                label: 'Replacement folder',
                hint: 'Absolute existing folder',
                picker: widget.selectDirectory,
                history: widget.pathHistory,
                onSubmitted: (_) => _replace(),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('workspace-choose-replacement'),
                onPressed: _chooseOrReplace,
                icon: const Icon(Icons.folder_open, size: 17),
                label: const Text('Choose replacement folder'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
