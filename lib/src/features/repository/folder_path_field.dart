import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum FolderPathPurpose {
  openRepository,
  cloneSource,
  cloneDestination,
  initializeRepository,
  nestedRootScan,
  worktreeDestination,
  replaceWorkspaceRoot,
}

enum FolderPathValidationStatus {
  valid,
  empty,
  notAbsolute,
  invalidCharacters,
  missing,
  inaccessible,
  file,
  notEmpty,
}

class FolderPathValidation {
  const FolderPathValidation({required this.status, this.message});

  const FolderPathValidation.valid()
    : this(status: FolderPathValidationStatus.valid);

  final FolderPathValidationStatus status;
  final String? message;

  bool get isValid => status == FolderPathValidationStatus.valid;
}

typedef FolderPathPicker = Future<String?> Function({String? initialDirectory});

/// Stores the last safe directory used by each folder workflow.
class FolderPathHistory {
  FolderPathHistory({this.preferences});

  static final shared = FolderPathHistory();

  final SharedPreferences? preferences;
  final Map<FolderPathPurpose, String> _memory = {};

  String? last(FolderPathPurpose purpose) {
    return _memory[purpose] ?? preferences?.getString(_key(purpose));
  }

  String? initialDirectory(FolderPathPurpose purpose) {
    final value = last(purpose);
    if (value == null || value.isEmpty) return null;
    try {
      final directory = Directory(value);
      return directory.existsSync() ? directory.path : directory.parent.path;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> remember(FolderPathPurpose purpose, String path) async {
    final value = path.trim();
    if (value.isEmpty) return;
    final directory = Directory(value);
    final remembered = directory.existsSync()
        ? directory.path
        : directory.parent.path;
    _memory[purpose] = remembered;
    await preferences?.setString(_key(purpose), remembered);
  }

  String _key(FolderPathPurpose purpose) => 'folder_picker.${purpose.name}';
}

FolderPathValidation validateAbsoluteFolderPath(
  String rawPath, {
  required bool allowMissing,
  bool allowRelative = false,
  bool requireEmpty = false,
}) {
  final path = rawPath.trim();
  if (path.isEmpty) {
    return const FolderPathValidation(
      status: FolderPathValidationStatus.empty,
      message: 'Enter a folder path.',
    );
  }
  if (_containsControlCharacters(path) || path.startsWith('-')) {
    return const FolderPathValidation(
      status: FolderPathValidationStatus.invalidCharacters,
      message: 'Use a folder path without options or control characters.',
    );
  }
  if (!_isAbsolutePath(path)) {
    if (allowRelative && _isSafeRelativePath(path)) {
      return const FolderPathValidation.valid();
    }
    return const FolderPathValidation(
      status: FolderPathValidationStatus.notAbsolute,
      message: 'Enter an absolute folder path.',
    );
  }

  FileSystemEntityType type;
  try {
    type = FileSystemEntity.typeSync(path, followLinks: true);
  } on FileSystemException {
    return const FolderPathValidation(
      status: FolderPathValidationStatus.inaccessible,
      message: 'This folder cannot be accessed.',
    );
  }
  if (type == FileSystemEntityType.file || type == FileSystemEntityType.link) {
    return const FolderPathValidation(
      status: FolderPathValidationStatus.file,
      message: 'Choose a folder, not a file.',
    );
  }
  if (type == FileSystemEntityType.notFound) {
    if (!allowMissing) {
      return const FolderPathValidation(
        status: FolderPathValidationStatus.missing,
        message: 'This folder does not exist.',
      );
    }
    try {
      if (!Directory(path).parent.existsSync()) {
        return const FolderPathValidation(
          status: FolderPathValidationStatus.missing,
          message: 'Choose a folder whose parent already exists.',
        );
      }
    } on FileSystemException {
      return const FolderPathValidation(
        status: FolderPathValidationStatus.inaccessible,
        message: 'The parent folder cannot be accessed.',
      );
    }
    return const FolderPathValidation.valid();
  }
  if (requireEmpty) {
    try {
      if (Directory(path).listSync(followLinks: true).isNotEmpty) {
        return const FolderPathValidation(
          status: FolderPathValidationStatus.notEmpty,
          message: 'Choose an empty folder.',
        );
      }
    } on FileSystemException {
      return const FolderPathValidation(
        status: FolderPathValidationStatus.inaccessible,
        message: 'This folder cannot be accessed.',
      );
    }
  }
  return const FolderPathValidation.valid();
}

class FolderPathField extends StatefulWidget {
  const FolderPathField({
    super.key,
    required this.controller,
    required this.purpose,
    required this.label,
    required this.hint,
    this.picker,
    this.history,
    this.allowMissing = false,
    this.requireEmpty = false,
    this.allowRelative = false,
    this.enabled = true,
    this.browseKey,
    this.clearKey,
    this.onChanged,
    this.fieldKey,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final FolderPathPurpose purpose;
  final String label;
  final String hint;
  final FolderPathPicker? picker;
  final FolderPathHistory? history;
  final bool allowMissing;
  final bool allowRelative;
  final bool requireEmpty;
  final bool enabled;
  final Key? browseKey;
  final Key? clearKey;
  final Key? fieldKey;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<FolderPathField> createState() => FolderPathFieldState();
}

class FolderPathFieldState extends State<FolderPathField> {
  FolderPathValidation? _validation;

  FolderPathValidation? get validation => _validation;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_syncValidation);
    _syncValidation();
  }

  @override
  void didUpdateWidget(covariant FolderPathField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncValidation);
      widget.controller.addListener(_syncValidation);
      _syncValidation();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncValidation);
    super.dispose();
  }

