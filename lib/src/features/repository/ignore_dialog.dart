import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gift/src/app/pixel_theme.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/error.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:gift/src/backend/ignore.dart';

/// Explains ignored paths and repository attributes without executing any
/// configured diff or clean/smudge command.
class IgnoreDialog extends StatefulWidget {
  const IgnoreDialog({
    super.key,
    required this.gateway,
    required this.repository,
  });

  final GitGateway gateway;
  final RepositoryOpened repository;

  @override
  State<IgnoreDialog> createState() => _IgnoreDialogState();
}

class _IgnoreDialogState extends State<IgnoreDialog>
    with SingleTickerProviderStateMixin {
  GitIgnoreSnapshot? _snapshot;
  GitAttributesSnapshot? _attributes;
  GitError? _error;
  String? _message;
  String? _selectedPath;
  var _isLoading = true;
  var _isBusy = false;
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    unawaited(_load());
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 560;
    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 32,
        vertical: 20,
      ),
      title: Row(
        children: [
          const Expanded(child: Text('Ignore & metadata')),
          if (_isBusy)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
      content: SizedBox(
        width: (size.width - (compact ? 24 : 64)).clamp(280.0, 760.0),
        height: (size.height - 150).clamp(300.0, 560.0),
        child: Column(
          children: [
            if (_error case final error?) _errorBanner(error),
            if (_message case final message?)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  message,
                  key: const Key('ignore-message'),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            TabBar(
              controller: _tabs,
              tabs: const [
                Tab(text: 'Path states'),
                Tab(text: 'Attributes'),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [_pathStates(context), _attributesView(context)],
              ),
            ),
          ],
        ),
      ),
      actionsOverflowButtonSpacing: 4,
      actions: [
        TextButton(
          key: const Key('refresh-ignore-metadata'),
          onPressed: _isBusy ? null : _load,
          child: const Text('Refresh'),
        ),
        TextButton(
          key: const Key('close-ignore-dialog'),
          onPressed: _isBusy ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _errorBanner(GitError error) {
    return Container(
      key: const Key('ignore-error'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      color: Theme.of(context).colorScheme.errorContainer,
      child: Text(error.userMessage),
    );
  }

  Widget _pathStates(BuildContext context) {
    if (_isLoading && _snapshot == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final entries = _snapshot?.entries ?? const <GitIgnoreEntry>[];
    if (entries.isEmpty) {
      return const Center(
        child: Text('No untracked, ignored, or modified paths.'),
      );
    }
    return ListView(
      key: const Key('ignore-path-list'),
      children: [
        Text(
          'Ignored paths are shown with their matching rule source.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        for (final entry in entries) _entryCard(context, entry),
      ],
    );
  }

  Widget _entryCard(BuildContext context, GitIgnoreEntry entry) {
    final colors = Theme.of(context).colorScheme;
    final (label, icon, color) = switch (entry.kind) {
      GitPathMetadataKind.ignored => (
        'Ignored',
        Icons.visibility_off_outlined,
        colors.tertiary,
      ),
      GitPathMetadataKind.untracked => (
        'Untracked',
        Icons.help_outline,
        colors.primary,
      ),
      GitPathMetadataKind.trackedModified => (
        'Tracked modified',
        Icons.edit_outlined,
        colors.error,
      ),
    };
    final source = entry.isIgnored ? _sourceLabel(entry.source) : null;
    return Card(
      key: ValueKey('ignore-entry:${entry.path}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: SelectableText(
                    entry.path,
                    maxLines: 2,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: TextStyle(color: color),
                  ),
                ),
              ],
            ),
            if (source != null || entry.pattern != null) ...[
              const SizedBox(height: 4),
              Text(
                [
                  ?source,
                  if (entry.pattern != null) 'rule: ${entry.pattern}',
                  if (entry.line case final line?) 'line $line',
                ].join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (entry.kind == GitPathMetadataKind.untracked) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                alignment: WrapAlignment.end,
                children: [
                  OutlinedButton(
                    key: ValueKey('ignore-repository:${entry.path}'),
                    onPressed: _isBusy
                        ? null
                        : () => _ignore(entry, GitIgnoreScope.repository),
                    child: const Text('Ignore in repository'),
                  ),
                  OutlinedButton(
                    key: ValueKey('ignore-local:${entry.path}'),
                    onPressed: _isBusy
                        ? null
                        : () => _ignore(entry, GitIgnoreScope.localExclude),
                    child: const Text('Exclude locally'),
                  ),
                  TextButton(
                    key: ValueKey('inspect-attributes:${entry.path}'),
                    onPressed: _isBusy ? null : () => _inspect(entry.path),
                    child: const Text('Attributes'),
                  ),
                ],
              ),
            ] else
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: ValueKey('inspect-attributes:${entry.path}'),
                  onPressed: _isBusy ? null : () => _inspect(entry.path),
                  child: const Text('Attributes'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _attributesView(BuildContext context) {
    final entries = _snapshot?.entries ?? const <GitIgnoreEntry>[];
    final paths = entries
        .map((entry) => entry.path)
        .toSet()
        .toList(growable: false);
    if (paths.isEmpty) {
      return const Center(
        child: Text('No paths are available for attributes.'),
      );
    }
    final selected = paths.contains(_selectedPath)
        ? _selectedPath
        : paths.first;
    final entry = _attributes?.entries
        .where((candidate) => candidate.path == selected)
        .firstOrNull;
    return ListView(
      key: const Key('attributes-view'),
      children: [
        DropdownButtonFormField<String>(
          key: const Key('attribute-path'),
          initialValue: selected,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Path',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final path in paths)
              DropdownMenuItem(value: path, child: pixelDropdownText(path)),
          ],
          onChanged: _isBusy
              ? null
              : (path) {
                  if (path != null) unawaited(_inspect(path));
                },
        ),
        const SizedBox(height: 12),
        if (_attributes == null)
          Center(
            child: OutlinedButton(
              key: const Key('load-attributes'),
              onPressed: _isBusy ? null : () => _inspect(selected!),
              child: const Text('Inspect attributes'),
            ),
          )
        else if (entry == null || entry.values.isEmpty)
          const Center(
            child: Text('No explicit attributes apply to this path.'),
          )
        else ...[
          Text('Raw values', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          for (final attribute in entry.values.entries)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(attribute.key),
              trailing: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  attribute.value,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                ),
              ),
            ),
          if (entry.explanations.isNotEmpty) ...[
            const Divider(),
            Text(
              'What this means',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            for (final explanation in entry.explanations)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.info_outline, size: 18),
                title: Text(explanation),
              ),
          ],
          const SizedBox(height: 8),
          Text(
            'Inspection reads attributes only; configured filters and textconv commands are not run.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  Future<void> _load() async {
    if (_isBusy) return;
    setState(() {
      _isLoading = true;
      _error = null;
      _message = null;
    });
    try {
      final snapshot = await widget.gateway.getIgnoreSnapshot(
        widget.repository.repositoryId,
      );
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _isLoading = false;
        if (_selectedPath == null && snapshot.entries.isNotEmpty) {
          _selectedPath = snapshot.entries.first.path;
        }
      });
    } on GitError catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _isLoading = false;
      });
    }
  }

  Future<void> _ignore(GitIgnoreEntry entry, GitIgnoreScope scope) async {
    await _run(() async {
      final result = await widget.gateway.addIgnorePattern(
        widget.repository.repositoryId,
        GitIgnoreRequest(path: entry.path, scope: scope),
      );
      if (!mounted) return;
      setState(() {
        _snapshot = result.snapshot;
        _message = result.summary;
        _selectedPath = entry.path;
      });
    });
  }

  Future<void> _inspect(String path) async {
    setState(() {
      _selectedPath = path;
      _tabs.index = 1;
    });
    await _run(() async {
      final attributes = await widget.gateway.getAttributes(
        widget.repository.repositoryId,
        paths: [path],
      );
      if (!mounted) return;
      setState(() => _attributes = attributes);
    });
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_isBusy) return;
    setState(() {
      _isBusy = true;
      _error = null;
      _message = null;
    });
    try {
      await operation();
    } on GitError catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }
}

String _sourceLabel(GitIgnoreSource source) => switch (source) {
  GitIgnoreSource.gitignore => '.gitignore',
  GitIgnoreSource.infoExclude => '.git/info/exclude',
  GitIgnoreSource.global => 'global ignore',
  GitIgnoreSource.commandLine => 'command-line ignore',
  GitIgnoreSource.unknown => 'unknown ignore source',
};
