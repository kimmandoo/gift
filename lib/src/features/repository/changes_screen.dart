import 'dart:async';

import 'package:gift/src/backend/commit.dart';
import 'package:gift/src/backend/branch.dart';
import 'package:gift/src/features/repository/conflict_workspace_screen.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/diff.dart';
import 'package:gift/src/backend/error.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:gift/src/backend/remote.dart';
import 'package:gift/src/backend/remote_branch.dart';
import 'package:gift/src/backend/reset.dart';
import 'package:gift/src/backend/push.dart';
import 'package:gift/src/backend/status.dart';
import 'package:gift/src/features/repository/context_actions.dart';
import 'package:gift/src/backend/signing.dart';
import 'package:gift/src/features/repository/changes_controller.dart';
import 'package:gift/src/features/repository/path_actions.dart';
import 'package:gift/src/features/repository/branch_dialog.dart';
import 'package:gift/src/features/repository/history_screen.dart';
import 'package:gift/src/features/repository/history_controller.dart';
import 'package:gift/src/features/repository/remote_dialog.dart';
import 'package:gift/src/features/repository/update_project_dialog.dart';
import 'package:gift/src/features/repository/object_dialog.dart';
import 'package:gift/src/features/repository/comparison_dialog.dart';
import 'package:gift/src/features/repository/shelf_dialog.dart';
import 'package:gift/src/features/repository/file_history_dialog.dart';
import 'package:gift/src/features/repository/reset_dialog.dart';
import 'package:gift/src/features/repository/push_dialog.dart';
import 'package:gift/src/features/repository/worktree_dialog.dart';
import 'package:gift/src/features/repository/ignore_dialog.dart';
import 'package:gift/src/features/repository/submodule_dialog.dart';
import 'package:gift/src/features/repository/recovery_dialog.dart';
import 'package:gift/src/features/repository/repository_setup_dialog.dart';
import 'package:gift/src/features/repository/folder_path_field.dart';
import 'package:gift/src/features/repository/hosting_dialog.dart';
import 'package:gift/src/features/repository/command_palette.dart';
import 'package:gift/src/features/repository/lfs_dialog.dart';
import 'package:gift/src/features/repository/signing_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:gift/src/app/pixel_theme.dart';
import 'package:gift/src/app/app_preferences.dart';
import 'package:gift/src/backend/credentials.dart';
import 'package:gift/src/app/credentials_dialog.dart';
import 'package:gift/src/app/repository_credential_store.dart';

const _diffSelectorHeight = 20.0;
const _diffCheckboxScale = 0.8;

/// Shows the repository's current changes grouped by their Git facets.
class ChangesScreen extends StatelessWidget {
  const ChangesScreen({
    super.key,
    required this.gateway,
    required this.repository,
    this.controller,
    this.historyController,
    this.onBack,
    this.onOpenRepository,
    this.credentialStore,
    this.repositoryCredentialStore,
    this.fileManager = const PlatformFileManagerRevealer(),
    this.pathHistory,
    this.autoInitialize = true,
  });

  final GitGateway gateway;
  final RepositoryOpened repository;
  final ChangesController? controller;
  final HistoryController? historyController;
  final VoidCallback? onBack;
  final Future<void> Function(RepositoryOpened repository)? onOpenRepository;
  final GitCredentialStore? credentialStore;
  final RepositoryCredentialStore? repositoryCredentialStore;
  final FileManagerRevealer fileManager;
  final bool autoInitialize;
  final FolderPathHistory? pathHistory;

  @override
  Widget build(BuildContext context) {
    // A local scope keeps this screen usable from tests and from future
    // navigation shells that do not already have a ProviderScope.
    return ProviderScope(
      child: _ChangesScreenBody(
        gateway: gateway,
        repository: repository,
        controller: controller,
        historyController: historyController,
        onBack: onBack,
        onOpenRepository: onOpenRepository,
        autoInitialize: autoInitialize,
        credentialStore: credentialStore,
        repositoryCredentialStore: repositoryCredentialStore,
        fileManager: fileManager,
        pathHistory: pathHistory,
      ),
    );
  }
}

class _ChangesScreenBody extends ConsumerStatefulWidget {
  const _ChangesScreenBody({
    required this.gateway,
    required this.repository,
    this.controller,
    this.historyController,
    this.onBack,
    this.credentialStore,
    this.repositoryCredentialStore,
    this.onOpenRepository,
    required this.fileManager,
    this.pathHistory,
    required this.autoInitialize,
  });

  final GitGateway gateway;
  final RepositoryOpened repository;
  final ChangesController? controller;
  final HistoryController? historyController;
  final VoidCallback? onBack;
  final Future<void> Function(RepositoryOpened repository)? onOpenRepository;
  final GitCredentialStore? credentialStore;
  final RepositoryCredentialStore? repositoryCredentialStore;
  final FileManagerRevealer fileManager;
  final bool autoInitialize;
  final FolderPathHistory? pathHistory;

  @override
  ConsumerState<_ChangesScreenBody> createState() => _ChangesScreenBodyState();
}

class _ChangesScreenBodyState extends ConsumerState<_ChangesScreenBody> {
  ChangesController? _manualController;
  late final ChangesControllerArgs _providerArgs;
  late final TextEditingController _commitMessageController;
  late final TextEditingController _authorNameController;
  late final TextEditingController _authorEmailController;
  late final TextEditingController _signingKeyController;
  var _commitOptionsExpanded = false;
  var _amend = false;
  var _signOff = false;
  var _sign = false;
  var _cleanup = GitCommitCleanupMode.defaultMode;
  String? _loadedTemplate;
  GitError? _templateError;
  GitSigningConfiguration? _signingConfiguration;
  GitError? _signingError;
  final Map<String, FocusNode> _changeSelectionFocusNodes = {};

  @override
  void initState() {
    super.initState();
    _commitMessageController = TextEditingController();
    _authorNameController = TextEditingController();
    _authorEmailController = TextEditingController();
    _signingKeyController = TextEditingController();
    _providerArgs = ChangesControllerArgs(
      gateway: widget.gateway,
      repositoryId: widget.repository.repositoryId,
      repositoryRoot: widget.repository.root,
    );
    final providedController = widget.controller;
    if (providedController != null) {
      _manualController = providedController;
      _manualController!.addListener(_onChanged);
      if (widget.autoInitialize) _manualController!.start();
    } else if (widget.autoInitialize) {
      Future<void>.microtask(() {
        if (mounted) ref.read(changesControllerProvider(_providerArgs)).start();
      });
    }
  }

