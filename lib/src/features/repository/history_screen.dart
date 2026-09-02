import 'dart:async';

import 'package:branchline/src/backend/domain.dart';
import 'package:branchline/src/backend/error.dart';
import 'package:branchline/src/backend/git_gateway.dart';
import 'package:branchline/src/backend/history.dart';
import 'package:branchline/src/features/repository/history_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    if (widget.autoInitialize) {
      Future<void>.microtask(_controller.start);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    if (_ownsController) _controller.dispose();
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
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        actions: [
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: const Text('Ctrl+R refresh · Esc back'),
              ),
          ],
        ),
      ),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyR, control: true):
            _controller.refresh,
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Focus(autofocus: true, child: scaffold),
    );
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
              Expanded(child: _commitDetails(context, state.selectedCommit)),
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
            Expanded(child: _commitDetails(context, state.selectedCommit)),
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
        return ListTile(
          key: ValueKey('commit:${commit.oid}'),
          selected: state.selectedOid == commit.oid,
          leading: SizedBox(
            width: 28,
            height: 44,
            child: CustomPaint(
              painter: _CommitGraphPainter(
                lane: commit.lane,
                laneCount: commit.laneCount,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          title: Text(
            commit.subject.isEmpty ? '(no subject)' : commit.subject,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${commit.authorName} · ${_formatDate(commit.authoredAt)} · ${commit.shortOid}',
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _controller.selectCommit(commit),
        );
      },
    );
  }

  Widget _commitDetails(BuildContext context, GitCommit? commit) {
    if (commit == null) {
      return const Center(child: Text('Select a commit to inspect it.'));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            commit.subject,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          SelectableText(
            commit.oid,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
          const SizedBox(height: 8),
          Text('${commit.authorName} <${commit.authorEmail}>'),
          Text(_formatDate(commit.authoredAt)),
          if (commit.parents.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Parents: ${commit.parents.length}'),
            SelectableText(commit.parents.join('\n')),
          ],
          if (commit.body.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),
            SelectableText(commit.body),
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
      child: Text(error.userMessage),
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
    required this.color,
  });

  final int lane;
  final int laneCount;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final x = 8.0 + lane.clamp(0, laneCount - 1) * 8;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    canvas.drawCircle(
      Offset(x, size.height / 2),
      5,
      paint..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_CommitGraphPainter oldDelegate) =>
      oldDelegate.lane != lane ||
      oldDelegate.laneCount != laneCount ||
      oldDelegate.color != color;
}

String _formatDate(DateTime date) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)} '
      '${two(date.hour)}:${two(date.minute)}';
}
