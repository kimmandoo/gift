import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gift/src/backend/domain.dart';
import 'package:gift/src/backend/error.dart';
import 'package:gift/src/backend/git_gateway.dart';
import 'package:gift/src/backend/hosting.dart';

/// Shows provider links without making hosting authentication a prerequisite
/// for any local Git operation.
class HostingDialog extends StatefulWidget {
  const HostingDialog({
    super.key,
    required this.gateway,
    required this.repository,
    this.initialRemote = 'origin',
    this.initialCommitOid = '',
    this.initialPath = '',
    this.initialLineStart,
    this.initialLineEnd,
    this.openUrl,
    this.copyUrl,
  });

  final GitGateway gateway;
  final RepositoryOpened repository;
  final String initialRemote;
  final String initialCommitOid;
  final String initialPath;
  final int? initialLineStart;
  final int? initialLineEnd;
  final Future<bool> Function(String url)? openUrl;
  final Future<void> Function(String url)? copyUrl;

  @override
  State<HostingDialog> createState() => _HostingDialogState();
}

class _HostingDialogState extends State<HostingDialog> {
  late final TextEditingController _remoteController;
  late final TextEditingController _commitController;
  late final TextEditingController _pathController;
  late final TextEditingController _lineStartController;
  late final TextEditingController _lineEndController;
  GitHostingSnapshot? _snapshot;
  GitHostingReviewCapability? _review;
  GitHostingLinks? _links;
  GitError? _error;
  String? _message;
  var _isLoading = true;
  var _isBusy = false;

  @override
  void initState() {
    super.initState();
    _remoteController = TextEditingController(text: widget.initialRemote);
    _commitController = TextEditingController(text: widget.initialCommitOid);
    _pathController = TextEditingController(text: widget.initialPath);
    _lineStartController = TextEditingController(
      text: widget.initialLineStart?.toString() ?? '',
    );
    _lineEndController = TextEditingController(
      text: widget.initialLineEnd?.toString() ?? '',
    );
    unawaited(_load());
  }