  @override
  void dispose() {
    _commitMessageController.dispose();
    _authorNameController.dispose();
    _authorEmailController.dispose();
    _signingKeyController.dispose();
    for (final node in _changeSelectionFocusNodes.values) {
      node.dispose();
    }
    _manualController?.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller =
        _manualController ??
        ref.watch(changesControllerProvider(_providerArgs))!;
    final state = controller.state;
    final snapshot = state.snapshot;
    final width = MediaQuery.sizeOf(context).width;
    final compactToolbar = width < 720;
    final showQuickActions = compactToolbar || width >= 1040;
    final showToolbarLabels = !showQuickActions && width >= 900;
    final scaffold = Scaffold(
      appBar: AppBar(
        leading: widget.onBack == null
            ? null
            : IconButton(
                tooltip: 'Back to repositories',
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back),
              ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Changes'),
            Text(
              widget.repository.root,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        actions: [
          if (!showQuickActions) ...[
            PixelToolbarActionButton(
              key: const Key('open-push'),
              tooltip: 'Push to remote',
              onPressed: () => unawaited(_openPush(context)),
              icon: const Icon(Icons.cloud_upload_outlined),
              label: 'Push',
              showLabel: showToolbarLabels,
            ),
            PixelToolbarActionButton(
              key: const Key('update-project'),
              tooltip: 'Update project',
              onPressed: () => unawaited(_openUpdateProject(context)),
              icon: const Icon(Icons.cloud_download_outlined),
              label: 'Update',
              showLabel: showToolbarLabels,
            ),
            PixelToolbarActionButton(
              key: const Key('open-branches'),
              tooltip: 'Open branches',
              onPressed: () => unawaited(_openBranches(context)),
              icon: const Icon(Icons.call_split),
              label: 'Branches',
              showLabel: false,
            ),
            PixelToolbarActionButton(
              key: const Key('open-history'),
              tooltip: 'Open history',
              onPressed: () => unawaited(_openHistory(context)),
              icon: const Icon(Icons.history),
              label: 'History',
              showLabel: false,
            ),
          ],
          PopupMenuButton<_ChangesMenuAction>(
            key: const Key('repository-actions-menu'),
            tooltip: 'More repository actions',
            icon: const Icon(Icons.menu_open),
            onSelected: (action) {
              switch (action) {
                case _ChangesMenuAction.remotes:
                  unawaited(_openRemotes(context));
                  break;
                case _ChangesMenuAction.gitAccounts:
                  unawaited(_openGitAccounts(context));
                  break;
                case _ChangesMenuAction.objects:
                  unawaited(_openObjects(context));
                  break;
                case _ChangesMenuAction.comparison:
                  unawaited(_openComparison(context));
                  break;
                case _ChangesMenuAction.threeWayComparison:
                  unawaited(_openThreeWayComparison(context));
                  break;
                case _ChangesMenuAction.shelves:
                  unawaited(_openShelves(context));
                  break;
                case _ChangesMenuAction.fileHistory:
                  unawaited(_openFileHistory(context));
                  break;
                case _ChangesMenuAction.resetBranch:
                  unawaited(
                    _openHistoryRollback(
                      context,
                      initialAction: GitHistoryRollbackAction.reset,
                    ),
                  );
                  break;
                case _ChangesMenuAction.undoCommit:
                  unawaited(
                    _openHistoryRollback(
                      context,
                      initialAction: GitHistoryRollbackAction.undo,
                    ),
                  );
                  break;
                case _ChangesMenuAction.revertCommits:
                  unawaited(
                    _openHistoryRollback(
                      context,
                      initialAction: GitHistoryRollbackAction.revert,
                    ),
                  );
                  break;
                case _ChangesMenuAction.worktrees:
                  unawaited(_openWorktrees(context));
                  break;
                case _ChangesMenuAction.ignoreMetadata:
                  unawaited(_openIgnoreMetadata(context));
                  break;
                case _ChangesMenuAction.submodules:
                  unawaited(_openSubmodules(context));
                  break;
                case _ChangesMenuAction.recovery:
                  unawaited(_openRecovery(context));
                  break;
                case _ChangesMenuAction.setup:
                  unawaited(_openRepositorySetup(context));
                  break;
                case _ChangesMenuAction.hosting:
                  unawaited(_openHosting(context));
                  break;
                case _ChangesMenuAction.refresh:
                  unawaited(controller.refresh());
                  break;
                case _ChangesMenuAction.lfs:
                  unawaited(_openLfs(context));
                  break;
                case _ChangesMenuAction.signing:
                  unawaited(_openSigning(context));
                  break;
              }
            },
            itemBuilder: (context) => [
              _menuHeading(context, 'SYNC & NAVIGATION'),
              _menuItem(
                _ChangesMenuAction.remotes,
                Icons.cloud_outlined,
                'Remote operations',
              ),
              const PopupMenuDivider(),
              _menuHeading(context, 'REVIEW & HISTORY'),
              _menuItem(
                _ChangesMenuAction.objects,
                Icons.inventory_2_outlined,
                'Stashes, tags & remote setup',
              ),
              _menuItem(
                _ChangesMenuAction.comparison,
                Icons.compare_arrows,
                'Compare revisions',
              ),
              _menuItem(
                _ChangesMenuAction.threeWayComparison,
                Icons.call_split,
                'Three-way compare',
              ),
              _menuItem(
                _ChangesMenuAction.shelves,
                Icons.archive_outlined,
                'Shelves & changelists',
              ),
              _menuItem(
                _ChangesMenuAction.fileHistory,
                Icons.history_edu_outlined,
                'File history & blame',
              ),
              _menuItem(
                _ChangesMenuAction.resetBranch,
                Icons.history_toggle_off,
                'Reset branch to a revision',
              ),
              _menuItem(
                _ChangesMenuAction.undoCommit,
                Icons.undo,
                'Undo latest unpushed commit',
              ),
              _menuItem(
                _ChangesMenuAction.revertCommits,
                Icons.reply,
                'Revert commit(s) with new commit(s)',
              ),
              const PopupMenuDivider(),
              _menuHeading(context, 'REPOSITORY TOOLS'),
              _menuItem(
                _ChangesMenuAction.gitAccounts,
                Icons.key_outlined,
                'Git accounts for this repository',
              ),
              _menuItem(
                _ChangesMenuAction.worktrees,
                Icons.account_tree_outlined,
                'Worktrees',
              ),
              _menuItem(
                _ChangesMenuAction.ignoreMetadata,
                Icons.rule_folder_outlined,
                'Ignore & metadata',
              ),
              _menuItem(
                _ChangesMenuAction.submodules,
                Icons.account_tree_outlined,
                'Submodules & nested roots',
              ),
              _menuItem(
                _ChangesMenuAction.recovery,
                Icons.restore,
                'Recovery diagnostics',
              ),
              _menuItem(
                _ChangesMenuAction.setup,
                Icons.settings_system_daydream_outlined,
                'Setup, roots, or full history',
              ),
              _menuItem(
                _ChangesMenuAction.hosting,
                Icons.link_outlined,
                'Hosting links & review',
              ),
              _menuItem(
                _ChangesMenuAction.lfs,
                Icons.cloud_download_outlined,
                'Git LFS status',
              ),
              _menuItem(
                _ChangesMenuAction.signing,
                Icons.verified_outlined,
                'Commit signing status',
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: _ChangesMenuAction.refresh,
                enabled: !state.isRefreshing,
                child: Row(
                  children: [
                    const Icon(Icons.refresh, size: 18),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        state.isRefreshing ? 'Refreshing…' : 'Refresh changes',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const PixelThemeToggle(),
          PixelToolbarIconButton(
            tooltip: 'Refresh changes',
            onPressed: state.isRefreshing ? null : controller.refresh,
            icon: state.isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (snapshot != null) ...[
              _summary(context, snapshot),
              if (showQuickActions) _quickActions(context, compactToolbar),
              if (snapshot.staged.isEmpty)
                _actionAvailability(context, snapshot, state),
              if (snapshot.conflicts.isNotEmpty)
                _conflictWorkspaceBanner(context, snapshot),
              if (state.error case final error?) _errorBanner(context, error),
            ],
            if (state.isLoading) const LinearProgressIndicator(),
            if (state.commitResult case final result?)
              _commitSuccess(context, result),
            if (state.commitError case final error?) _commitError(error),
            if (state.commitPreflightError case final error?)
              _commitPreflightError(error),
            if (state.commitPreflight?.failure case final error?)
              _commitPreflightError(error),
            if (snapshot != null && snapshot.staged.isNotEmpty)
              _commitPanel(context, controller, state),
            Expanded(
              child: snapshot == null && state.error != null
                  ? _errorState(state.error!)
                  : snapshot == null
                  ? const Center(child: CircularProgressIndicator())
                  : _changesLayout(context, snapshot, state),
            ),
            if (snapshot != null && controller.state.selectedPaths.isNotEmpty)
              _multiStageSelectionBar(context, controller, state),
            if (snapshot != null) _statusStrip(context, snapshot, state),
          ],
        ),
      ),
    );
    final preferences =
        AppPreferencesScope.maybeOf(context)?.preferences ??
        GiftPreferences.defaults;
    final bindings = <ShortcutActivator, VoidCallback>{};
    void bind(String id, VoidCallback action) {
      final activator = shortcutActivator(preferences.shortcut(id));
      if (activator != null) bindings[activator] = action;
    }

    bind('refresh', () => unawaited(controller.refresh()));
    bind('history', () => unawaited(_openHistory(context)));
    bind('branch', () => unawaited(_openBranches(context)));
    bind('remote', () => unawaited(_openRemotes(context)));
    bind('commit', () => unawaited(_submitCommit(controller)));
    void openPalette() {
      unawaited(_openCommandPalette(context, controller));
    }

    bind('commandPalette', openPalette);
    // Ctrl+Shift+P or Cmd+Shift+P remains available as a conventional alias.
    bindings.putIfAbsent(
      conventionalCommandPaletteActivator(),
      () => openPalette,
    );
    if (widget.onBack != null) bind('cancel', widget.onBack!);
    return CallbackShortcuts(
      bindings: bindings,

      child: Focus(autofocus: true, child: scaffold),
    );
  }

  Future<void> _openCommandPalette(
    BuildContext context,
    ChangesController controller,
  ) {
    return showCommandPalette(
      context,
      actions: [
        CommandPaletteAction(
          id: 'refresh',
          label: 'Refresh changes',
          icon: Icons.refresh,
          keywords: const ['reload', 'status'],
          enabled: !controller.state.isRefreshing,
          disabledReason: 'Refresh is already running.',
          onInvoke: controller.refresh,
        ),
        CommandPaletteAction(
          id: 'commit',
          label: 'Commit staged changes',
          icon: Icons.check,
          keywords: const ['commit', 'save'],
          enabled: controller.canCommit && !controller.state.isMutating,
          disabledReason: 'Stage changes and enter a commit message first.',
          onInvoke: () => _submitCommit(controller),
        ),
        CommandPaletteAction(
          id: 'history',
          label: 'Open history',
          icon: Icons.history,
          keywords: const ['log', 'commits'],
          onInvoke: () => _openHistory(context),
        ),
        CommandPaletteAction(
          id: 'branches',
          label: 'Open branches',
          icon: Icons.call_split,
          keywords: const ['branch', 'checkout'],
          onInvoke: () => _openBranches(context),
        ),
        CommandPaletteAction(
          id: 'remotes',
          label: 'Remote operations',
          icon: Icons.cloud_outlined,
          keywords: const ['fetch', 'pull', 'push'],
          onInvoke: () => _openRemotes(context),
        ),
        CommandPaletteAction(
          id: 'push',
          label: 'Push to remote',
          icon: Icons.cloud_upload_outlined,
          keywords: const ['publish', 'remote'],
          onInvoke: () => _openPush(context),
        ),
        CommandPaletteAction(
          id: 'update-project',
          label: 'Update project',
          icon: Icons.cloud_download_outlined,
          keywords: const ['pull', 'fetch', 'remote'],
          onInvoke: () => _openUpdateProject(context),
        ),
        CommandPaletteAction(
          id: 'comparison',
          label: 'Compare revisions',
          icon: Icons.compare_arrows,
          keywords: const ['diff', 'compare'],
          onInvoke: () => _openComparison(context),
        ),
        CommandPaletteAction(
          id: 'three-way-comparison',
          label: 'Three-way compare',
          icon: Icons.call_split,
          keywords: const ['diff', 'merge', 'compare'],
          onInvoke: () => _openThreeWayComparison(context),
        ),
        CommandPaletteAction(
          id: 'shelves',
          label: 'Shelves and changelists',
          icon: Icons.archive_outlined,
          keywords: const ['stash', 'shelf'],
          onInvoke: () => _openShelves(context),
        ),
        CommandPaletteAction(
          id: 'file-history',
          label: 'File history and blame',
          icon: Icons.history_edu_outlined,
          keywords: const ['log', 'blame', 'path'],
          onInvoke: () => _openFileHistory(context),
        ),
        CommandPaletteAction(
          id: 'reset-branch',
          label: 'Reset branch to a revision',
          icon: Icons.history_toggle_off,
          keywords: const ['reset', 'rollback', 'head'],
          onInvoke: () => _openHistoryRollback(
            context,
            initialAction: GitHistoryRollbackAction.reset,
          ),
        ),
        CommandPaletteAction(
          id: 'undo-commit',
          label: 'Undo latest unpushed commit',
          icon: Icons.undo,
          keywords: const ['undo', 'rollback', 'uncommit'],
          onInvoke: () => _openHistoryRollback(
            context,
            initialAction: GitHistoryRollbackAction.undo,
          ),
        ),
        CommandPaletteAction(
          id: 'revert-commits',
          label: 'Revert commit(s) with new commit(s)',
          icon: Icons.reply,
          keywords: const ['revert', 'rollback', 'commit'],
          onInvoke: () => _openHistoryRollback(
            context,
            initialAction: GitHistoryRollbackAction.revert,
          ),
        ),
        CommandPaletteAction(
          id: 'recovery',
          label: 'Recovery diagnostics',
          icon: Icons.restore,
          keywords: const ['reset', 'revert', 'undo'],
          onInvoke: () => _openRecovery(context),
        ),
        CommandPaletteAction(
          id: 'objects',
          label: 'Stashes, tags, and remote setup',
          icon: Icons.inventory_2_outlined,
          keywords: const ['stash', 'tag', 'remote'],
          onInvoke: () => _openObjects(context),
        ),
        CommandPaletteAction(
          id: 'git-accounts',
          label: 'Git accounts',
          icon: Icons.key_outlined,
          keywords: const ['credentials', 'authentication', 'auth'],
          enabled: widget.credentialStore != null,
          disabledReason: 'Git account storage is not configured.',
          onInvoke: () => _openGitAccounts(context),
        ),
        CommandPaletteAction(
          id: 'worktrees',
          label: 'Worktrees',
          icon: Icons.account_tree_outlined,
          keywords: const ['worktree', 'linked checkout'],
          onInvoke: () => _openWorktrees(context),
        ),
        CommandPaletteAction(
          id: 'ignore-metadata',
          label: 'Ignore and metadata',
          icon: Icons.rule_folder_outlined,
          keywords: const ['gitignore', 'attributes', 'exclude'],
          onInvoke: () => _openIgnoreMetadata(context),
        ),
        CommandPaletteAction(
          id: 'submodules',
          label: 'Submodules and nested roots',
          icon: Icons.account_tree_outlined,
          keywords: const ['submodule', 'nested repository'],
          onInvoke: () => _openSubmodules(context),
        ),
        CommandPaletteAction(
          id: 'repository-setup',
          label: 'Repository setup',
          icon: Icons.settings_system_daydream_outlined,
          keywords: const ['clone', 'initialize', 'publish'],
          onInvoke: () => _openRepositorySetup(context),
        ),
        CommandPaletteAction(
          id: 'hosting',
          label: 'Hosting links and review',
          icon: Icons.link_outlined,
          keywords: const ['github', 'gitlab', 'pull request'],
          onInvoke: () => _openHosting(context),
        ),
        CommandPaletteAction(
          id: 'lfs',
          label: 'Git LFS status',
          icon: Icons.cloud_download_outlined,
          keywords: const ['large files', 'objects', 'pull'],
          onInvoke: () => _openLfs(context),
        ),
        CommandPaletteAction(
          id: 'signing',
          label: 'Commit signing status',
          icon: Icons.verified_outlined,
          keywords: const ['gpg', 'ssh', 'signature'],
          onInvoke: () => _openSigning(context),
        ),
      ],
    );
  }

  Future<void> _openLfs(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) =>
          GitLfsDialog(gateway: widget.gateway, repository: widget.repository),
    );
  }

  Future<void> _openSigning(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => GitSigningDialog(
        gateway: widget.gateway,
        repository: widget.repository,
      ),
    );
  }

  PopupMenuItem<_ChangesMenuAction> _menuHeading(
    BuildContext context,
    String label,
  ) {
    return PopupMenuItem<_ChangesMenuAction>(
      enabled: false,
      height: 28,
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  PopupMenuItem<_ChangesMenuAction> _menuItem(
    _ChangesMenuAction action,
    IconData icon,
    String label,
  ) {
    return PopupMenuItem<_ChangesMenuAction>(
      value: action,
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 12),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }

  Widget _quickActions(BuildContext context, bool compact) {
    final theme = Theme.of(context);
    final horizontalPadding = compact ? 12.0 : 16.0;
    return Container(
      key: const Key('repository-quick-actions'),
      padding: EdgeInsets.fromLTRB(horizontalPadding, 4, horizontalPadding, 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: PixelActionRow(
        children: [
          FilledButton.icon(
            key: const Key('open-push'),
            onPressed: () => unawaited(_openPush(context)),
            icon: const Icon(Icons.cloud_upload_outlined),
            label: const Text('Push'),
          ),
          OutlinedButton.icon(
            key: const Key('update-project'),
            onPressed: () => unawaited(_openUpdateProject(context)),
            icon: const Icon(Icons.cloud_download_outlined),
            label: const Text('Update'),
          ),
          OutlinedButton.icon(
            key: const Key('open-branches'),
            onPressed: () => unawaited(_openBranches(context)),
            icon: const Icon(Icons.call_split),
            label: const Text('Branches'),
          ),
          OutlinedButton.icon(
            key: const Key('open-history'),
            onPressed: () => unawaited(_openHistory(context)),
            icon: const Icon(Icons.history),
            label: const Text('History'),
          ),
        ],
      ),
    );
  }

  Widget _summary(BuildContext context, GitStatusSnapshot snapshot) {
    final compact = MediaQuery.sizeOf(context).width < 480;
    final theme = Theme.of(context);
    final branch = snapshot.branch.head ?? 'Detached HEAD';
    final sync = snapshot.branch.hasUpstream
        ? '${snapshot.branch.ahead} ahead · ${snapshot.branch.behind} behind'
        : 'No upstream';
    final changeLabel =
        '${snapshot.changes.length} changed ${snapshot.changes.length == 1 ? 'file' : 'files'}';
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16, vertical: 8),
      color: theme.colorScheme.surfaceContainerHighest,
      child: LayoutBuilder(
        builder: (context, constraints) {
          Widget metric(
            IconData icon,
            String label, {
            bool emphasized = false,
          }) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: emphasized
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      (emphasized
                              ? theme.textTheme.bodyMedium
                              : theme.textTheme.labelLarge)
                          ?.copyWith(
                            color: emphasized
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.onSurfaceVariant,
                            fontWeight: emphasized
                                ? FontWeight.w700
                                : FontWeight.w600,
                          ),
                ),
              ],
            );
          }

          return Wrap(
            spacing: compact ? 12 : 20,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: compact ? constraints.maxWidth : 280,
                ),
                child: metric(
                  Icons.account_tree_outlined,
                  branch,
                  emphasized: true,
                ),
              ),
              metric(Icons.sync_alt, sync),
              metric(Icons.description_outlined, changeLabel),
            ],
          );
        },
      ),
    );
  }

  Widget _actionAvailability(
    BuildContext context,
    GitStatusSnapshot snapshot,
    ChangesState state,
  ) {
    final unavailable = <String>[
      if (state.isMutating) 'Repository busy: wait for the current operation.',
      if (snapshot.staged.isEmpty && snapshot.changes.isNotEmpty)
        'Commit: stage at least one path first.',
      if (snapshot.conflicts.isNotEmpty)
        'Commit: resolve conflicts before committing.',
      if (snapshot.branch.head == null || snapshot.branch.isDetached)
        'Push: check out a branch before publishing.',
      if (!snapshot.branch.hasUpstream)
        'Update: configure an upstream branch before pulling.',
    ];
    if (unavailable.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: 'Action availability. ${unavailable.join(' ')}',
      child: Container(
        key: const Key('action-availability'),
        padding: const EdgeInsets.symmetric(
          horizontal: PixelSpacing.lg,
          vertical: PixelSpacing.xs,
        ),
        color: theme.colorScheme.surfaceContainer,
        child: Row(
          children: [
            Icon(
              Icons.info_outline,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: PixelSpacing.sm),
            Text(
              'Unavailable',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: PixelSpacing.sm),
            Expanded(
              child: Text(
                unavailable.join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _conflictWorkspaceBanner(
    BuildContext context,
    GitStatusSnapshot snapshot,
  ) {
    return Container(
      key: const Key('conflict-workspace-banner'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      color: Theme.of(context).colorScheme.errorContainer,
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Text(
            '${snapshot.conflicts.length} conflicted path'
            '${snapshot.conflicts.length == 1 ? '' : 's'}',
          ),
          FilledButton.tonalIcon(
            key: const Key('open-conflict-workspace'),
            onPressed: _activeController.state.isMutating
                ? null
                : () => unawaited(_openConflictWorkspace(context)),
            icon: const Icon(Icons.merge_type),
            label: const Text('Resolve conflicts'),
          ),
        ],
      ),
    );
  }

  Widget _multiStageSelectionBar(
    BuildContext context,
    ChangesController controller,
    ChangesState state,
  ) {
    final count = state.selectedPaths.length;
    final label = '$count file${count == 1 ? '' : 's'} selected';
    final theme = Theme.of(context);
    return Container(
      key: const Key('multi-stage-selection'),
      padding: const EdgeInsets.fromLTRB(
        PixelSpacing.lg,
        PixelSpacing.xs,
        PixelSpacing.lg,
        PixelSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        border: Border(top: BorderSide(color: theme.colorScheme.primary)),
      ),
      child: PixelActionRow(
        children: [
          Icon(
            Icons.checklist,
            size: 18,
            color: theme.colorScheme.onPrimaryContainer,
          ),
          Text(
            label,
            style: TextStyle(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
          OutlinedButton(
            key: const Key('clear-stage-selection'),
            onPressed: state.isMutating ? null : controller.clearPathSelection,
            child: const Text('Clear'),
          ),
          FilledButton.icon(
            key: const Key('stage-selected-changes'),
            onPressed: state.isMutating || !controller.canStageSelectedPaths
                ? null
                : () => unawaited(controller.stageSelectedPaths()),
            icon: state.isMutating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add, size: 18),
            label: const Text('Stage selected'),
          ),
          OutlinedButton.icon(
            key: const Key('stage-and-commit'),
            onPressed: state.isMutating || !controller.canStageSelectedPaths
                ? null
                : () => unawaited(_openStageAndCommit(context, controller)),
            icon: const Icon(Icons.playlist_add_check, size: 18),
            label: const Text('Stage & commit'),
          ),
        ],
      ),
    );
  }

  Widget _statusStrip(
    BuildContext context,
    GitStatusSnapshot snapshot,
    ChangesState state,
  ) {
    final compact = MediaQuery.sizeOf(context).width < 480;
    final preferences =
        AppPreferencesScope.maybeOf(context)?.preferences ??
        GiftPreferences.defaults;
    final shortcutHint = [
      '${formatShortcut(preferences.shortcut('refresh'))} refresh',
      '${formatShortcut(preferences.shortcut('history'))} history',
      '${formatShortcut(preferences.shortcut('commandPalette'))} palette',
    ].join(' · ');
    final status = state.isCommitting
        ? 'Committing…'
        : state.isMutating
        ? 'Updating repository…'
        : snapshot.isClean
        ? 'Working tree clean'
        : '${snapshot.staged.length} staged · ${snapshot.unstaged.length} unstaged';
    return Container(
      key: const Key('status-strip'),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16, vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final icon = Icon(
            state.isMutating ? Icons.sync : Icons.check_circle_outline,
            size: 16,
          );
          if (constraints.maxWidth < 760) {
            return Row(
              children: [
                icon,
                const SizedBox(width: 8),
                Expanded(child: Text(status, overflow: TextOverflow.ellipsis)),
              ],
            );
          }
          return Row(
            children: [
              icon,
              const SizedBox(width: 8),
              Expanded(child: Text(status, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 12),
              Text(
                shortcutHint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _commitPanel(
    BuildContext context,
    ChangesController controller,
    ChangesState state,
  ) {
    final compact = MediaQuery.sizeOf(context).width < 480;
    final canSubmit =
        controller.canCommit &&
        !state.isMutating &&
        _commitMessageController.text.trim().isNotEmpty;
    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 12 : 16, 8, compact ? 12 : 16, 4),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final editor = TextField(
                    key: const Key('commit-message'),
                    controller: _commitMessageController,
                    enabled: !state.isMutating,
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      labelText: 'Commit staged changes',
                      border: OutlineInputBorder(),
                      hintText: 'Describe the staged changes',
                    ),
                    onChanged: (_) => setState(() {}),
                  );
                  final button = FilledButton.icon(
                    key: const Key('commit-staged'),
                    onPressed: canSubmit
                        ? () => unawaited(_submitCommit(controller))
                        : null,
                    icon: state.isCommitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check, size: 18),
                    label: const Text('Commit'),
                  );
                  if (constraints.maxWidth < 540) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        editor,
                        _commitCharacterGuidance(context),
                        const SizedBox(height: 8),
                        button,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [editor, _commitCharacterGuidance(context)],
                        ),
                      ),
                      const SizedBox(width: 8),
                      button,
                    ],
                  );
                },
              ),
              const SizedBox(height: 4),
              ListTileTheme(
                dense: false,
                minVerticalPadding: 8,
                child: ExpansionTile(
                  key: const Key('commit-options-toggle'),
                  initiallyExpanded: _commitOptionsExpanded,
                  onExpansionChanged: (expanded) {
                    setState(() => _commitOptionsExpanded = expanded);
                    if (expanded) {
                      _requestCommitPreflight(controller);
                      unawaited(_loadSigningConfiguration());
                    }
                  },
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(top: 8),
                  title: const Text('Commit options'),
                  subtitle: const Text(
                    'Identity, amend, sign, sign-off, and cleanup',
                  ),
                  children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: compact ? 180 : 200,
                      ),
                      child: SingleChildScrollView(
                        key: const Key('commit-options-scroll'),
                        child: _commitOptionsPanel(context, controller, state),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _commitCharacterGuidance(BuildContext context) {
    final length = _commitMessageController.text.length;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        '$length characters. Keep the subject line concise; use a blank line before details.',
        key: const Key('commit-character-guidance'),
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }

  Widget _commitOptionsPanel(
    BuildContext context,
    ChangesController controller,
    ChangesState state,
  ) {
    final preflight = state.commitPreflight;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CheckboxListTile(
          key: const Key('commit-amend'),
          value: _amend,
          onChanged: state.isMutating
              ? null
              : (value) {
                  setState(() => _amend = value ?? false);
                  _requestCommitPreflight(controller);
                },
          title: const Text('Amend previous commit'),
          subtitle: const Text(
            'Replaces the current HEAD commit. Review this destructive option carefully.',
          ),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
        ),
        CheckboxListTile(
          key: const Key('commit-signoff'),
          value: _signOff,
          onChanged: state.isMutating
              ? null
              : (value) {
                  setState(() => _signOff = value ?? false);
                  _requestCommitPreflight(controller);
                },
          title: const Text('Add sign-off'),
          subtitle: const Text('Append a Signed-off-by trailer.'),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
        ),
        DropdownButtonFormField<GitCommitCleanupMode>(
          key: const Key('commit-cleanup'),
          initialValue: _cleanup,
          decoration: const InputDecoration(labelText: 'Message cleanup'),
          items: GitCommitCleanupMode.values
              .map(
                (mode) => DropdownMenuItem(
                  value: mode,
                  child: pixelDropdownText(_cleanupLabel(mode)),
                ),
              )
              .toList(),
          onChanged: state.isMutating
              ? null
              : (mode) {
                  if (mode == null) return;
                  setState(() => _cleanup = mode);
                  _requestCommitPreflight(controller);
                },
        ),
        const SizedBox(height: 10),
        TextField(
          key: const Key('commit-author-name'),
          controller: _authorNameController,
          enabled: !state.isMutating,
          decoration: const InputDecoration(
            labelText: 'Author override name (optional)',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('commit-author-email'),
          controller: _authorEmailController,
          enabled: !state.isMutating,
          decoration: const InputDecoration(
            labelText: 'Author override email (optional)',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const Key('commit-load-template'),
              onPressed: state.isMutating
                  ? null
                  : () => unawaited(_loadCommitTemplate()),
              icon: const Icon(Icons.download_outlined),
              label: const Text('Load template'),
            ),
            OutlinedButton.icon(
              key: const Key('commit-reset-template'),
              onPressed: state.isMutating
                  ? null
                  : () {
                      final template = _loadedTemplate ?? '';
                      _commitMessageController.text = template;
                      _commitMessageController.selection =
                          TextSelection.collapsed(offset: template.length);
                      setState(() {});
                    },
              icon: const Icon(Icons.restart_alt),
              label: const Text('Reset template'),
            ),
          ],
        ),
        CheckboxListTile(
          key: const Key('commit-sign'),
          value: _sign,
          onChanged: state.isMutating
              ? null
              : (value) {
                  setState(() => _sign = value ?? false);
                  _requestCommitPreflight(controller);
                },
          title: const Text('Sign commit'),
          subtitle: Text(
            _signingConfiguration == null
                ? 'Uses the repository Git signing configuration.'
                : '${_signingConfiguration!.formatLabel} · '
                      '${_signingConfiguration!.agentAvailable ? 'key configured' : 'key not configured'}',
          ),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
        ),
        TextField(
          key: const Key('commit-signing-key'),
          controller: _signingKeyController,
          enabled: !state.isMutating && _sign,
          decoration: const InputDecoration(
            labelText: 'Signing key override (optional)',
            hintText: 'Uses user.signingkey when empty',
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (_signingError case final error?)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              error.userMessage,
              key: const Key('commit-signing-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (_templateError case final error?)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              error.userMessage,
              key: const Key('commit-template-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (preflight != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              preflight.identity.isComplete
                  ? 'Identity: ${preflight.identity.name} <${preflight.identity.email}> (${preflight.identity.source}).'
                  : preflight.identity.guidance,
              key: const Key('commit-identity-status'),
            ),
          ),
        if (state.isCommitPreflighting)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(),
          ),
      ],
    );
  }

  Widget _commitSuccess(BuildContext context, GitCommitResult result) {
    final shortOid = result.commitOid.length > 7
        ? result.commitOid.substring(0, 7)
        : result.commitOid;
    return Container(
      key: const Key('commit-success'),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: Text(
        'Committed $shortOid. History updated.',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onTertiaryContainer,
        ),
      ),
    );
  }

  Widget _commitError(GitError error) {
    final historyMessage =
        error.commitOutcome == GitCommitOutcome.createdButRefreshFailed
        ? 'History changed, but the repository status could not be refreshed. '
              'Verify history before retrying.'
        : 'History was not changed.';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(
        key: const Key('commit-error'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            error.userMessage,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          Text(historyMessage),
        ],
      ),
    );
  }

  Widget _commitPreflightError(GitError error) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Text(
        error.category == GitErrorCategory.missingIdentity
            ? '${error.userMessage} ${error.diagnostic}'
            : error.userMessage,
        key: const Key('commit-preflight-error'),
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }

  GitCommitOptions _buildCommitOptions() {
    final name = _authorNameController.text.trim();
    final email = _authorEmailController.text.trim();
    return GitCommitOptions(
      amend: _amend,
      signOff: _signOff,
      sign: _sign,
      signingKey: _signingKeyController.text.trim().isEmpty
          ? null
          : _signingKeyController.text.trim(),
      cleanup: _cleanup,
      author: name.isEmpty && email.isEmpty
          ? null
          : GitCommitAuthor(name: name, email: email),
    );
  }

  Future<void> _loadSigningConfiguration() async {
    if (!mounted) return;
    setState(() => _signingError = null);
    try {
      final configuration = await widget.gateway.getSigningConfiguration(
        widget.repository.repositoryId,
      );
      if (!mounted) return;
      setState(() {
        _signingConfiguration = configuration;
        if (_sign && _signingKeyController.text.isEmpty) {
          _signingKeyController.text = configuration.signingKey ?? '';
        }
      });
    } on GitError catch (error) {
      if (mounted) setState(() => _signingError = error);
    }
  }

  void _requestCommitPreflight(ChangesController controller) {
    unawaited(controller.preflightCommit(options: _buildCommitOptions()));
  }

  Future<void> _loadCommitTemplate() async {
    setState(() => _templateError = null);
    try {
      final template = await widget.gateway.loadCommitTemplate(
        widget.repository.repositoryId,
      );
      if (!mounted) return;
      _loadedTemplate = template.contents;
      _commitMessageController.text = template.contents;
      _commitMessageController.selection = TextSelection.collapsed(
        offset: template.contents.length,
      );
      setState(() {});
    } on GitError catch (error) {
      if (mounted) setState(() => _templateError = error);
    }
  }

  Future<void> _submitCommit(ChangesController controller) async {
    final message = _commitMessageController.text;
    if (message.trim().isEmpty) return;
    await controller.commit(message, options: _buildCommitOptions());
    if (!mounted || controller.state.commitResult == null) return;
    _commitMessageController.clear();
    setState(() {});
  }

  Future<void> _openStageAndCommit(
    BuildContext context,
    ChangesController controller,
  ) async {
    final message = await showDialog<String>(
      context: context,
      builder: (_) => const _StageAndCommitDialog(),
    );
    if (!mounted || message == null) return;
    await controller.stageSelectedPathsAndCommit(message);
  }

  Widget _changesLayout(
    BuildContext context,
    GitStatusSnapshot snapshot,
    ChangesState state,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 680) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: constraints.maxHeight * 0.32,
                child: _groupedChanges(context, snapshot, state),
              ),
              const Divider(height: 1),
              Expanded(child: _details(context, snapshot, state)),
            ],
          );
        }
        final listWidth = (constraints.maxWidth * 0.36)
            .clamp(320.0, 440.0)
            .toDouble();
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: listWidth,
              child: _groupedChanges(context, snapshot, state),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: _details(context, snapshot, state)),
          ],
        );
      },
    );
  }

  Widget _groupedChanges(
    BuildContext context,
    GitStatusSnapshot snapshot,
    ChangesState state,
  ) {
    if (snapshot.isClean) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text('Working tree is clean.'),
        ),
      );
    }

    final sections =
        <({String title, GitChangeGroup group, List<GitChange> changes})>[
          (
            title: 'Conflicts',
            group: GitChangeGroup.conflicts,
            changes: snapshot.conflicts,
          ),
          (
            title: 'Staged',
            group: GitChangeGroup.staged,
            changes: snapshot.staged,
          ),
          (
            title: 'Unstaged',
            group: GitChangeGroup.unstaged,
            changes: snapshot.unstaged,
          ),
          (
            title: 'Untracked',
            group: GitChangeGroup.untracked,
            changes: snapshot.untracked,
          ),
        ];

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final section in sections)
          if (section.changes.isNotEmpty) ...[
            _sectionHeader(context, section.title, section.changes.length),
            for (var index = 0; index < section.changes.length; index++) ...[
              _changeTile(
                context,
                section.changes[index],
                section.group,
                state,
              ),
            ],
            const SizedBox(height: 8),
          ],
      ],
    );
  }

  Widget _sectionHeader(BuildContext context, String title, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        '$title ($count)',
        style: Theme.of(context).textTheme.labelLarge
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _changeTile(
    BuildContext context,
    GitChange change,
    GitChangeGroup group,
    ChangesState state,
  ) {
    final selected = state.selectedPath == change.path;
    final actionSnapshot = _changeActionSnapshot(change, state);
    return ContextActionMenu(
      snapshot: actionSnapshot,
      actions: _changeActions(change, state, actionSnapshot),
      onAction: _handleChangeAction,
      child: Semantics(
        container: true,
        label: '${change.path}, ${_groupText(change)}',
        hint: 'Double tap to inspect. More actions opens file operations.',
        child: ListTile(
          key: ValueKey('${group.name}:${change.path}'),
          dense: true,
          selected: selected,
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _changeSelectionBox(change, state),
              _statusBadge(context, change),
            ],
          ),
          title: Text(
            change.path,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: change.originalPath == null
              ? null
              : Text(
                  'from ${change.originalPath}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _inlineChangeAction(change, state),
              ContextActionMenuButton(
                key: ValueKey('change-actions:${change.path}'),
                semanticLabel: 'More actions for ${change.path}',
              ),
            ],
          ),
          onTap: () => unawaited(_activeController.selectChange(change)),
        ),
      ),
    );
  }

  Widget _inlineChangeAction(GitChange change, ChangesState state) {
    final controller = _activeController;
    final canStage = controller.canStagePath(change);
    final canUnstage =
        !change.isConflicted && change.isStaged && !change.isUntracked;
    if (!canStage && !canUnstage) return const SizedBox.shrink();
    final stage = canStage;
    final label = stage ? 'Stage ${change.path}' : 'Unstage ${change.path}';
    return IconButton(
      key: ValueKey('${stage ? 'stage' : 'unstage'}-change:${change.path}'),
      tooltip: label,
      onPressed: state.isMutating
          ? null
          : () => unawaited(_runInlineChangeAction(change, stage: stage)),
      icon: Icon(stage ? Icons.add : Icons.undo, size: 18),
      visualDensity: VisualDensity.compact,
    );
  }

  Future<void> _runInlineChangeAction(
    GitChange change, {
    required bool stage,
  }) async {
    final controller = _activeController;
    controller.selectPath(change.path);
    if (stage) {
      await controller.stageSelected();
    } else {
      await controller.unstageSelected();
    }
  }

  Widget _changeSelectionBox(GitChange change, ChangesState state) {
    final controller = _activeController;
    final enabled = controller.canStagePath(change) && !state.isMutating;
    final focusNode = _changeSelectionFocusNodes.putIfAbsent(
      change.path,
      FocusNode.new,
    );
    return SizedBox(
      width: 36,
      child: Listener(
        onPointerDown: enabled ? (_) => focusNode.requestFocus() : null,
        child: Focus(
          focusNode: focusNode,
          canRequestFocus: enabled,
          descendantsAreFocusable: false,
          descendantsAreTraversable: false,
          onKeyEvent: enabled
              ? (node, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.space) {
                    controller.togglePathSelection(
                      change.path,
                      !state.selectedPaths.contains(change.path),
                    );
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                }
              : null,
          child: Transform.scale(
            scale: _diffCheckboxScale,
            child: Checkbox(
              key: ValueKey('change-select:${change.path}'),
              value: state.selectedPaths.contains(change.path),
              onChanged: enabled
                  ? (selected) {
                      if (selected != null) {
                        controller.togglePathSelection(change.path, selected);
                      }
                    }
                  : null,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              semanticLabel: enabled
                  ? 'Select ${change.path} for staging'
                  : '${change.path} cannot be staged',
            ),
          ),
        ),
      ),
    );
  }

  ContextActionSnapshot _changeActionSnapshot(
    GitChange change,
    ChangesState state,
  ) {
    final status = state.snapshot!;
    final scope = change.isStaged && !change.isUnstaged
        ? GitDiffScope.staged
        : GitDiffScope.workingTree;
    return ContextActionSnapshot(
      repository: widget.repository,
      target: ContextActionTarget.change(
        path: change.path,
        originalPath: change.originalPath,
        diffScope: scope,
      ),
      fingerprint:
          '${status.generation}:${status.contentHash}:${change.path}:'
          '${change.originalPath ?? ''}:${change.indexStatus}:'
          '${change.worktreeStatus}:${scope.name}',
    );
  }

  List<ContextActionDescriptor> _changeActions(
    GitChange change,
    ChangesState state,
    ContextActionSnapshot snapshot,
  ) {
    final busyReason = state.isMutating || state.isDiscardPreparing
        ? 'Git is already running.'
        : null;
    final tracked = !change.isUntracked && !change.isConflicted;
    final pathExists = repositoryPathExists(widget.repository, change.path);
    ContextActionDescriptor action({
      required ContextActionId id,
      required String label,
      required IconData icon,
      required ContextActionGroup group,
      required ContextActionRoute route,
      bool enabled = true,
      String? disabledReason,
    }) => ContextActionDescriptor(
      id: id,
      label: label,
      icon: icon,
      group: group,
      route: route,
      snapshot: snapshot,
      enabled: enabled && busyReason == null,
      disabledReason: busyReason ?? disabledReason,
    );

    final selected = state.selectedPath == change.path && state.diff != null;
    final canStageSelected =
        selected && _activeController.canStagePatch && busyReason == null;
    final ignoreReason = change.isUntracked
        ? null
        : 'Only untracked paths can receive an ignore rule.';
    return [
      action(
        id: ContextActionId.inspect,
        label: 'Inspect',
        icon: Icons.visibility_outlined,
        group: ContextActionGroup.inspect,
        route: ContextActionRoute.inspect,
      ),
      action(
        id: ContextActionId.fileHistory,
        label: 'File history',
        icon: Icons.history,
        group: ContextActionGroup.inspect,
        route: ContextActionRoute.fileHistory,
        enabled: tracked,
        disabledReason: tracked ? null : 'File history needs a tracked path.',
      ),
      action(
        id: ContextActionId.blame,
        label: 'Blame',
        icon: Icons.person_search_outlined,
        group: ContextActionGroup.inspect,
        route: ContextActionRoute.blame,
        enabled: tracked,
        disabledReason: tracked ? null : 'Blame needs a tracked path.',
      ),
      action(
        id: ContextActionId.compare,
        label: 'Compare with HEAD',
        icon: Icons.compare_arrows,
        group: ContextActionGroup.inspect,
        route: ContextActionRoute.compare,
      ),
      action(
        id: ContextActionId.copyRelativePath,
        label: 'Copy relative path',
        icon: Icons.content_copy,
        group: ContextActionGroup.inspect,
        route: ContextActionRoute.copyRelativePath,
      ),
      action(
        id: ContextActionId.copyAbsolutePath,
        label: 'Copy absolute path',
        icon: Icons.folder_copy_outlined,
        group: ContextActionGroup.inspect,
        route: ContextActionRoute.copyAbsolutePath,
      ),
      action(
        id: ContextActionId.reveal,
        label: 'Reveal in file manager',
        icon: Icons.folder_open_outlined,
        group: ContextActionGroup.inspect,
        route: ContextActionRoute.reveal,
        enabled: pathExists,
        disabledReason: pathExists
            ? null
            : 'The current working-tree file is not present.',
      ),
      action(
        id: ContextActionId.stage,
        label: 'Stage',
        icon: Icons.add,
        group: ContextActionGroup.workflow,
        route: ContextActionRoute.stage,
        enabled:
            !change.isConflicted && (change.isUntracked || change.isUnstaged),
        disabledReason:
            !change.isConflicted && (change.isUntracked || change.isUnstaged)
            ? null
            : change.isConflicted
            ? 'Conflicted paths need the conflict workflow.'
            : 'This path has no unstaged content to stage.',
      ),
      action(
        id: ContextActionId.unstage,
        label: 'Unstage',
        icon: Icons.undo,
        group: ContextActionGroup.workflow,
        route: ContextActionRoute.unstage,
        enabled: !change.isConflicted && change.isStaged && !change.isUntracked,
        disabledReason:
            !change.isConflicted && change.isStaged && !change.isUntracked
            ? null
            : change.isConflicted
            ? 'Conflicted paths need the conflict workflow.'
            : 'This path has no staged content to unstage.',
      ),
      action(
        id: ContextActionId.stageSelectedPatch,
        label: 'Stage selected lines/hunks',
        icon: Icons.checklist,
        group: ContextActionGroup.workflow,
        route: ContextActionRoute.stageSelectedPatch,
        enabled: canStageSelected,
        disabledReason: canStageSelected
            ? null
            : 'Select lines or hunks from this file first.',
      ),
      action(
        id: ContextActionId.moveToChangelist,
        label: 'Move to changelist',
        icon: Icons.playlist_add,
        group: ContextActionGroup.workflow,
        route: ContextActionRoute.moveToChangelist,
        enabled: tracked,
        disabledReason: tracked
            ? null
            : 'Only tracked paths can move to a changelist.',
      ),
      action(
        id: ContextActionId.shelve,
        label: 'Shelve selected',
        icon: Icons.inventory_2_outlined,
        group: ContextActionGroup.workflow,
        route: ContextActionRoute.shelve,
        enabled: tracked,
        disabledReason: tracked ? null : 'Only tracked paths can be shelved.',
      ),
      action(
        id: ContextActionId.ignoreLocal,
        label: 'Ignore locally',
        icon: Icons.visibility_off_outlined,
        group: ContextActionGroup.workflow,
        route: ContextActionRoute.ignoreLocal,
        enabled: change.isUntracked,
        disabledReason: ignoreReason,
      ),
      action(
        id: ContextActionId.ignoreRepository,
        label: 'Ignore in repository',
        icon: Icons.rule_folder_outlined,
        group: ContextActionGroup.workflow,
        route: ContextActionRoute.ignoreRepository,
        enabled: change.isUntracked,
        disabledReason: ignoreReason,
      ),
      action(
        id: ContextActionId.discard,
        label: 'Discard',
        icon: Icons.delete_outline,
        group: ContextActionGroup.destructive,
        route: ContextActionRoute.discard,
        enabled:
            !change.isConflicted && !change.isUntracked && change.isUnstaged,
        disabledReason:
            !change.isConflicted && !change.isUntracked && change.isUnstaged
            ? null
            : change.isConflicted
            ? 'Conflicted paths need the conflict workflow.'
            : change.isUntracked
            ? 'Untracked files are not discarded by this action.'
            : 'This path has no working-tree changes to discard.',
      ),
    ];
  }

  Future<void> _handleChangeAction(ContextActionDescriptor action) async {
    final currentState = _activeController.state;
    final currentSnapshot = currentState.snapshot;
    if (currentSnapshot == null ||
        action.snapshot.repository != widget.repository ||
        action.snapshot.target.kind != ContextActionTargetKind.change) {
      return;
    }
    final current = currentSnapshot.changes
        .where((change) => change.path == action.snapshot.target.identity)
        .firstOrNull;
    if (current == null) return;
    final currentActionSnapshot = _changeActionSnapshot(current, currentState);
    if (currentActionSnapshot != action.snapshot) return;

    switch (action.route) {
      case ContextActionRoute.inspect:
        await _activeController.selectChange(current);
      case ContextActionRoute.stage:
        _activeController.selectPath(current.path);
        await _activeController.stageSelected();
      case ContextActionRoute.unstage:
        _activeController.selectPath(current.path);
        await _activeController.unstageSelected();
      case ContextActionRoute.stageSelectedPatch:
        final alreadySelected =
            currentState.selectedPath == current.path &&
            currentState.diff?.scope == GitDiffScope.workingTree;
        if (!alreadySelected) {
          await _activeController.selectChange(current);
        }
        if (_activeController.canStagePatch) {
          await _activeController.stageSelectedPatch();
        }

      case ContextActionRoute.discard:
        _activeController.selectPath(current.path);
        await _showDiscardDialog(context, _activeController);
      case ContextActionRoute.moveToChangelist:
        await _openShelves(context, path: current.path);
      case ContextActionRoute.shelve:
        await _openShelves(context, path: current.path);
      case ContextActionRoute.ignoreLocal:
        await _openIgnoreForPath(context, current.path);
      case ContextActionRoute.ignoreRepository:
        await _openIgnoreForPath(context, current.path);
      case ContextActionRoute.fileHistory:
        await _openFileHistoryForPath(context, current.path);
      case ContextActionRoute.blame:
        await _openFileHistoryForPath(context, current.path, blame: true);
      case ContextActionRoute.compare:
        await _openComparisonForPath(context, current.path);
      case ContextActionRoute.copyRelativePath:
        await _copyPath(current.path, absolute: false);
      case ContextActionRoute.copyAbsolutePath:
        await _copyPath(current.path, absolute: true);
      case ContextActionRoute.reveal:
        await _revealPath(current.path);
      case ContextActionRoute.cherryPick ||
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
          ContextActionRoute.compareBranch ||
          ContextActionRoute.compareRemote ||
          ContextActionRoute.checkoutRemote ||
          ContextActionRoute.deleteRemote ||
          ContextActionRoute.cherryPickRemote ||
          ContextActionRoute.hostLink ||
          ContextActionRoute.openRepository ||
          ContextActionRoute.activateRepository ||
          ContextActionRoute.closeRepository ||
          ContextActionRoute.closeOtherRepositories ||
          ContextActionRoute.removeRecentRepository ||
          ContextActionRoute.copyRepositoryPath ||
          ContextActionRoute.revealRepository ||
          ContextActionRoute.openNestedRepository:
        return;
    }
  }

  Future<void> _openIgnoreForPath(BuildContext context, String path) async {
    await showDialog<void>(
      context: context,
      builder: (_) => IgnoreDialog(
        gateway: widget.gateway,
        repository: widget.repository,
        initialPath: path,
      ),
    );
    if (context.mounted) await _activeController.refresh();
  }

  Future<void> _openFileHistoryForPath(
    BuildContext context,
    String path, {
    bool blame = false,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (_) => FileHistoryDialog(
        gateway: widget.gateway,
        repository: widget.repository,
        initialPath: path,
        initialBlame: blame,
      ),
    );
  }

  Future<void> _openComparisonForPath(BuildContext context, String path) async {
    await showDialog<void>(
      context: context,
      builder: (_) => ComparisonDialog(
        gateway: widget.gateway,
        repository: widget.repository,
        initialLeft: 'HEAD',
        initialRight: 'WORKTREE',
        fileManager: widget.fileManager,
        initialPath: path,
      ),
    );
  }

  Future<void> _copyPath(String path, {required bool absolute}) async {
    final value = absolute
        ? repositoryAbsolutePath(widget.repository.root, path)
        : path;
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) {
      _showActionMessage(
        absolute ? 'Absolute path copied.' : 'Relative path copied.',
      );
    }
  }

  Future<void> _revealPath(String path) async {
    final result = await widget.fileManager.reveal(
      repositoryAbsolutePath(widget.repository.root, path),
    );
    if (!mounted) return;
    _showActionMessage(
      result.isSuccess
          ? 'Opened the file manager.'
          : result.message ?? 'The file manager could not reveal this path.',
    );
  }

  void _showActionMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _statusBadge(BuildContext context, GitChange change) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground, border) = change.isConflicted
        ? (scheme.errorContainer, scheme.onErrorContainer, scheme.error)
        : change.isUntracked
        ? (
            scheme.tertiaryContainer,
            scheme.onTertiaryContainer,
            scheme.tertiary,
          )
        : (scheme.primaryContainer, scheme.onPrimaryContainer, scheme.primary);
    return Container(
      width: 28,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: border),
      ),
      child: Text(
        change.shortStatus,
        style: TextStyle(
          color: foreground,
          fontSize: pixelLabelSmallSize,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _details(
    BuildContext context,
    GitStatusSnapshot snapshot,
    ChangesState state,
  ) {
    final selectedPath = state.selectedPath;
    if (selectedPath == null) {
      final theme = Theme.of(context);
      return LayoutBuilder(
        builder: (context, constraints) {
          final short = constraints.maxHeight < 180;
          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: 24,
              vertical: short ? 8 : 24,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!short) ...[
                      Icon(
                        Icons.difference_outlined,
                        size: 32,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 12),
                    ],
                    Text('Select a change', style: theme.textTheme.titleMedium),
                    if (!short) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Choose a file from the changes list to inspect its '
                        'diff and available actions.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      );
    }
    GitChange? selected;
    for (final change in snapshot.changes) {
      if (change.path == selectedPath) {
        selected = change;
        break;
      }
    }
    if (selected == null) {
      return const Center(child: Text('That change is no longer present.'));
    }

    final compact = MediaQuery.sizeOf(context).width < 480;
    final smallHeight = MediaQuery.sizeOf(context).height < 700;
    final header = <Widget>[
      Text(
        selected.path,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 10),
      Text('Status ${selected.shortStatus}'),
      const SizedBox(height: 6),
      Text(_groupText(selected)),
      if (selected.originalPath case final originalPath?) ...[
        const SizedBox(height: 6),
        Text('Original path: $originalPath'),
      ],
      if (selected.isStaged || selected.isUnstaged) ...[
        const SizedBox(height: 16),
        _scopeSelector(context, selected, state),
      ],
      if (_activeController.canStagePatch ||
          _activeController.canUnstagePatch ||
          _activeController.canStageSelected ||
          _activeController.canUnstageSelected ||
          _activeController.canDiscardSelected) ...[
        const SizedBox(height: 16),
        _mutationActions(context, state),
      ],
      if (state.mutationError case final error?) ...[
        const SizedBox(height: 10),
        Text(
          error.userMessage,
          key: const Key('mutation-error'),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ],
      if (state.discardError case final error?) ...[
        const SizedBox(height: 10),
        Text(
          error.userMessage,
          key: const Key('discard-error'),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ],
      if (state.isDiscardPreparing || state.isMutating)
        const LinearProgressIndicator(),
      const SizedBox(height: 16),
      if (state.isDiffLoading) const LinearProgressIndicator(),
      if (state.diffError case final error?) ...[
        const SizedBox(height: 12),
        Text(
          error.userMessage,
          key: const Key('diff-error'),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ],
      if (state.diff?.hunks.isNotEmpty == true) ...[
        const SizedBox(height: 8),
        _patchSelectionHint(context, state),
      ],
      const SizedBox(height: 12),
    ];
    if (!compact && smallHeight) {
      return _smallHeightDetails(context, selected, state);
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 12 : 16, 16, compact ? 12 : 16, 0),
      child: compact
          ? ListView(
              key: const Key('compact-details-scroll'),
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: header,
                ),
                _diffBody(context, state, scrollable: false),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...header,
                Expanded(child: _diffBody(context, state)),
              ],
            ),
    );
  }

  /// Keeps the diff viewport usable on short desktop windows. The regular
  /// details header is intentionally spacious, so short windows get a small
  /// independently scrollable header while the diff keeps its own viewport.
  Widget _smallHeightDetails(
    BuildContext context,
    GitChange selected,
    ChangesState state,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 160,
            child: ListView(
              key: const Key('short-details-header-scroll'),
              padding: EdgeInsets.zero,
              children: [
                Text(
                  selected.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text('Status ${selected.shortStatus}'),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _groupText(selected),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (selected.isStaged || selected.isUnstaged) ...[
                  const SizedBox(height: 6),
                  _scopeSelector(context, selected, state),
                ],
                if (_activeController.canStagePatch ||
                    _activeController.canUnstagePatch ||
                    _activeController.canStageSelected ||
                    _activeController.canUnstageSelected ||
                    _activeController.canDiscardSelected) ...[
                  const SizedBox(height: 6),
                  _mutationActions(context, state),
                ],
                if (state.mutationError case final error?)
                  Text(
                    error.userMessage,
                    key: const Key('mutation-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (state.discardError case final error?)
                  Text(
                    error.userMessage,
                    key: const Key('discard-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(child: _diffBody(context, state)),
        ],
      ),
    );
  }

  Widget _mutationActions(BuildContext context, ChangesState state) {
    final controller = _activeController;
    final hasPartialStage = controller.canStagePatch;
    final hasPartialUnstage = controller.canUnstagePatch;
    return PixelActionRow(
      children: [
        if (controller.canStagePatch)
          FilledButton.icon(
            key: const Key('stage-selected-patch'),
            onPressed: state.isMutating || state.isDiscardPreparing
                ? null
                : controller.stageSelectedPatch,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Stage selection'),
          ),
        if (controller.canUnstagePatch)
          OutlinedButton.icon(
            key: const Key('unstage-selected-patch'),
            onPressed: state.isMutating || state.isDiscardPreparing
                ? null
                : controller.unstageSelectedPatch,
            icon: const Icon(Icons.undo, size: 18),
            label: const Text('Unstage selection'),
          ),
        if (controller.canStageSelected && !hasPartialStage)
          FilledButton.icon(
            key: const Key('stage-selected'),
            onPressed: state.isMutating || state.isDiscardPreparing
                ? null
                : controller.stageSelected,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Stage'),
          ),
        if (controller.canUnstageSelected && !hasPartialUnstage)
          OutlinedButton.icon(
            key: const Key('unstage-selected'),
            onPressed: state.isMutating || state.isDiscardPreparing
                ? null
                : controller.unstageSelected,
            icon: const Icon(Icons.undo, size: 18),
            label: const Text('Unstage'),
          ),
        if (controller.canDiscardSelected)
          TextButton.icon(
            key: const Key('discard-selected'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: state.isMutating || state.isDiscardPreparing
                ? null
                : () => unawaited(_showDiscardDialog(context, controller)),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Discard'),
          ),
      ],
    );
  }

  Future<void> _showDiscardDialog(
    BuildContext context,
    ChangesController controller,
  ) async {
    final preview = await controller.prepareDiscard();
    if (!context.mounted || preview == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: Text(
          'Discard the working-tree changes in ${preview.path}? '
          'Staged changes will be kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-discard'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    if (confirmed == true) {
      await controller.confirmDiscard(preview);
    } else {
      controller.cancelDiscardPreview();
    }
  }

  Future<void> _openHistory(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HistoryScreen(
          gateway: widget.gateway,
          repository: widget.repository,
          controller: widget.historyController,
        ),
      ),
    );
  }

  Future<void> _openConflictWorkspace(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(20),
        child: SizedBox(
          width: MediaQuery.sizeOf(context).width < 900
              ? MediaQuery.sizeOf(context).width - 40
              : 1120,
          height: MediaQuery.sizeOf(context).height < 720
              ? MediaQuery.sizeOf(context).height - 40
              : 680,
          child: ConflictWorkspaceScreen(
            gateway: widget.gateway,
            repository: widget.repository,
            onClose: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    );
    if (!context.mounted) return;
    await _activeController.refresh();
  }

  Future<void> _openBranches(BuildContext context) async {
    final preferences = AppPreferencesScope.maybeOf(context)?.preferences;
    final result = await showDialog<Object>(
      context: context,
      builder: (_) => BranchDialog(
        gateway: widget.gateway,
        repository: widget.repository,
        preferredBranch: preferences?.defaultBranch,
        preferredRemote: preferences?.defaultRemote,
        credentialStore: widget.credentialStore,
        repositoryCredentialStore: widget.repositoryCredentialStore,
      ),
    );
    if (!context.mounted || result == null) return;
    await _activeController.refresh();
    if (!context.mounted) return;
    if (result case final GitRemoteBranchActionResult remoteResult) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(remoteResult.summary)));
      return;
    }
    if (result is! GitBranchActionResult) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Switched to ${result.branchName}.')),
    );
  }

  Future<void> _openGitAccounts(BuildContext context) async {
    final store = widget.credentialStore;
    if (store == null) return;
    await showDialog<void>(
      context: context,
      builder: (_) => CredentialsDialog(
        store: store,
        oauthGateway: widget.gateway is GitCredentialOAuthGateway
            ? widget.gateway as GitCredentialOAuthGateway
            : null,
        tester: widget.gateway is GitCredentialTestGateway
            ? widget.gateway as GitCredentialTestGateway
            : null,
        repositoryRoot: widget.repository.root,
        repositoryCredentialStore: widget.repositoryCredentialStore,
      ),
    );
  }

  Future<void> _openRemotes(BuildContext context) async {
    final preferences = AppPreferencesScope.maybeOf(context)?.preferences;
    final result = await showDialog<Object?>(
      context: context,
      builder: (_) => RemoteDialog(
        gateway: widget.gateway,
        repository: widget.repository,
        preferredRemote: preferences?.defaultRemote,
        credentialStore: widget.credentialStore,
        repositoryCredentialStore: widget.repositoryCredentialStore,
      ),
    );
    if (!context.mounted || result == null) return;
    await _activeController.refresh();
    if (!context.mounted) return;
    final message = switch (result) {
      GitRemoteOperationResult() =>
        '${_remoteOperationLabel(result.operation)} ${result.remote} complete.',
      GitPushResult() => result.summary,
      _ => null,
    };
    if (message != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _openPush(BuildContext context) async {
    final result = await showDialog<GitPushResult>(
      context: context,
      builder: (_) => PushDialog(
        gateway: widget.gateway,
        repository: widget.repository,
        credentialStore: widget.credentialStore,
        repositoryCredentialStore: widget.repositoryCredentialStore,
        preferredRemote: AppPreferencesScope.maybeOf(context)
            ?.preferences
            .defaultRemote,
      ),
    );
    if (!context.mounted || result == null) return;
    await _activeController.refresh();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(result.summary)));
  }

  Future<void> _openUpdateProject(BuildContext context) async {
    final result = await showDialog<GitUpdateProjectResult>(
      context: context,
      builder: (_) => UpdateProjectDialog(
        gateway: widget.gateway,
        repository: widget.repository,
      ),
    );
    if (!context.mounted || result == null) return;
    await _activeController.refresh();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(result.summary)));
  }

  Future<void> _openObjects(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) =>
          ObjectDialog(gateway: widget.gateway, repository: widget.repository),
    );
    if (!context.mounted) return;
    await _activeController.refresh();
  }

  Future<void> _openComparison(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => ComparisonDialog(
        gateway: widget.gateway,
        repository: widget.repository,
      ),
    );
  }

  Future<void> _openThreeWayComparison(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => ThreeWayComparisonDialog(
        gateway: widget.gateway,
        repository: widget.repository,
        initialPath: _activeController.state.selectedPath,
      ),
    );
  }

  Future<void> _openShelves(BuildContext context, {String? path}) async {
    await showDialog<void>(
      context: context,
      builder: (_) => ShelfDialog(
        gateway: widget.gateway,
        repository: widget.repository,
        initialPaths: [?(path ?? _activeController.state.selectedPath)],
      ),
    );
    if (!context.mounted) return;
    await _activeController.refresh();
  }

  Future<void> _openFileHistory(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => FileHistoryDialog(
        gateway: widget.gateway,
        repository: widget.repository,
        initialPath: _activeController.state.selectedPath ?? '',
      ),
    );
  }

  Future<void> _openHistoryRollback(
    BuildContext context, {
    GitHistoryRollbackAction? initialAction,
  }) async {
    final result = await showDialog<GitHistoryRollbackResult>(
      context: context,
      builder: (_) => ResetDialog(
        gateway: widget.gateway,
        repository: widget.repository,
        initialAction: initialAction,
      ),
    );
    if (!context.mounted || result == null) return;
    await _activeController.refresh();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(result.summary)));
  }

  Future<void> _openWorktrees(BuildContext context) async {
    final opened = await showDialog<RepositoryOpened>(
      context: context,
      builder: (_) => WorktreeDialog(
        gateway: widget.gateway,
        repository: widget.repository,
        pathHistory: widget.pathHistory,
      ),
    );
    if (!context.mounted || opened == null) return;
    final onOpenRepository = widget.onOpenRepository;
    if (onOpenRepository != null) {
      await onOpenRepository(opened);
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Opened ${opened.root}.')));
  }

  Future<void> _openIgnoreMetadata(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) =>
          IgnoreDialog(gateway: widget.gateway, repository: widget.repository),
    );
    if (!context.mounted) return;
    await _activeController.refresh();
  }

  Future<void> _openSubmodules(BuildContext context) async {
    final opened = await showDialog<RepositoryOpened>(
      context: context,
      builder: (_) => SubmoduleDialog(
        gateway: widget.gateway,
        repository: widget.repository,
        onOpenRepository: (repository) async {
          if (context.mounted) Navigator.of(context).pop(repository);
        },
      ),
    );
    if (!context.mounted || opened == null) return;
    final onOpenRepository = widget.onOpenRepository;
    if (onOpenRepository != null) {
      await onOpenRepository(opened);
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Opened ${opened.root}.')));
  }

  Future<void> _openRecovery(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => RecoveryDialog(
        gateway: widget.gateway,
        repository: widget.repository,
      ),
    );
    if (!context.mounted) return;
    await _activeController.refresh();
  }

  Future<void> _openRepositorySetup(BuildContext context) async {
    await showDialog<RepositoryOpened>(
      context: context,
      builder: (_) => RepositorySetupDialog(
        gateway: widget.gateway,
        repository: widget.repository,
        credentialStore: widget.credentialStore,
        pathHistory: widget.pathHistory,
      ),
    );
    if (!context.mounted) return;
    await _activeController.refresh();
  }

  Future<void> _openHosting(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => HostingDialog(
        gateway: widget.gateway,
        repository: widget.repository,
        initialPath: _activeController.state.selectedPath ?? '',
      ),
    );
  }

  Widget _scopeSelector(
    BuildContext context,
    GitChange selected,
    ChangesState state,
  ) {
    return SegmentedButton<GitDiffScope>(
      segments: const [
        ButtonSegment(value: GitDiffScope.workingTree, label: Text('Worktree')),
        ButtonSegment(value: GitDiffScope.staged, label: Text('Staged')),
      ],
      selected: {state.diffScope},
      onSelectionChanged: (scopes) {
        final scope = scopes.firstOrNull;
        if (scope == null) return;
        unawaited(
          _activeController.loadDiff(
            selected.path,
            originalPath: selected.originalPath,
            scope: scope,
          ),
        );
      },
    );
  }

  Widget _diffBody(
    BuildContext context,
    ChangesState state, {
    bool scrollable = true,
  }) {
    if (state.isDiffLoading && state.diff == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.diffError != null && state.diff == null) {
      return const Center(child: Text('The diff could not be loaded.'));
    }
    final diff = state.diff;
    if (diff == null) {
      return const Center(child: Text('Select a change to inspect its diff.'));
    }
    if (diff.isBinary) {
      return const Center(
        child: Text('Binary file changes are not shown as text.'),
      );
    }
    if (diff.isEmpty) {
      return const Center(child: Text('No changes in this scope.'));
    }

    final visibleLineCount = state.visibleDiffLineCount;
    final hasMoreLines = state.hasMoreDiffLines;
    final lines = scrollable
        ? ListView.builder(
            key: const Key('diff-lines'),
            itemCount: visibleLineCount + (hasMoreLines ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == visibleLineCount) {
                return _loadMoreDiffLines(context, state);
              }
              return _diffLine(context, diff.lines[index], index, state);
            },
          )
        : Column(
            key: const Key('diff-lines'),
            children: [
              for (var index = 0; index < visibleLineCount; index++)
                _diffLine(context, diff.lines[index], index, state),
              if (hasMoreLines) _loadMoreDiffLines(context, state),
            ],
          );
    return SelectionArea(key: const Key('diff-selection-area'), child: lines);
  }

  Widget _loadMoreDiffLines(BuildContext context, ChangesState state) {
    final total = state.diff?.lines.length ?? 0;
    return Semantics(
      container: true,
      label: 'Diff output truncated. Load more lines.',
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(
              'Showing ${state.visibleDiffLineCount} of $total diff lines.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            TextButton(
              key: const Key('load-more-diff-lines'),
              onPressed: _activeController.loadMoreDiffLines,
              child: const Text('Load more diff lines'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _patchSelectionHint(BuildContext context, ChangesState state) {
    final selectedCount = _activeController.selectedDiffChangeCount;
    final selectedHunks = state.selectedDiffHunks.length;
    final scope = state.diffScope == GitDiffScope.workingTree
        ? 'Working-tree changes'
        : 'Staged changes';
    return Text(
      selectedCount == 0 && selectedHunks == 0
          ? '$scope · select hunks or lines to make a partial change.'
          : '$scope · $selectedCount line(s) selected. Shift+Space extends a range.',
      key: const Key('diff-scope-label'),
      style: Theme.of(context).textTheme.bodySmall,
    );
  }

  Widget _diffLine(
    BuildContext context,
    GitDiffLine line,
    int index,
    ChangesState state,
  ) {
    final colors = Theme.of(context).colorScheme;
    final background = switch (line.kind) {
      GitDiffLineKind.addition => colors.tertiaryContainer,
      GitDiffLineKind.deletion => colors.errorContainer,
      GitDiffLineKind.hunkHeader => colors.primaryContainer,
      _ => Colors.transparent,
    };
    final foreground = switch (line.kind) {
      GitDiffLineKind.addition => colors.onTertiaryContainer,
      GitDiffLineKind.deletion => colors.onErrorContainer,
      GitDiffLineKind.hunkHeader => colors.onPrimaryContainer,
      _ => colors.onSurface,
    };
    return Container(
      key: ValueKey('diff-line-$index'),
      color: background,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _diffSelector(context, line, index, state),
          SelectionContainer.disabled(child: _lineNumber(line.oldLineNumber)),
          SelectionContainer.disabled(child: _lineNumber(line.newLineNumber)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              line.text,
              style: TextStyle(
                color: foreground,
                fontFamily: 'monospace',
                fontSize: pixelBodySmallSize,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _diffSelector(
    BuildContext context,
    GitDiffLine line,
    int lineIndex,
    ChangesState state,
  ) {
    final controller = _activeController;
    final hunkIndex = line.hunkIndex;
    if (line.kind == GitDiffLineKind.hunkHeader && hunkIndex != null) {
      return SizedBox(
        width: 40,
        height: _diffSelectorHeight,
        child: Center(
          child: Transform.scale(
            scale: _diffCheckboxScale,
            child: Checkbox(
              key: ValueKey('diff-hunk-select-$hunkIndex'),
              value: controller.isDiffHunkSelected(hunkIndex),
              onChanged: state.isMutating
                  ? null
                  : (selected) {
                      if (selected != null) {
                        controller.toggleDiffHunk(hunkIndex, selected);
                      }
                    },
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              semanticLabel: 'Select hunk ${hunkIndex + 1}',
            ),
          ),
        ),
      );
    }
    final isChanged =
        line.kind == GitDiffLineKind.addition ||
        line.kind == GitDiffLineKind.deletion;
    if (!isChanged || hunkIndex == null) return const SizedBox(width: 40);
    return SizedBox(
      width: 40,
      height: _diffSelectorHeight,
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.space &&
              _isShiftPressed) {
            controller.toggleDiffLine(
              lineIndex,
              !controller.isDiffLineSelected(lineIndex),
              extend: true,
            );
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Center(
          child: Transform.scale(
            scale: _diffCheckboxScale,
            child: Checkbox(
              key: ValueKey('diff-line-select-$lineIndex'),
              value: controller.isDiffLineSelected(lineIndex),
              onChanged: state.isMutating
                  ? null
                  : (selected) {
                      if (selected != null) {
                        controller.toggleDiffLine(
                          lineIndex,
                          selected,
                          extend: _isShiftPressed,
                        );
                      }
                    },
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              semanticLabel: 'Select changed line ${lineIndex + 1}',
            ),
          ),
        ),
      ),
    );
  }

  bool get _isShiftPressed {
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    return pressed.contains(LogicalKeyboardKey.shiftLeft) ||
        pressed.contains(LogicalKeyboardKey.shiftRight);
  }

  Widget _lineNumber(int? number) {
    return SizedBox(
      width: 42,
      child: Text(
        number?.toString() ?? '',
        textAlign: TextAlign.right,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: pixelLabelSmallSize,
          height: 1.25,
        ),
      ),
    );
  }

  String _groupText(GitChange change) {
    if (change.isConflicted) return 'This path needs conflict resolution.';
    if (change.isUntracked) return 'This path is not tracked by Git yet.';
    if (change.isStaged && change.isUnstaged) {
      return 'This path has both staged and unstaged changes.';
    }
    if (change.isStaged) return 'This path is ready for the next commit.';
    return 'This path has working-tree changes.';
  }

  Widget _errorState(GitError error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(error.userMessage, key: const Key('changes-error')),
      ),
    );
  }

  Widget _errorBanner(BuildContext context, GitError error) {
    return Container(
      key: const Key('changes-refresh-error'),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      color: Theme.of(context).colorScheme.errorContainer,
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error.userMessage,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  ChangesController get _activeController =>
      _manualController ?? ref.read(changesControllerProvider(_providerArgs));
}

String _remoteOperationLabel(GitRemoteOperation operation) =>
    switch (operation) {
      GitRemoteOperation.fetch => 'Fetch',
      GitRemoteOperation.pull => 'Pull',
      GitRemoteOperation.push => 'Push',
    };

String _cleanupLabel(GitCommitCleanupMode mode) => switch (mode) {
  GitCommitCleanupMode.defaultMode => 'Git default',
  GitCommitCleanupMode.strip => 'Strip whitespace',
  GitCommitCleanupMode.whitespace => 'Clean whitespace only',
  GitCommitCleanupMode.verbatim => 'Verbatim',
  GitCommitCleanupMode.scissors => 'Scissors marker',
};

enum _ChangesMenuAction {
  remotes,
  gitAccounts,
  objects,
  comparison,
  threeWayComparison,
  shelves,
  fileHistory,
  resetBranch,
  undoCommit,
  revertCommits,
  worktrees,
  ignoreMetadata,
  submodules,
  recovery,
  setup,
  hosting,
  lfs,
  signing,
  refresh,
}

class _StageAndCommitDialog extends StatefulWidget {
  const _StageAndCommitDialog();

  @override
  State<_StageAndCommitDialog> createState() => _StageAndCommitDialogState();
}

class _StageAndCommitDialogState extends State<_StageAndCommitDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _controller.text.trim().isNotEmpty;
    return AlertDialog(
      key: const Key('stage-and-commit-dialog'),
      title: const Text('Stage and commit'),
      content: TextField(
        key: const Key('stage-and-commit-message'),
        controller: _controller,
        autofocus: true,
        minLines: 2,
        maxLines: 4,
        textInputAction: TextInputAction.newline,
        decoration: const InputDecoration(
          labelText: 'Commit message',
          hintText: 'Describe the selected changes',
        ),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(
          key: const Key('stage-and-commit-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('stage-and-commit-submit'),
          onPressed: canSubmit
              ? () => Navigator.of(context).pop(_controller.text.trim())
              : null,
          child: const Text('Stage & commit'),
        ),
      ],
    );
  }
}
