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
      final paint = Paint()
        ..color = colors[colorLane % colors.length].withValues(alpha: 0.88)
        ..strokeWidth = 2.25
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke;
      final path = Path();
      if (from == to) {
        path
          ..moveTo(from, startsAtNode ? middle : 0)
          ..lineTo(to, size.height);
      } else if (startsAtNode) {
        path
          ..moveTo(from, middle)
          ..cubicTo(from, middle + 9, to, middle + 9, to, size.height);
      } else {
        path
          ..moveTo(from, 0)
          ..lineTo(from, middle - 9)
          ..cubicTo(from, middle - 2, to, middle + 2, to, middle + 9)
          ..lineTo(to, size.height);
      }
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
          ..strokeWidth = 2.25
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true,
      );
    }
    if (isSelected) {
      canvas.drawCircle(
        center,
        parentCount > 1 ? 10 : 9,
        Paint()
          ..color = nodeColor.withValues(alpha: 0.16)
          ..isAntiAlias = true,
      );
    }
    final outerRadius = parentCount > 1 ? 7.0 : 6.0;
    canvas.drawCircle(
      center,
      outerRadius,
      Paint()
        ..color = surface
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );
    canvas.drawCircle(
      center,
      outerRadius,
      Paint()
        ..color = nodeColor
        ..strokeWidth = parentCount > 1 ? 2.5 : 2.25
        ..style = PaintingStyle.stroke
        ..isAntiAlias = true,
    );
    canvas.drawCircle(
      center,
      parentCount > 1 ? 3.0 : 2.75,
      Paint()
        ..color = nodeColor
        ..isAntiAlias = true,
    );
    if (parentCount > 1) {
      canvas.drawCircle(
        center,
        9,
        Paint()
          ..color = outline.withValues(alpha: 0.34)
          ..strokeWidth = 1
          ..style = PaintingStyle.stroke
          ..isAntiAlias = true,
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
