import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gift/src/app/pixel_theme.dart';
import 'package:gift/src/backend/conflict.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:gift/src/features/repository/conflict_controller.dart';

/// A three-pane conflict resolver: ours, editable result, and theirs.
///
/// The base blob is shown above the panes because it explains the common
/// ancestor without taking space away from the result the user is editing.
class ConflictWorkspaceScreen extends StatefulWidget {
  const ConflictWorkspaceScreen({
    super.key,
    required this.gateway,
    required this.repository,
    this.controller,
    this.onClose,
    this.autoInitialize = true,
  });

  final GitGateway gateway;
  final RepositoryOpened repository;
  final ConflictController? controller;
  final VoidCallback? onClose;
  final bool autoInitialize;

  @override
  State<ConflictWorkspaceScreen> createState() =>
      _ConflictWorkspaceScreenState();
}

class _ConflictWorkspaceScreenState extends State<ConflictWorkspaceScreen> {
  late final ConflictController _controller;
  late final bool _ownsController;
  late final TextEditingController _resultController;
  String? _editorPath;
  var _deleteResult = false;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller =
        widget.controller ??
        ConflictController(
          gateway: widget.gateway,
          repositoryId: widget.repository.repositoryId,
        );
    _controller.addListener(_onControllerChanged);
    _resultController = TextEditingController();
    if (widget.autoInitialize) _controller.start();
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    if (_ownsController) _controller.dispose();
    _resultController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _controller.state;
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 760;
    _syncEditor(state.selectedConflict);
    return Scaffold(
      appBar: AppBar(
        leading: widget.onClose == null
            ? null
            : IconButton(
                key: const Key('close-conflict-workspace'),
                tooltip: 'Close conflict workspace',
                onPressed: widget.onClose,
                icon: const Icon(Icons.close),
              ),
        title: const Text('Conflict workspace'),
        actions: [
          IconButton(
            key: const Key('refresh-conflicts'),
            tooltip: 'Refresh conflicts',
            onPressed: state.isLoading || state.isMutating
                ? null
                : _controller.refresh,
            icon: const Icon(Icons.refresh),
          ),
          const PixelThemeToggle(),
        ],
      ),
      body: SafeArea(
        child: state.snapshot == null && state.error == null
            ? const Center(child: CircularProgressIndicator())
            : state.snapshot == null
            ? _errorState(state)
            : _workspace(context, state, compact: compact),
      ),
    );
  }

  Widget _workspace(
    BuildContext context,
    ConflictState state, {
    required bool compact,
  }) {
    final snapshot = state.snapshot!;
    final conflict = state.selectedConflict;
    if (compact) {
      return ListView(
        padding: const EdgeInsets.only(bottom: 8),
        children: [
          _operationBanner(context, state),
          if (state.error case final error?) _errorBanner(error),
          if (state.operationResult case final result?)
            _operationFeedback(result),
          _navigation(context, state),
          if (conflict == null)
            SizedBox(height: 220, child: _resolvedState(context, snapshot))
          else ...[
            _baseReference(context, conflict),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: _panes(context, state, conflict, compact: true),
            ),
          ],
          _operationActions(context, state),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _operationBanner(context, state),
        if (state.error case final error?) _errorBanner(error),
        if (state.operationResult case final result?)
          _operationFeedback(result),
        _navigation(context, state),
        if (conflict == null)
          Expanded(child: _resolvedState(context, snapshot))
        else ...[
          _baseReference(context, conflict),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: _panes(context, state, conflict, compact: false),
            ),
          ),
        ],
        _operationActions(context, state),
      ],
    );
  }

  Widget _operationBanner(BuildContext context, ConflictState state) {
    final operation = state.snapshot?.operation;
    final text = operation == null
        ? 'No merge, rebase, or cherry-pick metadata was found.'
        : '${_operationLabel(operation.operation)} in progress'
              '${operation.hasProgress ? ' · ${operation.currentStep ?? '?'} of ${operation.totalSteps ?? '?'}' : ''}';
    return Container(
      key: const Key('conflict-operation-banner'),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  Widget _navigation(BuildContext context, ConflictState state) {
    final count = state.snapshot?.conflicts.length ?? 0;
    final selected = count == 0 ? 0 : state.selectedIndex + 1;
    final path = state.selectedConflict?.path ?? 'All conflicts resolved';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Text(
            count == 0 ? path : 'Conflict $selected of $count · $path',
            key: const Key('conflict-selection-label'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                key: const Key('previous-conflict'),
                onPressed: count > 1 && !state.isMutating
                    ? _controller.selectPrevious
                    : null,
                icon: const Icon(Icons.chevron_left),
                label: const Text('Previous'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                key: const Key('next-conflict'),
                onPressed: count > 1 && !state.isMutating
                    ? _controller.selectNext
                    : null,
                icon: const Icon(Icons.chevron_right),
                label: const Text('Next'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _baseReference(BuildContext context, GitConflictEntry conflict) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: _contentCard(
        context,
        key: const Key('conflict-base-pane'),
        title: 'BASE · common ancestor',
        side: conflict.base,
        compact: true,
      ),
    );
  }

  Widget _panes(
    BuildContext context,
    ConflictState state,
    GitConflictEntry conflict, {
    required bool compact,
  }) {
    final rawPanes = [
      _contentCard(
        context,
        key: const Key('conflict-ours-pane'),
        title: 'OURS · current branch',
        side: conflict.ours,
      ),
      _resultPane(context, state, conflict),
      _contentCard(
        context,
        key: const Key('conflict-theirs-pane'),
        title: 'THEIRS · incoming change',
        side: conflict.theirs,
      ),
    ];
    final panes = compact
        ? rawPanes
              .map((pane) => SizedBox(height: 250, child: pane))
              .toList(growable: false)
        : rawPanes;
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final pane in panes) ...[pane, const SizedBox(height: 10)],
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < panes.length; index++) ...[
          Expanded(child: panes[index]),
          if (index < panes.length - 1) const SizedBox(width: 10),
        ],
      ],
    );
  }

  Widget _contentCard(
    BuildContext context, {
    required Key key,
    required String title,
    required GitConflictSide? side,
    bool compact = false,
  }) {
    final content = side?.content;
    final state = content?.state ?? GitConflictContentState.missing;
    final status = _contentStatus(state);
    return Card(
      key: key,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(compact ? 8 : 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Semantics(
              label: '$title: $status',
              child: Text('Status: $status', key: Key('$title-status')),
            ),
            if (!compact) ...[
              const Divider(),
              Expanded(child: _contentBody(context, content)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _contentBody(BuildContext context, GitConflictContent? content) {
    if (content?.isEditable != true) {
      return Align(
        alignment: Alignment.topLeft,
        child: Text(
          _contentStatus(content?.state ?? GitConflictContentState.missing),
        ),
      );
    }
    return SingleChildScrollView(
      child: SelectableText(
        content!.text!,
        key: const Key('conflict-side-text'),
      ),
    );
  }

  Widget _resultPane(
    BuildContext context,
    ConflictState state,
    GitConflictEntry conflict,
  ) {
    final content = conflict.result?.content;
    final editable = _controller.canEditResult;
    return Card(
      key: const Key('conflict-result-pane'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'RESULT · working tree',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Semantics(
              label:
                  'RESULT working tree: ${_contentStatus(content?.state ?? GitConflictContentState.missing)}',
              child: Text(
                'Status: ${_contentStatus(content?.state ?? GitConflictContentState.missing)}',
                key: const Key('conflict-result-status'),
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: editable
                  ? TextField(
                      key: const Key('conflict-result-editor'),
                      controller: _resultController,
                      enabled: !state.isMutating,
                      expands: true,
                      maxLines: null,
                      minLines: null,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Enter the resolved result',
                      ),
                    )
                  : _contentBody(context, content),
            ),
          ],
        ),
      ),
    );
  }

  Widget _operationActions(BuildContext context, ConflictState state) {
    final snapshot = state.snapshot;
    if (snapshot == null) {
      return const SizedBox(height: 4);
    }
    final conflict = state.selectedConflict;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 8,
        children: [
          if (conflict != null)
            OutlinedButton(
              key: const Key('accept-conflict-ours'),
              onPressed: state.isMutating || !_controller.canAcceptOurs
                  ? null
                  : () => unawaited(_controller.acceptOurs()),
              child: const Text('Accept ours'),
            ),
          if (conflict != null)
            OutlinedButton(
              key: const Key('accept-conflict-theirs'),
              onPressed: state.isMutating || !_controller.canAcceptTheirs
                  ? null
                  : () => unawaited(_controller.acceptTheirs()),
              child: const Text('Accept theirs'),
            ),
          if (conflict != null)
            OutlinedButton(
              key: const Key('save-conflict-result'),
              onPressed: state.isMutating || !_controller.canEditResult
                  ? null
                  : () => unawaited(
                      _controller.editResult(_resultController.text),
                    ),
              child: const Text('Save result'),
            ),
          if (conflict != null)
            Semantics(
              label: 'Resolve as deleted',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    key: const Key('conflict-delete-result'),
                    value: _deleteResult,
                    onChanged: state.isMutating
                        ? null
                        : (value) =>
                              setState(() => _deleteResult = value ?? false),
                  ),
                  const Text('Resolve as deleted'),
                ],
              ),
            ),
          if (conflict != null)
            TextButton(
              key: const Key('mark-conflict-resolved'),
              onPressed: state.isMutating
                  ? null
                  : () => unawaited(
                      _controller.markResolved(deleteResult: _deleteResult),
                    ),
              child: const Text('Mark resolved'),
            ),
          if (snapshot.operation != null) ...[
            OutlinedButton(
              key: const Key('abort-conflict-operation'),
              onPressed: state.isMutating
                  ? null
                  : () => unawaited(_controller.abortOperation()),
              child: const Text('Abort operation'),
            ),
            FilledButton(
              key: const Key('continue-conflict-operation'),
              onPressed: state.isMutating || !state.canContinue
                  ? null
                  : () => unawaited(_controller.continueOperation()),
              child: const Text('Continue operation'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _operationFeedback(GitConflictOperationResult result) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Text(result.summary, key: const Key('conflict-operation-result')),
    );
  }

  Widget _resolvedState(BuildContext context, GitConflictSnapshot snapshot) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline, size: 36),
            const SizedBox(height: 10),
            Text(
              snapshot.operation == null
                  ? 'No unresolved conflicts.'
                  : 'All paths are resolved. Continue or abort the operation.',
              textAlign: TextAlign.center,
              key: const Key('conflicts-resolved'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorState(ConflictState state) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(state.error?.userMessage ?? 'Unable to load conflicts.'),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('retry-conflicts'),
            onPressed: _controller.refresh,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _errorBanner(dynamic error) {
    return Container(
      key: const Key('conflict-error'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(error.userMessage),
    );
  }

  void _syncEditor(GitConflictEntry? conflict) {
    if (conflict?.path == _editorPath) return;
    _editorPath = conflict?.path;
    _resultController.text = conflict?.result?.content.text ?? '';
    _deleteResult = false;
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  String _operationLabel(GitConflictOperation operation) => switch (operation) {
    GitConflictOperation.merge => 'Merge',
    GitConflictOperation.rebase => 'Rebase',
    GitConflictOperation.cherryPick => 'Cherry-pick',
    GitConflictOperation.revert => 'Revert',
  };

  String _contentStatus(GitConflictContentState state) => switch (state) {
    GitConflictContentState.notLoaded => 'Not loaded',
    GitConflictContentState.available => 'Available text',
    GitConflictContentState.missing => 'Missing on this side',
    GitConflictContentState.binary => 'Binary content',
    GitConflictContentState.tooLarge => 'Too large to display',
    GitConflictContentState.unreadable => 'Unreadable content',
  };
}
