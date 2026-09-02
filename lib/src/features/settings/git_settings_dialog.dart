import 'package:gitflu/src/features/settings/git_settings_controller.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

class GitSettingsDialog extends StatefulWidget {
  const GitSettingsDialog({
    super.key,
    required this.controller,
    this.selectExecutable,
  });

  final GitSettingsController controller;
  final Future<String?> Function()? selectExecutable;

  @override
  State<GitSettingsDialog> createState() => _GitSettingsDialogState();
}

class _GitSettingsDialogState extends State<GitSettingsDialog> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    Future<void>.microtask(widget.controller.initialize);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;
    final width = (MediaQuery.sizeOf(context).width - 80).clamp(0.0, 420.0);
    return AlertDialog(
      title: const Text('Git executable'),
      content: SizedBox(
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (state.isLoading) const LinearProgressIndicator(),
            if (state.installation case final installation?) ...[
              SelectableText(installation.executablePath),
              const SizedBox(height: 4),
              Text('Version ${installation.version}'),
            ],
            if (state.error case final error?)
              Text(error.userMessage, key: const Key('git-settings-error')),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: state.isLoading ? null : widget.controller.retry,
          child: const Text('Retry'),
        ),
        OutlinedButton(
          onPressed: state.isLoading ? null : _selectExecutable,
          child: const Text('Choose Git executable'),
        ),
      ],
    );
  }

  Future<void> _selectExecutable() async {
    final path = widget.selectExecutable == null
        ? await _pickExecutable()
        : await widget.selectExecutable!();
    if (path == null || path.isEmpty) return;
    await widget.controller.configurePath(path);
  }

  Future<String?> _pickExecutable() async {
    final file = await openFile();
    return file?.path;
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }
}
