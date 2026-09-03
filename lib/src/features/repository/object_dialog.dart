import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/error.dart';
import 'package:gift/src/backend/executor.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:gift/src/backend/objects.dart';
import 'package:gift/src/backend/remote.dart';

/// Focused object-management workflows for stashes, tags, remotes, and
/// upstream tracking. Every destructive action shows the backend preview
/// details before consuming its one-shot confirmation token.
class ObjectDialog extends StatefulWidget {
  const ObjectDialog({
    super.key,
    required this.gateway,
    required this.repository,
  });

  final GitGateway gateway;
  final RepositoryOpened repository;

  @override
  State<ObjectDialog> createState() => _ObjectDialogState();
}

class _ObjectDialogState extends State<ObjectDialog> {
  List<GitStashEntry>? _stashes;
  List<GitTag>? _tags;
  List<GitRemote>? _remotes;
  GitUpstreamSnapshot? _upstream;
  GitError? _error;
  var _loading = true;
  var _busy = false;
  final _stashMessage = TextEditingController();
  final _tagName = TextEditingController();
  final _tagTarget = TextEditingController();
  final _tagMessage = TextEditingController();
  final _remoteName = TextEditingController();
  final _remoteUrl = TextEditingController();
  var _includeUntracked = false;
  var _annotated = false;
  String? _selectedRemote;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _stashMessage.dispose();
    _tagName.dispose();
    _tagTarget.dispose();
    _tagMessage.dispose();
    _remoteName.dispose();
    _remoteUrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 560;
    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 32,
        vertical: 20,
      ),
      title: Row(
        children: [
          const Expanded(child: Text('Git objects')),
          if (_busy)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
      content: SizedBox(
        width: (size.width - (compact ? 24 : 64)).clamp(280.0, 760.0),
        height: (size.height - 150).clamp(280.0, 560.0),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : DefaultTabController(
                length: 4,
                child: Column(
                  children: [
                    if (_error case final error?) _errorBanner(error),
                    const TabBar(
                      tabs: [
                        Tab(text: 'Stashes'),
                        Tab(text: 'Tags'),
                        Tab(text: 'Remotes'),
                        Tab(text: 'Upstream'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _stashTab(context),
                          _tagTab(context),
                          _remoteTab(context),
                          _upstreamTab(context),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          key: const Key('close-object-dialog'),
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _errorBanner(GitError error) {
    return Container(
      key: const Key('object-error'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      color: Theme.of(context).colorScheme.errorContainer,
      child: Text(error.userMessage),
    );
  }

  Widget _stashTab(BuildContext context) {
    final stashes = _stashes ?? const <GitStashEntry>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('stash-message'),
                controller: _stashMessage,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'Stash message',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const Key('create-stash'),
              onPressed: _busy ? null : _createStash,
              child: const Text('Stash changes'),
            ),
          ],
        ),
        CheckboxListTile(
          key: const Key('stash-include-untracked'),
          value: _includeUntracked,
          onChanged: _busy
              ? null
              : (value) => setState(() => _includeUntracked = value ?? false),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('Include untracked files'),
        ),
        const Divider(),
        Expanded(
          child: stashes.isEmpty
              ? const Center(child: Text('No stashes found.'))
              : ListView.builder(
                  key: const Key('stash-list'),
                  itemCount: stashes.length,
                  itemBuilder: (context, index) => _stashCard(stashes[index]),
                ),
        ),
      ],
    );
  }

  Widget _stashCard(GitStashEntry stash) {
    return Card(
      key: ValueKey('stash:${stash.oid}'),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(stash.subject, maxLines: 2, overflow: TextOverflow.ellipsis),
            Text(
              '${stash.selector} · ${stash.oid.substring(0, 8)}'
              '${stash.branch == null ? '' : ' · ${stash.branch}'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                OutlinedButton(
                  key: ValueKey('apply-stash:${stash.oid}'),
                  onPressed: _busy ? null : () => _applyStash(stash),
                  child: const Text('Apply'),
                ),
                OutlinedButton(
                  key: ValueKey('pop-stash:${stash.oid}'),
                  onPressed: _busy ? null : () => _popStash(stash),
                  child: const Text('Pop'),
                ),
                OutlinedButton(
                  key: ValueKey('branch-stash:${stash.oid}'),
                  onPressed: _busy ? null : () => _branchFromStash(stash),
                  child: const Text('Branch'),
                ),
                TextButton(
                  key: ValueKey('drop-stash:${stash.oid}'),
                  onPressed: _busy ? null : () => _dropStash(stash),
                  child: const Text('Drop'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tagTab(BuildContext context) {
    final tags = _tags ?? const <GitTag>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 150,
              child: TextField(
                key: const Key('tag-name'),
                controller: _tagName,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'Tag name',
                  isDense: true,
                ),
              ),
            ),
            SizedBox(
              width: 150,
              child: TextField(
                key: const Key('tag-target'),
                controller: _tagTarget,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'Target (default HEAD)',
                  isDense: true,
                ),
              ),
            ),
            FilledButton(
              key: const Key('create-tag'),
              onPressed: _busy ? null : _createTag,
              child: const Text('Create'),
            ),
          ],
        ),
        CheckboxListTile(
          key: const Key('tag-annotated'),
          value: _annotated,
          onChanged: _busy
              ? null
              : (value) => setState(() => _annotated = value ?? false),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('Annotated tag'),
        ),
        if (_annotated)
          TextField(
            key: const Key('tag-message'),
            controller: _tagMessage,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'Annotation message',
              isDense: true,
            ),
          ),
        const Divider(),
        Expanded(
          child: tags.isEmpty
              ? const Center(child: Text('No tags found.'))
              : ListView.builder(
                  key: const Key('tag-list'),
                  itemCount: tags.length,
                  itemBuilder: (context, index) => _tagCard(tags[index]),
                ),
        ),
      ],
    );
  }

  Widget _tagCard(GitTag tag) {
    return Card(
      key: ValueKey('tag:${tag.name}'),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tag.name, style: Theme.of(context).textTheme.titleMedium),
            Text('${tag.kind.name} · ${tag.targetOid.substring(0, 8)}'),
            if (tag.subject case final subject?)
              Text(subject, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              children: [
                OutlinedButton(
                  key: ValueKey('inspect-tag:${tag.name}'),
                  onPressed: _busy ? null : () => _inspectTag(tag),
                  child: const Text('Inspect'),
                ),
                OutlinedButton(
                  key: ValueKey('push-tag:${tag.name}'),
                  onPressed: _busy ? null : () => _pushTag(tag),
                  child: const Text('Push tag'),
                ),
                TextButton(
                  key: ValueKey('delete-tag:${tag.name}'),
                  onPressed: _busy ? null : () => _deleteTag(tag),
                  child: const Text('Delete'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _remoteTab(BuildContext context) {
    final remotes = _remotes ?? const <GitRemote>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SizedBox(
              width: 130,
              child: TextField(
                key: const Key('remote-name'),
                controller: _remoteName,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  isDense: true,
                ),
              ),
            ),
            SizedBox(
              width: 220,
              child: TextField(
                key: const Key('remote-url'),
                controller: _remoteUrl,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'URL',
                  isDense: true,
                ),
              ),
            ),
            FilledButton(
              key: const Key('add-remote'),
              onPressed: _busy ? null : _addRemote,
              child: const Text('Add'),
            ),
          ],
        ),
        const Divider(),
        Expanded(
          child: remotes.isEmpty
              ? const Center(child: Text('No remotes are configured.'))
              : ListView.builder(
                  key: const Key('remote-list'),
                  itemCount: remotes.length,
                  itemBuilder: (context, index) => _remoteCard(remotes[index]),
                ),
        ),
      ],
    );
  }

  Widget _remoteCard(GitRemote remote) {
    return Card(
      key: ValueKey('managed-remote:${remote.name}'),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(remote.name, style: Theme.of(context).textTheme.titleMedium),
            if (remote.fetchUrl case final url?)
              Text(
                'fetch: ${redactRemote(url)}',
                overflow: TextOverflow.ellipsis,
              ),
            if (remote.pushUrl case final url?)
              Text(
                'push: ${redactRemote(url)}',
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              children: [
                OutlinedButton(
                  key: ValueKey('rename-remote:${remote.name}'),
                  onPressed: _busy ? null : () => _renameRemote(remote),
                  child: const Text('Rename'),
                ),
                OutlinedButton(
                  key: ValueKey('edit-remote:${remote.name}'),
                  onPressed: _busy ? null : () => _editRemote(remote),
                  child: const Text('Edit URL'),
                ),
                OutlinedButton(
                  key: ValueKey('prune-remote:${remote.name}'),
                  onPressed: _busy ? null : () => _pruneRemote(remote),
                  child: const Text('Prune'),
                ),
                TextButton(
                  key: ValueKey('remove-remote:${remote.name}'),
                  onPressed: _busy ? null : () => _removeRemote(remote),
                  child: const Text('Remove'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _upstreamTab(BuildContext context) {
    final upstream = _upstream;
    final remotes = _remotes ?? const <GitRemote>[];
    return ListView(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Branch: ${upstream?.branch ?? 'Detached HEAD'}'),
                Text(
                  upstream?.hasUpstream == true
                      ? 'Upstream: ${upstream!.remote}/${upstream.remoteBranch}'
                      : 'No upstream configured.',
                ),
                Text(
                  'Ahead ${upstream?.ahead ?? 0} · behind ${upstream?.behind ?? 0}',
                ),
              ],
            ),
          ),
        ),
        if (remotes.isEmpty)
          const ListTile(title: Text('Add a remote before setting upstream.'))
        else
          _upstreamControls(remotes),
      ],
    );
  }

  Widget _upstreamControls(List<GitRemote> remotes) {
    final selected =
        _selectedRemote != null &&
            remotes.any((remote) => remote.name == _selectedRemote)
        ? _selectedRemote
        : remotes.first.name;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: const Key('upstream-remote'),
          initialValue: selected,
          decoration: const InputDecoration(labelText: 'Remote'),
          items: remotes
              .map(
                (remote) => DropdownMenuItem(
                  value: remote.name,
                  child: Text(remote.name),
                ),
              )
              .toList(),
          onChanged: _busy
              ? null
              : (value) => setState(() => _selectedRemote = value),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              key: const Key('publish-branch'),
              onPressed: _busy ? null : () => _publishBranch(selected!),
              child: const Text('Publish branch'),
            ),
            OutlinedButton(
              key: const Key('set-upstream'),
              onPressed: _busy ? null : () => _setUpstream(selected!),
              child: const Text('Set upstream'),
            ),
            TextButton(
              key: const Key('unset-upstream'),
              onPressed: _busy || _upstream?.hasUpstream != true
                  ? null
                  : _unsetUpstream,
              child: const Text('Unset upstream'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Publish uses git push --set-upstream and updates ahead/behind after success.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final stashes = await widget.gateway.getStashes(
        widget.repository.repositoryId,
      );
      final tags = await widget.gateway.getTags(widget.repository.repositoryId);
      final remotes = await widget.gateway.getRemotes(
        widget.repository.repositoryId,
      );
      final upstream = await widget.gateway.getUpstream(
        widget.repository.repositoryId,
      );
      if (!mounted) return;
      setState(() {
        _stashes = stashes.entries;
        _tags = tags.tags;
        _remotes = remotes;
        _upstream = upstream;
        _selectedRemote =
            upstream.remote != null &&
                remotes.any((remote) => remote.name == upstream.remote)
            ? upstream.remote
            : remotes.firstOrNull?.name;
        _loading = false;
      });
    } on GitError catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _stashes ??= const [];
        _tags ??= const [];
        _remotes ??= const [];
        _loading = false;
      });
    }
  }

  Future<void> _refreshObjects() async {
    await _load();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      await _refreshObjects();
    } on GitError catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createStash() => _run(() async {
    await widget.gateway.createStash(
      widget.repository.repositoryId,
      message: _stashMessage.text.trim(),
      includeUntracked: _includeUntracked,
    );
    _stashMessage.clear();
  });

  Future<void> _applyStash(GitStashEntry stash) => _run(() async {
    await widget.gateway.applyStash(
      widget.repository.repositoryId,
      stash.oid,
      fingerprint: (await widget.gateway.getStashes(
        widget.repository.repositoryId,
      )).fingerprint,
    );
  });

  Future<void> _popStash(GitStashEntry stash) => _run(() async {
    await widget.gateway.popStash(
      widget.repository.repositoryId,
      stash.oid,
      fingerprint: (await widget.gateway.getStashes(
        widget.repository.repositoryId,
      )).fingerprint,
    );
  });

  Future<void> _dropStash(GitStashEntry stash) async {
    final preview = await _preview(
      () => widget.gateway.previewStashDrop(
        widget.repository.repositoryId,
        stash.oid,
      ),
    );
    if (preview == null || !await _confirm(preview)) return;
    await _run(
      () => widget.gateway.dropStash(widget.repository.repositoryId, preview),
    );
  }

  Future<void> _branchFromStash(GitStashEntry stash) async {
    final branch = await _ask('Create branch from stash', 'Branch name');
    if (branch == null || branch.trim().isEmpty) return;
    final snapshot = await widget.gateway.getStashes(
      widget.repository.repositoryId,
    );
    await _run(
      () => widget.gateway.branchFromStash(
        widget.repository.repositoryId,
        branch.trim(),
        stash.oid,
        fingerprint: snapshot.fingerprint,
      ),
    );
  }

  Future<void> _createTag() => _run(() async {
    await widget.gateway.createTag(
      widget.repository.repositoryId,
      _tagName.text.trim(),
      target: _tagTarget.text.trim().isEmpty ? null : _tagTarget.text.trim(),
      annotated: _annotated,
      message: _tagMessage.text,
    );
    _tagName.clear();
    _tagTarget.clear();
    _tagMessage.clear();
  });

  Future<void> _inspectTag(GitTag tag) async {
    try {
      final inspected = await widget.gateway.getTag(
        widget.repository.repositoryId,
        tag.name,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(inspected.name),
          content: SelectableText(
            '${inspected.kind.name}\nTarget: ${inspected.targetOid}\n'
            '${inspected.tagger == null ? '' : 'Tagger: ${inspected.tagger}\n'}'
            '${inspected.message ?? inspected.subject ?? ''}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } on GitError catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _deleteTag(GitTag tag) async {
    final preview = await _preview(
      () => widget.gateway.previewTagDelete(
        widget.repository.repositoryId,
        tag.name,
      ),
    );
    if (preview == null || !await _confirm(preview)) return;
    await _run(
      () => widget.gateway.deleteTag(widget.repository.repositoryId, preview),
    );
  }

  Future<void> _pushTag(GitTag tag) async {
    final remote = await _selectRemote();
    if (remote == null) return;
    await _run(
      () => widget.gateway.pushTag(
        widget.repository.repositoryId,
        remote,
        tag.name,
      ),
    );
  }

  Future<void> _addRemote() => _run(() async {
    await widget.gateway.addRemote(
      widget.repository.repositoryId,
      _remoteName.text.trim(),
      _remoteUrl.text.trim(),
    );
    _remoteName.clear();
    _remoteUrl.clear();
  });

  Future<void> _renameRemote(GitRemote remote) async {
    final name = await _ask(
      'Rename ${remote.name}',
      'New remote name',
      initial: remote.name,
    );
    if (name == null || name.trim().isEmpty) return;
    await _run(
      () => widget.gateway.renameRemote(
        widget.repository.repositoryId,
        remote.name,
        name.trim(),
      ),
    );
  }

  Future<void> _editRemote(GitRemote remote) async {
    final url = await _ask(
      'Edit ${remote.name} URL',
      'Fetch URL',
      initial: remote.fetchUrl ?? '',
    );
    if (url == null || url.trim().isEmpty) return;
    await _run(
      () => widget.gateway.setRemoteUrl(
        widget.repository.repositoryId,
        remote.name,
        url.trim(),
      ),
    );
  }

  Future<void> _removeRemote(GitRemote remote) async {
    final preview = await _preview(
      () => widget.gateway.previewRemoteRemove(
        widget.repository.repositoryId,
        remote.name,
      ),
    );
    if (preview == null || !await _confirm(preview)) return;
    await _run(
      () =>
          widget.gateway.removeRemote(widget.repository.repositoryId, preview),
    );
  }

  Future<void> _pruneRemote(GitRemote remote) async {
    final preview = await _preview(
      () => widget.gateway.previewRemotePrune(
        widget.repository.repositoryId,
        remote.name,
      ),
    );
    if (preview == null || !await _confirm(preview)) return;
    await _run(
      () => widget.gateway.pruneRemote(widget.repository.repositoryId, preview),
    );
  }

  Future<void> _setUpstream(String remote) => _run(
    () => widget.gateway.setUpstream(widget.repository.repositoryId, remote),
  );

  Future<void> _unsetUpstream() =>
      _run(() => widget.gateway.unsetUpstream(widget.repository.repositoryId));

  Future<void> _publishBranch(String remote) => _run(
    () => widget.gateway.publishBranch(widget.repository.repositoryId, remote),
  );

  Future<GitObjectPreview?> _preview(
    Future<GitObjectPreview> Function() action,
  ) async {
    try {
      return await action();
    } on GitError catch (error) {
      if (mounted) setState(() => _error = error);
      return null;
    }
  }

  Future<bool> _confirm(GitObjectPreview preview) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_previewTitle(preview.action)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(preview.objectName),
              if (preview.objectId case final objectId?)
                SelectableText(objectId),
              ...preview.details.map(Text.new),
              const SizedBox(height: 8),
              const Text(
                'This confirmation expires when the repository object changes.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<String?> _ask(
    String title,
    String label, {
    String initial = '',
  }) async {
    final controller = TextEditingController(text: initial);
    try {
      return await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: TextField(
            autofocus: true,
            controller: controller,
            decoration: InputDecoration(labelText: label),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<String?> _selectRemote() async {
    final remotes = _remotes ?? const <GitRemote>[];
    if (remotes.isEmpty) {
      if (mounted) {
        setState(
          () => _error = const GitError(
            category: GitErrorCategory.objectNotFound,
            userMessage: 'Add a remote before pushing a tag.',
            diagnostic: 'tag push requested without a configured remote',
            retryable: false,
          ),
        );
      }
      return null;
    }
    if (remotes.length == 1) return remotes.single.name;
    return showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Push tag to remote'),
        children: remotes
            .map(
              (remote) => SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(remote.name),
                child: Text(remote.name),
              ),
            )
            .toList(),
      ),
    );
  }
}

String _previewTitle(GitObjectPreviewAction action) => switch (action) {
  GitObjectPreviewAction.dropStash => 'Drop stash?',
  GitObjectPreviewAction.deleteTag => 'Delete tag?',
  GitObjectPreviewAction.removeRemote => 'Remove remote?',
  GitObjectPreviewAction.pruneRemote => 'Prune remote?',
};
