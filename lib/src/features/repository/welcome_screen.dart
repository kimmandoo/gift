import 'package:gift/src/features/repository/recent_repository_store.dart';
import 'package:gift/src/features/repository/changes_screen.dart';
import 'package:gift/src/features/repository/repository_controller.dart';
import 'package:gift/src/features/settings/git_settings_controller.dart';
import 'package:gift/src/features/settings/git_settings_dialog.dart';
import 'package:gift/src/features/repository/workspace_controller.dart';
import 'package:gift/src/features/repository/workspace_screen.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gift/src/app/pixel_theme.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({
    super.key,
    required this.gateway,
    required this.recentStore,
    this.preferences,
    this.selectDirectory,
    this.selectExecutable,
    this.workspaceController,
    this.autoInitialize = true,
  });

  final GitGateway gateway;
  final RecentRepositoryStore recentStore;
  final SharedPreferences? preferences;
  final Future<String?> Function()? selectDirectory;
  final Future<String?> Function()? selectExecutable;
  final WorkspaceController? workspaceController;
  final bool autoInitialize;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  late final RepositoryController _repositoryController;
  GitSettingsController? _gitSettingsController;
  WorkspaceController? _workspaceController;

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
    _workspaceController = widget.workspaceController;
    _workspaceController?.addListener(_onChanged);
    if (widget.autoInitialize) {
      Future<void>.microtask(_initialize);
    }
  }

  @override
  void dispose() {
    _repositoryController
      ..removeListener(_onChanged)
      ..dispose();
    _workspaceController?.removeListener(_onChanged);
    _gitSettingsController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _repositoryController.state;
    final textTheme = Theme.of(context).textTheme;
    final compact = MediaQuery.sizeOf(context).width < 480;
    final workspace = _workspaceController;
    if (workspace != null &&
        (workspace.state.isRestoring || workspace.state.tabs.isNotEmpty)) {
      return WorkspaceScreen(
        controller: workspace,
        onOpenRepository: _selectAndOpen,
        onWorkspaceEmpty: _repositoryController.closeRepository,
      );
    }
    if (state.openedRepository case final opened?) {
      return ChangesScreen(
        gateway: widget.gateway,
        repository: opened,
        onBack: _repositoryController.closeRepository,
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('GIFT'),
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
              padding: EdgeInsets.fromLTRB(
                compact ? 16 : 24,
                compact ? 20 : 28,
                compact ? 16 : 24,
                compact ? 16 : 24,
              ),
              child: ListView(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Image(
                      key: const Key('welcome-logo'),
                      image: const AssetImage('assets/images/gift_icon.png'),
                      width: compact ? 80 : 96,
                      height: compact ? 80 : 96,
                      filterQuality: FilterQuality.none,
                      semanticLabel: 'GIFT pixel mascot',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Open a Git repository',
                    style: textTheme.headlineMedium,
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
                  Text('Recent repositories', style: textTheme.titleLarge),
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
          onTap: repository.exists ? () => _openPath(repository.path) : null,
          trailing: IconButton(
            tooltip: 'Remove',
            onPressed: () => _repositoryController.removeRecent(repository),
            icon: const Icon(Icons.close),
          ),
        );
      },
    );
  }

  Future<void> _selectAndOpen([int? replaceIndex]) async {
    final path = widget.selectDirectory == null
        ? await getDirectoryPath(confirmButtonText: 'Open')
        : await widget.selectDirectory!();
    if (path == null || path.isEmpty) return;
    await _openPath(path, replaceIndex: replaceIndex);
  }

  Future<void> _openPath(String path, {int? replaceIndex}) async {
    final workspace = _workspaceController;
    if (workspace == null) {
      await _repositoryController.openPath(path);
      return;
    }
    final opened = await workspace.openPath(path, replaceIndex: replaceIndex);
    if (opened?.repository != null) {
      await _repositoryController.reloadRecent();
    }
  }

  Future<void> _initialize() async {
    await _repositoryController.initialize();
    if (!mounted) return;
    final workspace = _workspaceController;
    if (workspace != null &&
        _repositoryController.state.gitInstallation != null) {
      await workspace.restore();
    }
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
