import 'package:flutter/services.dart';
import 'package:gift/src/features/repository/context_actions.dart';
import 'package:gift/src/features/repository/path_actions.dart';
import 'package:gift/src/features/repository/recent_repository_store.dart';
import 'package:gift/src/features/repository/folder_path_field.dart';
import 'package:gift/src/features/repository/changes_screen.dart';
import 'package:gift/src/features/repository/repository_controller.dart';
import 'package:gift/src/features/settings/git_settings_controller.dart';
import 'package:gift/src/features/settings/git_settings_dialog.dart';
import 'package:gift/src/features/repository/workspace_controller.dart';
import 'package:gift/src/features/repository/workspace_screen.dart';
import 'package:gift/src/features/repository/repository_setup_dialog.dart';
import 'package:gift/src/app/app_preferences.dart';
import 'package:gift/src/app/preferences_dialog.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/credentials.dart';
import 'package:gift/src/app/repository_credential_store.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gift/src/app/pixel_theme.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({
    super.key,
    required this.gateway,
    required this.recentStore,
    this.credentialStore,
    this.repositoryCredentialStore,
    this.oauthGateway,
    this.preferences,
    this.selectDirectory,
    this.selectExecutable,
    this.workspaceController,
    this.fileManager = const PlatformFileManagerRevealer(),
    this.autoInitialize = true,
  });

  final GitGateway gateway;
  final RecentRepositoryStore recentStore;
  final GitCredentialStore? credentialStore;
  final RepositoryCredentialStore? repositoryCredentialStore;
  final GitCredentialOAuthGateway? oauthGateway;
  final SharedPreferences? preferences;
  final Future<String?> Function()? selectDirectory;
  final Future<String?> Function()? selectExecutable;
  final WorkspaceController? workspaceController;
  final FileManagerRevealer fileManager;
  final bool autoInitialize;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  late final RepositoryController _repositoryController;
  GitSettingsController? _gitSettingsController;
  WorkspaceController? _workspaceController;
  late final FolderPathHistory _folderHistory;

  @override
  void initState() {
    super.initState();
    _folderHistory = FolderPathHistory(preferences: widget.preferences);
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
        credentialStore: widget.credentialStore,
        repositoryCredentialStore: widget.repositoryCredentialStore,
        selectDirectory: widget.selectDirectory == null
            ? null
            : ({String? initialDirectory}) => widget.selectDirectory!(),
        pathHistory: _folderHistory,
        onOpenRepositoryPath: (path, replaceIndex) =>
            _openPath(path, replaceIndex: replaceIndex),
      );
    }
    if (state.openedRepository case final opened?) {
      return ChangesScreen(
        gateway: widget.gateway,
        repository: opened,
        onBack: _repositoryController.closeRepository,
        credentialStore: widget.credentialStore,
        repositoryCredentialStore: widget.repositoryCredentialStore,
        pathHistory: _folderHistory,
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('GIFT'),
        actions: [
          const PixelThemeToggle(),
          Builder(
            builder: (context) => PixelToolbarIconButton(
              key: const Key('open-preferences'),
              tooltip: 'Accessibility and preferences',
              onPressed: () => _showPreferences(context),
              icon: const Icon(Icons.tune_outlined),
            ),
          ),
          if (_gitSettingsController != null)
            PixelToolbarIconButton(
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
                  Text('Get started', style: textTheme.titleLarge),
                  const SizedBox(height: 8),
                  const Text(
                    'Open an existing repository, or clone and initialize one.',
                  ),
                  const SizedBox(height: 24),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final openButton = FilledButton.icon(
                        onPressed: state.canOpen && !state.isLoading
                            ? _selectAndOpen
                            : null,
                        icon: const Icon(Icons.folder_open, size: 18),
                        label: const Text('Open Repository'),
                      );
                      final setupButton = OutlinedButton.icon(
                        key: const Key('setup-repository'),
                        onPressed:
                            state.gitInstallation == null || state.isLoading
                            ? null
                            : _showRepositorySetup,
                        icon: const Icon(Icons.add_box_outlined, size: 18),
                        label: const Text('Clone or initialize'),
                      );
                      if (constraints.maxWidth < 520) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            openButton,
                            const SizedBox(height: 8),
                            setupButton,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: openButton),
                          const SizedBox(width: 8),
                          Expanded(child: setupButton),
                        ],
                      );
                    },
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
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: repositories.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final repository = repositories[index];
        final available = repository.exists;
        final colors = Theme.of(context).colorScheme;
        return ContextActionMenu(
          key: ValueKey('recent-menu:${repository.path}'),
          snapshot: _recentActionSnapshot(repository),
          actions: _recentActions(repository),
          onAction: _handleRecentAction,
          child: Card(
            key: ValueKey('recent-repository:${repository.path}'),
            child: ListTile(
              leading: Icon(
                available
                    ? Icons.account_tree_outlined
                    : Icons.folder_off_outlined,
                color: available ? colors.primary : colors.error,
              ),
              title: Text(
                repository.path,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                available ? 'Available · click to open' : 'Missing',
              ),
              onTap: available ? () => _openPath(repository.path) : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ContextActionMenuButton(
                    key: ValueKey('recent-actions:${repository.path}'),
                  ),
                  IconButton(
                    tooltip: 'Remove',
                    onPressed: () =>
                        _repositoryController.removeRecent(repository),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  ContextActionSnapshot _recentActionSnapshot(RecentRepository repository) {
    final opened = RepositoryOpened(
      repositoryId: RepositoryId(value: 'recent:${repository.path}'),
      root: repository.path,
    );
    return ContextActionSnapshot(
      repository: opened,
      target: ContextActionTarget.repository(
        path: repository.path,
        label: repository.path,
      ),
      fingerprint: '${repository.path}|${repository.exists}',
    );
  }

  List<ContextActionDescriptor> _recentActions(RecentRepository repository) {
    final snapshot = _recentActionSnapshot(repository);
    final available = repository.exists;
    return [
      ContextActionDescriptor(
        id: ContextActionId.openRepository,
        label: 'Open repository',
        icon: Icons.folder_open,
        group: ContextActionGroup.workflow,
        route: ContextActionRoute.openRepository,
        snapshot: snapshot,
        enabled: available,
        disabledReason: available ? null : 'Repository path is not available.',
      ),
      ContextActionDescriptor(
        id: ContextActionId.removeRecentRepository,
        label: 'Remove from recent',
        icon: Icons.remove_circle_outline,
        group: ContextActionGroup.destructive,
        route: ContextActionRoute.removeRecentRepository,
        snapshot: snapshot,
      ),
      ContextActionDescriptor(
        id: ContextActionId.copyRepositoryPath,
        label: 'Copy repository path',
        icon: Icons.content_copy,
        group: ContextActionGroup.inspect,
        route: ContextActionRoute.copyRepositoryPath,
        snapshot: snapshot,
      ),
      ContextActionDescriptor(
        id: ContextActionId.revealRepository,
        label: 'Reveal in file manager',
        icon: Icons.folder_open,
        group: ContextActionGroup.inspect,
        route: ContextActionRoute.revealRepository,
        snapshot: snapshot,
        enabled: available,
        disabledReason: available ? null : 'Repository path is not available.',
      ),
    ];
  }

  Future<void> _handleRecentAction(ContextActionDescriptor action) async {
    if (action.snapshot.target.kind != ContextActionTargetKind.repository) {
      return;
    }
    final repository = _repositoryController.state.recentRepositories
        .where((item) => item.path == action.snapshot.target.identity)
        .firstOrNull;
    if (repository == null ||
        _recentActionSnapshot(repository) != action.snapshot) {
      return;
    }
    switch (action.route) {
      case ContextActionRoute.openRepository:
        await _openPath(repository.path);
      case ContextActionRoute.removeRecentRepository:
        await _repositoryController.removeRecent(repository);
      case ContextActionRoute.copyRepositoryPath:
        await Clipboard.setData(ClipboardData(text: repository.path));
      case ContextActionRoute.revealRepository:
        final result = await widget.fileManager.reveal(repository.path);
        if (!mounted || result.isSuccess) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message ?? 'Could not reveal path.')),
        );
      case ContextActionRoute.inspect ||
          ContextActionRoute.activateRepository ||
          ContextActionRoute.closeRepository ||
          ContextActionRoute.closeOtherRepositories ||
          ContextActionRoute.openNestedRepository ||
          ContextActionRoute.stage ||
          ContextActionRoute.unstage ||
          ContextActionRoute.stageSelectedPatch ||
          ContextActionRoute.discard ||
          ContextActionRoute.moveToChangelist ||
          ContextActionRoute.shelve ||
          ContextActionRoute.ignoreLocal ||
          ContextActionRoute.ignoreRepository ||
          ContextActionRoute.fileHistory ||
          ContextActionRoute.blame ||
          ContextActionRoute.compare ||
          ContextActionRoute.compareBranch ||
          ContextActionRoute.copyRelativePath ||
          ContextActionRoute.copyAbsolutePath ||
          ContextActionRoute.reveal ||
          ContextActionRoute.cherryPick ||
          ContextActionRoute.revert ||
          ContextActionRoute.createBranch ||
          ContextActionRoute.createTag ||
          ContextActionRoute.reset ||
          ContextActionRoute.copyFullHash ||
          ContextActionRoute.copyShortHash ||
          ContextActionRoute.checkoutBranch ||
          ContextActionRoute.mergeBranch ||
          ContextActionRoute.rebaseBranch ||
          ContextActionRoute.renameBranch ||
          ContextActionRoute.deleteBranch ||
          ContextActionRoute.pushBranch ||
          ContextActionRoute.upstream ||
          ContextActionRoute.copyBranchName ||
          ContextActionRoute.copyBranchRef ||
          ContextActionRoute.compareRemote ||
          ContextActionRoute.checkoutRemote ||
          ContextActionRoute.deleteRemote ||
          ContextActionRoute.cherryPickRemote ||
          ContextActionRoute.hostLink:
        return;
    }
  }

  Future<void> _selectAndOpen([int? replaceIndex]) async {
    final path = await _pickDirectory();
    if (path == null || path.isEmpty) return;
    await _openPath(path, replaceIndex: replaceIndex);
  }

  Future<String?> _pickDirectory() {
    if (widget.selectDirectory case final picker?) return picker();
    return getDirectoryPath(
      confirmButtonText: 'Open',
      initialDirectory: _folderHistory.initialDirectory(
        FolderPathPurpose.openRepository,
      ),
    );
  }

  Future<void> _openPath(String path, {int? replaceIndex}) async {
    final normalizedPath = path.trim();
    final workspace = _workspaceController;
    if (workspace == null) {
      await _repositoryController.openPath(normalizedPath);
      if (_repositoryController.state.openedRepository case final opened?) {
        await _folderHistory.remember(
          FolderPathPurpose.openRepository,
          opened.root,
        );
      }
      return;
    }
    final opened = await workspace.openPath(
      normalizedPath,
      replaceIndex: replaceIndex,
    );
    if (opened?.repository != null) {
      await _folderHistory.remember(
        FolderPathPurpose.openRepository,
        opened!.repository!.root,
      );
      await _repositoryController.reloadRecent();
    }
  }

  Future<void> _showPreferences(BuildContext context) async {
    final scope = AppPreferencesScope.maybeOf(context);
    if (scope == null) return;
    await showDialog<void>(
      context: context,
      builder: (_) => PreferencesDialog(
        preferences: scope.preferences,
        onSave: scope.update,
        credentialStore: widget.credentialStore,
        tester: widget.gateway is GitCredentialTestGateway
            ? widget.gateway as GitCredentialTestGateway
            : null,
        oauthGateway: widget.oauthGateway,
      ),
    );
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

  Future<void> _showRepositorySetup() async {
    final repository = await showDialog<RepositoryOpened>(
      context: context,
      builder: (_) => RepositorySetupDialog(
        gateway: widget.gateway,
        credentialStore: widget.credentialStore,
        selectDirectory: widget.selectDirectory == null
            ? null
            : ({String? initialDirectory}) => widget.selectDirectory!(),
        pathHistory: _folderHistory,
      ),
    );
    if (!mounted || repository == null) return;
    await _openPath(repository.root);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }
}
