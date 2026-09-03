import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gift/src/backend/comparison.dart';
import 'package:gift/src/backend/diff.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/error.dart';
import 'package:gift/src/backend/git_gateway.dart';

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
  GitComparisonSnapshot? _comparison;
  GitDiffSnapshot? _diff;
  String? _selectedPath;
  GitError? _error;
  var _busy = false;
  var _requestNumber = 0;

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
        final fields = [
          TextField(
            key: const Key('comparison-left'),
            controller: _leftController,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'Left revision',
              hintText: 'HEAD~1, branch, or tag',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _compare(),
          ),
          TextField(
            key: const Key('comparison-right'),
            controller: _rightController,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'Right revision',
              hintText: 'HEAD, branch, or tag',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _compare(),
          ),
        ];
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
              fields[0],
              const SizedBox(height: 8),
              fields[1],
              const SizedBox(height: 8),
              path,
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerRight, child: compareButton),
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
          SizedBox(height: 96, child: fileList),
          const SizedBox(height: 10),
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
    if (diff.lines.isEmpty) {
      return Card(
        margin: EdgeInsets.zero,
        child: Center(child: Text('No text diff for ${diff.path}.')),
      );
    }
    return Card(
      margin: EdgeInsets.zero,
      child: SelectionArea(
        child: ListView.builder(
          key: const Key('comparison-diff-lines'),
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: diff.lines.length,
          itemBuilder: (context, index) {
            final line = diff.lines[index];
            final color = switch (line.kind) {
              GitDiffLineKind.addition => Colors.green.withValues(alpha: .14),
              GitDiffLineKind.deletion => Colors.red.withValues(alpha: .14),
              GitDiffLineKind.hunkHeader => Theme.of(
                context,
              ).colorScheme.primaryContainer,
              _ => null,
            };
            return Container(
              width: double.infinity,
              color: color,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              child: Text(
                line.text,
                softWrap: true,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            );
          },
        ),
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
      final comparison = await widget.gateway.compareRevisions(
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
}
