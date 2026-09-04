import 'package:gift/src/app/credentials_dialog.dart';
import 'package:gift/src/backend/credentials.dart';
import 'package:flutter/material.dart';
import 'package:gift/src/app/app_preferences.dart';
import 'package:gift/src/app/app_strings.dart';
import 'package:gift/src/app/error_dialog.dart';
import 'package:gift/src/backend/error.dart';

class PreferencesDialog extends StatefulWidget {
  const PreferencesDialog({
    super.key,
    this.credentialStore,
    this.tester,
    this.oauthGateway,
    required this.preferences,
    required this.onSave,
  });

  final GiftPreferences preferences;
  final Future<void> Function(GiftPreferences) onSave;
  final GitCredentialStore? credentialStore;
  final GitCredentialTestGateway? tester;
  final GitCredentialOAuthGateway? oauthGateway;

  @override
  State<PreferencesDialog> createState() => _PreferencesDialogState();
}

class _PreferencesDialogState extends State<PreferencesDialog> {
  late double _uiScale;
  late bool _reducedMotion;
  late bool _highContrast;
  late bool _colorSafeGraph;
  late int _refreshSeconds;
  late final TextEditingController _defaultBranchController;
  late final TextEditingController _defaultRemoteController;
  late final Map<String, TextEditingController> _shortcutControllers;
  String? _error;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    final preferences = widget.preferences;
    _uiScale = preferences.uiScale;
    _reducedMotion = preferences.reducedMotion;
    _highContrast = preferences.highContrast;
    _colorSafeGraph = preferences.colorSafeGraph;
    _refreshSeconds = preferences.refreshInterval.inSeconds;
    _defaultBranchController = TextEditingController(
      text: preferences.defaultBranch ?? '',
    );
    _defaultRemoteController = TextEditingController(
      text: preferences.defaultRemote ?? '',
    );
    _shortcutControllers = {
      for (final id in const [
        'refresh',
        'history',
        'commit',
        'fileHistory',
        'focusSearch',
        'cancel',
        'nextCommit',
        'previousCommit',
        'nextTab',
        'previousTab',
        'branch',
        'remote',
      ])
        id: TextEditingController(text: preferences.shortcut(id)),
    };
  }

  @override
  void dispose() {
    _defaultBranchController.dispose();
    _defaultRemoteController.dispose();
    for (final controller in _shortcutControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return AlertDialog(
      title: const Text(GiftStrings.preferences),
      content: SizedBox(
        width: (size.width - 64).clamp(260.0, 520.0),
        height: (size.height - 180).clamp(300.0, 560.0),
        child: ListView(
          children: [
            Text(
              GiftStrings.uiScale,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Semantics(
              label: '${GiftStrings.uiScale}: ${_uiScale.toStringAsFixed(1)}x',
              slider: true,
              child: Slider(
                key: const Key('preference-ui-scale'),
                min: 0.8,
                max: 1.6,
                divisions: 8,
                value: _uiScale,
                label: '${_uiScale.toStringAsFixed(1)}x',
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _uiScale = value),
              ),
            ),
            Text('${_uiScale.toStringAsFixed(1)}x'),
            const SizedBox(height: 12),
            SwitchListTile(
              key: const Key('preference-reduced-motion'),
              title: const Text(GiftStrings.reducedMotion),
              subtitle: const Text(
                'Disable avoidable transitions and effects.',
              ),
              value: _reducedMotion,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _reducedMotion = value),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              key: const Key('preference-high-contrast'),
              title: const Text(GiftStrings.highContrast),
              value: _highContrast,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _highContrast = value),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              key: const Key('preference-color-safe-graph'),
              title: const Text(GiftStrings.colorSafeGraph),
              subtitle: const Text(
                'Keep graph lanes distinguishable by palette.',
              ),
              value: _colorSafeGraph,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _colorSafeGraph = value),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              key: const Key('preference-refresh-policy'),
              initialValue: _refreshSeconds,
              decoration: const InputDecoration(
                labelText: GiftStrings.refreshPolicy,
              ),
              items: const [5, 15, 30, 60, 300]
                  .map(
                    (seconds) => DropdownMenuItem(
                      value: seconds,
                      child: Text('$seconds seconds'),
                    ),
                  )
                  .toList(),
              onChanged: _saving
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() => _refreshSeconds = value);
                      }
                    },
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('preference-default-branch'),
              controller: _defaultBranchController,
              decoration: const InputDecoration(
                labelText: GiftStrings.defaultBranch,
                hintText: 'main',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('preference-default-remote'),
              controller: _defaultRemoteController,
              decoration: const InputDecoration(
                labelText: GiftStrings.defaultRemote,
                hintText: 'origin',
              ),
            ),
            if (widget.credentialStore case final store?)
              OutlinedButton.icon(
                key: const Key('manage-git-accounts'),
                onPressed: _saving
                    ? null
                    : () => showDialog<void>(
                        context: context,
                        builder: (_) => CredentialsDialog(
                          store: store,
                          tester: widget.tester,
                          oauthGateway: widget.oauthGateway,
                        ),
                      ),
                icon: const Icon(Icons.key_outlined),
                label: const Text('Manage Git accounts'),
              ),
            const SizedBox(height: 16),
            Text(
              GiftStrings.shortcuts,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            for (final entry in _shortcutControllers.entries) ...[
              TextField(
                key: ValueKey('preference-shortcut-${entry.key}'),
                controller: entry.value,
                decoration: InputDecoration(
                  labelText: switch (entry.key) {
                    'refresh' => GiftStrings.refreshShortcut,
                    'history' => GiftStrings.historyShortcut,
                    'commit' => GiftStrings.commitShortcut,
                    'fileHistory' => GiftStrings.fileHistoryShortcut,
                    'focusSearch' => GiftStrings.focusSearchShortcut,
                    'cancel' => GiftStrings.cancelShortcut,
                    'nextCommit' => GiftStrings.nextCommitShortcut,
                    'previousCommit' => GiftStrings.previousCommitShortcut,
                    'nextTab' => GiftStrings.nextTabShortcut,
                    'previousTab' => GiftStrings.previousTabShortcut,
                    'branch' => GiftStrings.branchShortcut,
                    'remote' => GiftStrings.remoteShortcut,
                    _ => entry.key,
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (_error case final error?)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  error,
                  key: const Key('preference-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text(GiftStrings.cancel),
        ),
        FilledButton(
          key: const Key('save-preferences'),
          onPressed: _saving ? null : _save,
          child: const Text(GiftStrings.save),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final shortcuts = {
      ...widget.preferences.shortcuts,
      for (final entry in _shortcutControllers.entries)
        entry.key: entry.value.text,
    };
    final invalid = shortcuts.entries
        .where((entry) => shortcutActivator(entry.value) == null)
        .map((entry) => entry.key)
        .toList(growable: false);
    if (invalid.isNotEmpty) {
      final message = 'Invalid shortcut: ${invalid.join(', ')}.';
      setState(() => _error = message);
      await showGiftErrorDialog(context, message);
      return;
    }
    final next = widget.preferences.copyWith(
      uiScale: _uiScale,
      reducedMotion: _reducedMotion,
      highContrast: _highContrast,
      colorSafeGraph: _colorSafeGraph,
      shortcuts: shortcuts,
      defaultBranch: _defaultBranchController.text,
      defaultRemote: _defaultRemoteController.text,
      clearDefaultBranch: _defaultBranchController.text.trim().isEmpty,
      clearDefaultRemote: _defaultRemoteController.text.trim().isEmpty,
      refreshInterval: Duration(seconds: _refreshSeconds),
    );
    if (next.shortcutConflicts.isNotEmpty) {
      final message =
          '${GiftStrings.shortcutConflict}${next.shortcutConflicts.keys.join(', ')}.';
      setState(() => _error = message);
      await showGiftErrorDialog(context, message);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(next);
    } on GitError catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.userMessage;
      });
      await showGiftErrorDialog(context, error.userMessage);
      return;
    } on Object {
      if (!mounted) return;
      const message = 'Preferences could not be saved. Try again.';
      setState(() {
        _saving = false;
        _error = message;
      });
      await showGiftErrorDialog(context, message);
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }
}
