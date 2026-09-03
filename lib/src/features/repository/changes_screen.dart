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
import 'package:gift/src/features/repository/changes_controller.dart';
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
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:gift/src/app/pixel_theme.dart';

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
    this.autoInitialize = true,
  });

  final GitGateway gateway;
  final RepositoryOpened repository;
  final ChangesController? controller;
  final HistoryController? historyController;
  final VoidCallback? onBack;
  final Future<void> Function(RepositoryOpened repository)? onOpenRepository;
  final bool autoInitialize;

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
    this.onOpenRepository,
    required this.autoInitialize,
  });

  final GitGateway gateway;
  final RepositoryOpened repository;
  final ChangesController? controller;
  final HistoryController? historyController;
  final VoidCallback? onBack;
  final Future<void> Function(RepositoryOpened repository)? onOpenRepository;
  final bool autoInitialize;

  @override
  ConsumerState<_ChangesScreenBody> createState() => _ChangesScreenBodyState();
}

class _ChangesScreenBodyState extends ConsumerState<_ChangesScreenBody> {
  ChangesController? _manualController;
  late final ChangesControllerArgs _providerArgs;
  late final TextEditingController _commitMessageController;
  late final TextEditingController _authorNameController;
  late final TextEditingController _authorEmailController;
  var _commitOptionsExpanded = false;
  var _amend = false;
  var _signOff = false;
  var _cleanup = GitCommitCleanupMode.defaultMode;
  String? _loadedTemplate;
  GitError? _templateError;

