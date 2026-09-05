import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:gift/src/backend/repository_paths.dart';
import 'package:gift/src/features/repository/path_actions.dart';

enum RepositoryPathMode { file, directory, either }

String normalizeRepositoryRelativePath(String rawPath) =>
    rawPath.trim().replaceAll('\\', '/');

String? validateRepositoryRelativePath(
  String rawPath, {
  required RepositoryPathMode mode,
  GitRepositoryPathSnapshot? snapshot,
  bool allowEmpty = true,
}) {
  final path = normalizeRepositoryRelativePath(rawPath);
  if (path.isEmpty) return allowEmpty ? null : 'Enter a repository path.';
  if (!isSafeRepositoryRelativePath(path)) {
    return 'Enter a safe repository-relative path.';
  }
  if (snapshot == null) return null;
  final entry = snapshot.paths
      .where((candidate) => candidate.path == path)
      .firstOrNull;
  if (entry == null) return null;
  final matches = switch (mode) {
    RepositoryPathMode.file => entry.kind == GitRepositoryPathKind.file,
    RepositoryPathMode.directory =>
      entry.kind == GitRepositoryPathKind.directory,
    RepositoryPathMode.either => true,
  };
  return matches
      ? null
      : 'Choose a ${mode == RepositoryPathMode.file ? 'file' : 'folder'} path.';
}

class RepositoryPathField extends StatefulWidget {
  const RepositoryPathField({
    super.key,
    required this.gateway,
    required this.repository,
    required this.controller,
    required this.label,
    required this.hint,
    required this.mode,
    this.fieldKey,
    this.browseKey,
    this.clearKey,
    this.enabled = true,
    this.allowEmpty = true,
    this.onSubmitted,
    this.onChanged,
  });

  final GitGateway gateway;
  final RepositoryOpened repository;
  final TextEditingController controller;
  final String label;
  final String hint;
  final RepositoryPathMode mode;
  final Key? fieldKey;
  final Key? browseKey;
  final Key? clearKey;
  final bool enabled;
  final bool allowEmpty;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;

  @override
  State<RepositoryPathField> createState() => RepositoryPathFieldState();
}

class RepositoryPathFieldState extends State<RepositoryPathField> {
  static const _maxSuggestions = 50;
  static const _debounceDuration = Duration(milliseconds: 150);
  late final FocusNode _focusNode;

