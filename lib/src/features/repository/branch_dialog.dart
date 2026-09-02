import 'package:gitflu/src/backend/branch.dart';
import 'package:gitflu/src/backend/domain.dart';
import 'package:gitflu/src/backend/error.dart';
import 'package:gitflu/src/backend/git_gateway.dart';
import 'package:flutter/material.dart';

/// A small branch popup that keeps branch work separate from the Changes list.
class BranchDialog extends StatefulWidget {
  const BranchDialog({
    super.key,
    required this.gateway,
    required this.repository,
  });

  final GitGateway gateway;
  final RepositoryOpened repository;

  @override
  State<BranchDialog> createState() => _BranchDialogState();
}

class _BranchDialogState extends State<BranchDialog> {
  final _nameController = TextEditingController();
  List<GitBranch>? _branches;
  GitError? _error;
  var _isLoading = true;
  var _isMutating = false;

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.sizeOf(context).width - 64).clamp(240.0, 380.0);
    return AlertDialog(
      title: const Text('Branches'),
      content: SizedBox(
        width: width,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('new-branch-name'),
                    controller: _nameController,
                    enabled: !_isMutating,
                    decoration: const InputDecoration(
                      labelText: 'New branch name',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _createBranch(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  key: const Key('create-branch'),
                  tooltip: 'Create branch',
                  onPressed: _isMutating || _nameController.text.trim().isEmpty
                      ? null
                      : _createBranch,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_isLoading) const LinearProgressIndicator(),
            if (_error case final error?) ...[
              Text(error.userMessage, key: const Key('branch-error')),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _isMutating ? null : _loadBranches,
                child: const Text('Retry'),
              ),
            ],
            Expanded(child: _branchList(context)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isMutating ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _branchList(BuildContext context) {
    final branches = _branches;
    if (_isLoading && branches == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (branches != null && branches.isEmpty) {
      return const Center(child: Text('No local branches yet.'));
    }
    if (branches == null) return const SizedBox.shrink();
    return ListView.builder(
      itemCount: branches.length,
      itemBuilder: (context, index) {
        final branch = branches[index];
        return ListTile(
          key: ValueKey('branch:${branch.name}'),
          leading: Icon(
            branch.isCurrent ? Icons.radio_button_checked : Icons.call_split,
          ),
          title: Text(branch.name),
          subtitle: Text(
            branch.isCurrent
                ? 'Current branch'
                : branch.hasUpstream
                ? 'Tracks ${branch.upstream}'
                : 'Local branch',
          ),
          trailing: branch.isCurrent
              ? const Text('HEAD')
              : const Icon(Icons.arrow_forward),
          onTap: branch.isCurrent || _isMutating
              ? null
              : () => _switchBranch(branch.name),
        );
      },
    );
  }

  Future<void> _loadBranches() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final branches = await widget.gateway.getBranches(
        widget.repository.repositoryId,
      );
      if (!mounted) return;
      setState(() {
        _branches = branches;
        _isLoading = false;
      });
    } on GitError catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _isLoading = false;
      });
    }
  }

  Future<void> _createBranch() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _isMutating) return;
    await _runAction(
      () => widget.gateway.createBranch(widget.repository.repositoryId, name),
    );
  }

  Future<void> _switchBranch(String name) async {
    if (_isMutating) return;
    await _runAction(
      () => widget.gateway.switchBranch(widget.repository.repositoryId, name),
    );
  }

  Future<void> _runAction(
    Future<GitBranchActionResult> Function() action,
  ) async {
    setState(() {
      _isMutating = true;
      _error = null;
    });
    try {
      final result = await action();
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } on GitError catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _isMutating = false);
    }
  }
}
