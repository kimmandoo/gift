import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gitshiba/src/features/repository/changes_screen.dart';
import 'package:gitshiba/src/features/repository/workspace_controller.dart';

/// The tab shell that keeps one Changes screen alive for every open repository.
///
/// `IndexedStack` is intentional: switching tabs changes visibility without
/// throwing away a tab's selected file, diff, or in-flight status request.
class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({
    super.key,
    required this.controller,
    required this.onOpenRepository,
    required this.onWorkspaceEmpty,
    this.autoInitialize = true,
  });

  final WorkspaceController controller;
  final Future<void> Function(int? replaceIndex) onOpenRepository;
  final VoidCallback onWorkspaceEmpty;
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
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.tab, control: true):
            widget.controller.selectNext,
        const SingleActivator(
          LogicalKeyboardKey.tab,
          control: true,
          shift: true,
        ): widget.controller.selectPrevious,
        const SingleActivator(LogicalKeyboardKey.keyW, control: true):
            _closeActive,
      },
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
        autoInitialize: widget.autoInitialize,
      );
    }
    return _UnavailableWorkspaceTab(
      tab: tab,
      onReplace: () =>
          widget.onOpenRepository(widget.controller.state.tabs.indexOf(tab)),
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
  });

  final WorkspaceState state;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onClose;
  final Future<void> Function(int oldIndex, int newIndex) onReorder;
  final VoidCallback onAdd;

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
                    return ReorderableDelayedDragStartListener(
                      key: ValueKey('workspace-tab:${tab.path}'),
                      index: index,
                      child: _WorkspaceTab(
                        width: tabWidth,
                        tab: tab,
                        selected: selected,
                        onSelect: () => onSelect(index),
                        onClose: () => onClose(index),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          IconButton(
            key: const Key('workspace-open-repository'),
            tooltip: 'Open repository',
            onPressed: onAdd,
            icon: const Icon(Icons.add),
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
                  IconButton(
                    key: ValueKey('workspace-close:${tab.path}'),
                    tooltip: 'Close ${tab.displayName}',
                    onPressed: onClose,
                    icon: const Icon(Icons.close, size: 15),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UnavailableWorkspaceTab extends StatelessWidget {
  const _UnavailableWorkspaceTab({required this.tab, required this.onReplace});

  final WorkspaceTab tab;
  final VoidCallback onReplace;

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
                tab.displayName,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(tab.path, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              Text(tab.error?.userMessage ?? 'This repository is unavailable.'),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onReplace,
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