  @override
  void initState() {
    super.initState();
    _commitMessageController = TextEditingController();
    _authorNameController = TextEditingController();
    _authorEmailController = TextEditingController();
    _providerArgs = ChangesControllerArgs(
      gateway: widget.gateway,
      repositoryId: widget.repository.repositoryId,
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
    // Ten action icons do not fit beside a repository path on tablet-sized
    // windows. Keep the app bar predictable by switching to the same menu
    // before those actions start crowding the title.
    final compactAppBar = MediaQuery.sizeOf(context).width < 1040;
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
          const PixelThemeToggle(),
          if (compactAppBar)
            PopupMenuButton<_ChangesMenuAction>(
              key: const Key('repository-actions-menu'),
              tooltip: 'Repository actions',
              icon: const Icon(Icons.more_vert),
              onSelected: (action) {
                switch (action) {
                  case _ChangesMenuAction.remotes:
                    unawaited(_openRemotes(context));
                    break;
                  case _ChangesMenuAction.push:
                    unawaited(_openPush(context));
                    break;
                  case _ChangesMenuAction.updateProject:
                    unawaited(_openUpdateProject(context));
                    break;
                  case _ChangesMenuAction.branches:
                    unawaited(_openBranches(context));
                    break;
                  case _ChangesMenuAction.history:
                    unawaited(_openHistory(context));
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
                  case _ChangesMenuAction.historyRollback:
                    unawaited(_openHistoryRollback(context));
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
                  case _ChangesMenuAction.refresh:
                    unawaited(controller.refresh());
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: _ChangesMenuAction.remotes,
                  child: Text('Remote operations'),
                ),
                const PopupMenuItem(
                  value: _ChangesMenuAction.push,
                  child: Text('Push'),
                ),
                const PopupMenuItem(
                  value: _ChangesMenuAction.updateProject,
                  child: Text('Update project'),
                ),
                const PopupMenuItem(
                  value: _ChangesMenuAction.branches,
                  child: Text('Branches'),
                ),
                const PopupMenuItem(
                  value: _ChangesMenuAction.history,
                  child: Text('History'),
                ),
                const PopupMenuItem(
                  value: _ChangesMenuAction.objects,
                  child: Text('Git objects'),
                ),
                const PopupMenuItem(
                  value: _ChangesMenuAction.comparison,
                  child: Text('Compare revisions'),
                ),
                const PopupMenuItem(
                  value: _ChangesMenuAction.threeWayComparison,
                  child: Text('Three-way compare'),
                ),
                const PopupMenuItem(
                  value: _ChangesMenuAction.shelves,
                  child: Text('Shelves & changelists'),
                ),
                const PopupMenuItem(
                  value: _ChangesMenuAction.fileHistory,
                  child: Text('File history & blame'),
                ),
                const PopupMenuItem(
                  value: _ChangesMenuAction.historyRollback,
                  child: Text('Undo, reset, or revert'),
                ),
                const PopupMenuItem(
                  value: _ChangesMenuAction.worktrees,
                  child: Text('Worktrees'),
                ),
                const PopupMenuItem(
                  value: _ChangesMenuAction.ignoreMetadata,
                  child: Text('Ignore & metadata'),
                ),
                const PopupMenuItem(
                  value: _ChangesMenuAction.submodules,
                  child: Text('Submodules & nested roots'),
                ),
                PopupMenuItem(
                  value: _ChangesMenuAction.refresh,
                  enabled: !state.isRefreshing,
                  child: const Text('Refresh changes'),
                ),
              ],
            )
          else ...[
            IconButton(
              key: const Key('open-remotes'),
              tooltip: 'Open remote operations',
              onPressed: () => unawaited(_openRemotes(context)),
              icon: const Icon(Icons.cloud_outlined),
            ),
            IconButton(
              key: const Key('open-push'),
              tooltip: 'Push to remote',
              onPressed: () => unawaited(_openPush(context)),
              icon: const Icon(Icons.cloud_upload_outlined),
            ),
            IconButton(
              key: const Key('update-project'),
              tooltip: 'Update project',
              onPressed: () => unawaited(_openUpdateProject(context)),
              icon: const Icon(Icons.cloud_download_outlined),
            ),
            IconButton(
              key: const Key('open-branches'),
              tooltip: 'Open branches',
              onPressed: () => unawaited(_openBranches(context)),
              icon: const Icon(Icons.call_split),
            ),
            IconButton(
              key: const Key('open-history'),
              tooltip: 'Open history',
              onPressed: () => unawaited(_openHistory(context)),
              icon: const Icon(Icons.history),
            ),
            IconButton(
              key: const Key('open-objects'),
              tooltip: 'Open Git objects',
              onPressed: () => unawaited(_openObjects(context)),
              icon: const Icon(Icons.inventory_2_outlined),
            ),
            IconButton(
              key: const Key('open-comparison'),
              tooltip: 'Compare revisions',
              onPressed: () => unawaited(_openComparison(context)),
              icon: const Icon(Icons.compare_arrows),
            ),
            IconButton(
              key: const Key('open-three-way-comparison'),
              tooltip: 'Three-way comparison',
              onPressed: () => unawaited(_openThreeWayComparison(context)),
              icon: const Icon(Icons.call_split),
            ),
            IconButton(
              key: const Key('open-shelves'),
              tooltip: 'Shelves and changelists',
              onPressed: () => unawaited(_openShelves(context)),
              icon: const Icon(Icons.archive_outlined),
            ),
            IconButton(
              key: const Key('open-file-history'),
              tooltip: 'File history and blame',
              onPressed: () => unawaited(_openFileHistory(context)),
              icon: const Icon(Icons.history_edu_outlined),
            ),
            IconButton(
              key: const Key('open-history-rollback'),
              tooltip: 'Undo, reset, or revert history',
              onPressed: () => unawaited(_openHistoryRollback(context)),
              icon: const Icon(Icons.history_toggle_off),
            ),
            IconButton(
              key: const Key('open-worktrees'),
              tooltip: 'Manage worktrees',
              onPressed: () => unawaited(_openWorktrees(context)),
              icon: const Icon(Icons.account_tree_outlined),
            ),
            IconButton(
              key: const Key('open-ignore-metadata'),
              tooltip: 'Inspect ignore and metadata',
              onPressed: () => unawaited(_openIgnoreMetadata(context)),
              icon: const Icon(Icons.rule_folder_outlined),
            ),
            IconButton(
              key: const Key('open-submodules'),
              tooltip: 'Manage submodules and nested roots',
              onPressed: () => unawaited(_openSubmodules(context)),
              icon: const Icon(Icons.account_tree_outlined),
            ),
            IconButton(
              tooltip: 'Refresh changes',
              onPressed: state.isRefreshing ? null : controller.refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (snapshot != null) ...[
              _summary(context, snapshot),
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
            if (snapshot != null) _statusStrip(context, snapshot, state),
          ],
        ),
      ),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyR, control: true):
            controller.refresh,
        const SingleActivator(LogicalKeyboardKey.keyH, control: true): () =>
            unawaited(_openHistory(context)),
        const SingleActivator(
          LogicalKeyboardKey.keyB,
          control: true,
          shift: true,
        ): () =>
            unawaited(_openBranches(context)),
        const SingleActivator(
          LogicalKeyboardKey.keyR,
          control: true,
          shift: true,
        ): () =>
            unawaited(_openRemotes(context)),
        const SingleActivator(LogicalKeyboardKey.enter, control: true): () =>
            unawaited(_submitCommit(controller)),
        if (widget.onBack != null)
          const SingleActivator(LogicalKeyboardKey.escape): widget.onBack!,
      },
      child: Focus(autofocus: true, child: scaffold),
    );
  }

  Widget _summary(BuildContext context, GitStatusSnapshot snapshot) {
    final compact = MediaQuery.sizeOf(context).width < 480;
    final branch = snapshot.branch.head ?? 'Detached HEAD';
    final sync = snapshot.branch.hasUpstream
        ? '${snapshot.branch.ahead} ahead · ${snapshot.branch.behind} behind'
        : 'No upstream';
    final changeLabel =
        '${snapshot.changes.length} changed ${snapshot.changes.length == 1 ? 'file' : 'files'}';
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 20,
        vertical: compact ? 8 : 10,
      ),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final items = [
            const Icon(Icons.account_tree_outlined, size: 18),
            Text(
              branch,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            Text(sync),
            Text(changeLabel),
          ];
          if (constraints.maxWidth < 760) {
            return Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: items,
            );
          }
          return Row(
            children: [
              items[0],
              const SizedBox(width: 8),
              Flexible(child: items[1]),
              const SizedBox(width: 12),
              items[2],
              const Spacer(),
              items[3],
            ],
          );
        },
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

  Widget _statusStrip(
    BuildContext context,
    GitStatusSnapshot snapshot,
    ChangesState state,
  ) {
    final compact = MediaQuery.sizeOf(context).width < 480;
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
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 20, vertical: 7),
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
                'Ctrl+R refresh · Ctrl+H history',
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
      padding: EdgeInsets.fromLTRB(compact ? 12 : 20, 10, compact ? 12 : 20, 4),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: EdgeInsets.all(compact ? 10 : 14),
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
                        const SizedBox(height: 10),
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
                      const SizedBox(width: 10),
                      button,
                    ],
                  );
                },
              ),
              const SizedBox(height: 4),
              ExpansionTile(
                key: const Key('commit-options-toggle'),
                initiallyExpanded: _commitOptionsExpanded,
                onExpansionChanged: (expanded) {
                  setState(() => _commitOptionsExpanded = expanded);
                  if (expanded) _requestCommitPreflight(controller);
                },
                tilePadding: EdgeInsets.zero,
                title: const Text('Commit options'),
                subtitle: const Text('Identity, amend, sign-off, and cleanup'),
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: compact ? 180 : 200),
                    child: SingleChildScrollView(
                      key: const Key('commit-options-scroll'),
                      child: _commitOptionsPanel(context, controller, state),
                    ),
                  ),
                ],
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
                  child: Text(_cleanupLabel(mode)),
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
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
      cleanup: _cleanup,
      author: name.isEmpty && email.isEmpty
          ? null
          : GitCommitAuthor(name: name, email: email),
    );
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
        final listWidth = constraints.maxWidth < 720 ? 260.0 : 340.0;
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
            for (final change in section.changes)
              _changeTile(context, change, section.group, state),
          ],
      ],
    );
  }

  Widget _sectionHeader(BuildContext context, String title, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
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
    return ListTile(
      key: ValueKey('${group.name}:${change.path}'),
      dense: true,
      selected: selected,
      leading: _statusBadge(context, change),
      title: Text(change.path, overflow: TextOverflow.ellipsis),
      subtitle: change.originalPath == null
          ? null
          : Text(
              'from ${change.originalPath}',
              overflow: TextOverflow.ellipsis,
            ),
      onTap: () => unawaited(_activeController.selectChange(change)),
    );
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
      return const Center(child: Text('Select a change to inspect it.'));
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
      padding: EdgeInsets.fromLTRB(
        compact ? 12 : 20,
        compact ? 16 : 24,
        compact ? 12 : 20,
        0,
      ),
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
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (controller.canStagePatch)
          FilledButton.icon(
            key: const Key('stage-selected-patch'),
            onPressed: state.isMutating || state.isDiscardPreparing
                ? null
                : controller.stageSelectedPatch,
            icon: const Icon(Icons.playlist_add, size: 18),
            label: const Text('Stage selection'),
          ),
        if (controller.canUnstagePatch)
          OutlinedButton.icon(
            key: const Key('unstage-selected-patch'),
            onPressed: state.isMutating || state.isDiscardPreparing
                ? null
                : controller.unstageSelectedPatch,
            icon: const Icon(Icons.playlist_remove, size: 18),
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
            icon: const Icon(Icons.remove, size: 18),
            label: const Text('Unstage'),
          ),
        if (controller.canDiscardSelected)
          OutlinedButton.icon(
            key: const Key('discard-selected'),
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
    final result = await showDialog<Object>(
      context: context,
      builder: (_) =>
          BranchDialog(gateway: widget.gateway, repository: widget.repository),
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

  Future<void> _openRemotes(BuildContext context) async {
    final result = await showDialog<Object?>(
      context: context,
      builder: (_) =>
          RemoteDialog(gateway: widget.gateway, repository: widget.repository),
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
      builder: (_) =>
          PushDialog(gateway: widget.gateway, repository: widget.repository),
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

  Future<void> _openShelves(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => ShelfDialog(
        gateway: widget.gateway,
        repository: widget.repository,
        initialPaths: [?_activeController.state.selectedPath],
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

  Future<void> _openHistoryRollback(BuildContext context) async {
    final result = await showDialog<GitHistoryRollbackResult>(
      context: context,
      builder: (_) =>
          ResetDialog(gateway: widget.gateway, repository: widget.repository),
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

    final lines = scrollable
        ? ListView.builder(
            key: const Key('diff-lines'),
            itemCount: diff.lines.length,
            itemBuilder: (context, index) =>
                _diffLine(context, diff.lines[index], index, state),
          )
        : Column(
            key: const Key('diff-lines'),
            children: [
              for (var index = 0; index < diff.lines.length; index++)
                _diffLine(context, diff.lines[index], index, state),
            ],
          );
    return SelectionArea(key: const Key('diff-selection-area'), child: lines);
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
  push,
  updateProject,
  branches,
  history,
  objects,
  comparison,
  threeWayComparison,
  shelves,
  fileHistory,
  historyRollback,
  worktrees,
  ignoreMetadata,
  submodules,
  refresh,
}
