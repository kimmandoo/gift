import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A searchable action exposed by the current screen.
class CommandPaletteAction {
  const CommandPaletteAction({
    required this.id,
    required this.label,
    required this.icon,
    required this.onInvoke,
    this.subtitle,
    this.enabled = true,
    this.disabledReason,
    this.keywords = const <String>[],
  }) : assert(enabled || disabledReason != null);

  final String id;
  final String label;
  final IconData icon;
  final String? subtitle;
  final List<String> keywords;
  final bool enabled;
  final String? disabledReason;
  final FutureOr<void> Function() onInvoke;

  String get searchText =>
      <String>[label, subtitle ?? '', ...keywords].join(' ').toLowerCase();
}

List<CommandPaletteAction> filterCommandPaletteActions(
  Iterable<CommandPaletteAction> actions,
  String query,
) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) return List.unmodifiable(actions);
  final tokens = normalized.split(RegExp(r'\s+'));
  final matches = actions
      .where((action) {
        final text = action.searchText;
        return tokens.every(text.contains);
      })
      .toList(growable: false);
  return List.unmodifiable(matches);
}

Future<void> showCommandPalette(
  BuildContext context, {
  required List<CommandPaletteAction> actions,
}) async {
  final action = await showDialog<CommandPaletteAction>(
    context: context,
    barrierLabel: 'Command palette',
    builder: (_) => CommandPaletteDialog(actions: actions),
  );
  if (action == null || !action.enabled) return;
  await action.onInvoke();
}

class CommandPaletteDialog extends StatefulWidget {
  const CommandPaletteDialog({required this.actions, super.key});

  final List<CommandPaletteAction> actions;

  @override
  State<CommandPaletteDialog> createState() => _CommandPaletteDialogState();
}

class _CommandPaletteDialogState extends State<CommandPaletteDialog> {
  late final TextEditingController _queryController;
  late final FocusNode _focusNode;
  var _selectedIndex = 0;

  List<CommandPaletteAction> get _filtered =>
      filterCommandPaletteActions(widget.actions, _queryController.text);

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController()..addListener(_onQueryChanged);
    _focusNode = FocusNode(debugLabel: 'command-palette-list');
  }

  @override
  void dispose() {
    _queryController
      ..removeListener(_onQueryChanged)
      ..dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    if (!mounted) return;
    setState(() => _selectedIndex = 0);
  }

  void _moveSelection(int delta) {
    final count = _filtered.length;
    if (count == 0) return;
    setState(() => _selectedIndex = (_selectedIndex + delta + count) % count);
  }

  void _invokeSelected() {
    final actions = _filtered;
    if (actions.isEmpty) return;
    final action = actions[_selectedIndex.clamp(0, actions.length - 1)];
    if (!action.enabled) return;
    Navigator.of(context).pop(action);
  }

  @override
  Widget build(BuildContext context) {
    final actions = _filtered;
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      key: const Key('command-palette-dialog'),
      child: SizedBox(
        width: (size.width - 48).clamp(280.0, 640.0),
        height: (size.height - 120).clamp(220.0, 520.0),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                _moveSelection(1),
            const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                _moveSelection(-1),
            const SingleActivator(LogicalKeyboardKey.enter): _invokeSelected,
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                Navigator.of(context).pop(),
          },
          child: Focus(
            focusNode: _focusNode,
            autofocus: true,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Command palette',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('command-palette-search'),
                    controller: _queryController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      labelText: 'Search actions',
                      hintText: 'Type an action name or keyword',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: actions.isEmpty
                        ? const Center(child: Text('No matching actions.'))
                        : ListView.builder(
                            key: const Key('command-palette-results'),
                            itemCount: actions.length,
                            itemBuilder: (context, index) {
                              final action = actions[index];
                              final selected = index == _selectedIndex;
                              return ListTile(
                                key: ValueKey('command-palette-${action.id}'),
                                selected: selected,
                                enabled: action.enabled,
                                leading: Icon(action.icon),
                                title: Text(action.label),
                                subtitle: Text(
                                  action.enabled
                                      ? action.subtitle ?? ''
                                      : action.disabledReason!,
                                ),
                                onTap: action.enabled
                                    ? () => Navigator.of(context).pop(action)
                                    : null,
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Arrow keys to move · Enter to run · Esc to close',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
