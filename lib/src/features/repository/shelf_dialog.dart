import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/error.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:gift/src/backend/shelf.dart';

/// Presents local changelists and reusable shelves as separate concepts from
/// Git stash. A shelf is an app-managed patch; it never creates a stash ref.
class ShelfDialog extends StatefulWidget {
  const ShelfDialog({
    super.key,
    required this.gateway,
    required this.repository,
    this.initialPaths = const <String>[],
  });

  final GitGateway gateway;
  final RepositoryOpened repository;
  final List<String> initialPaths;

  @override
  State<ShelfDialog> createState() => _ShelfDialogState();
}

class _ShelfDialogState extends State<ShelfDialog> {
  late final TextEditingController _changelistName;
  late final TextEditingController _shelfName;
  GitChangelistSnapshot? _changelists;
  GitShelfSnapshot? _shelves;
  GitError? _error;
  String? _message;
  var _loading = true;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _changelistName = TextEditingController();
    _shelfName = TextEditingController();
    Future<void>.microtask(_reload);
  }

  @override
  void dispose() {
    _changelistName.dispose();
    _shelfName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 520;
    final width = (size.width - (compact ? 28 : 80)).clamp(0.0, 640.0);
    final dataReady = !_loading && _changelists != null && _shelves != null;
    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 14 : 40,
        vertical: 22,
      ),
      title: const Text('Shelves & changelists'),
      content: SizedBox(
        width: width,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: size.height * .72),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_error case final error?) _errorBanner(error),
                      if (_message case final message?)
                        Text(message, key: const Key('shelf-message')),
                      _localStateNotice(context),
                      const SizedBox(height: 12),
                      _changelistSection(context, compact, dataReady),
                      const SizedBox(height: 16),
                      _shelfSection(context, compact, dataReady),
                    ],
                  ),
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _localStateNotice(BuildContext context) => Container(
    key: const Key('shelf-semantics'),
    padding: const EdgeInsets.all(10),
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: const Text(
      'Shelves are local reusable patches. They do not touch Git stash. '
      'Unversioned files are not included in tracked-path shelves.',
    ),
  );

  Widget _changelistSection(
    BuildContext context,
    bool compact,
    bool dataReady,
  ) {
    final lists = _changelists?.lists ?? const <GitChangelist>[];
    return Column(
      key: const Key('changelist-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Changelists', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        if (dataReady)
          ...lists.map(
            (list) => ListTile(
              key: ValueKey('changelist:${list.id}'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                list.isActive
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                size: 18,
              ),
              title: Text(list.name),
              subtitle: Text('${_pathCount(list.paths.length)} assigned'),
              onTap: _busy || list.isActive
                  ? null
                  : () => unawaited(_activateChangelist(list.id)),
              trailing: Wrap(
                spacing: 0,
                children: [
                  IconButton(
                    key: ValueKey('rename-changelist:${list.id}'),
                    tooltip: 'Rename changelist',
                    onPressed: _busy
                        ? null
                        : () => unawaited(_renameChangelist(list)),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                  ),
                  IconButton(
                    key: ValueKey('delete-changelist:${list.id}'),
                    tooltip: 'Delete changelist',
                    onPressed: _busy || list.id == 'default'
                        ? null
                        : () => unawaited(_deleteChangelist(list.id)),
                    icon: const Icon(Icons.delete_outline, size: 18),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 6),
        if (compact)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [_changelistNameField(), _createChangelistButton()],
          )
        else
          Row(
            children: [
              Expanded(child: _changelistNameField()),
              const SizedBox(width: 8),
              _createChangelistButton(),
            ],
          ),
      ],
    );
  }

  Widget _changelistNameField() => TextField(
    key: const Key('new-changelist-name'),
    controller: _changelistName,
    enabled: !_busy,
    decoration: const InputDecoration(
      labelText: 'New changelist',
      border: OutlineInputBorder(),
    ),
    onSubmitted: (_) => unawaited(_createChangelist()),
  );

  Widget _createChangelistButton() => FilledButton(
    key: const Key('create-changelist'),
    onPressed: _busy ? null : () => unawaited(_createChangelist()),
    child: const Text('Create'),
  );

  Widget _shelfSection(BuildContext context, bool compact, bool dataReady) {
    final shelves = _shelves?.shelves ?? const <GitShelf>[];
    return Column(
      key: const Key('shelf-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Shelf', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        if (compact)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [_shelfNameField(), _shelveButton()],
          )
        else
          Row(
            children: [
              Expanded(child: _shelfNameField()),
              const SizedBox(width: 8),
              _shelveButton(),
            ],
          ),
        const SizedBox(height: 8),
        if (dataReady && shelves.isEmpty)
          const Text('No local shelves yet.', key: Key('empty-shelves')),
        ...shelves.map(_shelfTile),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('import-shelf'),
          onPressed: _busy ? null : () => unawaited(_importShelf()),
          icon: const Icon(Icons.file_open_outlined),
          label: const Text('Import patch file'),
        ),
      ],
    );
  }

  Widget _shelfNameField() => TextField(
    key: const Key('shelf-name'),
    controller: _shelfName,
    enabled: !_busy,
    decoration: const InputDecoration(
      labelText: 'Shelf name (optional)',
      border: OutlineInputBorder(),
    ),
  );

  Widget _shelveButton() => FilledButton.icon(
    key: const Key('shelve-selected'),
    onPressed: _busy ? null : () => unawaited(_shelve()),
    icon: const Icon(Icons.archive_outlined),
    label: Text(
      widget.initialPaths.isEmpty ? 'Shelve changes' : 'Shelve selected',
    ),
  );

  Widget _shelfTile(GitShelf shelf) => ListTile(
    key: ValueKey('shelf:${shelf.id}'),
    dense: true,
    contentPadding: EdgeInsets.zero,
    title: Text(shelf.name),
    subtitle: Text(
      '${_pathCount(shelf.paths.length)} · ${shelf.imported ? 'imported' : 'tracked'}',
    ),
    trailing: Wrap(
      spacing: 0,
      children: [
        IconButton(
          key: ValueKey('unshelve:${shelf.id}'),
          tooltip: 'Unshelve',
          onPressed: _busy ? null : () => unawaited(_unshelve(shelf)),
          icon: const Icon(Icons.unarchive_outlined, size: 18),
        ),
        IconButton(
          key: ValueKey('restore-shelf:${shelf.id}'),
          tooltip: 'Restore already-unshelved changes',
          onPressed: _busy ? null : () => unawaited(_restoreShelf(shelf)),
          icon: const Icon(Icons.undo, size: 18),
        ),
        IconButton(
          key: ValueKey('export-shelf:${shelf.id}'),
          tooltip: 'Export patch',
          onPressed: _busy ? null : () => unawaited(_exportShelf(shelf)),
          icon: const Icon(Icons.save_alt_outlined, size: 18),
        ),
        IconButton(
          key: ValueKey('delete-shelf:${shelf.id}'),
          tooltip: 'Delete shelf',
          onPressed: _busy ? null : () => unawaited(_deleteShelf(shelf)),
          icon: const Icon(Icons.delete_outline, size: 18),
        ),
      ],
    ),
  );

  Widget _errorBanner(GitError error) =>
      Text(error.userMessage, key: const Key('shelf-error'));

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await Future.wait([
        widget.gateway.getChangelists(widget.repository.repositoryId),
        widget.gateway.getShelves(widget.repository.repositoryId),
      ]);
      if (!mounted) return;
      setState(() {
        _changelists = values[0] as GitChangelistSnapshot;
        _shelves = values[1] as GitShelfSnapshot;
        _loading = false;
      });
    } on GitError catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _createChangelist() async {
    final name = _changelistName.text.trim();
    if (name.isEmpty) return;
    await _run(() async {
      _changelists = await widget.gateway.createChangelist(
        widget.repository.repositoryId,
        name,
      );
      _changelistName.clear();
      _message = 'Created changelist "$name".';
    });
  }

  Future<void> _renameChangelist(GitChangelist list) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController(text: list.name);
        return AlertDialog(
          title: const Text('Rename changelist'),
          content: TextField(controller: controller, autofocus: true),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Rename'),
            ),
          ],
        );
      },
    );
    if (name == null || name.trim().isEmpty) return;
    await _run(() async {
      _changelists = await widget.gateway.renameChangelist(
        widget.repository.repositoryId,
        list.id,
        name,
      );
    });
  }

  Future<void> _activateChangelist(String id) async {
    await _run(() async {
      _changelists = await widget.gateway.activateChangelist(
        widget.repository.repositoryId,
        id,
      );
    });
  }

  Future<void> _deleteChangelist(String id) async {
    await _run(() async {
      _changelists = await widget.gateway.deleteChangelist(
        widget.repository.repositoryId,
        id,
      );
    });
  }

  Future<void> _shelve() async {
    await _run(() async {
      final result = await widget.gateway.shelve(
        widget.repository.repositoryId,
        name: _shelfName.text,
        paths: widget.initialPaths,
      );
      _shelves = result.shelves;
      _shelfName.clear();
      _message = result.summary;
    });
  }

  Future<void> _unshelve(GitShelf shelf) async {
    await _run(() async {
      final result = await widget.gateway.unshelve(
        widget.repository.repositoryId,
        shelf.id,
      );
      _shelves = result.shelves;
      _message = result.summary;
    });
  }

  Future<void> _restoreShelf(GitShelf shelf) async {
    await _run(() async {
      final result = await widget.gateway.restoreShelf(
        widget.repository.repositoryId,
        shelf.id,
      );
      _shelves = result.shelves;
      _message = result.summary;
    });
  }

  Future<void> _deleteShelf(GitShelf shelf) async {
    await _run(() async {
      final result = await widget.gateway.deleteShelf(
        widget.repository.repositoryId,
        shelf.id,
      );
      _shelves = result.shelves;
      _message = result.summary;
    });
  }

  Future<void> _importShelf() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Patch', extensions: ['patch', 'diff']),
      ],
    );
    if (file == null) return;
    await _run(() async {
      final result = await widget.gateway.importShelf(
        widget.repository.repositoryId,
        file.name,
        await file.readAsBytes(),
      );
      _shelves = result.shelves;
      _message = result.summary;
    });
  }

  Future<void> _exportShelf(GitShelf shelf) async {
    final location = await getSaveLocation(
      suggestedName: '${shelf.name}.patch',
    );
    if (location == null) return;
    await _run(() async {
      final bytes = await widget.gateway.exportShelf(
        widget.repository.repositoryId,
        shelf.id,
      );
      await File(location.path).writeAsBytes(bytes, flush: true);
      _message = 'Exported ${shelf.name}.';
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await action();
    } on GitError catch (error) {
      if (mounted) _error = error;
    } on FileSystemException catch (error) {
      if (mounted) {
        _error = GitError(
          category: GitErrorCategory.permissionDenied,
          userMessage: 'The patch file could not be written.',
          diagnostic: error.message,
          retryable: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

String _pathCount(int count) => '$count ${count == 1 ? 'path' : 'paths'}';
