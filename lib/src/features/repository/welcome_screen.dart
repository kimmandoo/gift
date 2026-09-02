import 'package:gitflu/src/features/repository/recent_repository_store.dart';
import 'package:gitflu/src/features/repository/changes_screen.dart';
import 'package:gitflu/src/features/repository/repository_controller.dart';
import 'package:gitflu/src/features/settings/git_settings_controller.dart';
import 'package:gitflu/src/features/settings/git_settings_dialog.dart';
import 'package:gitflu/src/backend/git_gateway.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gitflu/src/app/pixel_theme.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({
    super.key,
    required this.gateway,
    required this.recentStore,
    this.preferences,
    this.selectDirectory,
    this.selectExecutable,
    this.autoInitialize = true,
  });

  final GitGateway gateway;
  final RecentRepositoryStore recentStore;
  final SharedPreferences? preferences;
  final Future<String?> Function()? selectDirectory;
  final Future<String?> Function()? selectExecutable;
  final bool autoInitialize;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  late final RepositoryController _repositoryController;
  GitSettingsController? _gitSettingsController;

  @override
  void initState() {
    super.initState();
    // The controller owns loading and errors; this widget only rebuilds when
    // the controller tells it that visible state changed.
    if (widget.preferences case final preferences?) {
      _gitSettingsController = GitSettingsController(
        gateway: widget.gateway,
        preferences: preferences,
      );
    }
    _repositoryController = RepositoryController(
      gateway: widget.gateway,
      recentStore: widget.recentStore,
      gitSettingsController: _gitSettingsController,
    )..addListener(_onChanged);
    if (widget.autoInitialize) {
      Future<void>.microtask(_repositoryController.initialize);
    }
  }

  @override
  void dispose() {
    _repositoryController
      ..removeListener(_onChanged)
      ..dispose();
    _gitSettingsController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _repositoryController.state;
    if (state.openedRepository case final opened?) {
      return ChangesScreen(
        gateway: widget.gateway,
        repository: opened,
        onBack: _repositoryController.closeRepository,
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('gitflu'),
        actions: [
          const PixelThemeToggle(),
          if (_gitSettingsController != null)
            IconButton(
              tooltip: 'Git settings',
              onPressed: _showGitSettings,
              icon: const Icon(Icons.settings_outlined),
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: ListView(
                children: [
                  const Text(
                    'Open a Git repository',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Choose a working folder to start reviewing changes.',
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: state.canOpen && !state.isLoading
                        ? _selectAndOpen
                        : null,
                    child: const Text('Open Repository'),
                  ),
                  if (state.isLoading) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                  ],
                  if (state.errorMessage case final message?) ...[
                    const SizedBox(height: 16),
                    Text(
                      message,
                      key: const Key('repository-error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  const Text(
                    'Recent repositories',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  _recentList(state.recentRepositories),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _recentList(List<RecentRepository> repositories) {
    if (repositories.isEmpty) {
      return const Align(
        alignment: Alignment.topLeft,
        child: Text('No recently opened repositories.'),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: repositories.length,
      itemBuilder: (context, index) {
        final repository = repositories[index];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(repository.path),
          subtitle: Text(repository.exists ? 'Available' : 'Missing'),
          onTap: repository.exists
              ? () => _repositoryController.openPath(repository.path)
              : null,
          trailing: IconButton(
            tooltip: 'Remove',
            onPressed: () => _repositoryController.removeRecent(repository),
            icon: const Icon(Icons.close),
          ),
        );
      },
    );
  }

  Future<void> _selectAndOpen() async {
    final path = widget.selectDirectory == null
        ? await getDirectoryPath(confirmButtonText: 'Open')
        : await widget.selectDirectory!();
    if (path == null || path.isEmpty) return;
    await _repositoryController.openPath(path);
  }

  Future<void> _showGitSettings() async {
    final controller = _gitSettingsController;
    if (controller == null) return;
    await showDialog<void>(
      context: context,
      builder: (context) => GitSettingsDialog(
        controller: controller,
        selectExecutable: widget.selectExecutable,
      ),
    );
    _repositoryController.applyGitSettings(controller.state);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }
}
