import 'dart:async';

import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/error.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:gift/src/backend/history.dart';
import 'package:gift/src/features/repository/history_controller.dart';
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
          const PixelThemeToggle(),
          IconButton(
            tooltip: 'Refresh history',
            onPressed: state.isLoading ? null : _controller.refresh,
            icon: const Icon(Icons.refresh),
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

  Widget _filtersPanel(BuildContext context) {
    return ExpansionTile(
      key: const Key('history-filters-toggle'),
      initiallyExpanded: false,
      title: Row(
        children: [
          Expanded(
            child: TextField(
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
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            key: const Key('history-apply-filters'),
            onPressed: _applyFilters,
            child: const Text('Apply'),
          ),
        ],
      ),
      children: [
        Padding(
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
        ),
      ],
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
    final graphWidth = (maxLaneCount * 14.0 + 20).clamp(42.0, 180.0);
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
        return InkWell(
          key: ValueKey('commit:${commit.oid}'),
          onTap: () => _controller.selectCommit(commit),
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            color: state.selectedOid == commit.oid
                ? scheme.surfaceContainerHighest
                : null,
            padding: const EdgeInsets.only(right: 12),
            child: Row(
              children: [
                SizedBox(
                  width: graphWidth,
                  height: 64,
                  child: CustomPaint(
                    key: ValueKey('graph:${commit.oid}'),
                    painter: _CommitGraphPainter(
                      lane: commit.lane,
                      laneCount: maxLaneCount,
                      segments: commit.graphSegments,
                      hasIncoming: commit.graphHasIncoming,
                      colors: [
                        scheme.primary,
                        scheme.secondary,
                        scheme.tertiary,
                        scheme.error,
                      ],
                      background: Theme.of(context).scaffoldBackgroundColor,
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
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(narrow ? 16 : 20, 20, narrow ? 16 : 20, 24),
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
          Text('Changed files', style: Theme.of(context).textTheme.titleMedium),
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
            for (final file in state.commitFiles!)
              ListTile(
                key: Key('commit-file:${file.path}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Text(file.statusLabel),
                title: Text(file.path),
                subtitle: file.oldPath == null
                    ? null
                    : Text('from ${file.oldPath}'),
                onTap: () => _controller.selectFile(file),
              ),
          if (state.selectedPath != null) ...[
            const SizedBox(height: 12),
            Text(
              'Diff: ${state.selectedPath}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (state.isLoadingCommitDiff)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: LinearProgressIndicator(),
              )
            else if (state.commitDiffError case final error?)
              Text(error.userMessage, key: const Key('commit-diff-error'))
            else if (state.commitDiff?.isBinary == true)
              const Text('Binary file changed; no text diff is available.')
            else if (state.commitDiff == null)
              const Text('Select a file to load its diff.')
            else if (state.commitDiff!.isEmpty)
              const Text('No textual diff is available.')
            else
              Container(
                key: const Key('commit-diff'),
                width: double.infinity,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                padding: const EdgeInsets.all(10),
                child: SelectableText(
                  state.commitDiff!.lines.map((line) => line.text).join('\n'),
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
          ],
        ],
      ),
    );
  }

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
}

class _CommitGraphPainter extends CustomPainter {
  const _CommitGraphPainter({
    required this.lane,
    required this.laneCount,
    required this.segments,
    required this.hasIncoming,
    required this.colors,
    required this.background,
  });

  final int lane;
  final int laneCount;
  final List<GitGraphSegment> segments;
  final bool hasIncoming;
  final List<Color> colors;
  final Color background;

  double _laneX(int value, Size size) {
    if (laneCount <= 1) return size.width / 2;
    final spacing = ((size.width - 20) / (laneCount - 1)).clamp(3.0, 14.0);
    return 10 + value * spacing;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final middle = size.height / 2;
    for (final segment in segments) {
      final from = _laneX(segment.fromLane, size);
      final to = _laneX(segment.toLane, size);
      final paint = Paint()
        ..color = colors[segment.fromLane % colors.length]
        ..strokeWidth = 2
        ..isAntiAlias = false
        ..style = PaintingStyle.stroke;
      final startsAtNode = segment.fromLane == lane;
      final path = Path()
        ..moveTo(from, startsAtNode ? middle : 0)
        ..lineTo(from, startsAtNode ? middle : middle - 5)
        ..lineTo(to, middle + 5)
        ..lineTo(to, size.height);
      canvas.drawPath(path, paint);
    }
    final nodeColor = colors[lane % colors.length];
    final center = Offset(_laneX(lane, size), middle);
    if (hasIncoming) {
      canvas.drawLine(
        Offset(center.dx, 0),
        center,
        Paint()
          ..color = nodeColor
          ..strokeWidth = 2
          ..isAntiAlias = false,
      );
    }
    canvas.drawRect(
      Rect.fromCenter(center: center, width: 10, height: 10),
      Paint()
        ..color = background
        ..isAntiAlias = false,
    );
    canvas.drawRect(
      Rect.fromCenter(center: center, width: 8, height: 8),
      Paint()
        ..color = nodeColor
        ..isAntiAlias = false,
    );
  }

  @override
  bool shouldRepaint(_CommitGraphPainter oldDelegate) =>
      oldDelegate.lane != lane ||
      oldDelegate.laneCount != laneCount ||
      oldDelegate.segments != segments ||
      oldDelegate.hasIncoming != hasIncoming ||
      oldDelegate.colors != colors ||
      oldDelegate.background != background;
}

String _formatDate(DateTime date) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)} '
      '${two(date.hour)}:${two(date.minute)}';
}
