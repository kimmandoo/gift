import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/error.dart';
import 'package:gift/src/backend/file_history.dart';
import 'package:gift/src/backend/git_gateway.dart';

/// Shows path-scoped history and blame without replacing the global graph.
class FileHistoryDialog extends StatefulWidget {
  const FileHistoryDialog({
    super.key,
    required this.gateway,
    required this.repository,
    this.initialPath = '',
  });

  final GitGateway gateway;
  final RepositoryOpened repository;
  final String initialPath;

  @override
  State<FileHistoryDialog> createState() => _FileHistoryDialogState();
}

class _FileHistoryDialogState extends State<FileHistoryDialog> {
  late final TextEditingController _path;
  late final TextEditingController _lineStart;
  late final TextEditingController _lineEnd;
  GitFileHistorySnapshot? _history;
  GitBlameSnapshot? _blame;
  GitError? _error;
  String? _message;
  var _loading = false;
  var _blameMode = false;
  var _follow = true;
  var _directoryMode = false;
  var _ignoreWhitespace = false;
  var _detectMoves = false;
  var _detectCopies = false;

  @override
  void initState() {
    super.initState();
    _path = TextEditingController(text: widget.initialPath);
    _lineStart = TextEditingController();
    _lineEnd = TextEditingController();
  }

