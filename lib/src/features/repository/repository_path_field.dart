import 'dart:async';

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

  Timer? _debounce;
  GitRepositoryPathSnapshot? _snapshot;
  List<GitRepositoryPath> _suggestions = const [];
  String? _error;
  int _loadGeneration = 0;
  bool _showSuggestions = false;

  @override
  void initState() {
    super.initState();
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
    widget.controller.removeListener(_handleTextChanged);
    super.dispose();
  }

  Future<void> _loadPaths() async {
    final generation = ++_loadGeneration;
    try {
      final snapshot = await widget.gateway.getRepositoryPaths(
        widget.repository.repositoryId,
      );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _snapshot = snapshot;
        _updateSuggestions();
      });
    } on Object {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _snapshot = null;
        _suggestions = const [];
      });
    }
  }

  void _handleTextChanged() {
    _debounce?.cancel();
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
      return;
    }
    _suggestions = snapshot.matching(
      widget.controller.text,
      kind: switch (widget.mode) {
        RepositoryPathMode.file => GitRepositoryPathKind.file,
        RepositoryPathMode.directory => GitRepositoryPathKind.directory,
        RepositoryPathMode.either => null,
      },
      limit: _maxSuggestions,
    );
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
      _showSuggestions = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final showSuggestions = _showSuggestions && _suggestions.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: widget.fieldKey,
          controller: widget.controller,
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
                IconButton(
                  key: widget.clearKey,
                  tooltip: 'Clear path',
                  onPressed: widget.enabled
                      ? () {
                          widget.controller.clear();
                          setState(() {
                            _error = null;
                            _showSuggestions = true;
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
                          FocusScope.of(context).unfocus();
                          setState(() => _showSuggestions = true);
                        }
                      : null,
                  icon: const Icon(Icons.folder_open),
                ),
              ],
            ),
          ),
        ),
        if (showSuggestions)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: Material(
              elevation: 1,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _suggestions.length,
                itemBuilder: (context, index) {
                  final entry = _suggestions[index];
                  final slash = entry.path.lastIndexOf('/');
                  final parent = slash == -1
                      ? 'Repository root'
                      : entry.path.substring(0, slash);
                  return ListTile(
                    key: Key('repository-path-suggestion:${entry.path}'),
                    dense: true,
                    title: Text(entry.path),
                    subtitle: Text(parent),
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
        if (_snapshot?.isTruncated == true && showSuggestions)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('Some repository paths are hidden. Refine the search.'),
          ),
      ],
    );
  }
}
