import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gift/src/backend/comparison.dart';
import 'package:gift/src/backend/diff.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/error.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:flutter/services.dart';

/// A bounded revision comparison workspace.
///
/// The file list and individual diff are separate requests so a large
/// comparison does not force the UI to load every patch at once.
class ComparisonDialog extends StatefulWidget {
  const ComparisonDialog({
    super.key,
    required this.gateway,
    required this.repository,
  });

  final GitGateway gateway;
  final RepositoryOpened repository;

  @override
  State<ComparisonDialog> createState() => _ComparisonDialogState();
}

class _ComparisonDialogState extends State<ComparisonDialog> {
  final _leftController = TextEditingController(text: 'HEAD~1');
  final _rightController = TextEditingController(text: 'HEAD');
  final _pathController = TextEditingController();
  final _externalTextController = TextEditingController();
  GitComparisonSnapshot? _comparison;
  GitDiffSnapshot? _diff;
  String? _selectedPath;
  GitError? _error;
  var _busy = false;
  var _requestNumber = 0;
  var _externalMode = false;
  var _externalSourceKind = GitComparisonSourceKind.text;

  @override
  void initState() {
    super.initState();
    unawaited(_compare());
  }

  @override
  void dispose() {
    _leftController.dispose();
    _rightController.dispose();
    _pathController.dispose();
    _externalTextController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 640;
    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 32,
        vertical: 20,
      ),
      title: Row(
        children: [
          const Expanded(child: Text('Compare revisions')),
          TextButton(
            key: const Key('comparison-source-mode'),
            onPressed: _busy ? null : _toggleExternalMode,
            child: Text(_externalMode ? 'External' : 'Revisions'),
          ),
          if (_externalMode)
            IconButton(
              key: const Key('comparison-paste-clipboard'),
              tooltip: 'Paste clipboard',
              onPressed: _busy ? null : _pasteClipboard,
              icon: const Icon(Icons.content_paste),
            ),
          if (_busy)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
      content: SizedBox(
        width: (size.width - (compact ? 24 : 64)).clamp(280.0, 1080.0),
        height: (size.height - 150).clamp(340.0, 720.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _comparisonControls(context),
            if (_error case final error?) ...[
              const SizedBox(height: 8),
              _errorBanner(error),
            ],
            const SizedBox(height: 12),
            Expanded(child: _comparisonBody(context, compact: compact)),
          ],
        ),
      ),
      actions: [
        if (_diff != null) ...[
          TextButton.icon(
            key: const Key('apply-comparison'),
            onPressed: _busy
                ? null
                : () => _transfer(GitComparisonTransferAction.apply),
            icon: const Icon(Icons.input),
            label: const Text('Apply'),
          ),
          TextButton.icon(
            key: const Key('revert-comparison'),
            onPressed: _busy
                ? null
                : () => _transfer(GitComparisonTransferAction.revert),
            icon: const Icon(Icons.undo),
            label: const Text('Revert'),
          ),
        ],
        TextButton(
          key: const Key('close-comparison-dialog'),
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _comparisonControls(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final leftField = TextField(
          key: const Key('comparison-left'),
          controller: _leftController,
          enabled: !_busy,
          decoration: const InputDecoration(
            labelText: 'Left revision',
            hintText: 'HEAD~1, branch, or tag',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _compare(),
        );
        final rightField = _externalMode
            ? TextField(
                key: const Key('comparison-external-text'),
                controller: _externalTextController,
                enabled: !_busy,
                minLines: 2,
                maxLines: 4,
                maxLength: maxComparisonTextBytes,
                decoration: const InputDecoration(
                  labelText: 'External text',
                  hintText: 'Paste text to compare with the left revision',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) {
                  if (_externalSourceKind != GitComparisonSourceKind.text) {
                    setState(() {
                      _externalSourceKind = GitComparisonSourceKind.text;
                    });
                  }
                },
                onSubmitted: (_) => _compare(),
              )
            : TextField(
                key: const Key('comparison-right'),
                controller: _rightController,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'Right revision',
                  hintText: 'HEAD, branch, or tag',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _compare(),
              );
        final path = TextField(
          key: const Key('comparison-path'),
          controller: _pathController,
          enabled: !_busy,
          decoration: const InputDecoration(
            labelText: 'Folder (optional)',
            hintText: 'src/',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _compare(),
        );
        final compareButton = FilledButton.icon(
          key: const Key('compare-revisions'),
          onPressed: _busy ? null : _compare,
          icon: const Icon(Icons.compare_arrows),
          label: const Text('Compare'),
        );
        if (constraints.maxWidth < 620) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: leftField),
                  const SizedBox(width: 8),
                  Expanded(child: rightField),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: path),
                  const SizedBox(width: 8),
                  compareButton,
                ],
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: leftField),
            const SizedBox(width: 8),
            Expanded(child: rightField),
            const SizedBox(width: 8),
            Expanded(child: path),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: compareButton,
            ),
          ],
        );
      },
    );
  }

  Widget _comparisonBody(BuildContext context, {required bool compact}) {
    final comparison = _comparison;
    if (comparison == null) {
      return _busy
          ? const Center(child: CircularProgressIndicator())
          : const Center(child: Text('Enter two revisions to compare.'));
    }
    if (comparison.files.isEmpty) {
      return Center(
        child: Text(
          'No differences between ${comparison.request.left.displayName} '
          'and ${comparison.request.right.displayName}.',
          textAlign: TextAlign.center,
        ),
      );
    }
    final fileList = _fileList(context, comparison);
    final diffPane = _diffPane(context);
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 64, child: fileList),
          const SizedBox(height: 6),
          Expanded(child: diffPane),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 300, child: fileList),
        const VerticalDivider(width: 16),
        Expanded(child: diffPane),
      ],
    );
  }

  Widget _fileList(BuildContext context, GitComparisonSnapshot comparison) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListView.separated(
        key: const Key('comparison-file-list'),
        itemCount: comparison.files.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final file = comparison.files[index];
          final selected = file.path == _selectedPath;
          return ListTile(
            key: Key('comparison-file-${file.path}'),
            dense: true,
            selected: selected,
            onTap: _busy ? null : () => _selectFile(file.path),
            leading: CircleAvatar(radius: 14, child: Text(file.statusLabel)),
            title: Text(file.path, overflow: TextOverflow.ellipsis),
            subtitle: file.oldPath == null
                ? null
                : Text('from ${file.oldPath}', overflow: TextOverflow.ellipsis),
          );
        },
      ),
    );
  }

  Widget _diffPane(BuildContext context) {
    final diff = _diff;
    if (diff == null) {
      return Card(
        margin: EdgeInsets.zero,
        child: Center(
          child: _busy
              ? const CircularProgressIndicator()
              : const Text('Select a changed file.'),
        ),
      );
    }
    if (diff.isBinary) {
      return Card(
        margin: EdgeInsets.zero,
        child: Center(child: Text('${diff.path} is a binary file.')),
      );
    }
    if (diff.isOversized) {
      return Card(
        margin: EdgeInsets.zero,
        child: Center(child: Text('${diff.path} is too large to display.')),
      );
    }
    if (diff.isMissing) {
      return Card(
        margin: EdgeInsets.zero,
        child: Center(child: Text('${diff.path} is not available as text.')),
      );
    }
    if (diff.lines.isEmpty) {
      return Card(
        margin: EdgeInsets.zero,
        child: Center(child: Text('No text diff for ${diff.path}.')),
      );
    }
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          if (_comparison != null)
            SizedBox(
              height: 32,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'File: ${_selectedPath ?? ''}',
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                    SizedBox.square(
                      dimension: 32,
                      child: IconButton(
                        key: const Key('comparison-previous-file'),
                        tooltip: 'Previous changed file',
                        onPressed: _canMoveFile(-1)
                            ? () => unawaited(_moveFile(-1))
                            : null,
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.chevron_left),
                      ),
                    ),
                    SizedBox.square(
                      dimension: 32,
                      child: IconButton(
                        key: const Key('comparison-next-file'),
                        tooltip: 'Next changed file',
                        onPressed: _canMoveFile(1)
                            ? () => unawaited(_moveFile(1))
                            : null,
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: SelectionArea(
              child: ListView.builder(
                key: const Key('comparison-diff-lines'),
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: diff.lines.length,
                itemBuilder: (context, index) {
                  final line = diff.lines[index];
                  final color = switch (line.kind) {
                    GitDiffLineKind.addition => Colors.green.withValues(
                      alpha: .14,
                    ),
                    GitDiffLineKind.deletion => Colors.red.withValues(
                      alpha: .14,
                    ),
                    GitDiffLineKind.hunkHeader => Theme.of(
                      context,
                    ).colorScheme.primaryContainer,
                    _ => null,
                  };
                  return Container(
                    width: double.infinity,
                    color: color,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 2,
                    ),
                    child: Text(
                      line.text,
                      softWrap: true,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorBanner(GitError error) {
    return Container(
      key: const Key('comparison-error'),
      padding: const EdgeInsets.all(10),
      color: Theme.of(context).colorScheme.errorContainer,
      child: Row(
        children: [
          Expanded(child: Text(error.userMessage)),
          if (error.retryable)
            TextButton(onPressed: _compare, child: const Text('Refresh')),
        ],
      ),
    );
  }

  Future<void> _compare() async {
    final left = _leftController.text.trim();
    final right = _rightController.text.trim();
    final externalText = _externalTextController.text;
    final path = _pathController.text.trim();
    final requestNumber = ++_requestNumber;
    setState(() {
      _busy = true;
      _error = null;
      _comparison = null;
      _diff = null;
      _selectedPath = null;
    });
    try {
      final comparison = _externalMode
          ? await widget.gateway.compareSources(
              widget.repository.repositoryId,
              GitComparisonSource.revision(left),
              _externalSourceKind == GitComparisonSourceKind.clipboard
                  ? GitComparisonSource.clipboard(externalText)
                  : GitComparisonSource.text(externalText),
              path: path.isEmpty ? null : path,
            )
          : await widget.gateway.compareRevisions(
              widget.repository.repositoryId,
              left,
              right,
              path: path.isEmpty ? null : path,
            );
      if (!mounted || requestNumber != _requestNumber) return;
      setState(() {
        _comparison = comparison;
        _busy = false;
      });
      final first = comparison.files.firstOrNull;
      if (first != null) {
        await _selectFile(first.path, requestNumber: requestNumber);
      }
    } on GitError catch (error) {
      if (!mounted || requestNumber != _requestNumber) return;
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  Future<void> _pasteClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (!mounted || text == null) return;
    setState(() {
      _externalTextController.text = text;
      _externalTextController.selection = TextSelection.collapsed(
        offset: text.length,
      );
      _externalSourceKind = GitComparisonSourceKind.clipboard;
    });
  }

  void _toggleExternalMode() {
    setState(() {
      _externalMode = !_externalMode;
      _comparison = null;
      _diff = null;
      _selectedPath = null;
    });
  }

  bool _canMoveFile(int delta) {
    final comparison = _comparison;
    final selectedPath = _selectedPath;
    if (comparison == null || selectedPath == null) return false;
    final index = comparison.files.indexWhere(
      (file) => file.path == selectedPath,
    );
    return index >= 0 &&
        index + delta >= 0 &&
        index + delta < comparison.files.length;
  }

  Future<void> _moveFile(int delta) async {
    final comparison = _comparison;
    final selectedPath = _selectedPath;
    if (comparison == null || selectedPath == null) return;
    final index = comparison.files.indexWhere(
      (file) => file.path == selectedPath,
    );
    final next = index + delta;
    if (index < 0 || next < 0 || next >= comparison.files.length) return;
    await _selectFile(comparison.files[next].path);
  }

  Future<void> _selectFile(String path, {int? requestNumber}) async {
    final comparison = _comparison;
    if (comparison == null) return;
    final currentRequest = requestNumber ?? ++_requestNumber;
    setState(() {
      _busy = true;
      _error = null;
      _selectedPath = path;
      _diff = null;
    });
    try {
      final diff = await widget.gateway.getComparisonDiff(
        widget.repository.repositoryId,
        comparison,
        path,
      );
      if (!mounted || currentRequest != _requestNumber) return;
      setState(() {
        _busy = false;
        _diff = diff;
      });
    } on GitError catch (error) {
      if (!mounted || currentRequest != _requestNumber) return;
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  Future<void> _transfer(GitComparisonTransferAction action) async {
    final comparison = _comparison;
    final path = _selectedPath;
    if (comparison == null || path == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.gateway.applyComparison(
        widget.repository.repositoryId,
        comparison,
        path,
        action: action,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(result.summary)));
    } on GitError catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }
}

/// Presents the base and both candidate contents without treating a text pane
/// as an implicit mutation. Transfer actions stay on the reviewed two-way
/// diff, while this view makes conflicting candidate content explicit.
class ThreeWayComparisonDialog extends StatefulWidget {
  const ThreeWayComparisonDialog({
    super.key,
    required this.gateway,
    required this.repository,
    this.initialPath,
  });

  final GitGateway gateway;
  final RepositoryOpened repository;
  final String? initialPath;

  @override
  State<ThreeWayComparisonDialog> createState() =>
      _ThreeWayComparisonDialogState();
}

class _ThreeWayComparisonDialogState extends State<ThreeWayComparisonDialog> {
  late final TextEditingController _baseController;
  late final TextEditingController _leftController;
  late final TextEditingController _rightController;
  late final TextEditingController _pathController;
  GitThreeWayComparisonSnapshot? _comparison;
  GitError? _error;
  var _busy = false;
  var _requestNumber = 0;

  @override
  void initState() {
    super.initState();
    _baseController = TextEditingController(text: 'HEAD~2');
    _leftController = TextEditingController(text: 'HEAD~1');
    _rightController = TextEditingController(text: 'HEAD');
    _pathController = TextEditingController(text: widget.initialPath ?? '');
  }

  @override
  void dispose() {
    _baseController.dispose();
    _leftController.dispose();
    _rightController.dispose();
    _pathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 640;
    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 32,
        vertical: 20,
      ),
      title: Row(
        children: [
          const Expanded(child: Text('Three-way comparison')),
          if (_busy)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
      content: SizedBox(
        width: (size.width - (compact ? 24 : 64)).clamp(280.0, 1080.0),
        height: (size.height - 150).clamp(340.0, 720.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _controls(context),
            if (_error case final error?) ...[
              const SizedBox(height: 8),
              Container(
                key: const Key('three-way-error'),
                padding: const EdgeInsets.all(10),
                color: Theme.of(context).colorScheme.errorContainer,
                child: Text(error.userMessage),
              ),
            ],
            const SizedBox(height: 12),
            Expanded(child: _body(context)),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('close-three-way-dialog'),
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _controls(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fields = [
          _sourceField(
            key: const Key('three-way-base'),
            controller: _baseController,
            label: 'Base revision',
            hint: 'Common ancestor or base tag',
          ),
          _sourceField(
            key: const Key('three-way-left'),
            controller: _leftController,
            label: 'Left candidate',
            hint: 'Ours, branch, or tag',
          ),
          _sourceField(
            key: const Key('three-way-right'),
            controller: _rightController,
            label: 'Right candidate',
            hint: 'Theirs, branch, or tag',
          ),
        ];
        final path = TextField(
          key: const Key('three-way-path'),
          controller: _pathController,
          enabled: !_busy,
          decoration: const InputDecoration(
            labelText: 'File path',
            hintText: 'src/notes.txt',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _compare(),
        );
        final button = FilledButton.icon(
          key: const Key('compare-three-way'),
          onPressed: _busy ? null : _compare,
          icon: const Icon(Icons.call_split),
          label: const Text('Compare'),
        );
        if (constraints.maxWidth < 700) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: fields[0]),
                  const SizedBox(width: 8),
                  Expanded(child: fields[1]),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: fields[2]),
                  const SizedBox(width: 8),
                  Expanded(child: path),
                ],
              ),
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerRight, child: button),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: fields[0]),
            const SizedBox(width: 8),
            Expanded(child: fields[1]),
            const SizedBox(width: 8),
            Expanded(child: fields[2]),
            const SizedBox(width: 8),
            Expanded(child: path),
            const SizedBox(width: 8),
            Padding(padding: const EdgeInsets.only(top: 4), child: button),
          ],
        );
      },
    );
  }

  Widget _sourceField({
    required Key key,
    required TextEditingController controller,
    required String label,
    required String hint,
  }) => TextField(
    key: key,
    controller: controller,
    enabled: !_busy,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      border: const OutlineInputBorder(),
    ),
    onSubmitted: (_) => _compare(),
  );

  Widget _body(BuildContext context) {
    final comparison = _comparison;
    if (comparison == null) {
      return Center(
        child: _busy
            ? const CircularProgressIndicator()
            : const Text('Enter three revisions and a file path to compare.'),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final panes = [
          _pane(
            context,
            key: const Key('three-way-pane-base'),
            label: 'Base',
            content: comparison.base,
          ),
          _pane(
            context,
            key: const Key('three-way-pane-left'),
            label: 'Left candidate',
            content: comparison.left,
          ),
          _pane(
            context,
            key: const Key('three-way-pane-right'),
            label: 'Right candidate',
            content: comparison.right,
          ),
        ];
        final panesView = constraints.maxWidth < 700
            ? Column(
                children: [
                  for (var index = 0; index < panes.length; index++) ...[
                    if (index > 0) const SizedBox(height: 6),
                    Expanded(child: panes[index]),
                  ],
                ],
              )
            : Row(
                children: [
                  for (var index = 0; index < panes.length; index++) ...[
                    if (index > 0) const SizedBox(width: 6),
                    Expanded(child: panes[index]),
                  ],
                ],
              );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (comparison.hasConflict)
              Container(
                key: const Key('three-way-conflict'),
                padding: const EdgeInsets.all(8),
                color: Theme.of(context).colorScheme.errorContainer,
                child: const Text(
                  'Both candidates changed from the base. Review each pane.',
                ),
              ),
            if (comparison.hasConflict) const SizedBox(height: 8),
            Expanded(child: panesView),
          ],
        );
      },
    );
  }

  Widget _pane(
    BuildContext context, {
    required Key key,
    required String label,
    required GitComparisonContent content,
  }) {
    final body = switch (content.state) {
      GitComparisonContentState.available => SelectionArea(
        child: ListView(
          key: Key('${key.toString()}-content'),
          padding: const EdgeInsets.all(8),
          children: [
            Text(
              content.text ?? '',
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ],
        ),
      ),
      GitComparisonContentState.missing => const Center(
        child: Text('Missing in this source.'),
      ),
      GitComparisonContentState.binary => const Center(
        child: Text('Binary content is not shown.'),
      ),
      GitComparisonContentState.oversized => const Center(
        child: Text('Content is too large to display.'),
      ),
      GitComparisonContentState.unreadable => const Center(
        child: Text('Content could not be read.'),
      ),
    };
    return Card(
      key: key,
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Text(label),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }

  Future<void> _compare() async {
    final requestNumber = ++_requestNumber;
    setState(() {
      _busy = true;
      _error = null;
      _comparison = null;
    });
    try {
      final comparison = await widget.gateway.compareThreeWay(
        widget.repository.repositoryId,
        GitComparisonSource.revision(_baseController.text.trim()),
        GitComparisonSource.revision(_leftController.text.trim()),
        GitComparisonSource.revision(_rightController.text.trim()),
        path: _pathController.text.trim(),
      );
      if (!mounted || requestNumber != _requestNumber) return;
      setState(() {
        _comparison = comparison;
        _busy = false;
      });
    } on GitError catch (error) {
      if (!mounted || requestNumber != _requestNumber) return;
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }
}