  Timer? _debounce;
  GitRepositoryPathSnapshot? _snapshot;
  List<GitRepositoryPath> _suggestions = const [];
  String? _error;
  int _loadGeneration = 0;
  bool _loading = false;
  bool _loadFailed = false;
  bool _browseAll = false;
  int _highlightedIndex = -1;
  bool _showSuggestions = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    widget.controller.addListener(_handleTextChanged);
    _loadPaths();
  }

  @override
  void didUpdateWidget(covariant RepositoryPathField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleTextChanged);
      widget.controller.addListener(_handleTextChanged);
    }
    if (oldWidget.gateway != widget.gateway ||
        oldWidget.repository.repositoryId != widget.repository.repositoryId) {
      _loadPaths();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focusNode.dispose();
    widget.controller.removeListener(_handleTextChanged);
    super.dispose();
  }

  Future<void> _loadPaths() async {
    final generation = ++_loadGeneration;
    if (mounted) {
      setState(() {
        _loading = true;
        _loadFailed = false;
      });
    }
    try {
      final snapshot = await widget.gateway.getRepositoryPaths(
        widget.repository.repositoryId,
      );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _snapshot = snapshot;
        _updateSuggestions();
      });
    } on Object {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
        _snapshot = null;
        _suggestions = const [];
      });
    }
  }

  void _handleTextChanged() {
    _debounce?.cancel();
    _browseAll = false;
    _highlightedIndex = -1;
    _debounce = Timer(_debounceDuration, () {
      if (!mounted) return;
      setState(() {
        _error = null;
        _showSuggestions = true;
        _updateSuggestions();
      });
    });
    widget.onChanged?.call(
      normalizeRepositoryRelativePath(widget.controller.text),
    );
  }

  void _updateSuggestions() {
    final snapshot = _snapshot;
    if (snapshot == null) {
      _suggestions = const [];
      _highlightedIndex = -1;
      return;
    }
    _suggestions = snapshot.matching(
      _browseAll ? '' : widget.controller.text,
      kind: switch (widget.mode) {
        RepositoryPathMode.file => GitRepositoryPathKind.file,
        RepositoryPathMode.directory => GitRepositoryPathKind.directory,
        RepositoryPathMode.either => null,
      },
      limit: _maxSuggestions,
    );
    if (_highlightedIndex >= _suggestions.length) {
      _highlightedIndex = _suggestions.isEmpty ? -1 : _suggestions.length - 1;
    }
  }

  void _submit() {
    final path = normalizeRepositoryRelativePath(widget.controller.text);
    final validation = validateRepositoryRelativePath(
      path,
      mode: widget.mode,
      snapshot: _snapshot,
      allowEmpty: widget.allowEmpty,
    );
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    if (widget.controller.text != path) {
      widget.controller.value = widget.controller.value.copyWith(
        text: path,
        selection: TextSelection.collapsed(offset: path.length),
        composing: TextRange.empty,
      );
    }
    setState(() {
      _error = null;
      _showSuggestions = false;
      _highlightedIndex = -1;
    });
    widget.onSubmitted?.call(path);
  }

  void _select(GitRepositoryPath entry) {
    widget.controller.value = TextEditingValue(
      text: entry.path,
      selection: TextSelection.collapsed(offset: entry.path.length),
    );
    setState(() {
      _error = null;
      _browseAll = false;
      _showSuggestions = false;
      _highlightedIndex = -1;
    });
  }

  void _moveHighlight(int delta) {
    if (_suggestions.isEmpty) return;
    final next = (_highlightedIndex + delta).clamp(0, _suggestions.length - 1);
    setState(() => _highlightedIndex = next);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || !_showSuggestions) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _moveHighlight(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _moveHighlight(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      setState(() {
        _showSuggestions = false;
        _highlightedIndex = -1;
      });
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter &&
        _highlightedIndex >= 0 &&
        _highlightedIndex < _suggestions.length) {
      _select(_suggestions[_highlightedIndex]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final showPanel = _showSuggestions && (_loading || _snapshot != null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Focus(
          onKeyEvent: _handleKeyEvent,
          child: TextField(
            key: widget.fieldKey,
            controller: widget.controller,
            focusNode: _focusNode,
            enabled: widget.enabled,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _submit(),
            onTap: () {
              if (mounted) setState(() => _showSuggestions = true);
            },
            decoration: InputDecoration(
              labelText: widget.label,
              hintText: widget.hint,
              isDense: true,
              border: const OutlineInputBorder(),
              errorText: _error,
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  if (widget.controller.text.isNotEmpty)
                    IconButton(
                      key: widget.clearKey,
                      tooltip: 'Clear path',
                      onPressed: widget.enabled
                          ? () {
                              widget.controller.clear();
                              setState(() {
                                _error = null;
                                _browseAll = true;
                                _showSuggestions = true;
                                _highlightedIndex = -1;
                                _updateSuggestions();
                              });
                            }
                          : null,
                      icon: const Icon(Icons.clear),
                    ),
                  IconButton(
                    key: widget.browseKey,
                    tooltip: 'Browse repository paths',
                    onPressed: widget.enabled
                        ? () {
                            _focusNode.requestFocus();
                            setState(() {
                              _browseAll = true;
                              _showSuggestions = true;
                              _highlightedIndex = -1;
                              _updateSuggestions();
                            });
                          }
                        : null,
                    icon: const Icon(Icons.folder_open),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (showPanel) _suggestionPanel(context),
      ],
    );
  }

  Widget _suggestionPanel(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final message = _loadFailed
        ? 'Repository paths are unavailable. You can still type a path.'
        : _suggestions.isEmpty
        ? (widget.controller.text.isEmpty
              ? 'No repository paths found.'
              : 'No paths match “${widget.controller.text}”.')
        : null;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          border: Border.all(color: colorScheme.outline.withValues(alpha: 0.7)),
        ),
        child: message != null
            ? Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(
                      _loadFailed ? Icons.info_outline : Icons.search_off,
                      size: 18,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        message,
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              )
            : Material(
                type: MaterialType.transparency,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: _suggestions.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final entry = _suggestions[index];
                      final slash = entry.path.lastIndexOf('/');
                      final parent = slash == -1
                          ? 'Repository root'
                          : entry.path.substring(0, slash);
                      final kind = entry.kind == GitRepositoryPathKind.directory
                          ? 'Folder'
                          : 'File';
                      return ListTile(
                        key: Key('repository-path-suggestion:${entry.path}'),
                        dense: true,
                        selected: index == _highlightedIndex,
                        selectedTileColor: colorScheme.primaryContainer,
                        title: Tooltip(
                          message: entry.path,
                          child: Text(
                            entry.path,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        subtitle: Text('$parent · $kind'),
                        leading: Icon(
                          entry.kind == GitRepositoryPathKind.directory
                              ? Icons.folder_outlined
                              : Icons.insert_drive_file_outlined,
                        ),
                        onTap: () => _select(entry),
                      );
                    },
                  ),
                ),
              ),
      ),
    );
  }
}