  @override
  void dispose() {
    _path.dispose();
    _lineStart.dispose();
    _lineEnd.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 560;
    final width = (size.width - (compact ? 28 : 80)).clamp(0.0, 720.0);
    return AlertDialog(
      key: const Key('file-history-dialog'),
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 14 : 40,
        vertical: 22,
      ),
      title: const Text('File history & blame'),
      content: SizedBox(
        width: width,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: size.height * .74),
          child: SingleChildScrollView(
            key: const Key('file-history-dialog-scroll'),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _pathControls(context, compact),
                if (_error case final error?)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      error.userMessage,
                      key: const Key('file-history-error'),
                    ),
                  ),
                if (_message case final message?)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      message,
                      key: const Key('file-history-message'),
                    ),
                  ),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(),
                  )
                else
                  _content(context),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _pathControls(BuildContext context, bool compact) {
    final pathField = TextField(
      key: const Key('file-history-path'),
      controller: _path,
      enabled: !_loading,
      decoration: const InputDecoration(
        labelText: 'File or directory path',
        border: OutlineInputBorder(),
      ),
      onSubmitted: (_) => unawaited(_loadHistory()),
    );
    final loadButton = FilledButton.icon(
      key: const Key('load-file-history'),
      onPressed: _loading ? null : () => unawaited(_loadHistory()),
      icon: const Icon(Icons.history, size: 18),
      label: const Text('Load history'),
    );
    final blameButton = OutlinedButton.icon(
      key: const Key('load-file-blame'),
      onPressed: _loading ? null : () => unawaited(_loadBlame()),
      icon: const Icon(Icons.person_search_outlined, size: 18),
      label: const Text('Load blame'),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackControls = compact || constraints.maxWidth < 560;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (stackControls)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  pathField,
                  const SizedBox(height: 8),
                  loadButton,
                  const SizedBox(height: 4),
                  blameButton,
                ],
              )
            else
              Row(
                children: [
                  Expanded(child: pathField),
                  const SizedBox(width: 8),
                  loadButton,
                  const SizedBox(width: 6),
                  blameButton,
                ],
              ),
            Wrap(
              spacing: 4,
              runSpacing: 0,
              children: [
                FilterChip(
                  key: const Key('file-history-follow'),
                  label: const Text('Follow renames'),
                  selected: _follow && !_directoryMode,
                  onSelected: _directoryMode || _loading
                      ? null
                      : (value) => setState(() => _follow = value),
                ),
                FilterChip(
                  key: const Key('file-history-directory'),
                  label: const Text('Directory'),
                  selected: _directoryMode,
                  onSelected: _loading
                      ? null
                      : (value) => setState(() => _directoryMode = value),
                ),
                if (!_blameMode)
                  TextButton.icon(
                    key: const Key('file-history-lines-toggle'),
                    onPressed: _loading ? null : _showLineRange,
                    icon: const Icon(Icons.format_list_numbered, size: 18),
                    label: const Text('Line range'),
                  ),
              ],
            ),
            if (!_blameMode &&
                (_lineStart.text.isNotEmpty || _lineEnd.text.isNotEmpty))
              Row(
                children: [
                  Expanded(
                    child: _lineField(
                      _lineStart,
                      'Start line',
                      'file-history-line-start',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _lineField(
                      _lineEnd,
                      'End line',
                      'file-history-line-end',
                    ),
                  ),
                ],
              ),
            if (_blameMode)
              Wrap(
                spacing: 4,
                children: [
                  FilterChip(
                    key: const Key('blame-ignore-whitespace'),
                    label: const Text('Ignore whitespace'),
                    selected: _ignoreWhitespace,
                    onSelected: _loading
                        ? null
                        : (value) => setState(() => _ignoreWhitespace = value),
                  ),
                  FilterChip(
                    key: const Key('blame-detect-moves'),
                    label: const Text('Detect moves'),
                    selected: _detectMoves,
                    onSelected: _loading
                        ? null
                        : (value) => setState(() => _detectMoves = value),
                  ),
                  FilterChip(
                    key: const Key('blame-detect-copies'),
                    label: const Text('Detect copies'),
                    selected: _detectCopies,
                    onSelected: _loading
                        ? null
                        : (value) => setState(() => _detectCopies = value),
                  ),
                ],
              ),
          ],
        );
      },
    );
  }

  Widget _lineField(
    TextEditingController controller,
    String label,
    String key,
  ) => TextField(
    key: Key(key),
    controller: controller,
    keyboardType: TextInputType.number,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
  );

  Widget _content(BuildContext context) {
    if (_blameMode && _blame != null) return _blameList(context, _blame!);
    final history = _history;
    if (history == null) {
      return const Center(child: Text('Enter a path to inspect its history.'));
    }
    if (history.entries.isEmpty) {
      return const Center(
        child: Text('No revisions were found for this path.'),
      );
    }
    return ListView.builder(
      key: const Key('file-history-list'),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: history.entries.length,
      itemBuilder: (context, index) =>
          _historyTile(context, history.entries[index]),
    );
  }

  Widget _historyTile(
    BuildContext context,
    GitFileHistoryEntry entry,
  ) => ListTile(
    key: ValueKey('file-history-entry:${entry.oid}'),
    dense: true,
    title: Text(entry.subject, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text(
      '${entry.commit.shortOid} · ${entry.authorName}'
      '${entry.originalPath == null ? '' : ' · renamed from ${entry.originalPath}'}',
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
    trailing: TextButton(
      key: ValueKey('get-from-revision:${entry.oid}'),
      onPressed: _loading ? null : () => unawaited(_getFromRevision(entry)),
      child: const Text('Restore'),
    ),
  );

  Widget _blameList(BuildContext context, GitBlameSnapshot blame) {
    if (blame.lines.isEmpty) {
      return const Center(child: Text('No blame lines were found.'));
    }
    return ListView.builder(
      key: const Key('blame-list'),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: blame.lines.length,
      itemBuilder: (context, index) {
        final line = blame.lines[index];
        return ListTile(
          key: ValueKey('blame-line:${line.lineNumber}'),
          dense: true,
          leading: SizedBox(width: 32, child: Text('${line.lineNumber}')),
          title: Text(line.text, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${line.commitOid.length > 8 ? line.commitOid.substring(0, 8) : line.commitOid} · ${line.authorName}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }

  void _showLineRange() {
    setState(() {
      if (_lineStart.text.isEmpty) _lineStart.text = '1';
      if (_lineEnd.text.isEmpty) _lineEnd.text = _lineStart.text;
    });
  }

  Future<void> _loadHistory() async {
    final path = _path.text.trim();
    if (path.isEmpty) return;
    final start = int.tryParse(_lineStart.text);
    final end = int.tryParse(_lineEnd.text);
    setState(() {
      _loading = true;
      _error = null;
      _message = null;
      _blameMode = false;
    });
    try {
      final history = await widget.gateway.getFileHistory(
        widget.repository.repositoryId,
        GitFileHistoryQuery(
          path: path,
          follow: _directoryMode ? false : _follow,
          scope: _directoryMode
              ? GitFileHistoryScope.directory
              : start == null
              ? GitFileHistoryScope.file
              : GitFileHistoryScope.selection,
          lineStart: start,
          lineEnd: end,
        ),
      );
      if (!mounted) return;
      setState(() {
        _history = history;
        _loading = false;
      });
    } on GitError catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadBlame() async {
    final path = _path.text.trim();
    if (path.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _message = null;
      _blameMode = true;
    });
    try {
      final blame = await widget.gateway.getBlame(
        widget.repository.repositoryId,
        path,
        options: GitBlameOptions(
          ignoreWhitespace: _ignoreWhitespace,
          detectMoves: _detectMoves,
          detectCopies: _detectCopies,
        ),
      );
      if (!mounted) return;
      setState(() {
        _blame = blame;
        _loading = false;
      });
    } on GitError catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  Future<void> _getFromRevision(GitFileHistoryEntry entry) async {
    final history = _history;
    if (history == null) return;
    setState(() {
      _loading = true;
      _error = null;
      _message = null;
    });
    try {
      final result = await widget.gateway.getFileFromRevision(
        widget.repository.repositoryId,
        history,
        entry.oid,
      );
      if (mounted) {
        setState(() {
          _message = result.summary;
          _loading = false;
        });
      }
    } on GitError catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }
}
