import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/error.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:gift/src/backend/setup.dart';

/// Provides clone/init actions for Welcome and shallow-history/root mapping
/// actions for an already opened repository. All path and branch validation
/// remains in the backend so this surface cannot turn text into shell syntax.
class RepositorySetupDialog extends StatefulWidget {
  const RepositorySetupDialog({
    super.key,
    required this.gateway,
    this.repository,
  });

  final GitGateway gateway;
  final RepositoryOpened? repository;

  @override
  State<RepositorySetupDialog> createState() => _RepositorySetupDialogState();
}

class _RepositorySetupDialogState extends State<RepositorySetupDialog> {
  final _sourceController = TextEditingController();
  final _cloneDestinationController = TextEditingController();
  final _cloneBranchController = TextEditingController();
  final _depthController = TextEditingController();
  final _initPathController = TextEditingController();
  final _initBranchController = TextEditingController(text: 'main');
  final _rootPathController = TextEditingController();
  GitRootDiscoverySnapshot? _roots;
  GitError? _error;
  String? _message;
  var _isBusy = false;
  var _recursive = false;

  @override
  void initState() {
    super.initState();
    _rootPathController.text = widget.repository?.root ?? '';
  }

  @override
  void dispose() {
    _sourceController.dispose();
    _cloneDestinationController.dispose();
    _cloneBranchController.dispose();
    _depthController.dispose();
    _initPathController.dispose();
    _initBranchController.dispose();
    _rootPathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 560;
    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 32,
        vertical: compact ? 12 : 20,
      ),
      title: Row(
        children: [
          const Icon(Icons.settings_system_daydream_outlined, size: 20),
          const SizedBox(width: 8),
          const Expanded(child: Text('Repository setup')),
          if (_isBusy)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
      content: SizedBox(
        width: (size.width - (compact ? 24 : 64)).clamp(260.0, 760.0),
        height: (size.height - (compact ? 200 : 150)).clamp(160.0, 580.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error case final error?) _errorBanner(error),
            if (_message case final message?)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  message,
                  key: const Key('setup-message'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            Expanded(
              child: DefaultTabController(
                length: 3,
                child: Column(
                  children: [
                    const TabBar(
                      tabs: [
                        Tab(text: 'Clone'),
                        Tab(text: 'Initialize'),
                        Tab(text: 'Roots'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _cloneView(context),
                          _initView(context),
                          _rootsView(context),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actionsOverflowButtonSpacing: 4,
      actions: [
        TextButton(
          key: const Key('close-setup-dialog'),
          onPressed: _isBusy ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _errorBanner(GitError error) => Container(
    key: const Key('setup-error'),
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(8),
    color: Theme.of(context).colorScheme.errorContainer,
    child: Text(error.userMessage),
  );

  Widget _cloneView(BuildContext context) => ListView(
    key: const Key('clone-view'),
    children: [
      _field(
        key: const Key('clone-source'),
        controller: _sourceController,
        label: 'Source URL or local path',
        hint: 'https://host.example/team/project.git',
      ),
      const SizedBox(height: 8),
      _field(
        key: const Key('clone-destination'),
        controller: _cloneDestinationController,
        label: 'Destination folder',
        hint: 'Absolute empty folder',
      ),
      const SizedBox(height: 8),
      _field(
        key: const Key('clone-branch'),
        controller: _cloneBranchController,
        label: 'Branch (optional)',
        hint: 'main',
      ),
      const SizedBox(height: 8),
      _field(
        key: const Key('clone-depth'),
        controller: _depthController,
        label: 'Shallow depth (optional)',
        hint: 'Leave blank for full history',
        keyboardType: TextInputType.number,
      ),
      SwitchListTile(
        key: const Key('clone-recursive'),
        contentPadding: EdgeInsets.zero,
        title: const Text('Clone submodules recursively'),
        value: _recursive,
        onChanged: _isBusy
            ? null
            : (value) => setState(() => _recursive = value),
      ),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton.icon(
          key: const Key('clone-repository'),
          onPressed: _isBusy ? null : _clone,
          icon: const Icon(Icons.download),
          label: const Text('Clone repository'),
        ),
      ),
    ],
  );

  Widget _initView(BuildContext context) => ListView(
    key: const Key('initialize-view'),
    children: [
      _field(
        key: const Key('init-path'),
        controller: _initPathController,
        label: 'Repository folder',
        hint: 'Existing or new empty folder',
      ),
      const SizedBox(height: 8),
      _field(
        key: const Key('init-branch'),
        controller: _initBranchController,
        label: 'Initial branch (optional)',
        hint: 'main',
      ),
      const SizedBox(height: 12),
      const Text(
        'Initialization only creates Git metadata. Existing files are not changed.',
      ),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton.icon(
          key: const Key('initialize-repository'),
          onPressed: _isBusy ? null : _initialize,
          icon: const Icon(Icons.create_new_folder_outlined),
          label: const Text('Initialize repository'),
        ),
      ),
    ],
  );

  Widget _rootsView(BuildContext context) => ListView(
    key: const Key('roots-view'),
    children: [
      _field(
        key: const Key('roots-path'),
        controller: _rootPathController,
        label: 'Folder to scan',
        hint: 'Absolute folder',
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          OutlinedButton.icon(
            key: const Key('discover-roots'),
            onPressed: _isBusy ? null : _discoverRoots,
            icon: const Icon(Icons.account_tree_outlined, size: 18),
            label: const Text('Map Git roots'),
          ),
          if (widget.repository != null)
            OutlinedButton.icon(
              key: const Key('unshallow-repository'),
              onPressed: _isBusy ? null : _unshallow,
              icon: const Icon(Icons.unfold_more, size: 18),
              label: const Text('Fetch full history'),
            ),
          if (widget.repository != null)
            OutlinedButton.icon(
              key: const Key('publish-repository'),
              onPressed: _isBusy ? null : _publish,
              icon: const Icon(Icons.cloud_upload_outlined, size: 18),
              label: const Text('Publish to origin'),
            ),
        ],
      ),
      if (_roots case final roots?) ...[
        const SizedBox(height: 12),
        Text(
          roots.isTruncated
              ? 'Scan stopped at its safety limit.'
              : '${roots.roots.length} Git root${roots.roots.length == 1 ? '' : 's'} found',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        for (final root in roots.roots)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.folder_special_outlined),
            title: Text(
              root.relativePath.isEmpty ? 'Selected folder' : root.relativePath,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(root.path, overflow: TextOverflow.ellipsis),
          ),
      ],
    ],
  );

  Widget _field({
    required Key key,
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType? keyboardType,
  }) => TextField(
    key: key,
    controller: controller,
    enabled: !_isBusy,
    keyboardType: keyboardType,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      border: const OutlineInputBorder(),
      isDense: true,
    ),
  );

  Future<void> _clone() async {
    final depthText = _depthController.text.trim();
    final depth = depthText.isEmpty ? null : int.tryParse(depthText);
    await _run(() async {
      final result = await widget.gateway.cloneRepository(
        GitCloneRequest(
          source: _sourceController.text,
          destination: _cloneDestinationController.text,
          branch: _cloneBranchController.text.trim().isEmpty
              ? null
              : _cloneBranchController.text.trim(),
          depth: depth,
          recursive: _recursive,
        ),
      );
      if (mounted) Navigator.of(context).pop(result.repository);
    });
  }

  Future<void> _initialize() async {
    await _run(() async {
      final result = await widget.gateway.initRepository(
        GitInitRequest(
          path: _initPathController.text,
          initialBranch: _initBranchController.text.trim().isEmpty
              ? null
              : _initBranchController.text.trim(),
        ),
      );
      if (mounted) Navigator.of(context).pop(result.repository);
    });
  }

  Future<void> _unshallow() async {
    final repository = widget.repository;
    if (repository == null) return;
    await _run(() async {
      final result = await widget.gateway.unshallowRepository(
        repository.repositoryId,
      );
      if (mounted) {
        setState(() => _message = result.summary);
      }
    });
  }

  Future<void> _publish() async {
    final repository = widget.repository;
    if (repository == null) return;
    await _run(() async {
      final result = await widget.gateway.publishBranch(
        repository.repositoryId,
        'origin',
      );
      if (mounted) setState(() => _message = result.summary);
    });
  }

  Future<void> _discoverRoots() async {
    await _run(() async {
      final roots = await widget.gateway.discoverRepositoryRoots(
        _rootPathController.text,
      );
      if (mounted) setState(() => _roots = roots);
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
