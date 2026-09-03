import 'dart:async';

import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/diff.dart';
import 'package:gift/src/backend/error.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:gift/src/backend/history.dart';
import 'package:gift/src/backend/interactive_rebase.dart';
import 'package:gift/src/backend/reset.dart';
import 'package:gift/src/features/repository/history_controller.dart';
import 'package:gift/src/features/repository/interactive_rebase_dialog.dart';
import 'package:gift/src/features/repository/reset_dialog.dart';
import 'package:gift/src/features/repository/hosting_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gift/src/app/pixel_theme.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    required this.gateway,
    required this.repository,
    this.controller,
    this.autoInitialize = true,
  });

  final GitGateway gateway;
  final RepositoryOpened repository;
  final HistoryController? controller;
  final bool autoInitialize;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late final HistoryController _controller;
  late final bool _ownsController;
  late final TextEditingController _searchController;
  late final TextEditingController _authorController;
  late final TextEditingController _pathController;
  late final TextEditingController _refController;
  late final TextEditingController _afterController;
  late final TextEditingController _beforeController;
  late final FocusNode _searchFocusNode;
  final _selectedDiffKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller =
        widget.controller ??
        HistoryController(
          gateway: widget.gateway,
          repositoryId: widget.repository.repositoryId,
        );
    _controller.addListener(_onChanged);
    _searchController = TextEditingController();
    _authorController = TextEditingController();
    _pathController = TextEditingController();
    _refController = TextEditingController();
    _afterController = TextEditingController();
    _beforeController = TextEditingController();
    _searchFocusNode = FocusNode();
    if (widget.autoInitialize) {
      Future<void>.microtask(_controller.start);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    if (_ownsController) _controller.dispose();
    _searchController.dispose();
    _authorController.dispose();
    _pathController.dispose();
    _refController.dispose();
    _afterController.dispose();
    _beforeController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _controller.state;
    final page = state.page;
    final scaffold = Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back to changes',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('History'),
            Text(
              widget.repository.root,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        actions: [
          IconButton(
            key: const Key('history-rollback'),
            tooltip: 'Undo, reset, or revert history',
            onPressed: () => unawaited(_openHistoryRollback(context)),
            icon: const Icon(Icons.history_toggle_off),
          ),
          IconButton(
            key: const Key('history-interactive-rebase'),
            tooltip: 'Interactive rebase',
            onPressed: state.isLoading
                ? null
                : () => unawaited(_openInteractiveRebase(context)),
            icon: const Icon(Icons.reorder),
          ),
          IconButton(
            key: const Key('history-hosting'),
            tooltip: 'Open hosting links',
            onPressed: state.selectedCommit == null
                ? null
                : () => unawaited(_openHosting(context, state)),
            icon: const Icon(Icons.link_outlined),
          ),
          const PixelThemeToggle(),
          IconButton(
            tooltip: 'Refresh history',
            onPressed: state.isLoading ? null : _controller.refresh,
            icon: state.isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _filtersPanel(context),
            if (state.isLoading) const LinearProgressIndicator(),
            if (state.error case final error?) _errorBanner(context, error),
            Expanded(
              child: page == null
                  ? state.error != null
                        ? _emptyError(state.error!)
                        : const Center(child: CircularProgressIndicator())
                  : _historyLayout(context, page, state),
            ),
            if (page != null)
              Container(
                key: const Key('history-status-strip'),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                padding: EdgeInsets.symmetric(
                  horizontal: MediaQuery.sizeOf(context).width < 480 ? 12 : 20,
                  vertical: 7,
                ),
                child: Text(
                  'Ctrl+R refresh · Esc back',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
          ],
        ),
      ),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyR, control: true):
            _controller.refresh,
        const SingleActivator(LogicalKeyboardKey.arrowDown):
            _controller.selectNext,
        const SingleActivator(LogicalKeyboardKey.arrowUp):
            _controller.selectPrevious,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
            _searchFocusNode.requestFocus(),
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Focus(autofocus: true, child: scaffold),
    );
  }

  Future<void> _openHosting(BuildContext context, HistoryState state) async {
    final commit = state.selectedCommit;
    if (commit == null) return;
    await showDialog<void>(
      context: context,
      builder: (_) => HostingDialog(
        gateway: widget.gateway,
        repository: widget.repository,
        initialCommitOid: commit.oid,
        initialPath: state.selectedPath ?? '',
      ),
    );
  }

  Widget _filtersPanel(BuildContext context) {
    final filterFields = Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fieldWidth = constraints.maxWidth < 520
              ? constraints.maxWidth
              : (constraints.maxWidth - 12) / 2;
          return Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _filterField(
                _authorController,
                'Author',
                'history-author-filter',
                fieldWidth,
              ),
              _filterField(
                _refController,
                'Branch or ref',
                'history-ref-filter',
                fieldWidth,
              ),
              _filterField(
                _pathController,
                'Changed path',
                'history-path-filter',
                fieldWidth,
              ),
              _filterField(
                _afterController,
                'Authored after (ISO date)',
                'history-after-filter',
                fieldWidth,
              ),
              _filterField(
                _beforeController,
                'Authored before (ISO date)',
                'history-before-filter',
                fieldWidth,
              ),
              TextButton(
                key: const Key('history-clear-filters'),
                onPressed: _clearFilters,
                child: const Text('Clear filters'),
              ),
            ],
          );
        },
      ),
    );
    final compactFilterHeight = (MediaQuery.sizeOf(context).height * 0.35)
        .clamp(120.0, 180.0);

    return ListTileTheme(
      dense: false,
      minVerticalPadding: 8,
      child: ExpansionTile(
        key: const Key('history-filters-toggle'),
        initiallyExpanded: false,
        title: LayoutBuilder(
          builder: (context, constraints) {
            final searchField = TextField(
              key: const Key('history-search'),
              controller: _searchController,
              focusNode: _searchFocusNode,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _applyFilters(),
              decoration: const InputDecoration(
                labelText: 'Search commits',
                hintText: 'Subject or body',
                isDense: true,
              ),
            );
            final searchButton = OutlinedButton.icon(
              key: const Key('history-apply-filters'),
              onPressed: _applyFilters,
              icon: const Icon(Icons.search, size: 18),
              label: const Text('Search'),
            );
            if (constraints.maxWidth < 360) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  searchField,
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerRight, child: searchButton),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: searchField),
                const SizedBox(width: 8),
                searchButton,
              ],
            );
          },
        ),
        children: [
          if (MediaQuery.sizeOf(context).height < 560)
            SizedBox(
              height: compactFilterHeight,
              child: SingleChildScrollView(child: filterFields),
            )
          else
            filterFields,
        ],
      ),
    );
  }

  Widget _filterField(
    TextEditingController controller,
    String label,
    String key,
    double width,
  ) {
    return SizedBox(
      width: width,
      child: TextField(
        key: Key(key),
        controller: controller,
        decoration: InputDecoration(labelText: label, isDense: true),
      ),
    );
  }

  void _applyFilters() {
    _controller.applyFilters(
      GitHistoryFilters(
        text: _searchController.text.trim(),
        author: _authorController.text.trim(),
        path: _pathController.text.trim(),
        ref: _refController.text.trim(),
        authoredAfter: DateTime.tryParse(_afterController.text.trim()),
        authoredBefore: DateTime.tryParse(_beforeController.text.trim()),
      ),
    );
  }

  void _clearFilters() {
    for (final controller in [
      _searchController,
      _authorController,
      _pathController,
      _refController,
      _afterController,
      _beforeController,
    ]) {
      controller.clear();
    }
    _applyFilters();
  }

  Widget _historyLayout(
    BuildContext context,
    GitHistoryPage page,
    HistoryState state,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 680) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: constraints.maxHeight * 0.45,
                child: _commitList(context, page, state),
              ),
              const Divider(height: 1),
              Expanded(child: _commitDetails(context, state)),
            ],
          );
        }
        final listWidth = constraints.maxWidth < 720 ? 320.0 : 400.0;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: listWidth,
              child: _commitList(context, page, state),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: _commitDetails(context, state)),
          ],
        );
      },
    );
  }

  Widget _commitList(
    BuildContext context,
    GitHistoryPage page,
    HistoryState state,
  ) {
    if (page.commits.isEmpty) {
      return const Center(child: Text('No commits yet.'));
    }
    final maxLaneCount = page.commits.fold<int>(
      1,
      (maximum, commit) =>
          commit.laneCount > maximum ? commit.laneCount : maximum,
    );
    // A fixed lane rhythm keeps the graph stable as branches appear and
    // disappear. Stretching the same lanes to fill the available gutter made
    // short histories look loose and wide histories look cramped.
    final graphWidth = (maxLaneCount * 16.0 + 24).clamp(48.0, 152.0);
    final extraRows = page.hasMore ? 1 : 0;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: page.commits.length + extraRows,
      itemBuilder: (context, index) {
        if (index == page.commits.length) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: OutlinedButton(
              onPressed: state.isLoadingMore ? null : _controller.loadMore,
              child: state.isLoadingMore
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Load more'),
            ),
          );
        }
        final commit = page.commits[index];
        final scheme = Theme.of(context).colorScheme;
        final selected = state.selectedOid == commit.oid;
        final rowSurface = selected
            ? scheme.surfaceContainerHighest
            : Theme.of(context).scaffoldBackgroundColor;
        return InkWell(
          key: ValueKey('commit:${commit.oid}'),
          onTap: () => _controller.selectCommit(commit),
          child: Container(
            constraints: const BoxConstraints(minHeight: 72),
            decoration: BoxDecoration(
              color: rowSurface,
              border: Border(
                bottom: BorderSide(
                  color: scheme.outline.withValues(alpha: 0.16),
                ),
                left: selected
                    ? BorderSide(color: scheme.primary, width: 2)
                    : BorderSide.none,
              ),
            ),
            padding: const EdgeInsets.only(right: 12),
            child: Row(
              children: [
                Semantics(
                  container: true,
                  explicitChildNodes: true,
                  image: true,
                  label:
                      'Commit graph · lane ${commit.lane + 1} of ${commit.laneCount}'
                      '${commit.parents.length > 1 ? ' · merge commit' : ''}',
                  child: SizedBox(
                    width: graphWidth,
                    height: 72,
                    child: CustomPaint(
                      key: ValueKey('graph:${commit.oid}'),
                      painter: _CommitGraphPainter(
                        lane: commit.lane,
                        laneCount: maxLaneCount,
                        segments: commit.graphSegments,
                        hasIncoming: commit.graphHasIncoming,
                        parentCount: commit.parents.length,
                        isSelected: selected,
                        colors: [
                          scheme.primary,
                          scheme.secondary,
                          scheme.tertiary,
                          scheme.error,
                        ],
                        surface: rowSurface,
                        outline: scheme.outline,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        commit.subject.isEmpty
                            ? '(no subject)'
                            : commit.subject,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${commit.authorName} · ${_formatDate(commit.authoredAt)} · ${commit.shortOid}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      if (commit.refs.isNotEmpty)
                        Text(
                          commit.refs.map((ref) => ref.shortName).join(', '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _commitDetails(BuildContext context, HistoryState state) {
    final commit = state.selectedCommit;
    if (commit == null) {
      return const Center(child: Text('Select a commit to inspect it.'));
    }
    final narrow = MediaQuery.sizeOf(context).width < 500;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        key: const Key('history-details-scroll'),
        padding: EdgeInsets.fromLTRB(
          narrow ? 16 : 20,
          20,
          narrow ? 16 : 20,
          24,
        ),
        child: SizedBox(
          width: constraints.hasBoundedWidth ? constraints.maxWidth : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                commit.subject.isEmpty ? '(no subject)' : commit.subject,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      commit.oid,
                      key: Key('oid:${commit.oid}'),
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(fontFamily: 'monospace'),
                    ),
                  ),
                  IconButton(
                    key: Key('copy-oid:${commit.oid}'),
                    tooltip: 'Copy commit ID',
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: commit.oid)),
                    icon: const Icon(Icons.copy, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${commit.authorName} <${commit.authorEmail}>',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                _formatDate(commit.authoredAt),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (commit.refs.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Refs'),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final ref in commit.refs)
                      Chip(label: Text('${ref.kind}: ${ref.shortName}')),
                  ],
                ),
              ],
              if (commit.parents.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Parents: ${commit.parents.length}'),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final parent in commit.parents)
                      OutlinedButton(
                        key: Key('parent:$parent'),
                        onPressed: () => _controller.selectParent(parent),
                        child: Text(parent.substring(0, 8)),
                      ),
                  ],
                ),
              ],
              if (commit.body.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 12),
                SelectableText(commit.body),
              ],
              const SizedBox(height: 20),
              Text(
                state.commitFiles == null
                    ? 'Changed files'
                    : 'Changed files (${state.commitFiles!.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (state.isLoadingCommitFiles)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: LinearProgressIndicator(),
                )
              else if (state.commitFilesError case final error?)
                Text(error.userMessage, key: const Key('commit-files-error'))
              else if (state.commitFiles == null)
                const Text('Commit files have not been loaded.')
              else if (state.commitFiles!.isEmpty)
                const Text('No changed files.')
              else
                for (final file in state.commitFiles!) ...[
                  _commitFileTile(context, file, state),
                  if (state.selectedPath == file.path) ...[
                    const SizedBox(height: 8),
                    KeyedSubtree(
                      key: _selectedDiffKey,
                      child: _selectedCommitFileDiff(context, state),
                    ),
                  ],
                ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _commitFileTile(
    BuildContext context,
    GitCommitFileChange file,
    HistoryState state,
  ) {
    final selected = state.selectedPath == file.path;
    return Card(
      key: Key('commit-file-section:${file.path}'),
      margin: EdgeInsets.zero,
      color: selected
          ? Theme.of(context).colorScheme.surfaceContainerHighest
          : null,
      child: ListTile(
        key: Key('commit-file:${file.path}'),
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
        leading: Text(file.statusLabel),
        title: Text(file.path, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: file.oldPath == null
            ? null
            : Text(
                'from ${file.oldPath}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
        trailing: Icon(
          selected ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
          size: 20,
        ),
        selected: selected,
        onTap: () =>
            selected ? _controller.clearFileSelection() : _selectFile(file),
      ),
    );
  }

  void _selectFile(GitCommitFileChange file) {
    _controller.selectFile(file);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _selectedDiffKey.currentContext;
      if (!mounted || context == null) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.12,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  Widget _selectedCommitFileDiff(BuildContext context, HistoryState state) {
    if (state.isLoadingCommitDiff) {
      return const Padding(
        key: Key('commit-diff-loading'),
        padding: EdgeInsets.symmetric(vertical: 16),
        child: LinearProgressIndicator(),
      );
    }
    if (state.commitDiffError case final error?) {
      return Text(error.userMessage, key: const Key('commit-diff-error'));
    }
    if (state.commitDiff?.isBinary == true) {
      return const Text(
        'Binary file changed; no text diff is available.',
        key: Key('commit-diff-binary'),
      );
    }
    if (state.commitDiff == null) {
      return const Text('Select a file to load its diff.');
    }
    if (state.commitDiff!.isEmpty) {
      return const Text(
        'No textual diff is available.',
        key: Key('commit-diff-empty'),
      );
    }
    return _historicalDiffCard(context, state.commitDiff!);
  }

  Widget _historicalDiffCard(BuildContext context, GitCommitDiff diff) {
    final scheme = Theme.of(context).colorScheme;
    final snapshot = diff.snapshot;
    final rawText = diff.lines.map((line) => line.text).join('\n');
    return Card(
      key: const Key('commit-diff'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: scheme.surfaceContainerHighest,
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                const Icon(Icons.description_outlined, size: 18),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Text(
                    snapshot.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (snapshot.oldPath != null && snapshot.newPath != null)
                  Text(
                    '${snapshot.oldPath} → ${snapshot.newPath}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                _diffCountBadge(
                  context,
                  '+${diff.additions}',
                  scheme.tertiaryContainer,
                  scheme.onTertiaryContainer,
                ),
                _diffCountBadge(
                  context,
                  '-${diff.deletions}',
                  scheme.errorContainer,
                  scheme.onErrorContainer,
                ),
                Tooltip(
                  message: 'Copy diff',
                  child: TextButton.icon(
                    key: const Key('copy-commit-diff'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: rawText)),
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copy diff'),
                  ),
                ),
              ],
            ),
          ),
          if (snapshot.patchHeader.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Text(
                snapshot.patchHeader.join('\n'),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontFamily: 'monospace',
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final viewportWidth = constraints.hasBoundedWidth
                    ? constraints.maxWidth
                    : MediaQuery.sizeOf(context).width;
                final contentMinWidth = (viewportWidth - 16).clamp(
                  0.0,
                  double.infinity,
                );
                return SelectionArea(
                  child: Scrollbar(
                    notificationPredicate: (notification) =>
                        notification.metrics.axis == Axis.horizontal,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: IgnorePointer(
                            child: ExcludeSemantics(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    for (
                                      var index = 0;
                                      index < diff.lines.length;
                                      index++
                                    )
                                      _historicalDiffBackgroundLine(
                                        context,
                                        diff.lines[index],
                                        index,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        SingleChildScrollView(
                          key: const Key('commit-diff-scroll'),
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minWidth: contentMinWidth,
                            ),
                            child: IntrinsicWidth(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (
                                    var index = 0;
                                    index < diff.lines.length;
                                    index++
                                  )
                                    _historicalDiffLine(
                                      context,
                                      diff.lines[index],
                                      index,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _diffCountBadge(
    BuildContext context,
    String label,
    Color background,
    Color foreground,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: foreground,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _historicalDiffBackgroundLine(
    BuildContext context,
    GitDiffLine line,
    int index,
  ) {
    return ColoredBox(
      key: Key('commit-diff-background:$index'),
      color: _historicalDiffBackgroundColor(context, line),
      child: const SizedBox(height: 20),
    );
  }

  Widget _historicalDiffLine(
    BuildContext context,
    GitDiffLine line,
    int index,
  ) {
    return SizedBox(
      height: 20,
      child: _historicalDiffLineContent(
        context,
        line,
        key: Key('commit-diff-line:$index'),
      ),
    );
  }

  Widget _historicalDiffLineContent(
    BuildContext context,
    GitDiffLine line, {
    Key? key,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = _historicalDiffForegroundColor(context, line);
    final marker = _historicalDiffMarker(line);
    return Row(
      key: key,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 42,
          child: Text(
            line.oldLineNumber?.toString() ?? '',
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontFamily: 'monospace',
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 42,
          child: Text(
            line.newLineNumber?.toString() ?? '',
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontFamily: 'monospace',
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 18,
          child: Text(
            marker,
            style: TextStyle(
              color: foreground,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          line.text,
          softWrap: false,
          style: TextStyle(color: foreground, fontFamily: 'monospace'),
        ),
      ],
    );
  }

  Color _historicalDiffBackgroundColor(BuildContext context, GitDiffLine line) {
    final scheme = Theme.of(context).colorScheme;
    return switch (line.kind) {
      GitDiffLineKind.addition => scheme.tertiaryContainer.withValues(
        alpha: 0.55,
      ),
      GitDiffLineKind.deletion => scheme.errorContainer.withValues(alpha: 0.65),
      GitDiffLineKind.hunkHeader => scheme.primaryContainer.withValues(
        alpha: 0.6,
      ),
      GitDiffLineKind.metadata ||
      GitDiffLineKind.noNewline => scheme.surfaceContainerHighest,
      GitDiffLineKind.context => Colors.transparent,
    };
  }

  Color _historicalDiffForegroundColor(BuildContext context, GitDiffLine line) {
    final scheme = Theme.of(context).colorScheme;
    return switch (line.kind) {
      GitDiffLineKind.addition => scheme.onTertiaryContainer,
      GitDiffLineKind.deletion => scheme.onErrorContainer,
      GitDiffLineKind.hunkHeader => scheme.onPrimaryContainer,
      GitDiffLineKind.metadata ||
      GitDiffLineKind.noNewline => scheme.onSurfaceVariant,
      GitDiffLineKind.context => scheme.onSurface,
    };
  }

  String _historicalDiffMarker(GitDiffLine line) => switch (line.kind) {
    GitDiffLineKind.addition => '+',
    GitDiffLineKind.deletion => '−',
    GitDiffLineKind.hunkHeader => '·',
    GitDiffLineKind.metadata => '·',
    GitDiffLineKind.noNewline => '·',
    GitDiffLineKind.context => ' ',
  };

  Widget _emptyError(GitError error) {
    return Center(
      child: Text(error.userMessage, key: const Key('history-error')),
    );
  }

  Widget _errorBanner(BuildContext context, GitError error) {
    return Container(
      key: const Key('history-error-banner'),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: Theme.of(context).colorScheme.errorContainer,
      child: Text(
        error.userMessage,
        style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
      ),
    );
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _openHistoryRollback(BuildContext context) async {
    final result = await showDialog<GitHistoryRollbackResult>(
      context: context,
      builder: (_) =>
          ResetDialog(gateway: widget.gateway, repository: widget.repository),
    );
    if (!context.mounted || result == null) return;
    await _controller.refresh();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(result.summary)));
  }

  Future<void> _openInteractiveRebase(BuildContext context) async {
    final result = await showDialog<GitInteractiveRebaseResult>(
      context: context,
      builder: (_) => InteractiveRebaseDialog(
        gateway: widget.gateway,
        repository: widget.repository,
      ),
    );
    if (!context.mounted || result == null) return;
    await _controller.refresh();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(result.summary)));
  }
}

class _CommitGraphPainter extends CustomPainter {
  const _CommitGraphPainter({
    required this.lane,
    required this.laneCount,
    required this.segments,
    required this.hasIncoming,
    required this.parentCount,
    required this.isSelected,
    required this.colors,
    required this.surface,
    required this.outline,
  });

  final int lane;
  final int laneCount;
  final List<GitGraphSegment> segments;
  final bool hasIncoming;
  final int parentCount;
  final bool isSelected;
  final List<Color> colors;
  final Color surface;
  final Color outline;

  double _laneX(int value, Size size) {
    return (20.0 + value * 16.0).clamp(10.0, size.width - 10.0);
  }

  void _drawDottedLine(
    Canvas canvas,
    Offset start,
    Offset end,
    Color color, {
    double dotSize = 3,
  }) {
    final delta = end - start;
    final distance = delta.distance;
    final steps = (distance / 4).ceil().clamp(1, 1000);
    final paint = Paint()
      ..color = color
      ..isAntiAlias = false
      ..style = PaintingStyle.fill;
    for (var index = 0; index <= steps; index++) {
      final progress = index / steps;
      final point = start + delta * progress;
      final snapped = Offset(
        point.dx.roundToDouble(),
        point.dy.roundToDouble(),
      );
      canvas.drawRect(
        Rect.fromCenter(center: snapped, width: dotSize, height: dotSize),
        paint,
      );
    }
  }

  void _drawSegment(
    Canvas canvas,
    Offset start,
    Offset end,
    Color color, {
    required bool changesLane,
  }) {
    if (!changesLane) {
      _drawDottedLine(canvas, start, end, color);
      return;
    }

    // Lane changes use a short diagonal staircase between two vertical runs.
    // Keeping the bend away from the row edges makes adjacent rows join
    // cleanly while the branch split or merge remains unmistakable.
    final direction = end.dy >= start.dy ? 1.0 : -1.0;
    final bendStart = Offset(start.dx, start.dy + 8 * direction);
    final bendEnd = Offset(end.dx, end.dy - 8 * direction);
    _drawDottedLine(canvas, start, bendStart, color);
    _drawDottedLine(canvas, bendStart, bendEnd, color);
    _drawDottedLine(canvas, bendEnd, end, color);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final middle = size.height / 2;
    for (final segment in segments) {
      final from = _laneX(segment.fromLane, size);
      final to = _laneX(segment.toLane, size);
      final startsAtNode = segment.fromLane == lane;
      final colorLane = startsAtNode && segment.fromLane != segment.toLane
          ? segment.toLane
          : segment.fromLane;
      final color = colors[colorLane % colors.length];
      final start = Offset(from, startsAtNode ? middle : 0);
      final end = Offset(to, size.height);
      _drawSegment(canvas, start, end, color, changesLane: from != to);
    }
    final nodeColor = colors[lane % colors.length];
    final center = Offset(_laneX(lane, size), middle);
    if (hasIncoming) {
      _drawDottedLine(canvas, Offset(center.dx, 0), center, nodeColor);
    }
    if (isSelected) {
      final haloSize = parentCount > 1 ? 22.0 : 18.0;
      canvas.drawRect(
        Rect.fromCenter(center: center, width: haloSize, height: haloSize),
        Paint()
          ..color = nodeColor.withValues(alpha: 0.16)
          ..isAntiAlias = false,
      );
    }
    final outerSize = parentCount > 1 ? 14.0 : 10.0;
    canvas.drawRect(
      Rect.fromCenter(center: center, width: outerSize, height: outerSize),
      Paint()
        ..color = surface
        ..style = PaintingStyle.fill
        ..isAntiAlias = false,
    );
    canvas.drawRect(
      Rect.fromCenter(center: center, width: outerSize, height: outerSize),
      Paint()
        ..color = nodeColor
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..isAntiAlias = false,
    );
    canvas.drawRect(
      Rect.fromCenter(
        center: center,
        width: parentCount > 1 ? 6 : 4,
        height: parentCount > 1 ? 6 : 4,
      ),
      Paint()
        ..color = nodeColor
        ..isAntiAlias = false,
    );
    if (parentCount > 1) {
      canvas.drawRect(
        Rect.fromCenter(center: center, width: 18, height: 18),
        Paint()
          ..color = outline.withValues(alpha: 0.34)
          ..strokeWidth = 1
          ..style = PaintingStyle.stroke
          ..isAntiAlias = false,
      );
    }
  }

  @override
  bool shouldRepaint(_CommitGraphPainter oldDelegate) =>
      oldDelegate.lane != lane ||
      oldDelegate.laneCount != laneCount ||
      oldDelegate.segments != segments ||
      oldDelegate.hasIncoming != hasIncoming ||
      oldDelegate.parentCount != parentCount ||
      oldDelegate.isSelected != isSelected ||
      oldDelegate.colors != colors ||
      oldDelegate.surface != surface ||
      oldDelegate.outline != outline;
}

String _formatDate(DateTime date) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)} '
      '${two(date.hour)}:${two(date.minute)}';
}