  FolderPathValidation validateNow() {
    final next = validateAbsoluteFolderPath(
      widget.controller.text,
      allowMissing: widget.allowMissing,
      allowRelative: widget.allowRelative,
      requireEmpty: widget.requireEmpty,
    );
    if (mounted && next != _validation) setState(() => _validation = next);
    return next;
  }

  Future<void> browse() => _browse();

  Future<void> _browse() async {
    final picker = widget.picker ?? _nativePicker;
    final history = widget.history ?? FolderPathHistory.shared;
    final selected = await picker(
      initialDirectory: history.initialDirectory(widget.purpose),
    );
    if (!mounted || selected == null || selected.trim().isEmpty) return;
    widget.controller.text = selected.trim();
    widget.controller.selection = TextSelection.collapsed(
      offset: widget.controller.text.length,
    );
    await history.remember(widget.purpose, widget.controller.text);
    validateNow();
  }

  Future<String?> _nativePicker({String? initialDirectory}) => getDirectoryPath(
    confirmButtonText: 'Choose',
    initialDirectory: initialDirectory,
  );

  void _clear() {
    widget.controller.clear();
    widget.controller.selection = const TextSelection.collapsed(offset: 0);
  }

  void _syncValidation() {
    final next = validateAbsoluteFolderPath(
      widget.controller.text,
      allowMissing: widget.allowMissing,
      allowRelative: widget.allowRelative,
      requireEmpty: widget.requireEmpty,
    );
    if (mounted && next != _validation) setState(() => _validation = next);
    widget.onChanged?.call(widget.controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final validation = _validation;
    final message = validation == null || validation.isValid
        ? null
        : validation.message;
    final text = widget.controller.text;
    return Tooltip(
      message: text.isEmpty ? widget.hint : text,
      child: TextField(
        key: widget.fieldKey,
        controller: widget.controller,
        enabled: widget.enabled,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: TextInputAction.done,
        onSubmitted: (value) {
          final result = validateNow();
          if (result.isValid) widget.onSubmitted?.call(value.trim());
        },
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          errorText: message,
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (text.isNotEmpty)
                IconButton(
                  key: widget.clearKey,
                  tooltip: 'Clear path',
                  onPressed: widget.enabled ? _clear : null,
                  icon: const Icon(Icons.clear, size: 18),
                ),
              IconButton(
                key: widget.browseKey,
                tooltip: 'Browse for folder',
                onPressed: widget.enabled ? _browse : null,
                icon: const Icon(Icons.folder_open, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _isSafeRelativePath(String path) {
  if (path.startsWith('/') ||
      path.startsWith('\\') ||
      RegExp(r'^[A-Za-z]:').hasMatch(path)) {
    return false;
  }
  final segments = path.replaceAll('\\', '/').split('/');
  return segments.every(
    (segment) => segment.isNotEmpty && segment != '.' && segment != '..',
  );
}

bool _isAbsolutePath(String path) =>
    path.startsWith('/') ||
    path.startsWith('\\') ||
    RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);

bool _containsControlCharacters(String path) =>
    path.runes.any((rune) => rune == 0 || rune < 0x20 || rune == 0x7f);