  @override
  void dispose() {
    _remoteController.dispose();
    _commitController.dispose();
    _pathController.dispose();
    _lineStartController.dispose();
    _lineEndController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 560;
    final dialogWidth = (size.width - (compact ? 24 : 64)).clamp(240.0, 760.0);
    final dialogHeight = (size.height - (compact ? 120 : 40)).clamp(
      240.0,
      700.0,
    );
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 32,
        vertical: 20,
      ),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(child: Text('Hosting links')),
                  if (_isBusy || _isLoading)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView(
                  key: const Key('hosting-scroll'),
                  padding: EdgeInsets.zero,
                  children: [
                    if (_error case final error?) _errorBanner(context, error),
                    if (_message case final message?)
                      _messageBanner(context, message),
                    _hostingStatus(context),
                    const SizedBox(height: 10),
                    _linkForm(context),
                    const SizedBox(height: 12),
                    _linkResults(context),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    key: const Key('refresh-hosting'),
                    onPressed: _isBusy ? null : _load,
                    child: const Text('Refresh'),
                  ),
                  TextButton(
                    key: const Key('close-hosting-dialog'),
                    onPressed: _isBusy
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorBanner(BuildContext context, GitError error) => Container(
    key: const Key('hosting-error'),
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(8),
    color: Theme.of(context).colorScheme.errorContainer,
    child: Text(error.userMessage),
  );

  Widget _messageBanner(BuildContext context, String message) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      message,
      key: const Key('hosting-message'),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: Theme.of(context).colorScheme.primary),
    ),
  );

  Widget _hostingStatus(BuildContext context) {
    final snapshot = _snapshot;
    if (snapshot == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text('Checking the selected remote…'),
        ),
      );
    }
    final repository = snapshot.repository;
    if (repository == null) {
      return Card(
        key: const Key('hosting-unavailable'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            snapshot.reason ??
                'Hosting links are unavailable; local Git remains available.',
          ),
        ),
      );
    }
    final provider = repository.provider == GitHostingProvider.github
        ? 'GitHub'
        : 'GitLab';
    return Card(
      key: const Key('hosting-available'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$provider · ${repository.displayName}'),
            const SizedBox(height: 3),
            Text(
              snapshot.sanitizedRemoteUrl ?? repository.webBase,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('hosting-review-handoff'),
              onPressed: _isBusy ? null : _showReviewCapability,
              icon: const Icon(Icons.rate_review_outlined, size: 18),
              label: const Text('Review handoff (optional)'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _linkForm(BuildContext context) => Card(
    key: const Key('hosting-link-form'),
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('hosting-remote'),
            controller: _remoteController,
            enabled: !_isBusy,
            decoration: const InputDecoration(
              labelText: 'Remote',
              hintText: 'origin',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('hosting-commit'),
            controller: _commitController,
            enabled: !_isBusy,
            decoration: const InputDecoration(
              labelText: 'Commit ID',
              hintText: 'Full or abbreviated hexadecimal ID',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('hosting-path'),
            controller: _pathController,
            enabled: !_isBusy,
            decoration: const InputDecoration(
              labelText: 'Repository-relative file (optional)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth - 8) / 2;
              return Row(
                children: [
                  SizedBox(
                    width: width,
                    child: TextField(
                      key: const Key('hosting-line-start'),
                      controller: _lineStartController,
                      enabled: !_isBusy,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Line from',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: width,
                    child: TextField(
                      key: const Key('hosting-line-end'),
                      controller: _lineEndController,
                      enabled: !_isBusy,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Line to',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              key: const Key('build-hosting-links'),
              onPressed: _isBusy ? null : _buildLinks,
              icon: const Icon(Icons.link, size: 18),
              label: const Text('Build links'),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _linkResults(BuildContext context) {
    final links = _links?.links ?? const <GitHostingLink>[];
    if (links.isEmpty) {
      return const Text(
        'Enter a commit ID to generate commit, file, and blame links.',
        key: Key('hosting-empty'),
      );
    }
    return Column(
      key: const Key('hosting-link-results'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Generated links'),
        const SizedBox(height: 6),
        for (final link in links) _linkCard(context, link),
      ],
    );
  }

  Widget _linkCard(BuildContext context, GitHostingLink link) => Card(
    key: Key('hosting-link-${link.kind.name}'),
    margin: const EdgeInsets.only(bottom: 8),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(link.label, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 3),
          SelectableText(link.url, key: Key('hosting-url-${link.kind.name}')),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: Key('copy-hosting-${link.kind.name}'),
                onPressed: _isBusy ? null : () => _copy(link),
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy'),
              ),
              OutlinedButton.icon(
                key: Key('open-hosting-${link.kind.name}'),
                onPressed: _isBusy ? null : () => _open(link),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Open'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _message = null;
      _links = null;
    });
    try {
      final remote = _remoteController.text.trim();
      final snapshot = await widget.gateway.getHostingRepository(
        widget.repository.repositoryId,
        remote: remote.isEmpty ? 'origin' : remote,
      );
      final review = await widget.gateway.getHostingReviewCapability(
        widget.repository.repositoryId,
        remote: remote.isEmpty ? 'origin' : remote,
      );
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _review = review;
        _isLoading = false;
      });
    } on GitError catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = GitError(
          category: GitErrorCategory.internal,
          userMessage: 'Hosting information could not be loaded.',
          diagnostic: '$error',
          retryable: true,
        );
        _isLoading = false;
      });
    }
  }

  Future<void> _buildLinks() async {
    setState(() {
      _isBusy = true;
      _error = null;
      _message = null;
    });
    try {
      final commit = _commitController.text.trim();
      final path = _pathController.text.trim();
      final lineStart = _parseLine(_lineStartController.text);
      final lineEnd = _parseLine(_lineEndController.text);
      final links = await widget.gateway.getHostingLinks(
        widget.repository.repositoryId,
        commit,
        remote: _remoteController.text.trim().isEmpty
            ? 'origin'
            : _remoteController.text.trim(),
        path: path.isEmpty ? null : path,
        lineStart: lineStart,
        lineEnd: lineEnd,
      );
      if (!mounted) return;
      setState(() {
        _links = links;
        _isBusy = false;
        if (links.links.isEmpty) {
          _message =
              'No supported host was found. Local Git remains available.';
        }
      });
    } on GitError catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _isBusy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = GitError(
          category: GitErrorCategory.internal,
          userMessage: 'Hosted links could not be generated.',
          diagnostic: '$error',
          retryable: false,
        );
        _isBusy = false;
      });
    }
  }

  Future<void> _copy(GitHostingLink link) async {
    final copy = widget.copyUrl;
    if (copy != null) {
      await copy(link.url);
    } else {
      await Clipboard.setData(ClipboardData(text: link.url));
    }
    if (!mounted) return;
    setState(() => _message = '${link.label} link copied.');
  }

  Future<void> _open(GitHostingLink link) async {
    setState(() => _isBusy = true);
    try {
      final opened = await (widget.openUrl ?? openHostingUrl)(link.url);
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _message = opened
            ? '${link.label} opened in the browser.'
            : 'The browser could not be opened. Copy the link instead.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _message = 'The browser could not be opened. Copy the link instead.';
      });
    }
  }

  void _showReviewCapability() {
    final review = _review;
    if (review == null) return;
    setState(
      () => _message = review.isSupported
          ? 'Review handoff is ready for this provider.'
          : review.reason,
    );
  }
}

int? _parseLine(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  return int.tryParse(trimmed);
}

Future<bool> openHostingUrl(String url) async {
  final (program, args) = switch (Platform.operatingSystem) {
    'windows' => ('rundll32.exe', ['url.dll,FileProtocolHandler', url]),
    'macos' => ('open', [url]),
    _ => ('xdg-open', [url]),
  };
  await Process.start(program, args);
  return true;
}
