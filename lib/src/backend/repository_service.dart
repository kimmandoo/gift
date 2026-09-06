import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'domain.dart';
import 'branch.dart';
import 'commit.dart';
import 'conflict.dart';
import 'comparison.dart';
import 'discard.dart';
import 'diff.dart';
import 'error.dart';
import 'executor.dart';
import 'repository_paths.dart';
import 'history.dart';
import 'history_batch.dart';
import 'interactive_rebase.dart';
import 'remote.dart';
import 'remote_branch.dart';
import 'reset.dart';
import 'status.dart';
import 'objects.dart';
import 'shelf.dart';
import 'file_history.dart';
import 'push.dart';
import 'worktree.dart';
import 'ignore.dart';
import 'submodule.dart';
import 'recovery.dart';
import 'setup.dart';
import 'hosting.dart';
import 'credentials.dart';
import 'lfs.dart';
import 'signing.dart';

/// In-memory registry for repository roots and session-local opaque IDs.
///
/// The registry deliberately never accepts a root supplied back by the UI:
/// later operations will resolve an ID through this object first.
class AppState {
  AppState({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final Map<RepositoryId, _RepositoryRecord> _repositories = {};
  final Map<RepositoryId, _MutationQueue> _mutationQueues = {};
  final Map<String, _DiscardPreviewRecord> _discardPreviews = {};
  final Map<String, _BranchPreviewRecord> _branchPreviews = {};
  final Map<String, _ObjectPreviewRecord> _objectPreviews = {};
  final Map<String, _HistoryBatchPreviewRecord> _batchPreviews = {};
  final Map<String, _HistoryBatchContinuationRecord> _batchContinuations = {};
  final Map<String, _HistoryRollbackPreviewRecord> _rollbackPreviews = {};
  final Map<String, _InteractiveRebasePreviewRecord>
  _interactiveRebasePreviews = {};
  final Map<String, _UpdatePreviewRecord> _updatePreviews = {};
  final Map<String, _PushPreviewRecord> _pushPreviews = {};
  final Map<String, _WorktreePreviewRecord> _worktreePreviews = {};
  final Map<String, _RecoveryPreviewRecord> _recoveryPreviews = {};
  final Map<String, _RemoteBranchDeletePreviewRecord>
  _remoteBranchDeletePreviews = {};
  final DateTime Function() _now;

  static const discardPreviewLifetime = Duration(minutes: 2);
  static const branchPreviewLifetime = Duration(minutes: 2);
  static const objectPreviewLifetime = Duration(minutes: 2);
  static const rollbackPreviewLifetime = Duration(minutes: 2);
  static const batchPreviewLifetime = Duration(minutes: 2);
  static const pushPreviewLifetime = Duration(minutes: 2);
  static const worktreePreviewLifetime = Duration(minutes: 2);
  static const recoveryPreviewLifetime = Duration(minutes: 2);

  RepositoryOpened register(String root) {
    final repositoryId = RepositoryId(value: _newRepositoryId());
    _repositories[repositoryId] = _RepositoryRecord(root);
    return RepositoryOpened(repositoryId: repositoryId, root: root);
  }

  Future<RepositoryHandle> lookup(RepositoryId repositoryId) async {
    final record = _repositories[repositoryId];
    if (record == null) {
      throw const GitError(
        category: GitErrorCategory.invalidOpaqueId,
        userMessage: 'The repository handle is not valid for this session.',
        diagnostic: 'repository ID was not found in this registry',
        retryable: false,
      );
    }
    if (!Directory(record.root).existsSync()) {
      throw const GitError(
        category: GitErrorCategory.repositoryMoved,
        userMessage: 'The repository folder is no longer available.',
        diagnostic: 'registered repository root does not exist',
        retryable: true,
      );
    }
    return RepositoryHandle(root: record.root, generation: record.generation);
  }

  int updateStatusGeneration(RepositoryId repositoryId, String contentHash) {
    final record = _repositories[repositoryId];
    if (record == null) {
      throw const GitError(
        category: GitErrorCategory.invalidOpaqueId,
        userMessage: 'The repository handle is not valid for this session.',
        diagnostic: 'status generation requested for an unknown repository ID',
        retryable: false,
      );
    }
    if (record.statusHash != contentHash) {
      record.statusHash = contentHash;
      record.statusGeneration++;
    }
    return record.statusGeneration;
  }

  /// Serializes mutations for one repository while allowing different
  /// repositories to continue independently.
  Future<T> runMutation<T>(
    RepositoryId repositoryId,
    Future<T> Function() action,
  ) {
    final queue = _mutationQueues.putIfAbsent(repositoryId, _MutationQueue.new);
    return queue.run(action);
  }

  DiscardPreview issueDiscardPreview({
    required RepositoryId repositoryId,
    required String path,
    required String statusHash,
    required String diffHash,
  }) {
    _discardPreviews.removeWhere(
      (_, record) => !record.expiresAt.isAfter(_now()),
    );
    final token = _newOpaqueToken();
    final expiresAt = _now().add(discardPreviewLifetime);
    _discardPreviews[token] = _DiscardPreviewRecord(
      repositoryId: repositoryId,
      path: path,
      statusHash: statusHash,
      diffHash: diffHash,
      expiresAt: expiresAt,
    );
    return DiscardPreview(
      repositoryId: repositoryId,
      token: token,
      path: path,
      expiresAt: expiresAt,
    );
  }

  _DiscardPreviewRecord _validateDiscardPreview(
    RepositoryId repositoryId,
    DiscardPreview preview,
  ) {
    final record = _discardPreviews[preview.token];
    if (record == null ||
        record.repositoryId != repositoryId ||
        record.repositoryId != preview.repositoryId ||
        record.path != preview.path ||
        !record.expiresAt.isAfter(_now())) {
      _discardPreviews.remove(preview.token);
      throw const GitError(
        category: GitErrorCategory.staleConfirmation,
        userMessage:
            'This discard confirmation has expired or is no longer valid.',
        diagnostic: 'discard preview token was missing, changed, or expired',
        retryable: false,
      );
    }
    return record;
  }

  void consumeDiscardPreview(String token) {
    _discardPreviews.remove(token);
  }

  void cancelDiscardPreview(DiscardPreview preview) {
    final record = _discardPreviews[preview.token];
    if (record?.repositoryId == preview.repositoryId &&
        record?.path == preview.path) {
      _discardPreviews.remove(preview.token);
    }
  }

  GitBranchPreviewToken issueBranchPreview({
    required RepositoryId repositoryId,
    required GitBranchOperationRequest request,
    required String fingerprint,
  }) {
    _branchPreviews.removeWhere(
      (_, record) => !record.expiresAt.isAfter(_now()),
    );
    final token = _newOpaqueToken();
    final expiresAt = _now().add(branchPreviewLifetime);
    _branchPreviews[token] = _BranchPreviewRecord(
      repositoryId: repositoryId,
      operation: request.operation,
      source: request.source,
      target: request.target,
      force: request.force,
      fingerprint: fingerprint,
      expiresAt: expiresAt,
    );
    return GitBranchPreviewToken(value: token, expiresAt: expiresAt);
  }

  void validateBranchPreview({
    required RepositoryId repositoryId,
    required GitBranchOperationRequest request,
    required String fingerprint,
  }) {
    final token = request.confirmationToken;
    final record = token == null ? null : _branchPreviews[token];
    final matches =
        record != null &&
        record.repositoryId == repositoryId &&
        record.operation == request.operation &&
        record.source == request.source &&
        record.target == request.target &&
        record.force == request.force &&
        record.fingerprint == fingerprint &&
        record.expiresAt.isAfter(_now());
    if (!matches) {
      if (token != null) _branchPreviews.remove(token);
      throw const GitError(
        category: GitErrorCategory.staleBranchPreview,
        userMessage: 'This branch preview is stale or expired. Review the operation again.',
        diagnostic: 'branch operation token was missing, changed, expired, or bound to a different repository state',
        retryable: true,
      );
    }
  }

  void consumeBranchPreview(String token) {
    _branchPreviews.remove(token);
  }

  GitObjectPreview issueObjectPreview({
    required RepositoryId repositoryId,
    required GitObjectPreviewAction action,
    required String objectName,
    String? objectId,
    required String fingerprint,
    List<String> details = const [],
  }) {
    _objectPreviews.removeWhere(
      (_, record) => !record.expiresAt.isAfter(_now()),
    );
    final token = _newOpaqueToken();
    final expiresAt = _now().add(objectPreviewLifetime);
    _objectPreviews[token] = _ObjectPreviewRecord(
      repositoryId: repositoryId,
      action: action,
      objectName: objectName,
      objectId: objectId,
      fingerprint: fingerprint,
      expiresAt: expiresAt,
    );
    return GitObjectPreview(
      repositoryId: repositoryId,
      action: action,
      objectName: objectName,
      objectId: objectId,
      fingerprint: fingerprint,
      details: details,
      token: token,
      expiresAt: expiresAt,
    );
  }

  void validateObjectPreview({
    required RepositoryId repositoryId,
    required GitObjectPreview preview,
    required String fingerprint,
    String? objectId,
  }) {
    final record = _objectPreviews[preview.token];
    final matches =
        record != null &&
        record.repositoryId == repositoryId &&
        record.repositoryId == preview.repositoryId &&
        record.action == preview.action &&
        record.objectName == preview.objectName &&
        record.objectId == preview.objectId &&
        record.objectId == objectId &&
        record.fingerprint == fingerprint &&
        record.expiresAt.isAfter(_now());
    if (!matches) {
      _objectPreviews.remove(preview.token);
      throw const GitError(
        category: GitErrorCategory.staleObject,
        userMessage: 'This object changed. Review the action again.',
        diagnostic: 'object preview token or snapshot fingerprint was stale',
        retryable: true,
      );
    }
  }

  void consumeObjectPreview(String token) {
    _objectPreviews.remove(token);
  }

  GitBranchPreviewToken issueHistoryRollbackPreview({
    required RepositoryId repositoryId,
    required GitHistoryRollbackRequest request,
    required String fingerprint,
  }) {
    _rollbackPreviews.removeWhere(
      (_, record) => !record.expiresAt.isAfter(_now()),
    );
    final token = _newOpaqueToken();
    final expiresAt = _now().add(rollbackPreviewLifetime);
    _rollbackPreviews[token] = _HistoryRollbackPreviewRecord(
      repositoryId: repositoryId,
      requestKey: request.queryKey,
      fingerprint: fingerprint,
      expiresAt: expiresAt,
    );
    return GitBranchPreviewToken(value: token, expiresAt: expiresAt);
  }

  void validateHistoryRollbackPreview({
    required RepositoryId repositoryId,
    required GitHistoryRollbackPreview preview,
    required String fingerprint,
  }) {
    final token = preview.token;
    final record = token == null ? null : _rollbackPreviews[token];
    final matches =
        record != null &&
        record.repositoryId == repositoryId &&
        record.repositoryId == preview.repositoryId &&
        record.requestKey == preview.request.queryKey &&
        record.fingerprint == fingerprint &&
        record.expiresAt.isAfter(_now());
    if (!matches) {
      if (token != null) _rollbackPreviews.remove(token);
      throw const GitError(
        category: GitErrorCategory.staleRollbackPreview,
        userMessage: 'This history rollback preview is stale or expired. Review it again.',
        diagnostic: 'rollback preview token or repository fingerprint was missing, changed, or expired',
        retryable: true,
      );
    }
  }

  void consumeHistoryRollbackPreview(String token) {
    _rollbackPreviews.remove(token);
  }

  GitBranchPreviewToken issueHistoryBatchPreview({
    required RepositoryId repositoryId,
    required GitHistoryBatchRequest request,
    required String fingerprint,
  }) {
    _batchPreviews.removeWhere(
      (_, record) => !record.expiresAt.isAfter(_now()),
    );
    final token = _newOpaqueToken();
    final expiresAt = _now().add(batchPreviewLifetime);
    _batchPreviews[token] = _HistoryBatchPreviewRecord(
      repositoryId: repositoryId,
      requestKey: request.queryKey,
      fingerprint: fingerprint,
      expiresAt: expiresAt,
    );
    return GitBranchPreviewToken(value: token, expiresAt: expiresAt);
  }

  void validateHistoryBatchPreview({
    required RepositoryId repositoryId,
    required GitHistoryBatchPreview preview,
    required String fingerprint,
  }) {
    final token = preview.token;
    final record = token == null ? null : _batchPreviews[token];
    final matches =
        record != null &&
        record.repositoryId == repositoryId &&
        record.repositoryId == preview.repositoryId &&
        record.requestKey == preview.request.queryKey &&
        record.fingerprint == fingerprint &&
        record.expiresAt.isAfter(_now());
    if (!matches) {
      if (token != null) _batchPreviews.remove(token);
      throw const GitError(
        category: GitErrorCategory.staleRollbackPreview,
        userMessage: 'This batch preview is stale or expired. Review it again.',
        diagnostic: 'history batch preview token or repository fingerprint was missing, changed, or expired',
        retryable: true,
      );
    }
  }

  void consumeHistoryBatchPreview(String token) {
    _batchPreviews.remove(token);
  }

  String issueHistoryBatchContinuation({
    required RepositoryId repositoryId,
    required String requestKey,
    required String fingerprint,
    required List<String> completedOids,
    required List<String> skippedOids,
    required String currentOid,
    required List<String> remainingOids,
  }) {
    _batchContinuations.removeWhere(
      (_, record) => !record.expiresAt.isAfter(_now()),
    );
    final token = _newOpaqueToken();
    _batchContinuations[token] = _HistoryBatchContinuationRecord(
      repositoryId: repositoryId,
      requestKey: requestKey,
      fingerprint: fingerprint,
      completedOids: completedOids,
      skippedOids: skippedOids,
      currentOid: currentOid,
      remainingOids: remainingOids,
      expiresAt: _now().add(batchPreviewLifetime),
    );
    return token;
  }

  void validateHistoryBatchContinuation({
    required RepositoryId repositoryId,
    required GitHistoryBatchRecoveryRequest request,
    required String fingerprint,
  }) {
    final record = _batchContinuations[request.continuationToken];
    final matches =
        record != null &&
        record.repositoryId == repositoryId &&
        record.requestKey == request.queryKey &&
        record.fingerprint == fingerprint &&
        _sameStrings(record.completedOids, request.completedOids) &&
        _sameStrings(record.skippedOids, request.skippedOids) &&
        record.currentOid == request.currentOid &&
        _sameStrings(record.remainingOids, request.remainingOids) &&
        record.expiresAt.isAfter(_now());
    if (!matches) {
      _batchContinuations.remove(request.continuationToken);
      throw const GitError(
        category: GitErrorCategory.staleRollbackPreview,
        userMessage: 'This batch recovery request is stale or expired. Review the selection again.',
        diagnostic: 'history batch continuation token or repository fingerprint was missing, changed, or expired',
        retryable: true,
      );
    }
  }

  void consumeHistoryBatchContinuation(String token) {
    _batchContinuations.remove(token);
  }

  GitBranchPreviewToken issueInteractiveRebasePreview({
    required RepositoryId repositoryId,
    required GitInteractiveRebasePlan plan,
    required String fingerprint,
  }) {
    _interactiveRebasePreviews.removeWhere(
      (_, record) => !record.expiresAt.isAfter(_now()),
    );
    final token = _newOpaqueToken();
    final expiresAt = _now().add(rollbackPreviewLifetime);
    _interactiveRebasePreviews[token] = _InteractiveRebasePreviewRecord(
      repositoryId: repositoryId,
      planKey: plan.queryKey,
      fingerprint: fingerprint,
      expiresAt: expiresAt,
    );
    return GitBranchPreviewToken(value: token, expiresAt: expiresAt);
  }

  void validateInteractiveRebasePreview({
    required RepositoryId repositoryId,
    required GitInteractiveRebasePreview preview,
    required String fingerprint,
  }) {
    final token = preview.token;
    final record = token == null ? null : _interactiveRebasePreviews[token];
    final matches =
        record != null &&
        record.repositoryId == repositoryId &&
        record.repositoryId == preview.repositoryId &&
        record.planKey == preview.plan.queryKey &&
        record.fingerprint == fingerprint &&
        record.expiresAt.isAfter(_now());
    if (!matches) {
      if (token != null) _interactiveRebasePreviews.remove(token);
      throw const GitError(
        category: GitErrorCategory.staleRollbackPreview,
        userMessage:
            'This rebase preview is stale or expired. Review the plan again.',
        diagnostic: 'interactive rebase preview token or repository fingerprint was missing, changed, or expired',
        retryable: true,
      );
    }
  }

  void consumeInteractiveRebasePreview(String token) {
    _interactiveRebasePreviews.remove(token);
  }

  GitBranchPreviewToken issueUpdatePreview({
    required RepositoryId repositoryId,
    required GitUpdateProjectRequest request,
    required String fingerprint,
  }) {
    _updatePreviews.removeWhere(
      (_, record) => !record.expiresAt.isAfter(_now()),
    );
    final token = _newOpaqueToken();
    final expiresAt = _now().add(rollbackPreviewLifetime);
    _updatePreviews[token] = _UpdatePreviewRecord(
      repositoryId: repositoryId,
      requestKey: _updateRequestKey(request),
      fingerprint: fingerprint,
      expiresAt: expiresAt,
    );
    return GitBranchPreviewToken(value: token, expiresAt: expiresAt);
  }

  void validateUpdatePreview({
    required RepositoryId repositoryId,
    required GitUpdateProjectRequest request,
    required String fingerprint,
  }) {
    final token = request.confirmationToken;
    final record = token == null ? null : _updatePreviews[token];
    final matches =
        record != null &&
        record.repositoryId == repositoryId &&
        record.requestKey == _updateRequestKey(request) &&
        record.fingerprint == fingerprint &&
        record.expiresAt.isAfter(_now());
    if (!matches) {
      if (token != null) _updatePreviews.remove(token);
      throw const GitError(
        category: GitErrorCategory.staleUpdatePreview,
        userMessage:
            'This update preview is stale or expired. Review it again.',
        diagnostic: 'update preview token or repository fingerprint was missing, changed, or expired',
        retryable: true,
      );
    }
  }

  void consumeUpdatePreview(String token) => _updatePreviews.remove(token);

  GitBranchPreviewToken issuePushPreview({
    required RepositoryId repositoryId,
    required GitPushRequest request,
    required String fingerprint,
  }) {
    _pushPreviews.removeWhere((_, record) => !record.expiresAt.isAfter(_now()));
    final token = _newOpaqueToken();
    final expiresAt = _now().add(pushPreviewLifetime);
    _pushPreviews[token] = _PushPreviewRecord(
      repositoryId: repositoryId,
      requestKey: request.queryKey,
      fingerprint: fingerprint,
      expiresAt: expiresAt,
    );
    return GitBranchPreviewToken(value: token, expiresAt: expiresAt);
  }

  void validatePushPreview({
    required RepositoryId repositoryId,
    required GitPushRequest request,
    required String fingerprint,
  }) {
    final token = request.confirmationToken;
    final record = token == null ? null : _pushPreviews[token];
    final matches =
        record != null &&
        record.repositoryId == repositoryId &&
        record.requestKey == request.queryKey &&
        record.fingerprint == fingerprint &&
        record.expiresAt.isAfter(_now());
    if (!matches) {
      if (token != null) _pushPreviews.remove(token);
      throw const GitError(
        category: GitErrorCategory.stalePushPreview,
        userMessage: 'This push review is stale or expired. Review it again.',
        diagnostic: 'push preview token or repository/remote fingerprint was missing, changed, or expired',
        retryable: true,
      );
    }
  }

  void consumePushPreview(String token) => _pushPreviews.remove(token);

  GitBranchPreviewToken issueWorktreePreview({
    required RepositoryId repositoryId,
    required GitWorktreeActionRequest request,
    required String fingerprint,
  }) {
    _worktreePreviews.removeWhere(
      (_, record) => !record.expiresAt.isAfter(_now()),
    );
    final token = _newOpaqueToken();
    final expiresAt = _now().add(worktreePreviewLifetime);
    _worktreePreviews[token] = _WorktreePreviewRecord(
      repositoryId: repositoryId,
      requestKey: request.queryKey,
      fingerprint: fingerprint,
      expiresAt: expiresAt,
    );
    return GitBranchPreviewToken(value: token, expiresAt: expiresAt);
  }

  void validateWorktreePreview({
    required RepositoryId repositoryId,
    required GitWorktreeActionRequest request,
    required String fingerprint,
  }) {
    final token = request.confirmationToken;
    final record = token == null ? null : _worktreePreviews[token];
    final matches =
        record != null &&
        record.repositoryId == repositoryId &&
        record.requestKey == request.queryKey &&
        record.fingerprint == fingerprint &&
        record.expiresAt.isAfter(_now());
    if (!matches) {
      if (token != null) _worktreePreviews.remove(token);
      throw const GitError(
        category: GitErrorCategory.staleWorktreePreview,
        userMessage:
            'This worktree action is stale or expired. Review it again.',
        diagnostic: 'worktree action token or repository snapshot was missing, changed, or expired',
        retryable: true,
      );
    }
  }

  void consumeWorktreePreview(String token) => _worktreePreviews.remove(token);

  GitBranchPreviewToken issueRecoveryPreview({
    required RepositoryId repositoryId,
    required GitRecoveryBranchRequest request,
    required String fingerprint,
  }) {
    _recoveryPreviews.removeWhere(
      (_, record) => !record.expiresAt.isAfter(_now()),
    );
    final token = _newOpaqueToken();
    final expiresAt = _now().add(recoveryPreviewLifetime);
    _recoveryPreviews[token] = _RecoveryPreviewRecord(
      repositoryId: repositoryId,
      requestKey: request.queryKey,
      fingerprint: fingerprint,
      expiresAt: expiresAt,
    );
    return GitBranchPreviewToken(value: token, expiresAt: expiresAt);
  }

  void validateRecoveryPreview({
    required RepositoryId repositoryId,
    required GitRecoveryBranchRequest request,
    required String fingerprint,
    required String token,
  }) {
    final record = _recoveryPreviews[token];
    final matches =
        record != null &&
        record.repositoryId == repositoryId &&
        record.requestKey == request.queryKey &&
        record.fingerprint == fingerprint &&
        record.expiresAt.isAfter(_now());
    if (!matches) {
      _recoveryPreviews.remove(token);
      throw const GitError(
        category: GitErrorCategory.staleRollbackPreview,
        userMessage:
            'This recovery preview is stale or expired. Review it again.',
        diagnostic: 'recovery branch preview token or reflog fingerprint was missing, changed, or expired',
        retryable: true,
      );
    }
  }

  void consumeRecoveryPreview(String token) => _recoveryPreviews.remove(token);

  String _updateRequestKey(GitUpdateProjectRequest request) =>
      '${request.strategy.name}:${request.localChanges.name}';

  GitBranchPreviewToken issueRemoteBranchDeletePreview({
    required RepositoryId repositoryId,
    required String branchName,
    required String oid,
    required String fingerprint,
  }) {
    _remoteBranchDeletePreviews.removeWhere(
      (_, record) => !record.expiresAt.isAfter(_now()),
    );
    final token = _newOpaqueToken();
    final expiresAt = _now().add(objectPreviewLifetime);
    _remoteBranchDeletePreviews[token] = _RemoteBranchDeletePreviewRecord(
      repositoryId: repositoryId,
      branchName: branchName,
      oid: oid,
      fingerprint: fingerprint,
      expiresAt: expiresAt,
    );
    return GitBranchPreviewToken(value: token, expiresAt: expiresAt);
  }

  void validateRemoteBranchDeletePreview({
    required RepositoryId repositoryId,
    required GitRemoteBranchDeletePreview preview,
    required String oid,
    required String fingerprint,
  }) {
    final record = _remoteBranchDeletePreviews[preview.token];
    final matches =
        record != null &&
        record.repositoryId == repositoryId &&
        record.branchName == preview.branch.name &&
        record.oid == oid &&
        record.oid == preview.oid &&
        record.fingerprint == fingerprint &&
        record.expiresAt.isAfter(_now());
    if (!matches) {
      _remoteBranchDeletePreviews.remove(preview.token);
      throw const GitError(
        category: GitErrorCategory.staleRemoteRef,
        userMessage: 'The remote branch changed. Review its deletion again.',
        diagnostic: 'remote branch deletion preview was stale or expired',
        retryable: true,
      );
    }
  }

  void consumeRemoteBranchDeletePreview(String token) =>
      _remoteBranchDeletePreviews.remove(token);
}

class _DiscardPreviewRecord {
  const _DiscardPreviewRecord({
    required this.repositoryId,
    required this.path,
    required this.statusHash,
    required this.diffHash,
    required this.expiresAt,
  });

  final RepositoryId repositoryId;
  final String path;
  final String statusHash;
  final String diffHash;
  final DateTime expiresAt;
}

class _BranchPreviewRecord {
  const _BranchPreviewRecord({
    required this.repositoryId,
    required this.operation,
    required this.source,
    required this.target,
    required this.force,
    required this.fingerprint,
    required this.expiresAt,
  });

  final RepositoryId repositoryId;
  final GitBranchOperation operation;
  final String? source;
  final String? target;
  final bool force;
  final String fingerprint;
  final DateTime expiresAt;
}

class _ObjectPreviewRecord {
  const _ObjectPreviewRecord({
    required this.repositoryId,
    required this.action,
    required this.objectName,
    required this.objectId,
    required this.fingerprint,
    required this.expiresAt,
  });

  final RepositoryId repositoryId;
  final GitObjectPreviewAction action;
  final String objectName;
  final String? objectId;
  final String fingerprint;
  final DateTime expiresAt;
}

class _HistoryRollbackPreviewRecord {
  const _HistoryRollbackPreviewRecord({
    required this.repositoryId,
    required this.requestKey,
    required this.fingerprint,
    required this.expiresAt,
  });

  final RepositoryId repositoryId;
  final String requestKey;
  final String fingerprint;
  final DateTime expiresAt;
}

class _InteractiveRebasePreviewRecord {
  const _InteractiveRebasePreviewRecord({
    required this.repositoryId,
    required this.planKey,
    required this.fingerprint,
    required this.expiresAt,
  });

  final RepositoryId repositoryId;
  final String planKey;
  final String fingerprint;
  final DateTime expiresAt;
}

class _UpdatePreviewRecord {
  const _UpdatePreviewRecord({
    required this.repositoryId,
    required this.requestKey,
    required this.fingerprint,
    required this.expiresAt,
  });

  final RepositoryId repositoryId;
  final String requestKey;
  final String fingerprint;
  final DateTime expiresAt;
}

class _RemoteBranchDeletePreviewRecord {
  const _RemoteBranchDeletePreviewRecord({
    required this.repositoryId,
    required this.branchName,
    required this.oid,
    required this.fingerprint,
    required this.expiresAt,
  });

  final RepositoryId repositoryId;
  final String branchName;
  final String oid;
  final String fingerprint;
  final DateTime expiresAt;
}

class _PushPreviewRecord {
  const _PushPreviewRecord({
    required this.repositoryId,
    required this.requestKey,
    required this.fingerprint,
    required this.expiresAt,
  });

  final RepositoryId repositoryId;
  final String requestKey;
  final String fingerprint;
  final DateTime expiresAt;
}

class _WorktreePreviewRecord {
  const _WorktreePreviewRecord({
    required this.repositoryId,
    required this.requestKey,
    required this.fingerprint,
    required this.expiresAt,
  });

  final RepositoryId repositoryId;
  final String requestKey;
  final String fingerprint;
  final DateTime expiresAt;
}

class _RecoveryPreviewRecord {
  const _RecoveryPreviewRecord({
    required this.repositoryId,
    required this.requestKey,
    required this.fingerprint,
    required this.expiresAt,
  });

  final RepositoryId repositoryId;
  final String requestKey;
  final String fingerprint;
  final DateTime expiresAt;
}

class _MutationQueue {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() action) {
    final previous = _tail;
    final finished = Completer<void>();
    _tail = finished.future;
    return previous.then((_) => action()).whenComplete(() {
      if (!finished.isCompleted) finished.complete();
    });
  }
}

class RepositoryHandle {
  const RepositoryHandle({required this.root, required this.generation});

  final String root;
  final int generation;
}

class RepositoryService {
  RepositoryService({
    required this.gitPath,
    required this.state,
    ProcessGitRunner? runner,
    GitShelfStore? shelfStore,
    GitCredentialResolver? credentialResolver,
  }) : _runner = runner ?? const ProcessGitRunner(),
       _shelfStore = shelfStore ?? const FileGitShelfStore(),
       _credentialResolver =
           credentialResolver ?? const NoopGitCredentialResolver();

  final String gitPath;
  final ProcessGitRunner _runner;
  final GitShelfStore _shelfStore;
  final GitCredentialResolver _credentialResolver;
  final AppState state;

  Future<ProcessOutput> _runWithCredentials({
    required String cwd,
    required List<String> args,
    required GitOperationKind kind,
    required int maxBytes,
    GitCancellationToken? cancellationToken,
    Map<String, String>? environment,
    String? remoteUrl,
    String? credentialId,
  }) async {
    final auth = remoteUrl == null
        ? null
        : await _credentialResolver.resolve(remoteUrl, accountId: credentialId);
    return _runner.run(
      GitInvocation(
        program: gitPath,
        args: args,
        cwd: cwd,
        kind: kind,
        outputPolicy: OutputPolicy.capture(maxBytes: maxBytes),
        cancellationToken: cancellationToken,
        environment: {...?auth?.environment, ...?environment},
        sensitiveValues: auth?.sensitiveValues ?? const <String>[],
        cleanup: auth?.cleanup,
      ),
    );
  }

  Future<RepositoryOpened> openRepository(String path) async {
    // Step 1: resolve the user's selection before passing it to Git.
    final workingDirectory = await _canonicalizeDirectory(path);

    // Step 2: reject bare repositories because the workspace needs a
    // working tree.
    final bareOutput = await _runForRepository(workingDirectory, const [
      'rev-parse',
      '--is-bare-repository',
    ]);
    final bare = utf8.decode(bareOutput.stdout, allowMalformed: true).trim();
    switch (bare) {
      case 'true':
        throw const GitError(
          category: GitErrorCategory.unsupportedRepositoryState,
          userMessage: 'Bare repositories cannot be opened in the workspace.',
          diagnostic: 'git rev-parse --is-bare-repository returned true',
          retryable: false,
        );
      case 'false':
        break;
      default:
        throw GitError(
          category: GitErrorCategory.parseFailure,
          userMessage: 'Git returned an unrecognized repository state.',
          diagnostic: 'unexpected bare-repository result: $bare',
          retryable: false,
        );
    }

    // Step 3: ask Git for the real root so nested folders open the same
    // workspace as their parent repository.
    final rootOutput = await _runForRepository(workingDirectory, const [
      'rev-parse',
      '--show-toplevel',
    ]);
    final reportedRoot = utf8
        .decode(rootOutput.stdout, allowMalformed: true)
        .trim();
    if (reportedRoot.isEmpty) {
      throw const GitError(
        category: GitErrorCategory.parseFailure,
        userMessage: 'Git returned an empty repository root.',
        diagnostic: 'rev-parse --show-toplevel returned no path',
        retryable: false,
      );
    }
    final canonicalRoot = await _canonicalizeDirectory(
      reportedRoot,
      moved: true,
    );
    return state.register(canonicalRoot);
  }

  Future<GitRepositorySetupResult> cloneRepository(
    GitCloneRequest request, {
    GitCancellationToken? cancellationToken,
  }) async {
    final source = _validateSetupSource(request.source);
    final destination = _validateSetupAbsolutePath(
      request.destination,
      label: 'clone destination',
    );
    final directory = Directory(destination);
    if (await directory.exists()) {
      var hasEntries = false;
      await for (final _ in directory.list().take(1)) {
        hasEntries = true;
      }
      if (hasEntries) {
        throw setupInputError(
          'Choose an empty clone destination.',
          'clone destination already contained files',
        );
      }
    } else if (!await directory.parent.exists()) {
      throw setupInputError(
        'Choose a destination whose parent folder exists.',
        'clone destination parent folder did not exist',
      );
    }
    if (request.branch case final branch?) {
      _validateBranchName(branch);
    }
    final depth = request.depth;
    if (depth != null && (depth < 1 || depth > 1_000_000)) {
      throw setupInputError(
        'Choose a clone depth between 1 and 1,000,000.',
        'clone depth was outside the safe bound',
      );
    }
    final args = <String>['clone'];
    if (request.branch case final branch?) {
      args.addAll(['--branch', branch]);
    }
    if (depth case final value?) args.addAll(['--depth', '$value']);
    if (request.recursive) args.add('--recurse-submodules');
    args.addAll([source, destination]);
    await _runWithCredentials(
      cwd: directory.parent.path,
      args: args,
      kind: GitOperationKind.remote,
      maxBytes: 4 * 1024 * 1024,
      cancellationToken: cancellationToken,
      remoteUrl: source,
      credentialId: request.credentialId,
    );
    return GitRepositorySetupResult(
      repository: await openRepository(destination),
      summary: 'Cloned repository into $destination.',
    );
  }

  Future<GitCredentialTestResult> testCredential(
    String remoteUrl, {
    required String accountId,
  }) async {
    final endpoint = parseGitRemoteEndpoint(remoteUrl);
    if (endpoint == null || endpoint.transport == GitRemoteTransport.other) {
      throw credentialInputError(
        'Enter an HTTPS or SSH remote URL to test this account.',
        'credential connection test received an unsupported remote',
      );
    }
    late final ProcessOutput output;
    try {
      output = await _runWithCredentials(
        cwd: Directory.current.path,
        args: ['ls-remote', '--refs', remoteUrl],
        kind: GitOperationKind.remote,
        maxBytes: 512 * 1024,
        remoteUrl: remoteUrl,
        credentialId: accountId,
      );
    } on GitError catch (error, stackTrace) {
      Error.throwWithStackTrace(_mapRemoteError(error), stackTrace);
    }
    final referenceCount = utf8
        .decode(output.stdout, allowMalformed: true)
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .length;
    return GitCredentialTestResult(
      host: endpoint.host,
      referenceCount: referenceCount,
      summary:
          'Connected to ${endpoint.host}; found $referenceCount remote reference${referenceCount == 1 ? '' : 's'}.',
    );
  }

  Future<GitRepositorySetupResult> initRepository(
    GitInitRequest request, {
    GitCancellationToken? cancellationToken,
  }) async {
    final destination = _validateSetupAbsolutePath(
      request.path,
      label: 'repository folder',
    );
    final directory = Directory(destination);
    if (File(destination).existsSync()) {
      throw setupInputError(
        'Choose a folder, not a file, for the repository.',
        'init destination was an existing file',
      );
    }
    await directory.create(recursive: true);
    if (request.initialBranch case final branch?) {
      _validateBranchName(branch);
    }
    final args = <String>['init'];
    if (request.initialBranch case final branch?) {
      args.addAll(['--initial-branch', branch]);
    }
    await _runner.run(
      GitInvocation(
        program: gitPath,
        args: args,
        cwd: destination,
        kind: GitOperationKind.mutation,
        outputPolicy: const OutputPolicy.capture(maxBytes: 256 * 1024),
        cancellationToken: cancellationToken,
      ),
    );
    return GitRepositorySetupResult(
      repository: await openRepository(destination),
      summary: 'Initialized a Git repository in $destination.',
    );
  }

  Future<GitUnshallowResult> unshallowRepository(
    RepositoryId repositoryId, {
    GitCancellationToken? cancellationToken,
  }) => state.runMutation(repositoryId, () async {
    final handle = await state.lookup(repositoryId);
    final output = await _runner.run(
      GitInvocation(
        program: gitPath,
        args: const ['rev-parse', '--is-shallow-repository'],
        cwd: handle.root,
        kind: GitOperationKind.read,
        outputPolicy: const OutputPolicy.capture(maxBytes: 4 * 1024),
      ),
    );
    final shallow = utf8.decode(output.stdout, allowMalformed: true).trim();
    if (shallow != 'true' && shallow != 'false') {
      throw const GitError(
        category: GitErrorCategory.parseFailure,
        userMessage: 'Git returned an unrecognized shallow state.',
        diagnostic: 'is-shallow-repository did not return true or false',
        retryable: true,
      );
    }
    final wasShallow = shallow == 'true';
    final unshallowRemoteUrl = wasShallow
        ? _findRemote(await getRemotes(repositoryId), 'origin')?.fetchUrl
        : null;
    if (wasShallow) {
      await _runWithCredentials(
        cwd: handle.root,
        args: const ['fetch', '--unshallow'],
        kind: GitOperationKind.remote,
        maxBytes: 4 * 1024 * 1024,
        cancellationToken: cancellationToken,
        remoteUrl: unshallowRemoteUrl,
      );
    }
    final status = await getStatus(repositoryId);
    return GitUnshallowResult(
      repositoryId: repositoryId,
      status: status,
      wasShallow: wasShallow,
      isShallow: false,
      summary: wasShallow
          ? 'Fetched the complete repository history.'
          : 'Repository history was already complete.',
    );
  });

  Future<GitRootDiscoverySnapshot> discoverRepositoryRoots(String path) async {
    final root = await _canonicalizeDirectory(path);
    final roots = <GitDiscoveredRoot>[];
    final queue = <({Directory directory, String relativePath, int depth})>[
      (directory: Directory(root), relativePath: '', depth: 0),
    ];
    final visited = <String>{};
    var inspectedEntries = 0;
    var truncated = false;
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      final canonical = current.directory.absolute.path;
      if (!visited.add(canonical)) continue;
      final marker = File(
        '${current.directory.path}${Platform.pathSeparator}.git',
      );
      final markerDirectory = Directory(marker.path);
      if (marker.existsSync() || markerDirectory.existsSync()) {
        roots.add(
          GitDiscoveredRoot(
            path: current.directory.path,
            relativePath: current.relativePath,
          ),
        );
      }
      if (current.depth >= 5) continue;
      try {
        await for (final entity in current.directory.list(followLinks: false)) {
          inspectedEntries++;
          if (inspectedEntries > 2_000) {
            truncated = true;
            break;
          }
          if (await FileSystemEntity.type(entity.path, followLinks: false) !=
              FileSystemEntityType.directory) {
            continue;
          }
          final name = _lastSetupPathSegment(entity.path);
          if (name == '.git') continue;
          final relative = current.relativePath.isEmpty
              ? name
              : '${current.relativePath}/$name';
          queue.add((
            directory: Directory(entity.path),
            relativePath: relative,
            depth: current.depth + 1,
          ));
        }
      } on FileSystemException {
        // A directory can disappear while it is being mapped. The remaining
        // roots are still useful and can be refreshed by the caller.
      }
      if (truncated) break;
    }
    roots.sort((left, right) => left.path.compareTo(right.path));
    return GitRootDiscoverySnapshot(
      path: root,
      roots: roots,
      isTruncated: truncated,
      fingerprint: hashGitObjectBytes(
        utf8.encode(roots.map((candidate) => candidate.path).join('\n')),
      ),
    );
  }

  String _validateSetupSource(String value) {
    final source = value.trim();
    if (source.isEmpty ||
        source.startsWith('-') ||
        source.contains('\u0000') ||
        source.runes.any((rune) => rune < 0x20)) {
      throw setupInputError(
        'Enter a Git URL or local repository path.',
        'clone source was empty, option-like, or contained control bytes',
      );
    }
    return source;
  }

  String _validateSetupAbsolutePath(String value, {required String label}) {
    final path = value.trim();
    final isAbsolute =
        path.startsWith('/') ||
        path.startsWith('\\') ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);
    if (path.isEmpty ||
        !isAbsolute ||
        path.startsWith('-') ||
        path.contains('\u0000') ||
        path.runes.any((rune) => rune < 0x20)) {
      throw setupInputError(
        'Choose an absolute path for the $label.',
        'setup path was empty, relative, option-like, or contained control bytes',
      );
    }
    return path;
  }

  String _lastSetupPathSegment(String path) {
    final normalized = path
        .replaceAll('\\', '/')
        .replaceFirst(RegExp(r'/$'), '');
    final slash = normalized.lastIndexOf('/');
    return slash == -1 ? normalized : normalized.substring(slash + 1);
  }

  Future<GitStatusSnapshot> getStatus(RepositoryId repositoryId) async {
    // The UI gives us only an opaque ID. Resolve it before using a path.
    final handle = await state.lookup(repositoryId);
    try {
      final output = await _runGit(handle.root, const [
        'status',
        '--porcelain=v2',
        '-z',
        '--branch',
      ]);
      final parsed = parseGitStatus(output.stdout);
      final generation = state.updateStatusGeneration(
        repositoryId,
        parsed.contentHash,
      );
      return GitStatusSnapshot(
        repositoryId: repositoryId,
        root: handle.root,
        branch: parsed.branch,
        changes: parsed.changes,
        contentHash: parsed.contentHash,
        generation: generation,
      );
    } on GitStatusParseException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        GitError(
          category: GitErrorCategory.parseFailure,
          userMessage: 'Git returned an unreadable status.',
          diagnostic: error.message,
          retryable: false,
        ),
        stackTrace,
      );
    }
  }

  Future<GitRepositoryPathSnapshot> getRepositoryPaths(
    RepositoryId repositoryId, {
    int maxEntries = 2000,
  }) async {
    final handle = await state.lookup(repositoryId);
    final output = await _runner.run(
      GitInvocation(
        program: gitPath,
        args: const ['ls-files', '--cached', '-z'],
        cwd: handle.root,
        kind: GitOperationKind.read,
        outputPolicy: const OutputPolicy.capture(maxBytes: 8 * 1024 * 1024),
      ),
    );
    final paths = <String, GitRepositoryPathKind>{};
    final decoded = utf8.decode(output.stdout, allowMalformed: true);
    for (final rawPath in decoded.split('\u0000')) {
      final path = rawPath;
      if (path.isEmpty) continue;
      paths[path] = GitRepositoryPathKind.file;
      _addRepositoryPathDirectories(paths, path);
    }
    final status = await getStatus(repositoryId);
    for (final change in status.changes) {
      paths[change.path] = GitRepositoryPathKind.file;
      _addRepositoryPathDirectories(paths, change.path);
      if (change.originalPath case final original?) {
        paths[original] = GitRepositoryPathKind.file;
        _addRepositoryPathDirectories(paths, original);
      }
    }
    final sorted = paths.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    final limited = sorted
        .take(maxEntries)
        .map((entry) => GitRepositoryPath(path: entry.key, kind: entry.value));
    return GitRepositoryPathSnapshot(
      paths: limited,
      fingerprint: hashGitObjectBytes(
        utf8.encode(
          sorted.map((entry) => '${entry.key}:${entry.value.name}').join('\n'),
        ),
      ),
      isTruncated: sorted.length > maxEntries,
    );
  }

  Future<GitIgnoreSnapshot> getIgnoreSnapshot(RepositoryId repositoryId) async {
    final handle = await state.lookup(repositoryId);
    final output = await _runner.run(
      GitInvocation(
        program: gitPath,
        args: const [
          'status',
          '--porcelain=v2',
          '--ignored=traditional',
          '--untracked-files=all',
          '-z',
          '--branch',
        ],
        cwd: handle.root,
        kind: GitOperationKind.read,
        outputPolicy: const OutputPolicy.capture(maxBytes: 4 * 1024 * 1024),
      ),
    );
    late final ParsedGitIgnoreStatus parsed;
    try {
      parsed = parseGitIgnoreStatus(output.stdout);
    } on GitStatusParseException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        GitError(
          category: GitErrorCategory.parseFailure,
          userMessage: 'Git returned an unreadable ignore status.',
          diagnostic: error.message,
          retryable: true,
        ),
        stackTrace,
      );
    }
    final ignoredPaths = parsed.entries
        .where((entry) => entry.isIgnored)
        .map((entry) => entry.path)
        .toList(growable: false);
    final rules = await _readIgnoreRules(handle.root, ignoredPaths);
    final entries = <GitIgnoreEntry>[];
    for (final entry in parsed.entries) {
      final rule = rules[entry.path];
      if (entry.isIgnored && rule != null) {
        entries.add(
          GitIgnoreEntry(
            path: entry.path,
            kind: entry.kind,
            source: rule.source,
            sourcePath: rule.sourcePath,
            line: rule.line,
            pattern: rule.pattern,
          ),
        );
      } else {
        entries.add(entry);
      }
    }
    final fingerprint = hashGitObjectBytes(
      utf8.encode(
        entries
            .map(
              (entry) => [
                entry.path,
                entry.kind.name,
                entry.source.name,
                entry.sourcePath ?? '',
                entry.line ?? '',
                entry.pattern ?? '',
              ].join('|'),
            )
            .join('\n'),
      ),
    );
    return GitIgnoreSnapshot(
      repositoryId: repositoryId,
      entries: entries,
      fingerprint: fingerprint,
    );
  }

  Future<GitIgnoreActionResult> addIgnorePattern(
    RepositoryId repositoryId,
    GitIgnoreRequest request,
  ) => state.runMutation(repositoryId, () async {
    final handle = await state.lookup(repositoryId);
    final path = _validateIgnorePath(request.path);
    final pattern = _ignorePatternForPath(path);
    final file = await _ignoreFile(handle.root, request.scope);
    final content = await _readMetadataText(file);
    final lines = content.split(RegExp(r'\r?\n'));
    final changed = !lines.any((line) => line == pattern);
    if (changed) {
      final separator = content.isEmpty || content.endsWith('\n') ? '' : '\n';
      await file.parent.create(recursive: true);
      await file.writeAsString('$content$separator$pattern\n', flush: true);
    }
    return GitIgnoreActionResult(
      repositoryId: repositoryId,
      request: request,
      snapshot: await getIgnoreSnapshot(repositoryId),
      status: await getStatus(repositoryId),
      pattern: pattern,
      changed: changed,
      summary: changed
          ? 'Added $pattern to ${_ignoreScopeLabel(request.scope)}.'
          : '$pattern is already present in ${_ignoreScopeLabel(request.scope)}.',
    );
  });

  Future<GitAttributesSnapshot> getAttributes(
    RepositoryId repositoryId, {
    List<String> paths = const [],
  }) async {
    if (paths.isEmpty) {
      throw const GitError(
        category: GitErrorCategory.parseFailure,
        userMessage: 'Select a file to inspect its Git attributes.',
        diagnostic: 'attribute inspection received no paths',
        retryable: false,
      );
    }
    final handle = await state.lookup(repositoryId);
    final validatedPaths = [
      for (final path in paths) _validateIgnorePath(path),
    ];
    final input = utf8.encode('${validatedPaths.join('\u0000')}\u0000');
    final output = await _runner.run(
      GitInvocation(
        program: gitPath,
        args: const ['check-attr', '-z', '--all', '--stdin'],
        cwd: handle.root,
        stdin: input,
        kind: GitOperationKind.read,
        outputPolicy: const OutputPolicy.capture(maxBytes: 2 * 1024 * 1024),
      ),
    );
    final entries = parseGitAttributes(
      output.stdout,
      requestedPaths: validatedPaths,
    );
    final fingerprint = hashGitObjectBytes(
      utf8.encode(
        entries
            .map(
              (entry) => [
                entry.path,
                ...entry.values.entries.map(
                  (item) => '${item.key}=${item.value}',
                ),
              ].join('|'),
            )
            .join('\n'),
      ),
    );
    return GitAttributesSnapshot(
      repositoryId: repositoryId,
      entries: entries,
      fingerprint: fingerprint,
    );
  }

  Future<GitSubmoduleSnapshot> getSubmodules(RepositoryId repositoryId) async {
    final handle = await state.lookup(repositoryId);
    final gitmodules = File(
      '${handle.root}${Platform.pathSeparator}.gitmodules',
    );
    if (!gitmodules.existsSync()) {
      return GitSubmoduleSnapshot(
        repositoryId: repositoryId,
        root: handle.root,
        modules: const [],
        fingerprint: hashGitObjectBytes(const []),
      );
    }

    final configOutput = await _runner.run(
      GitInvocation(
        program: gitPath,
        args: const ['config', '--null', '--file', '.gitmodules', '--list'],
        cwd: handle.root,
        kind: GitOperationKind.read,
        outputPolicy: const OutputPolicy.capture(maxBytes: 256 * 1024),
      ),
    );
    late final List<GitSubmoduleConfig> configs;
    try {
      configs = parseGitmodules(configOutput.stdout).modules;
    } on GitSubmoduleParseException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        GitError(
          category: GitErrorCategory.parseFailure,
          userMessage: 'Git returned unreadable submodule metadata.',
          diagnostic: error.message,
          retryable: true,
        ),
        stackTrace,
      );
    }
    if (configs.isEmpty) {
      return GitSubmoduleSnapshot(
        repositoryId: repositoryId,
        root: handle.root,
        modules: const [],
        fingerprint: hashGitObjectBytes(configOutput.stdout),
      );
    }

    final statusOutput = await _runner.run(
      GitInvocation(
        program: gitPath,
        args: const ['submodule', 'status', '--recursive'],
        cwd: handle.root,
        kind: GitOperationKind.read,
        outputPolicy: const OutputPolicy.capture(maxBytes: 2 * 1024 * 1024),
      ),
    );
    late final List<GitSubmoduleStatusRecord> statusRecords;
    try {
      statusRecords = parseGitSubmoduleStatus(statusOutput.stdout);
    } on GitSubmoduleParseException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        GitError(
          category: GitErrorCategory.parseFailure,
          userMessage: 'Git returned unreadable submodule status.',
          diagnostic: error.message,
          retryable: true,
        ),
        stackTrace,
      );
    }
    final byPath = {for (final record in statusRecords) record.path: record};
    final modules = <GitSubmodule>[];
    for (final config in configs) {
      final record = byPath[config.path];
      final child = _repositoryFile(handle.root, config.path);
      final exists = Directory(child.path).existsSync();
      final marker = record?.marker;
      final states = <GitSubmoduleState>[];
      final dirtyPaths = <String>[];
      final expectedOid = await _readGitlinkOid(handle.root, config.path);
      final isInitialized = marker != '-' && exists && record != null;
      if (!exists && marker != '-') {
        states.add(GitSubmoduleState.missing);
      }
      if (marker == '-') {
        states.add(GitSubmoduleState.uninitialized);
      } else if (marker == 'U') {
        states.add(GitSubmoduleState.conflicted);
      } else if (marker == '+') {
        states.add(GitSubmoduleState.changedCommit);
      }
      if (isInitialized) {
        states.add(GitSubmoduleState.initialized);
        final childStatus = await _readSubmoduleStatus(child.path);
        dirtyPaths.addAll(childStatus);
        if (dirtyPaths.isNotEmpty) states.add(GitSubmoduleState.dirty);
        if (await _isDetached(child.path)) {
          states.add(GitSubmoduleState.detached);
        }
      }
      if (states.isEmpty) states.add(GitSubmoduleState.missing);
      modules.add(
        GitSubmodule(
          name: config.name,
          path: config.path,
          url: config.url,
          branch: config.branch,
          expectedOid: expectedOid,
          currentOid: record?.currentOid,
          description: record?.description,
          states: states,
          dirtyPaths: dirtyPaths,
        ),
      );
    }
    final fingerprint = hashGitObjectBytes(
      utf8.encode(
        modules
            .map(
              (module) => [
                module.name,
                module.path,
                module.url,
                module.branch ?? '',
                module.expectedOid ?? '',
                module.currentOid ?? '',
                ...module.states.map((state) => state.name),
                ...module.dirtyPaths,
              ].join('|'),
            )
            .join('\n'),
      ),
    );
    return GitSubmoduleSnapshot(
      repositoryId: repositoryId,
      root: handle.root,
      modules: modules,
      fingerprint: fingerprint,
    );
  }

  Future<GitSubmoduleActionResult> executeSubmoduleAction(
    RepositoryId repositoryId,
    GitSubmoduleActionRequest request, {
    GitCancellationToken? cancellationToken,
  }) => state.runMutation(repositoryId, () async {
    final handle = await state.lookup(repositoryId);
    final before = await getSubmodules(repositoryId);
    final paths = _validateSubmodulePaths(before, request.paths);
    final subcommand = request.action == GitSubmoduleAction.init
        ? 'update'
        : request.action.name;
    final args = <String>['submodule', subcommand];
    if (request.recursive) args.add('--recursive');
    if (request.action == GitSubmoduleAction.init ||
        request.action == GitSubmoduleAction.update) {
      args.add('--init');
    }
    if (request.action == GitSubmoduleAction.deinit && request.force) {
      args.add('--force');
    }
    if (paths.isNotEmpty) args.addAll(['--', ...paths]);
    await _runner.run(
      GitInvocation(
        program: gitPath,
        args: args,
        cwd: handle.root,
        kind: GitOperationKind.mutation,
        outputPolicy: const OutputPolicy.capture(maxBytes: 2 * 1024 * 1024),
        cancellationToken: cancellationToken,
      ),
    );
    return GitSubmoduleActionResult(
      repositoryId: repositoryId,
      request: request,
      status: await getStatus(repositoryId),
      snapshot: await getSubmodules(repositoryId),
      summary: '${_submoduleActionLabel(request.action)} completed.',
    );
  });

  Future<GitNestedRootSnapshot> getNestedRoots(
    RepositoryId repositoryId,
  ) async {
    final submodules = await getSubmodules(repositoryId);
    final roots = <GitNestedRoot>[
      GitNestedRoot(
        path: submodules.root,
        relativePath: '',
        kind: GitNestedRootKind.superproject,
      ),
    ];
    for (final module in submodules.modules) {
      final path = _repositoryFile(submodules.root, module.path).path;
      if (!module.isInitialized || module.isMissing) continue;
      roots.add(
        GitNestedRoot(
          path: path,
          relativePath: module.path,
          kind: GitNestedRootKind.submodule,
          submodulePath: module.path,
        ),
      );
    }
    return GitNestedRootSnapshot(
      repositoryId: repositoryId,
      roots: roots,
      fingerprint: hashGitObjectBytes(
        utf8.encode(
          roots.map((root) => '${root.kind.name}|${root.path}').join('\n'),
        ),
      ),
    );
  }

  Future<GitReflogSnapshot> getReflog(
    RepositoryId repositoryId, {
    String ref = 'HEAD',
    int limit = 100,
  }) async {
    final handle = await state.lookup(repositoryId);
    _validateReflogRef(ref);
    final boundedLimit = limit.clamp(1, 500);
    try {
      final output = await _runner.run(
        GitInvocation(
          program: gitPath,
          args: [
            'reflog',
            'show',
            '--format=%H%x00%P%x00%gD%x00%aI%x00%an%x00%gs%x00',
            '-n',
            '$boundedLimit',
            ref,
          ],
          cwd: handle.root,
          kind: GitOperationKind.read,
          outputPolicy: const OutputPolicy.capture(maxBytes: 2 * 1024 * 1024),
        ),
      );
      late final List<GitReflogEntry> entries;
      try {
        entries = parseGitReflog(output.stdout);
      } on GitReflogParseException catch (error, stackTrace) {
        Error.throwWithStackTrace(
          GitError(
            category: GitErrorCategory.parseFailure,
            userMessage: 'Git returned unreadable recovery history.',
            diagnostic: error.message,
            retryable: true,
          ),
          stackTrace,
        );
      }
      return GitReflogSnapshot(
        repositoryId: repositoryId,
        ref: ref,
        entries: entries,
        fingerprint: hashGitObjectBytes(output.stdout),
      );
    } on GitError catch (error) {
      // An unborn branch has no reflog yet; it is a valid empty recovery view.
      if (error.category == GitErrorCategory.processFailed &&
          error.exitCode == 128) {
        return GitReflogSnapshot(
          repositoryId: repositoryId,
          ref: ref,
          entries: const [],
          fingerprint: hashGitObjectBytes(const []),
        );
      }
      rethrow;
    }
  }

  Future<GitRecoveryBranchPreview> previewRecoveryBranch(
    RepositoryId repositoryId,
    GitRecoveryBranchRequest request,
  ) async {
    final handle = await state.lookup(repositoryId);
    _validateRecoveryOid(request.oid);
    _validateBranchName(request.branchName);
    await _validateBranchNameWithGit(handle, request.branchName);
    await _ensureRecoveryBranchIsNew(handle, request.branchName);
    final reflog = await getReflog(repositoryId);
    if (request.reflogFingerprint != reflog.fingerprint) {
      throw const GitError(
        category: GitErrorCategory.staleRollbackPreview,
        userMessage: 'The recovery history changed. Review it again.',
        diagnostic: 'recovery request was based on a stale reflog fingerprint',
        retryable: true,
      );
    }
    final entry = reflog.entries
        .where((candidate) => candidate.oid == request.oid)
        .firstOrNull;
    if (entry == null) {
      throw const GitError(
        category: GitErrorCategory.invalidRevision,
        userMessage: 'That recovery entry is no longer available.',
        diagnostic: 'requested recovery OID was absent from the current reflog',
        retryable: true,
      );
    }
    await _ensureCommitObject(handle, request.oid);
    final token = state.issueRecoveryPreview(
      repositoryId: repositoryId,
      request: request,
      fingerprint: reflog.fingerprint,
    );
    return GitRecoveryBranchPreview(
      repositoryId: repositoryId,
      request: request,
      entry: entry,
      fingerprint: reflog.fingerprint,
      token: token.value,
      expiresAt: token.expiresAt,
    );
  }

  Future<GitRecoveryBranchResult> createRecoveryBranch(
    RepositoryId repositoryId,
    GitRecoveryBranchPreview preview,
  ) => state.runMutation(repositoryId, () async {
    final handle = await state.lookup(repositoryId);
    final reflog = await getReflog(repositoryId);
    state.validateRecoveryPreview(
      repositoryId: repositoryId,
      request: preview.request,
      fingerprint: reflog.fingerprint,
      token: preview.token,
    );
    if (preview.repositoryId != repositoryId ||
        preview.fingerprint != reflog.fingerprint ||
        preview.entry.oid != preview.request.oid ||
        !reflog.entries.any((entry) => entry.oid == preview.request.oid)) {
      state.consumeRecoveryPreview(preview.token);
      throw const GitError(
        category: GitErrorCategory.staleRollbackPreview,
        userMessage: 'The recovery history changed. Review it again.',
        diagnostic: 'recovery preview no longer matched the current reflog',
        retryable: true,
      );
    }
    _validateBranchName(preview.request.branchName);
    await _validateBranchNameWithGit(handle, preview.request.branchName);
    await _ensureRecoveryBranchIsNew(handle, preview.request.branchName);
    await _ensureCommitObject(handle, preview.request.oid);
    await _runner.run(
      GitInvocation(
        program: gitPath,
        args: ['branch', preview.request.branchName, preview.request.oid],
        cwd: handle.root,
        kind: GitOperationKind.mutation,
        outputPolicy: const OutputPolicy.capture(maxBytes: 128 * 1024),
      ),
    );
    state.consumeRecoveryPreview(preview.token);
    return GitRecoveryBranchResult(
      repositoryId: repositoryId,
      request: preview.request,
      branchName: preview.request.branchName,
      status: await getStatus(repositoryId),
      reflog: await getReflog(repositoryId),
      summary: 'Created recovery branch ${preview.request.branchName}.',
    );
  });

  Future<void> _ensureCommitObject(RepositoryHandle handle, String oid) async {
    try {
      await _runner.run(
        GitInvocation(
          program: gitPath,
          args: ['rev-parse', '--verify', '$oid^{commit}'],
          cwd: handle.root,
          kind: GitOperationKind.read,
          outputPolicy: const OutputPolicy.capture(maxBytes: 8 * 1024),
        ),
      );
    } on GitError catch (error, stackTrace) {
      if (error.category == GitErrorCategory.processFailed) {
        Error.throwWithStackTrace(
          error.copyWith(
            category: GitErrorCategory.invalidRevision,
            userMessage: 'The recovery object is not a commit.',
            retryable: false,
          ),
          stackTrace,
        );
      }
      rethrow;
    }
  }

  Future<void> _ensureRecoveryBranchIsNew(
    RepositoryHandle handle,
    String branchName,
  ) async {
    if (await _tryBranchOid(handle, branchName) != null) {
      throw const GitError(
        category: GitErrorCategory.invalidBranchName,
        userMessage: 'That recovery branch already exists.',
        diagnostic: 'recovery branch creation would overwrite an existing ref',
        retryable: false,
      );
    }
  }

  void _validateRecoveryOid(String oid) {
    if (!RegExp(r'^[0-9a-fA-F]{40,64}$').hasMatch(oid)) {
      throw recoveryInputError(
        'Choose a valid recovery commit.',
        'recovery request contained a non-hex or short object ID',
      );
    }
  }

  void _validateReflogRef(String ref) {
    if (ref.isEmpty ||
        ref.startsWith('-') ||
        ref.startsWith('/') ||
        ref.contains('\u0000') ||
        ref.contains('..') ||
        ref.contains('@{') ||
        ref.contains('//') ||
        !RegExp(r'^[A-Za-z0-9_./-]+$').hasMatch(ref)) {
      throw recoveryInputError(
        'Choose a valid branch or HEAD reference.',
        'reflog reference contained unsafe ref syntax',
      );
    }
  }

  Future<String?> _readGitlinkOid(String root, String path) async {
    try {
      final output = await _runner.run(
        GitInvocation(
          program: gitPath,
          args: ['ls-tree', '-z', 'HEAD', '--', path],
          cwd: root,
          kind: GitOperationKind.read,
          outputPolicy: const OutputPolicy.capture(maxBytes: 16 * 1024),
        ),
      );
      final text = utf8.decode(output.stdout, allowMalformed: true);
      final tab = text.indexOf('\t');
      if (tab < 0) return null;
      final fields = text.substring(0, tab).split(' ');
      return fields.length >= 3 ? fields[2] : null;
    } on GitError catch (error) {
      if (error.exitCode == 128) return null;
      rethrow;
    }
  }

  Future<List<String>> _readSubmoduleStatus(String path) async {
    try {
      final output = await _runner.run(
        GitInvocation(
          program: gitPath,
          args: const [
            'status',
            '--porcelain=v2',
            '--untracked-files=all',
            '-z',
            '--ignore-submodules=none',
          ],
          cwd: path,
          kind: GitOperationKind.read,
          outputPolicy: const OutputPolicy.capture(maxBytes: 512 * 1024),
        ),
      );
      final parsed = parseGitStatus(output.stdout);
      return parsed.changes
          .map((change) => change.path)
          .toList(growable: false);
    } on GitError catch (error) {
      if (error.exitCode == 128) return const [];
      rethrow;
    }
  }

  Future<bool> _isDetached(String path) async {
    try {
      await _runner.run(
        GitInvocation(
          program: gitPath,
          args: const ['symbolic-ref', '--quiet', '--short', 'HEAD'],
          cwd: path,
          kind: GitOperationKind.read,
          outputPolicy: const OutputPolicy.capture(maxBytes: 4 * 1024),
        ),
      );
      return false;
    } on GitError catch (error) {
      if (error.exitCode == 1) return true;
      if (error.exitCode == 128) return false;
      rethrow;
    }
  }

  List<String> _validateSubmodulePaths(
    GitSubmoduleSnapshot snapshot,
    List<String> requested,
  ) {
    final allowed = snapshot.modules.map((module) => module.path).toSet();
    final paths = requested.map((path) => path.trim().replaceAll('\\', '/'));
    for (final path in paths) {
      if (path.isEmpty ||
          path.startsWith('-') ||
          path.startsWith('/') ||
          RegExp(r'^[A-Za-z]:/').hasMatch(path) ||
          path.contains('\u0000') ||
          path
              .split('/')
              .any((part) => part.isEmpty || part == '.' || part == '..') ||
          !allowed.contains(path)) {
        throw submoduleInputError(
          'Choose a declared submodule path.',
          'submodule action path was not an exact declared module path: $path',
        );
      }
    }
    return paths.toSet().toList(growable: false);
  }

  String _submoduleActionLabel(GitSubmoduleAction action) => switch (action) {
    GitSubmoduleAction.init => 'Submodule initialization',
    GitSubmoduleAction.sync => 'Submodule URL synchronization',
    GitSubmoduleAction.update => 'Submodule update',
    GitSubmoduleAction.deinit => 'Submodule deinitialization',
  };

  Future<Map<String, GitIgnoreRule>> _readIgnoreRules(
    String root,
    List<String> paths,
  ) async {
    if (paths.isEmpty) return const {};
    final input = utf8.encode('${paths.join('\u0000')}\u0000');
    try {
      final output = await _runner.run(
        GitInvocation(
          program: gitPath,
          args: const ['check-ignore', '-v', '-z', '--no-index', '--stdin'],
          cwd: root,
          stdin: input,
          kind: GitOperationKind.read,
          outputPolicy: const OutputPolicy.capture(maxBytes: 2 * 1024 * 1024),
        ),
      );
      return {
        for (final rule in parseGitIgnoreRules(output.stdout)) rule.path: rule,
      };
    } on GitError catch (error) {
      // A path can stop matching between status and check-ignore. Keep the
      // status useful and leave only that path's provenance unknown.
      if (error.category == GitErrorCategory.processFailed &&
          error.exitCode == 1) {
        return const {};
      }
      rethrow;
    }
  }

  Future<File> _ignoreFile(String root, GitIgnoreScope scope) async {
    if (scope == GitIgnoreScope.repository) {
      return File('$root${Platform.pathSeparator}.gitignore');
    }
    final output = await _runner.run(
      GitInvocation(
        program: gitPath,
        args: const ['rev-parse', '--git-path', 'info/exclude'],
        cwd: root,
        kind: GitOperationKind.read,
        outputPolicy: const OutputPolicy.capture(maxBytes: 16 * 1024),
      ),
    );
    final value = utf8.decode(output.stdout, allowMalformed: true).trim();
    if (value.isEmpty) {
      throw const GitError(
        category: GitErrorCategory.parseFailure,
        userMessage: 'Git did not provide its local exclude file.',
        diagnostic:
            'git rev-parse --git-path info/exclude returned empty output',
        retryable: true,
      );
    }
    final path = File(value).isAbsolute
        ? value
        : '$root${Platform.pathSeparator}${value.replaceAll('/', Platform.pathSeparator)}';
    return File(path);
  }

  Future<String> _readMetadataText(File file) async {
    if (!file.existsSync()) return '';
    final bytes = await file.readAsBytes();
    if (bytes.length > 1024 * 1024) {
      throw const GitError(
        category: GitErrorCategory.outputOverflow,
        userMessage: 'The Git metadata file is too large to edit safely.',
        diagnostic: 'ignore metadata exceeded 1 MiB',
        retryable: false,
      );
    }
    try {
      return utf8.decode(bytes);
    } on FormatException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        GitError(
          category: GitErrorCategory.parseFailure,
          userMessage: 'The Git metadata file is not valid UTF-8.',
          diagnostic: error.message,
          retryable: false,
        ),
        stackTrace,
      );
    }
  }

  String _validateIgnorePath(String value) {
    final path = value.trim().replaceAll('\\', '/');
    if (path.isEmpty ||
        path.startsWith('-') ||
        path.startsWith('/') ||
        RegExp(r'^[A-Za-z]:/').hasMatch(path) ||
        path.contains('\u0000') ||
        path.runes.any((rune) => rune < 0x20) ||
        path
            .split('/')
            .any((part) => part.isEmpty || part == '..' || part == '.')) {
      throw const GitError(
        category: GitErrorCategory.parseFailure,
        userMessage: 'Choose a relative file path inside the repository.',
        diagnostic: 'ignore path was absolute, option-like, empty, or escaped the repository',
        retryable: false,
      );
    }
    return path;
  }

  String _ignorePatternForPath(String path) {
    final segments = path.split('/').map(_escapeIgnoreSegment);
    return '/${segments.join('/')}';
  }

  String _escapeIgnoreSegment(String segment) {
    var escaped = segment.replaceAll('\\', '\\\\');
    if (escaped.startsWith('#') || escaped.startsWith('!')) {
      escaped = '\\$escaped';
    }
    while (escaped.endsWith(' ')) {
      escaped = '${escaped.substring(0, escaped.length - 1)}\\ ';
    }
    return escaped;
  }

  String _ignoreScopeLabel(GitIgnoreScope scope) => switch (scope) {
    GitIgnoreScope.repository => '.gitignore',
    GitIgnoreScope.localExclude => '.git/info/exclude',
  };

  /// Reads the unmerged index and the in-progress operation as one bounded
  /// snapshot. The fingerprint is rebuilt before each mutation, so a view
  /// cannot silently resolve a file that changed while it was open.
  Future<GitConflictSnapshot> getConflicts(RepositoryId repositoryId) async {
    final handle = await state.lookup(repositoryId);
    final status = await getStatus(repositoryId);
    final output = await _runner.run(
      GitInvocation(
        program: gitPath,
        args: const ['ls-files', '-u', '-z'],
        cwd: handle.root,
        kind: GitOperationKind.read,
        outputPolicy: const OutputPolicy.capture(maxBytes: 2 * 1024 * 1024),
      ),
    );
    late final List<GitConflictEntry> parsed;
    try {
      parsed = parseGitUnmergedIndex(output.stdout);
    } on FormatException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        GitError(
          category: GitErrorCategory.parseFailure,
          userMessage: 'Git returned an unreadable conflict index.',
          diagnostic: error.message,
          retryable: false,
        ),
        stackTrace,
      );
    }

    final loaded = <GitConflictEntry>[];
    for (final conflict in parsed) {
      final statusChange = _findChange(status, conflict.path);
      loaded.add(
        conflict.copyWith(
          originalPath: statusChange?.originalPath,
          base: await _loadConflictSide(handle, conflict.base),
          ours: await _loadConflictSide(handle, conflict.ours),
          theirs: await _loadConflictSide(handle, conflict.theirs),
          result: await _loadWorkingConflictSide(handle, conflict.path),
        ),
      );
    }
    final fingerprint = await _readConflictFingerprint(
      handle,
      output.stdout,
      parsed,
    );
    return GitConflictSnapshot(
      repositoryId: repositoryId,
      conflicts: loaded,
      fingerprint: fingerprint,
      operation: await _readConflictOperation(handle),
    );
  }

  Future<GitConflictResolutionResult> acceptConflictOurs(
    RepositoryId repositoryId,
    String path, {
    required String fingerprint,
  }) => _acceptConflictSide(
    repositoryId,
    path,
    fingerprint: fingerprint,
    ours: true,
  );

  Future<GitConflictResolutionResult> acceptConflictTheirs(
    RepositoryId repositoryId,
    String path, {
    required String fingerprint,
  }) => _acceptConflictSide(
    repositoryId,
    path,
    fingerprint: fingerprint,
    ours: false,
  );

  Future<GitConflictResolutionResult> _acceptConflictSide(
    RepositoryId repositoryId,
    String path, {
    required String fingerprint,
    required bool ours,
  }) {
    return state.runMutation(repositoryId, () async {
      final snapshot = await _validateConflictMutation(
        repositoryId,
        path,
        fingerprint,
      );
      final conflict = _findConflict(snapshot, path)!;
      final side = ours ? conflict.ours : conflict.theirs;
      final handle = await state.lookup(repositoryId);
      final command = side?.exists == true
          ? ['checkout', ours ? '--ours' : '--theirs', '--', path]
          : ['rm', '--force', '--', path];
      try {
        await _runner.run(
          GitInvocation(
            program: gitPath,
            args: command,
            cwd: handle.root,
            kind: GitOperationKind.mutation,
            outputPolicy: const OutputPolicy.capture(maxBytes: 128 * 1024),
          ),
        );
        if (side?.exists == true) {
          await _runner.run(
            GitInvocation(
              program: gitPath,
              args: ['add', '--', path],
              cwd: handle.root,
              kind: GitOperationKind.mutation,
              outputPolicy: const OutputPolicy.capture(maxBytes: 128 * 1024),
            ),
          );
        }
      } on GitError catch (error, stackTrace) {
        Error.throwWithStackTrace(_mapConflictError(error), stackTrace);
      }
      return GitConflictResolutionResult(
        repositoryId: repositoryId,
        path: path,
        action: ours
            ? GitConflictResolutionAction.acceptOurs
            : GitConflictResolutionAction.acceptTheirs,
        snapshot: await getConflicts(repositoryId),
        summary: ours
            ? 'The ours side was selected for this path.'
            : 'The theirs side was selected for this path.',
      );
    });
  }

  Future<GitConflictResolutionResult> editConflictResult(
    RepositoryId repositoryId,
    String path,
    String content, {
    required String fingerprint,
  }) {
    final bytes = utf8.encode(content);
    if (bytes.length > _maxConflictTextBytes || content.contains('\u0000')) {
      throw const GitError(
        category: GitErrorCategory.outputOverflow,
        userMessage: 'The editable conflict result is too large or binary.',
        diagnostic: 'edited conflict result exceeded the text safety bound',
        retryable: false,
      );
    }
    return state.runMutation(repositoryId, () async {
      final snapshot = await _validateConflictMutation(
        repositoryId,
        path,
        fingerprint,
      );
      final conflict = _findConflict(snapshot, path)!;
      final resultState = conflict.result?.content.state;
      if (resultState == GitConflictContentState.binary ||
          resultState == GitConflictContentState.tooLarge ||
          resultState == GitConflictContentState.unreadable) {
        throw const GitError(
          category: GitErrorCategory.conflictResolutionNotAllowed,
          userMessage:
              'Binary conflict results must be resolved outside the editor.',
          diagnostic:
              'editable result was requested for a non-text worktree file',
          retryable: false,
        );
      }
      final handle = await state.lookup(repositoryId);
      try {
        await _writeConflictResult(handle, path, bytes);
      } on FileSystemException catch (error, stackTrace) {
        Error.throwWithStackTrace(
          GitError(
            category: GitErrorCategory.permissionDenied,
            userMessage: 'The conflict result could not be written.',
            diagnostic: '$error',
            retryable: true,
          ),
          stackTrace,
        );
      }
      return GitConflictResolutionResult(
        repositoryId: repositoryId,
        path: path,
        action: GitConflictResolutionAction.editResult,
        snapshot: await getConflicts(repositoryId),
        summary: 'The working result was updated. Mark it resolved when ready.',
      );
    });
  }

  Future<GitConflictResolutionResult> markConflictResolved(
    RepositoryId repositoryId,
    String path, {
    required String fingerprint,
    bool deleteResult = false,
  }) {
    return state.runMutation(repositoryId, () async {
      await _validateConflictMutation(repositoryId, path, fingerprint);
      final handle = await state.lookup(repositoryId);
      try {
        if (deleteResult) {
          await _runner.run(
            GitInvocation(
              program: gitPath,
              args: ['rm', '--force', '--', path],
              cwd: handle.root,
              kind: GitOperationKind.mutation,
              outputPolicy: const OutputPolicy.capture(maxBytes: 128 * 1024),
            ),
          );
        } else {
          await _runner.run(
            GitInvocation(
              program: gitPath,
              args: ['add', '--', path],
              cwd: handle.root,
              kind: GitOperationKind.mutation,
              outputPolicy: const OutputPolicy.capture(maxBytes: 128 * 1024),
            ),
          );
        }
      } on GitError catch (error, stackTrace) {
        Error.throwWithStackTrace(_mapConflictError(error), stackTrace);
      }
      return GitConflictResolutionResult(
        repositoryId: repositoryId,
        path: path,
        action: GitConflictResolutionAction.markResolved,
        snapshot: await getConflicts(repositoryId),
        summary: deleteResult
            ? 'The deletion was marked resolved.'
            : 'The working result was marked resolved.',
      );
    });
  }

  Future<GitConflictOperationResult> continueConflict(
    RepositoryId repositoryId, {
    required String fingerprint,
    GitCancellationToken? cancellationToken,
  }) => _runConflictOperation(
    repositoryId,
    GitConflictOperationAction.continueOperation,
    fingerprint: fingerprint,
    cancellationToken: cancellationToken,
  );

  Future<GitConflictOperationResult> abortConflict(
    RepositoryId repositoryId, {
    required String fingerprint,
    GitCancellationToken? cancellationToken,
  }) => _runConflictOperation(
    repositoryId,
    GitConflictOperationAction.abort,
    fingerprint: fingerprint,
    cancellationToken: cancellationToken,
  );

  Future<GitConflictOperationResult> _runConflictOperation(
    RepositoryId repositoryId,
    GitConflictOperationAction action, {
    required String fingerprint,
    GitCancellationToken? cancellationToken,
  }) {
    return state.runMutation(repositoryId, () async {
      final before = await _validateConflictSnapshot(repositoryId, fingerprint);
      final operation = before.operation;
      if (operation == null) {
        throw const GitError(
          category: GitErrorCategory.operationInProgress,
          userMessage: 'No merge, rebase, or cherry-pick is in progress.',
          diagnostic:
              'conflict recovery was requested without operation metadata',
          retryable: false,
        );
      }
      if (action == GitConflictOperationAction.continueOperation &&
          before.hasConflicts) {
        throw const GitError(
          category: GitErrorCategory.unresolvedConflicts,
          userMessage: 'Resolve every conflicted path before continuing.',
          diagnostic:
              'continue was requested while unmerged index entries remained',
          retryable: false,
        );
      }
      final args = _conflictOperationArgs(operation.operation, action);
      try {
        await _runner.run(
          GitInvocation(
            program: gitPath,
            args: args,
            cwd: (await state.lookup(repositoryId)).root,
            kind: GitOperationKind.mutation,
            outputPolicy: const OutputPolicy.capture(maxBytes: 512 * 1024),
            cancellationToken: cancellationToken,
            environment: const {'GIT_EDITOR': ':'},
          ),
        );
      } on GitError catch (error, stackTrace) {
        final afterFailure = await getConflicts(repositoryId);
        if (error.category == GitErrorCategory.cancelled) {
          return GitConflictOperationResult(
            repositoryId: repositoryId,
            operation: operation,
            action: action,
            state: GitConflictOperationState.cancelled,
            snapshot: afterFailure,
            summary: 'The recovery command was cancelled; review the conflict state.',
          );
        }
        if (afterFailure.hasConflicts) {
          return GitConflictOperationResult(
            repositoryId: repositoryId,
            operation: operation,
            action: action,
            state: GitConflictOperationState.conflicted,
            snapshot: afterFailure,
            summary: 'Git still has conflicts. Resolve them before continuing.',
          );
        }
        Error.throwWithStackTrace(_mapConflictError(error), stackTrace);
      }
      final after = await getConflicts(repositoryId);
      final completed = after.operation == null;
      return GitConflictOperationResult(
        repositoryId: repositoryId,
        operation: operation,
        action: action,
        state: action == GitConflictOperationAction.abort
            ? GitConflictOperationState.aborted
            : completed
            ? GitConflictOperationState.completed
            : GitConflictOperationState.continued,
        snapshot: after,
        summary: action == GitConflictOperationAction.abort
            ? 'The operation was aborted.'
            : completed
            ? 'The operation was completed.'
            : 'The operation continued to its next step.',
      );
    });
  }

  /// Captures all state needed to explain and authorize one history rollback.
  /// The preview does not mutate refs or the index; execution repeats this
  /// inspection and rejects the token if any reviewed fact changed.
  Future<GitHistoryRollbackPreview> previewHistoryRollback(
    RepositoryId repositoryId,
    GitHistoryRollbackRequest request,
  ) async {
    final handle = await state.lookup(repositoryId);
    final inspection = await _inspectHistoryRollback(
      repositoryId,
      handle,
      request,
    );
    GitBranchPreviewToken? token;
    if (inspection.blockingMessage == null) {
      token = state.issueHistoryRollbackPreview(
        repositoryId: repositoryId,
        request: request,
        fingerprint: inspection.fingerprint,
      );
    }
    return GitHistoryRollbackPreview(
      repositoryId: repositoryId,
      request: request,
      currentBranch: inspection.currentBranch,
      currentHead: inspection.currentHead,
      targetHead: inspection.targetHead,
      upstreamHead: inspection.upstreamHead,
      branchProtected: inspection.branchProtected,
      pushedCommits: inspection.pushedCommits,
      detachedHead: inspection.detachedHead,
      dirtyWorktree: inspection.dirtyWorktree,
      operationInProgress: inspection.operationInProgress,
      impact: inspection.impact,
      fingerprint: inspection.fingerprint,
      requiresConfirmation: true,
      token: token?.value,
      expiresAt: token?.expiresAt,
      blockingMessage: inspection.blockingMessage,
      revisions: inspection.revisionOids,
    );
  }

  Future<GitHistoryRollbackResult> executeHistoryRollback(
    RepositoryId repositoryId,
    GitHistoryRollbackPreview preview, {
    GitCancellationToken? cancellationToken,
  }) async {
    return state.runMutation(repositoryId, () async {
      final handle = await state.lookup(repositoryId);
      final inspection = await _inspectHistoryRollback(
        repositoryId,
        handle,
        preview.request,
      );
      _throwIfHistoryRollbackBlocked(inspection);
      state.validateHistoryRollbackPreview(
        repositoryId: repositoryId,
        preview: preview,
        fingerprint: inspection.fingerprint,
      );
      if (preview.token case final token?) {
        state.consumeHistoryRollbackPreview(token);
      }

      final args = switch (preview.request.action) {
        GitHistoryRollbackAction.reset || GitHistoryRollbackAction.undo => [
          'reset',
          '--${preview.request.mode.gitValue}',
          inspection.targetHead,
        ],
        GitHistoryRollbackAction.revert => [
          'revert',
          '--no-edit',
          ...inspection.revisionOids,
        ],
      };
      try {
        await _runner.run(
          GitInvocation(
            program: gitPath,
            args: args,
            cwd: handle.root,
            kind: GitOperationKind.mutation,
            outputPolicy: const OutputPolicy.capture(maxBytes: 512 * 1024),
            cancellationToken: cancellationToken,
            environment:
                preview.request.action == GitHistoryRollbackAction.revert
                ? const {'GIT_EDITOR': ':'}
                : null,
          ),
        );
      } on GitError catch (error, stackTrace) {
        final afterFailure = await _inspectHistoryRollbackState(
          repositoryId,
          handle,
          preview.request,
        );
        final revertConflict =
            preview.request.action == GitHistoryRollbackAction.revert &&
            afterFailure.operationInProgress;
        if (error.category == GitErrorCategory.cancelled) {
          return _historyRollbackResult(
            repositoryId,
            preview.request,
            GitHistoryRollbackState.cancelled,
            await getStatus(repositoryId),
            inspection.currentHead,
            await _readHeadOid(handle) ?? inspection.currentHead,
            'The rollback was cancelled. Review the repository state before retrying.',
            inspection.revisionOids,
            revertConflict,
          );
        }
        if (revertConflict) {
          return _historyRollbackResult(
            repositoryId,
            preview.request,
            GitHistoryRollbackState.conflicted,
            await getStatus(repositoryId),
            inspection.currentHead,
            await _readHeadOid(handle) ?? inspection.currentHead,
            'Git stopped while reverting. Resolve the conflicts, then continue or abort the revert.',
            inspection.revisionOids,
            true,
          );
        }
        Error.throwWithStackTrace(_mapHistoryRollbackError(error), stackTrace);
      }

      final status = await getStatus(repositoryId);
      final resultingHead = await _readHeadOid(handle) ?? inspection.targetHead;
      return _historyRollbackResult(
        repositoryId,
        preview.request,
        GitHistoryRollbackState.completed,
        status,
        inspection.currentHead,
        resultingHead,
        preview.request.action == GitHistoryRollbackAction.revert
            ? 'The selected commit(s) were reverted into new commit(s).'
            : preview.request.action == GitHistoryRollbackAction.undo
            ? 'The latest unpushed commit was undone and its changes were preserved.'
            : '${preview.request.mode.label} reset completed.',
        inspection.revisionOids,
        false,
      );
    });
  }

  Future<GitHistoryRollbackPreview> previewReset(
    RepositoryId repositoryId,
    String targetRevision, {
    GitResetMode mode = GitResetMode.mixed,
  }) => previewHistoryRollback(
    repositoryId,
    GitHistoryRollbackRequest(
      action: GitHistoryRollbackAction.reset,
      targetRevision: targetRevision,
      mode: mode,
    ),
  );

  /// Captures the exact commit range and repository state before an
  /// interactive history rewrite. This preview never starts Git rebase.
  Future<GitInteractiveRebasePreview> previewInteractiveRebase(
    RepositoryId repositoryId,
    GitInteractiveRebasePlan plan,
  ) async {
    if (plan.repositoryId != repositoryId) {
      throw const GitError(
        category: GitErrorCategory.invalidOpaqueId,
        userMessage: 'This rebase plan belongs to another repository.',
        diagnostic:
            'interactive rebase plan repository ID did not match the request',
        retryable: false,
      );
    }
    final handle = await state.lookup(repositoryId);
    final inspection = await _inspectInteractiveRebase(
      repositoryId,
      handle,
      plan,
    );
    GitBranchPreviewToken? token;
    if (inspection.blockingMessage == null && plan.isValid) {
      token = state.issueInteractiveRebasePreview(
        repositoryId: repositoryId,
        plan: plan,
        fingerprint: inspection.fingerprint,
      );
    }
    return GitInteractiveRebasePreview(
      repositoryId: repositoryId,
      plan: plan,
      currentBranch: inspection.currentBranch,
      currentHead: inspection.currentHead,
      upstreamHead: inspection.upstreamHead,
      selectedCommitCount: plan.entries.length,
      mergeCommitCount: inspection.mergeCommitCount,
      branchProtected: inspection.branchProtected,
      pushedCommits: inspection.pushedCommits,
      detachedHead: inspection.detachedHead,
      dirtyWorktree: inspection.dirtyWorktree,
      operationInProgress: inspection.operationInProgress,
      fingerprint: inspection.fingerprint,
      requiresConfirmation: true,
      token: token?.value,
      expiresAt: token?.expiresAt,
      blockingMessage: inspection.blockingMessage,
      optionLimitations: inspection.optionLimitations,
      planIssues: plan.validationIssues,
    );
  }

  /// Executes only a fresh, token-bound plan. Git receives a temporary
  /// sequence-editor command that copies the machine-generated todo file; the
  /// UI never supplies an arbitrary command or todo path.
  Future<GitInteractiveRebaseResult> executeInteractiveRebase(
    RepositoryId repositoryId,
    GitInteractiveRebasePreview preview, {
    GitCancellationToken? cancellationToken,
  }) {
    return state.runMutation(repositoryId, () async {
      final handle = await state.lookup(repositoryId);
      final inspection = await _inspectInteractiveRebase(
        repositoryId,
        handle,
        preview.plan,
      );
      if (preview.token != null) {
        // Validate before translating a changed range into a generic blocker;
        // a reviewed preview must fail as stale when refs moved underneath it.
        state.validateInteractiveRebasePreview(
          repositoryId: repositoryId,
          preview: preview,
          fingerprint: inspection.fingerprint,
        );
      } else {
        _throwIfInteractiveRebaseBlocked(inspection);
        throw const GitError(
          category: GitErrorCategory.staleRollbackPreview,
          userMessage: 'Review the rebase plan before starting it.',
          diagnostic: 'interactive rebase execution received no preview token',
          retryable: true,
        );
      }
      _throwIfInteractiveRebaseBlocked(inspection);

      final recoveryRef = await _createInteractiveRebaseRecoveryRef(
        handle,
        inspection.currentHead,
      );
      state.consumeInteractiveRebasePreview(preview.token!);
      final editor = await _createInteractiveRebaseEditor(preview.plan);
      try {
        final args = [
          'rebase',
          '--interactive',
          ...preview.plan.options.toGitArguments(),
          if (!preview.plan.options.root) inspection.upstreamHead!,
        ];
        try {
          await _runner.run(
            GitInvocation(
              program: gitPath,
              args: args,
              cwd: handle.root,
              kind: GitOperationKind.mutation,
              outputPolicy: const OutputPolicy.capture(maxBytes: 512 * 1024),
              cancellationToken: cancellationToken,
              environment: {
                'GIT_SEQUENCE_EDITOR': editor.sequenceEditorCommand,
                'GIT_EDITOR': editor.messageEditorCommand,
                'GIT_TERMINAL_PROMPT': '0',
                'GIT_REFLOG_ACTION': 'gift interactive rebase',
              },
            ),
          );
        } on GitError catch (error, stackTrace) {
          final afterFailure = await _readInteractiveRebaseRecovery(
            repositoryId,
          );
          final operationStillActive =
              afterFailure.operation?.operation == GitConflictOperation.rebase;
          if (error.category == GitErrorCategory.cancelled) {
            return _interactiveRebaseResult(
              repositoryId: repositoryId,
              phase: GitInteractiveRebasePhase.start,
              state: GitInteractiveRebaseExecutionState.cancelled,
              status: await getStatus(repositoryId),
              previousHead: inspection.currentHead,
              resultingHead:
                  await _readHeadOid(handle) ?? inspection.currentHead,
              summary: 'The rebase was cancelled. Review the repository state before choosing a recovery action.',
              plan: preview.plan,
              recoveryRef: recoveryRef,
              recovery: operationStillActive ? afterFailure : null,
              pauseReason: operationStillActive
                  ? GitInteractiveRebasePauseReason.cancelled
                  : null,
            );
          }
          if (operationStillActive) {
            final pauseReason = _interactiveRebasePauseReason(
              error: error,
              recovery: afterFailure,
            );
            return _interactiveRebaseResult(
              repositoryId: repositoryId,
              phase: GitInteractiveRebasePhase.start,
              state: afterFailure.hasConflicts
                  ? GitInteractiveRebaseExecutionState.conflicted
                  : GitInteractiveRebaseExecutionState.paused,
              status: await getStatus(repositoryId),
              previousHead: inspection.currentHead,
              resultingHead:
                  await _readHeadOid(handle) ?? inspection.currentHead,
              summary: _interactiveRebasePauseSummary(pauseReason),
              plan: preview.plan,
              recoveryRef: recoveryRef,
              recovery: afterFailure,
              pauseReason: pauseReason,
            );
          }
          final mappedError = _mapInteractiveRebaseError(error);
          final resultingHead = await _readHeadOid(handle);
          if (mappedError.category == GitErrorCategory.hookRejected &&
              resultingHead != null &&
              resultingHead != inspection.currentHead) {
            final status = await getStatus(repositoryId);
            return _interactiveRebaseResult(
              repositoryId: repositoryId,
              phase: GitInteractiveRebasePhase.start,
              state: GitInteractiveRebaseExecutionState.completed,
              status: status,
              previousHead: inspection.currentHead,
              resultingHead: resultingHead,
              summary: 'The rebase changed history, but a Git hook reported a failure afterward. Review the recovery ref.',
              plan: preview.plan,
              recoveryRef: recoveryRef,
              pauseReason: GitInteractiveRebasePauseReason.hookRejected,
              rewrittenCommitOids: await _readInteractiveRebaseRewriteMap(
                handle,
                preview.plan,
                resultingHead,
              ),
              recoveryRefs: await _readInteractiveRebaseRecoveryRefs(
                handle,
                recoveryRef,
                inspection.currentHead,
              ),
            );
          }
          Error.throwWithStackTrace(mappedError, stackTrace);
        }

        final afterStart = await _readInteractiveRebaseRecovery(repositoryId);
        if (afterStart.operation?.operation == GitConflictOperation.rebase) {
          return _interactiveRebaseResult(
            repositoryId: repositoryId,
            phase: GitInteractiveRebasePhase.start,
            state: afterStart.hasConflicts
                ? GitInteractiveRebaseExecutionState.conflicted
                : GitInteractiveRebaseExecutionState.paused,
            status: await getStatus(repositoryId),
            previousHead: inspection.currentHead,
            resultingHead: await _readHeadOid(handle) ?? inspection.currentHead,
            summary: afterStart.hasConflicts
                ? 'Git stopped with conflicts. Resolve them, then choose continue, skip, or abort.'
                : 'Git paused the rebase. Choose continue, skip, or abort after reviewing the worktree.',
            plan: preview.plan,
            recoveryRef: recoveryRef,
            recovery: afterStart,
            pauseReason: afterStart.hasConflicts
                ? GitInteractiveRebasePauseReason.conflict
                : GitInteractiveRebasePauseReason.edit,
          );
        }
        final status = await getStatus(repositoryId);
        final resultingHead =
            await _readHeadOid(handle) ?? inspection.currentHead;
        final rewritten = await _readInteractiveRebaseRewriteMap(
          handle,
          preview.plan,
          resultingHead,
        );
        return _interactiveRebaseResult(
          repositoryId: repositoryId,
          phase: GitInteractiveRebasePhase.start,
          state: GitInteractiveRebaseExecutionState.completed,
          status: status,
          previousHead: inspection.currentHead,
          resultingHead: resultingHead,
          summary: 'The interactive rebase completed.',
          plan: preview.plan,
          recoveryRef: recoveryRef,
          rewrittenCommitOids: rewritten,
          recoveryRefs: await _readInteractiveRebaseRecoveryRefs(
            handle,
            recoveryRef,
            inspection.currentHead,
          ),
        );
      } finally {
        await editor.dispose();
      }
    });
  }

  /// Runs one explicit recovery command for an already-started rebase.
  Future<GitInteractiveRebaseResult> recoverInteractiveRebase(
    RepositoryId repositoryId,
    GitInteractiveRebaseRecoveryRequest request, {
    GitCancellationToken? cancellationToken,
  }) {
    return state.runMutation(repositoryId, () async {
      final handle = await state.lookup(repositoryId);
      final before = await _readInteractiveRebaseRecovery(repositoryId);
      if (before.operation?.operation != GitConflictOperation.rebase) {
        throw const GitError(
          category: GitErrorCategory.operationInProgress,
          userMessage: 'No interactive rebase is in progress.',
          diagnostic: 'interactive rebase recovery was requested without rebase metadata',
          retryable: false,
        );
      }
      if (before.fingerprint != request.fingerprint) {
        throw const GitError(
          category: GitErrorCategory.staleConflict,
          userMessage:
              'The rebase state changed. Refresh it before recovering.',
          diagnostic:
              'interactive rebase recovery fingerprint no longer matched',
          retryable: true,
        );
      }
      if (request.action ==
              GitInteractiveRebaseRecoveryAction.continueOperation &&
          before.hasConflicts) {
        throw const GitError(
          category: GitErrorCategory.unresolvedConflicts,
          userMessage: 'Resolve every conflicted path before continuing.',
          diagnostic: 'interactive rebase continue was requested with unresolved conflicts',
          retryable: false,
        );
      }

      final previousHead = await _readHeadOid(handle) ?? '';
      final originalHead = before.originalHead ?? previousHead;
      final recoveryRefs = await _readInteractiveRebaseRecoveryRefs(
        handle,
        null,
        originalHead,
      );
      final args = switch (request.action) {
        GitInteractiveRebaseRecoveryAction.continueOperation => const [
          'rebase',
          '--continue',
        ],
        GitInteractiveRebaseRecoveryAction.skip => const ['rebase', '--skip'],
        GitInteractiveRebaseRecoveryAction.abort => const ['rebase', '--abort'],
      };
      try {
        await _runner.run(
          GitInvocation(
            program: gitPath,
            args: args,
            cwd: handle.root,
            kind: GitOperationKind.mutation,
            outputPolicy: const OutputPolicy.capture(maxBytes: 512 * 1024),
            cancellationToken: cancellationToken,
            environment: const {'GIT_EDITOR': ':', 'GIT_TERMINAL_PROMPT': '0'},
          ),
        );
      } on GitError catch (error, stackTrace) {
        final afterFailure = await _readInteractiveRebaseRecovery(repositoryId);
        final operationStillActive =
            afterFailure.operation?.operation == GitConflictOperation.rebase;
        if (error.category == GitErrorCategory.cancelled) {
          return _interactiveRebaseRecoveryResult(
            repositoryId,
            request,
            GitInteractiveRebaseExecutionState.cancelled,
            await getStatus(repositoryId),
            originalHead,
            await _readHeadOid(handle) ?? previousHead,
            'The rebase recovery command was cancelled. Review its current state.',
            afterFailure,
            originalCommitOids: request.originalCommitOids,
            recoveryRefs: recoveryRefs,
            pauseReason: afterFailure.operation == null
                ? null
                : GitInteractiveRebasePauseReason.cancelled,
          );
        }
        if (operationStillActive) {
          final pauseReason = _interactiveRebasePauseReason(
            error: error,
            recovery: afterFailure,
          );
          return _interactiveRebaseRecoveryResult(
            repositoryId,
            request,
            afterFailure.hasConflicts
                ? GitInteractiveRebaseExecutionState.conflicted
                : GitInteractiveRebaseExecutionState.paused,
            await getStatus(repositoryId),
            originalHead,
            await _readHeadOid(handle) ?? previousHead,
            _interactiveRebasePauseSummary(pauseReason),
            afterFailure,
            originalCommitOids: request.originalCommitOids,
            recoveryRefs: recoveryRefs,
            pauseReason: pauseReason,
          );
        }
        Error.throwWithStackTrace(
          _mapInteractiveRebaseError(error),
          stackTrace,
        );
      }

      final after = await _readInteractiveRebaseRecovery(repositoryId);
      return _interactiveRebaseRecoveryResult(
        repositoryId,
        request,
        request.action == GitInteractiveRebaseRecoveryAction.abort
            ? GitInteractiveRebaseExecutionState.aborted
            : after.operation == null
            ? GitInteractiveRebaseExecutionState.completed
            : GitInteractiveRebaseExecutionState.paused,
        await getStatus(repositoryId),
        originalHead,
        await _readHeadOid(handle) ?? previousHead,
        request.action == GitInteractiveRebaseRecoveryAction.abort
            ? 'The interactive rebase was aborted.'
            : after.operation == null
            ? 'The interactive rebase completed.'
            : 'The interactive rebase remains paused.',
        after,
        originalCommitOids: request.originalCommitOids,
        recoveryRefs: await _readInteractiveRebaseRecoveryRefs(
          handle,
          null,
          originalHead,
        ),
        pauseReason: after.operation == null
            ? null
            : GitInteractiveRebasePauseReason.edit,
      );
    });
  }

  Future<String?> _readInteractiveRebaseOriginalHead(
    RepositoryHandle handle,
  ) async {
    for (final directoryName in const ['rebase-merge', 'rebase-apply']) {
      final path = await _readGitPath(handle, directoryName);
      if (path == null || !Directory(path).existsSync()) continue;
      final original = await _readFileAt(
        '$path${Platform.pathSeparator}orig-head',
      );
      final value = original?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  Future<_InteractiveRebaseRecovery> _readInteractiveRebaseRecovery(
    RepositoryId repositoryId,
  ) async {
    final handle = await state.lookup(repositoryId);
    final snapshot = await getConflicts(repositoryId);
    final originalHead =
        snapshot.operation?.operation == GitConflictOperation.rebase
        ? await _readInteractiveRebaseOriginalHead(handle)
        : null;
    return _InteractiveRebaseRecovery(
      fingerprint: snapshot.fingerprint,
      operation: snapshot.operation,
      hasConflicts: snapshot.hasConflicts,
      originalHead: originalHead,
    );
  }

  GitInteractiveRebasePauseReason _interactiveRebasePauseReason({
    required GitError? error,
    required _InteractiveRebaseRecovery recovery,
  }) {
    if (error?.category == GitErrorCategory.hookRejected ||
        (error != null &&
            RegExp(
              r'\b(?:hook|pre-commit|commit-msg|pre-rebase)\b',
              caseSensitive: false,
            ).hasMatch(error.diagnostic))) {
      return GitInteractiveRebasePauseReason.hookRejected;
    }
    if (recovery.hasConflicts) return GitInteractiveRebasePauseReason.conflict;
    return GitInteractiveRebasePauseReason.edit;
  }

  String _interactiveRebasePauseSummary(
    GitInteractiveRebasePauseReason reason,
  ) => switch (reason) {
    GitInteractiveRebasePauseReason.conflict => 'Git stopped with conflicts. Resolve them, then choose continue, skip, or abort.',
    GitInteractiveRebasePauseReason.hookRejected => 'A Git hook stopped the rebase. Fix the hook or worktree, then choose continue, skip, or abort.',
    GitInteractiveRebasePauseReason.cancelled => 'The rebase was cancelled while it was in progress. Review the worktree, then choose continue, skip, or abort.',
    GitInteractiveRebasePauseReason.edit => 'Git paused the rebase for review. Choose continue, skip, or abort after checking the worktree.',
  };

  void _throwIfInteractiveRebaseBlocked(
    _InteractiveRebaseInspection inspection,
  ) {
    final message = inspection.blockingMessage;
    if (message == null) return;
    final category = inspection.operationInProgress != null
        ? GitErrorCategory.operationInProgress
        : inspection.detachedHead
        ? GitErrorCategory.detachedHead
        : inspection.branchProtected
        ? GitErrorCategory.protectedBranch
        : inspection.pushedCommits
        ? GitErrorCategory.pushedHistory
        : inspection.dirtyWorktree
        ? GitErrorCategory.dirtyWorktree
        : GitErrorCategory.historyRollbackNotAllowed;
    throw GitError(
      category: category,
      userMessage: message,
      diagnostic: 'interactive rebase preflight rejected the request',
      retryable: false,
    );
  }

  Future<String> _createInteractiveRebaseRecoveryRef(
    RepositoryHandle handle,
    String currentHead,
  ) async {
    final suffix =
        '${currentHead.substring(0, min(12, currentHead.length))}-${DateTime.now().microsecondsSinceEpoch}';
    final ref = 'refs/gift/rebase/$suffix';
    await _runner.run(
      GitInvocation(
        program: gitPath,
        args: ['update-ref', ref, currentHead],
        cwd: handle.root,
        kind: GitOperationKind.mutation,
        outputPolicy: const OutputPolicy.capture(maxBytes: 16 * 1024),
      ),
    );
    return ref;
  }

  Future<_InteractiveRebaseEditor> _createInteractiveRebaseEditor(
    GitInteractiveRebasePlan plan,
  ) async {
    final directory = await Directory.systemTemp.createTemp(
      'gift-rebase-editor-',
    );
    final todo = File('${directory.path}${Platform.pathSeparator}todo');
    final todoContents = plan.entries
        .map(
          (entry) =>
              '${entry.action.gitValue} ${entry.originalOid} ${_todoSubject(entry.subject)}',
        )
        .join('\n');
    await todo.writeAsString('$todoContents\n');
    final script = File(
      '${directory.path}${Platform.pathSeparator}sequence-editor.sh',
    );
    final messageScript = File(
      '${directory.path}${Platform.pathSeparator}message-editor.sh',
    );
    final rewordEntries = plan.entries
        .where((entry) => entry.action == GitInteractiveRebaseAction.reword)
        .toList(growable: false);
    await script.writeAsString(
      '#!/bin/sh\n'
      'cp -- ${_shellPath(todo.path)} "\$1"\n',
    );
    final messageScriptContents = StringBuffer(
      '#!/bin/sh\n'
      'head=\$(git rev-parse HEAD 2>/dev/null || true)\n',
    );
    for (var index = 0; index < rewordEntries.length; index++) {
      final entry = rewordEntries[index];
      final messageFile = File(
        '${directory.path}${Platform.pathSeparator}message-$index.txt',
      );
      await messageFile.writeAsString('${_todoSubject(entry.subject)}\n');
      messageScriptContents
        ..writeln('if [ "\$head" = "${entry.originalOid}" ]; then')
        ..writeln('  cp -- ${_shellPath(messageFile.path)} "\$1"')
        ..writeln('  exit 0')
        ..writeln('fi');
    }
    messageScriptContents.write('exit 0\n');
    await messageScript.writeAsString(messageScriptContents.toString());
    return _InteractiveRebaseEditor(
      directory: directory,
      sequenceEditorCommand: 'sh ${_shellPath(script.path)}',
      messageEditorCommand: 'sh ${_shellPath(messageScript.path)}',
    );
  }

  Future<Map<String, String>> _readInteractiveRebaseRewriteMap(
    RepositoryHandle handle,
    GitInteractiveRebasePlan plan,
    String resultingHead,
  ) async {
    final finalOids = await _readInteractiveRebaseRange(
      handle,
      resultingHead,
      plan.options.root
          ? null
          : await _resolveCommit(handle, plan.upstreamRevision!),
      root: plan.options.root,
    );
    final rewritten = <String, String>{};
    var resultIndex = 0;
    String? lastResult;
    for (final entry in plan.entries) {
      if (entry.action == GitInteractiveRebaseAction.drop) continue;
      if (entry.action == GitInteractiveRebaseAction.squash ||
          entry.action == GitInteractiveRebaseAction.fixup) {
        if (lastResult != null) rewritten[entry.originalOid] = lastResult;
        continue;
      }
      if (resultIndex >= finalOids.length) continue;
      lastResult = finalOids[resultIndex++];
      rewritten[entry.originalOid] = lastResult;
    }
    return rewritten;
  }

  Future<List<String>> _readInteractiveRebaseRecoveryRefs(
    RepositoryHandle handle,
    String? recoveryRef,
    String previousHead,
  ) async {
    final refs = <String>[];
    if (recoveryRef != null) refs.add(recoveryRef);
    try {
      final output = await _runner.run(
        GitInvocation(
          program: gitPath,
          args: const [
            'for-each-ref',
            '--format=%(refname)',
            'refs/gift/rebase',
          ],
          cwd: handle.root,
          kind: GitOperationKind.read,
          outputPolicy: const OutputPolicy.capture(maxBytes: 64 * 1024),
        ),
      );
      for (final ref
          in utf8
              .decode(output.stdout, allowMalformed: true)
              .split('\n')
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)) {
        if (!refs.contains(ref)) refs.add(ref);
      }
    } on GitError {
      // The explicit recovery ref is still useful when listing refs is not
      // available in a damaged repository.
    }
    if (await _tryResolve(handle, 'HEAD@{1}') == previousHead) {
      if (!refs.contains('HEAD@{1}')) refs.add('HEAD@{1}');
    }
    return refs;
  }

  GitInteractiveRebaseResult _interactiveRebaseResult({
    required RepositoryId repositoryId,
    required GitInteractiveRebasePhase phase,
    required GitInteractiveRebaseExecutionState state,
    required GitStatusSnapshot status,
    required String previousHead,
    required String resultingHead,
    required String summary,
    required GitInteractiveRebasePlan plan,
    required String recoveryRef,
    _InteractiveRebaseRecovery? recovery,
    GitInteractiveRebasePauseReason? pauseReason,
    Map<String, String> rewrittenCommitOids = const <String, String>{},
    Iterable<String>? recoveryRefs,
  }) => GitInteractiveRebaseResult(
    repositoryId: repositoryId,
    phase: phase,
    state: state,
    status: status,
    previousHead: previousHead,
    resultingHead: resultingHead,
    summary: summary,
    originalCommitOids: plan.entries.map((entry) => entry.originalOid),
    rewrittenCommitOids: rewrittenCommitOids,
    recoveryRefs: recoveryRefs ?? [recoveryRef],
    recoveryActions: recovery == null
        ? const <GitInteractiveRebaseRecoveryAction>[]
        : const [
            GitInteractiveRebaseRecoveryAction.continueOperation,
            GitInteractiveRebaseRecoveryAction.skip,
            GitInteractiveRebaseRecoveryAction.abort,
          ],
    pauseReason: pauseReason,
    recoveryFingerprint: recovery?.fingerprint,
  );

  GitInteractiveRebaseResult _interactiveRebaseRecoveryResult(
    RepositoryId repositoryId,
    GitInteractiveRebaseRecoveryRequest request,
    GitInteractiveRebaseExecutionState state,
    GitStatusSnapshot status,
    String previousHead,
    String resultingHead,
    String summary,
    _InteractiveRebaseRecovery recovery, {
    GitInteractiveRebasePauseReason? pauseReason,
    Iterable<String> originalCommitOids = const <String>[],
    Iterable<String> recoveryRefs = const <String>[],
  }) => GitInteractiveRebaseResult(
    repositoryId: repositoryId,
    phase: switch (request.action) {
      GitInteractiveRebaseRecoveryAction.continueOperation =>
        GitInteractiveRebasePhase.continueOperation,
      GitInteractiveRebaseRecoveryAction.skip => GitInteractiveRebasePhase.skip,
      GitInteractiveRebaseRecoveryAction.abort =>
        GitInteractiveRebasePhase.abort,
    },
    state: state,
    status: status,
    previousHead: previousHead,
    resultingHead: resultingHead,
    summary: summary,
    originalCommitOids: originalCommitOids,
    recoveryRefs: recoveryRefs,
    recoveryActions: recovery.operation == null
        ? const <GitInteractiveRebaseRecoveryAction>[]
        : const [
            GitInteractiveRebaseRecoveryAction.continueOperation,
            GitInteractiveRebaseRecoveryAction.skip,
            GitInteractiveRebaseRecoveryAction.abort,
          ],
    pauseReason: pauseReason,
    recoveryFingerprint: recovery.operation == null
        ? null
        : recovery.fingerprint,
  );

  Future<_InteractiveRebaseInspection> _inspectInteractiveRebase(
    RepositoryId repositoryId,
    RepositoryHandle handle,
    GitInteractiveRebasePlan plan,
  ) async {
    final status = await getStatus(repositoryId);
    final currentHead = await _readHeadOid(handle);
    if (currentHead == null || currentHead.isEmpty) {
      throw const GitError(
        category: GitErrorCategory.unbornBranch,
        userMessage: 'There is no commit to rebase yet.',
        diagnostic: 'interactive rebase was requested on an unborn HEAD',
        retryable: false,
      );
    }

    final planIssues = plan.validationIssues;
    String? upstreamHead;
    if (!plan.options.root &&
        plan.upstreamRevision != null &&
        planIssues.every(
          (issue) =>
              issue.kind != GitInteractiveRebaseIssueKind.upstreamRequired &&
              issue.kind != GitInteractiveRebaseIssueKind.rootHasUpstream &&
              issue.kind != GitInteractiveRebaseIssueKind.invalidUpstream,
        )) {
      upstreamHead = await _resolveCommit(handle, plan.upstreamRevision!);
    }

    final expectedCommitOids = upstreamHead == null && !plan.options.root
        ? const <String>[]
        : await _readInteractiveRebaseRange(
            handle,
            currentHead,
            upstreamHead,
            root: plan.options.root,
          );
    final commitsToInspect = expectedCommitOids.isNotEmpty
        ? expectedCommitOids
        : plan.entries
              .map((entry) => entry.originalOid)
              .where(_isCommitOid)
              .toList(growable: false);
    final mergeCommitCount = commitsToInspect.isEmpty
        ? 0
        : await _readMergeCommitCount(handle, commitsToInspect);

    final planOids = plan.entries.map((entry) => entry.originalOid).toSet();
    final expectedOids = expectedCommitOids.toSet();
    final matchesCapturedRange =
        plan.isValid &&
        expectedCommitOids.length == plan.entries.length &&
        planOids.length == expectedOids.length &&
        planOids.containsAll(expectedOids);
    final upstreamIsAncestor =
        plan.options.root ||
        (upstreamHead != null &&
            await _isAncestor(handle, upstreamHead, currentHead));
    final operation = await _readConflictOperation(handle);
    final trackingHead = status.branch.upstream == null
        ? null
        : await _tryResolve(handle, '@{upstream}');
    final pushedCommits = await _hasPushedInteractiveRebaseCommits(
      handle,
      currentHead,
      upstreamHead,
      trackingHead,
      expectedCommitOids.length,
      root: plan.options.root,
    );
    final optionLimitations = <String>[
      if (plan.options.root) 'Root mode rewrites every reachable commit, so the complete history must be loaded and remain linear.',
      if (plan.options.autosquash) 'Autosquash only moves existing squash!/fixup! commits; it does not create those messages.',
      if (plan.options.updateRefs) 'Update refs may move local branches pointing into the rewritten range; branches checked out in another worktree are left unchanged by Git.',
    ];
    final branch = status.branch.head;
    final fingerprint = hashGitObjectBytes(
      utf8.encode(
        [
          status.contentHash,
          currentHead,
          upstreamHead ?? '',
          trackingHead ?? '',
          branch ?? '',
          operation?.operation.name ?? 'idle',
          expectedCommitOids.join(','),
          plan.queryKey,
        ].join('\u0000'),
      ),
    );

    String? blockingMessage;
    if (planIssues.isNotEmpty) {
      blockingMessage = planIssues.first.message;
    } else if (operation != null) {
      blockingMessage =
          'Finish or abort the in-progress ${operation.operation.name} operation first.';
    } else if (status.branch.isDetached) {
      blockingMessage = 'Switch to a branch before rewriting its history.';
    } else if (_protectedRollbackBranches.contains(branch)) {
      blockingMessage =
          'Interactive rebase is blocked on protected branches such as main.';
    } else if (pushedCommits) {
      blockingMessage =
          'This rebase would rewrite commits that are already pushed.';
    } else if (!status.isClean) {
      blockingMessage =
          'Commit or stash local changes before rewriting history.';
    } else if (mergeCommitCount > 0) {
      blockingMessage = 'Interactive rebase is limited to a linear commit range; merge commits are not supported yet.';
    } else if (!upstreamIsAncestor) {
      blockingMessage =
          'The selected upstream is not an ancestor of the current branch.';
    } else if (expectedCommitOids.isEmpty) {
      blockingMessage =
          'The selected range does not contain any commits to rebase.';
    } else if (!matchesCapturedRange) {
      blockingMessage =
          'The rebase plan does not match the current linear commit range.';
    }

    return _InteractiveRebaseInspection(
      currentBranch: branch,
      currentHead: currentHead,
      upstreamHead: upstreamHead,
      mergeCommitCount: mergeCommitCount,
      branchProtected: _protectedRollbackBranches.contains(branch),
      pushedCommits: pushedCommits,
      detachedHead: status.branch.isDetached,
      dirtyWorktree: !status.isClean,
      operationInProgress: operation?.operation,
      fingerprint: fingerprint,
      blockingMessage: blockingMessage,
      optionLimitations: optionLimitations,
    );
  }

  Future<List<String>> _readInteractiveRebaseRange(
    RepositoryHandle handle,
    String currentHead,
    String? upstreamHead, {
    required bool root,
  }) async {
    final range = root ? currentHead : '$upstreamHead..$currentHead';
    final output = await _runner.run(
      GitInvocation(
        program: gitPath,
        args: ['rev-list', '--reverse', range],
        cwd: handle.root,
        kind: GitOperationKind.read,
        outputPolicy: const OutputPolicy.capture(maxBytes: 2 * 1024 * 1024),
      ),
    );
    final oids = utf8
        .decode(output.stdout, allowMalformed: true)
        .split('\n')
        .map((oid) => oid.trim())
        .where((oid) => oid.isNotEmpty)
        .toList(growable: false);
    if (oids.any((oid) => !_isCommitOid(oid))) {
      throw const GitError(
        category: GitErrorCategory.parseFailure,
        userMessage: 'Git returned an unreadable rebase commit range.',
        diagnostic:
            'rev-list returned a non-object ID in the interactive range',
        retryable: false,
      );
    }
    return oids;
  }

  Future<int> _readMergeCommitCount(
    RepositoryHandle handle,
    Iterable<String> commitOids,
  ) async {
    final oids = commitOids.toList(growable: false);
    if (oids.isEmpty) return 0;
    final output = await _runner.run(
      GitInvocation(
        program: gitPath,
        args: ['rev-list', '--parents', '--no-walk=unsorted', ...oids],
        cwd: handle.root,
        kind: GitOperationKind.read,
        outputPolicy: const OutputPolicy.capture(maxBytes: 512 * 1024),
      ),
    );
    var mergeCount = 0;
    for (final line in utf8.decode(output.stdout).split('\n')) {
      if (line.trim().isEmpty) continue;
      if (line.trim().split(RegExp(r'\s+')).length > 2) mergeCount++;
    }
    return mergeCount;
  }

  Future<bool> _isAncestor(
    RepositoryHandle handle,
    String ancestor,
    String descendant,
  ) async {
    try {
      await _runner.run(
        GitInvocation(
          program: gitPath,
          args: ['merge-base', '--is-ancestor', ancestor, descendant],
          cwd: handle.root,
          kind: GitOperationKind.read,
          outputPolicy: const OutputPolicy.capture(maxBytes: 128),
        ),
      );
      return true;
    } on GitError catch (error) {
      if (error.category == GitErrorCategory.processFailed &&
          error.exitCode == 1) {
        return false;
      }
      rethrow;
    }
  }

  Future<bool> _hasPushedInteractiveRebaseCommits(
    RepositoryHandle handle,
    String currentHead,
    String? upstreamHead,
    String? trackingHead,
    int selectedCommitCount, {
    required bool root,
  }) async {
    if (trackingHead == null || selectedCommitCount == 0) return false;
    final total = root
        ? await _readReachableCommitCount(handle, currentHead)
        : selectedCommitCount;
    if (total == 0) return false;
    final unpushed = root
        ? await _readReachableCommitCountExcluding(
            handle,
            currentHead,
            trackingHead,
          )
        : upstreamHead == null
        ? 0
        : await _readCommitCountExcluding(
            handle,
            upstreamHead,
            currentHead,
            trackingHead,
          );
    return unpushed < total;
  }

  Future<int> _readReachableCommitCount(
    RepositoryHandle handle,
    String head,
  ) async {
    final output = await _runner.run(
      GitInvocation(
        program: gitPath,
        args: ['rev-list', '--count', head],
        cwd: handle.root,
        kind: GitOperationKind.read,
        outputPolicy: const OutputPolicy.capture(maxBytes: 4 * 1024),
      ),
    );
    return int.tryParse(utf8.decode(output.stdout).trim()) ?? 0;
  }

  Future<int> _readReachableCommitCountExcluding(
    RepositoryHandle handle,
    String head,
    String excludedHead,
  ) async {
    final output = await _runner.run(
      GitInvocation(
        program: gitPath,
        args: ['rev-list', '--count', head, '--not', excludedHead],
        cwd: handle.root,
        kind: GitOperationKind.read,
        outputPolicy: const OutputPolicy.capture(maxBytes: 4 * 1024),
      ),
    );
    return int.tryParse(utf8.decode(output.stdout).trim()) ?? 0;
  }

  Future<GitHistoryRollbackPreview> previewUndo(RepositoryId repositoryId) =>
      previewHistoryRollback(
        repositoryId,
        const GitHistoryRollbackRequest(action: GitHistoryRollbackAction.undo),
      );

  Future<GitHistoryRollbackPreview> previewRevert(
    RepositoryId repositoryId,
    Iterable<String> revisions,
  ) => previewHistoryRollback(
    repositoryId,
    GitHistoryRollbackRequest(
      action: GitHistoryRollbackAction.revert,
      revisions: revisions.toList(growable: false),
    ),
  );

  Future<GitHistoryBatchPreview> previewHistoryBatch(
    RepositoryId repositoryId,
    GitHistoryBatchRequest request,
  ) async {
    final handle = await state.lookup(repositoryId);
    final inspection = await _inspectHistoryBatch(
      repositoryId,
      handle,
      request,
    );
    GitBranchPreviewToken? token;
    if (inspection.blockingMessage == null) {
      token = state.issueHistoryBatchPreview(
        repositoryId: repositoryId,
        request: request,
        fingerprint: inspection.fingerprint,
      );
    }
    return GitHistoryBatchPreview(
      repositoryId: repositoryId,
      request: request,
      currentBranch: inspection.currentBranch,
      currentHead: inspection.currentHead,
      targetBranch: inspection.targetBranch,
      displayedOids: inspection.displayedOids,
      executionOids: inspection.executionOids,
      executionDirection: inspection.executionDirection,
      dirtyWorktree: inspection.dirtyWorktree,
      detachedHead: inspection.detachedHead,
      operationInProgress: inspection.operationInProgress,
      duplicateOids: inspection.duplicateOids,
      containedOids: inspection.containedOids,
      mergeCommitOids: inspection.mergeCommitOids,
      mergeMainlineRequired: inspection.mergeMainlineRequired,
      impactedPaths: inspection.impactedPaths,
      fingerprint: inspection.fingerprint,
      requiresConfirmation: true,
      token: token?.value,
      expiresAt: token?.expiresAt,
      blockingMessage: inspection.blockingMessage,
    );
  }

  Future<GitHistoryBatchResult> executeHistoryBatch(
    RepositoryId repositoryId,
    GitHistoryBatchPreview preview, {
    GitCancellationToken? cancellationToken,
  }) async {
    return state.runMutation(repositoryId, () async {
      final handle = await state.lookup(repositoryId);
      final inspection = await _inspectHistoryBatch(
        repositoryId,
        handle,
        preview.request,
      );
      _throwIfHistoryBatchBlocked(inspection);
      state.validateHistoryBatchPreview(
        repositoryId: repositoryId,
        preview: preview,
        fingerprint: inspection.fingerprint,
      );
      if (preview.token case final token?) {
        state.consumeHistoryBatchPreview(token);
      }
      return _executeHistoryBatchSequence(
        repositoryId: repositoryId,
        handle: handle,
        request: preview.request,
        targetBranch: inspection.targetBranch!,
        executionOids: inspection.executionOids,
        allExecutionOids: inspection.executionOids,
        completedOids: const [],
        skippedOids: const [],
        previousHead: inspection.currentHead,
        cancellationToken: cancellationToken,
      );
    });
  }

  Future<GitHistoryBatchResult> recoverHistoryBatch(
    RepositoryId repositoryId,
    GitHistoryBatchRecoveryRequest request, {
    GitCancellationToken? cancellationToken,
  }) async {
    return state.runMutation(repositoryId, () async {
      final handle = await state.lookup(repositoryId);
      final status = await getStatus(repositoryId);
      final currentHead = await _readHeadOid(handle) ?? '';
      final operation = await _detectBranchOperation(handle);
      final sequencerInProgress =
          operation != null || await _gitPathExists(handle.root, 'REVERT_HEAD');
      final fingerprint = _historyBatchRecoveryFingerprint(
        status: status,
        currentHead: currentHead,
        request: request.request,
        executionOids: request.executionOids,
      );
      state.validateHistoryBatchContinuation(
        repositoryId: repositoryId,
        request: request,
        fingerprint: fingerprint,
      );
      state.consumeHistoryBatchContinuation(request.continuationToken);

      if (request.recoveryAction ==
          GitHistoryBatchRecoveryAction.abortRemaining) {
        return _historyBatchResult(
          repositoryId: repositoryId,
          request: request.request,
          state: GitHistoryBatchState.aborted,
          status: status,
          previousHead: currentHead,
          currentOid: request.currentOid,
          completedOids: request.completedOids,
          skippedOids: request.skippedOids,
          remainingOids: request.remainingOids,
          summary: 'The remaining batch commits were not applied.',
        );
      }

      if (request.recoveryAction ==
          GitHistoryBatchRecoveryAction.continueRemaining) {
        if (sequencerInProgress) {
          throw const GitError(
            category: GitErrorCategory.operationInProgress,
            userMessage: 'Recover the current Git operation before continuing.',
            diagnostic: 'batch remainder was requested while a sequencer operation remained active',
            retryable: true,
          );
        }
        return _executeHistoryBatchSequence(
          repositoryId: repositoryId,
          handle: handle,
          request: request.request,
          targetBranch: request.targetBranch,
          executionOids: request.remainingOids,
          allExecutionOids: request.executionOids,
          completedOids: request.completedOids,
          skippedOids: request.skippedOids,
          previousHead: currentHead,
          cancellationToken: cancellationToken,
        );
      }

      if (!sequencerInProgress) {
        throw const GitError(
          category: GitErrorCategory.operationInProgress,
          userMessage: 'There is no in-progress batch commit to recover.',
          diagnostic:
              'batch recovery was requested without a Git sequencer operation',
          retryable: false,
        );
      }
      final recoveryArgs = switch (request.recoveryAction) {
        GitHistoryBatchRecoveryAction.continueCurrent => [
          request.action == GitHistoryBatchAction.cherryPick
              ? 'cherry-pick'
              : 'revert',
          '--continue',
        ],
        GitHistoryBatchRecoveryAction.skipCurrent => [
          request.action == GitHistoryBatchAction.cherryPick
              ? 'cherry-pick'
              : 'revert',
          '--skip',
        ],
        GitHistoryBatchRecoveryAction.abortCurrent => [
          request.action == GitHistoryBatchAction.cherryPick
              ? 'cherry-pick'
              : 'revert',
          '--abort',
        ],
        GitHistoryBatchRecoveryAction.continueRemaining ||
        GitHistoryBatchRecoveryAction.abortRemaining => const <String>[],
      };
      if (request.recoveryAction ==
          GitHistoryBatchRecoveryAction.abortCurrent) {
        await _runHistoryBatchRecovery(
          handle,
          recoveryArgs,
          cancellationToken: cancellationToken,
        );
        return _historyBatchResult(
          repositoryId: repositoryId,
          request: request.request,
          state: GitHistoryBatchState.aborted,
          status: await getStatus(repositoryId),
          previousHead: currentHead,
          currentOid: request.currentOid,
          completedOids: request.completedOids,
          skippedOids: request.skippedOids,
          remainingOids: [request.currentOid, ...request.remainingOids],
          summary: 'The current batch operation was aborted.',
        );
      }

      await _runHistoryBatchRecovery(
        handle,
        recoveryArgs,
        cancellationToken: cancellationToken,
      );
      final after = await getStatus(repositoryId);
      final afterHead = await _readHeadOid(handle) ?? currentHead;
      final completed = [...request.completedOids];
      final skipped = [...request.skippedOids];
      if (request.recoveryAction ==
          GitHistoryBatchRecoveryAction.continueCurrent) {
        completed.add(request.currentOid);
      } else {
        skipped.add(request.currentOid);
      }
      final afterFingerprint = _historyBatchRecoveryFingerprint(
        status: after,
        currentHead: afterHead,
        request: request.request,
        executionOids: request.executionOids,
      );
      final continuationRequest = GitHistoryBatchRecoveryRequest(
        action: request.action,
        revisions: request.revisions,
        executionOids: request.executionOids,
        completedOids: completed,
        skippedOids: skipped,
        currentOid: request.currentOid,
        remainingOids: request.remainingOids,
        targetBranch: request.targetBranch,
        mainlines: request.mainlines,
        selectionFingerprint: afterFingerprint,
        recoveryAction: GitHistoryBatchRecoveryAction.continueRemaining,
        continuationToken: '',
      );
      final continuationToken = state.issueHistoryBatchContinuation(
        repositoryId: repositoryId,
        requestKey: continuationRequest.queryKey,
        fingerprint: afterFingerprint,
        completedOids: completed,
        skippedOids: skipped,
        currentOid: request.currentOid,
        remainingOids: request.remainingOids,
      );
      return _historyBatchResult(
        repositoryId: repositoryId,
        request: request.request,
        state: GitHistoryBatchState.readyToContinue,
        status: after,
        previousHead: currentHead,
        currentOid: request.currentOid,
        completedOids: completed,
        skippedOids: skipped,
        remainingOids: request.remainingOids,
        continuationToken: continuationToken,
        selectionFingerprint: afterFingerprint,
        recoveryActions: const [
          GitHistoryBatchRecoveryAction.continueRemaining,
          GitHistoryBatchRecoveryAction.abortRemaining,
        ],
        summary: 'The current commit was recovered. Choose whether to continue the remaining batch.',
      );
    });
  }

  Future<GitHistoryBatchResult> _executeHistoryBatchSequence({
    required RepositoryId repositoryId,
    required RepositoryHandle handle,
    required GitHistoryBatchRequest request,
    required String targetBranch,
    required List<String> executionOids,
    required List<String> allExecutionOids,
    required List<String> completedOids,
    required List<String> skippedOids,
    required String previousHead,
    GitCancellationToken? cancellationToken,
  }) async {
    final completed = [...completedOids];
    final skipped = [...skippedOids];
    for (var index = 0; index < executionOids.length; index++) {
      final oid = executionOids[index];
      final remaining = executionOids.sublist(index + 1);
      if (cancellationToken?.isCancelled == true) {
        return _historyBatchResult(
          repositoryId: repositoryId,
          request: request,
          state: GitHistoryBatchState.cancelled,
          status: await getStatus(repositoryId),
          previousHead: previousHead,
          currentOid: oid,
          completedOids: completed,
          skippedOids: skipped,
          remainingOids: [oid, ...remaining],
          summary: 'The batch was cancelled before the next commit.',
        );
      }
      try {
        await _runner.run(
          GitInvocation(
            program: gitPath,
            args: _historyBatchStepArgs(request, oid),
            cwd: handle.root,
            kind: GitOperationKind.mutation,
            outputPolicy: const OutputPolicy.capture(maxBytes: 512 * 1024),
            cancellationToken: cancellationToken,
            environment: const {'GIT_EDITOR': ':'},
          ),
        );
        completed.add(oid);
      } on GitError catch (error) {
        final mapped = _mapHistoryRollbackError(error);
        final status = await getStatus(repositoryId);
        final currentHead = await _readHeadOid(handle) ?? previousHead;
        final operation = await _detectBranchOperation(handle);
        final sequencerInProgress =
            operation == GitBranchOperation.cherryPick ||
            await _gitPathExists(handle.root, 'REVERT_HEAD');
        if (sequencerInProgress) {
          final conflictFingerprint = _historyBatchRecoveryFingerprint(
            status: status,
            currentHead: currentHead,
            request: request,
            executionOids: allExecutionOids,
          );
          final recoveryRequest = GitHistoryBatchRecoveryRequest(
            action: request.action,
            revisions: request.revisions,
            executionOids: allExecutionOids,
            completedOids: completed,
            skippedOids: skipped,
            currentOid: oid,
            remainingOids: remaining,
            targetBranch: targetBranch,
            mainlines: request.mainlines,
            selectionFingerprint: conflictFingerprint,
            recoveryAction: GitHistoryBatchRecoveryAction.continueCurrent,
            continuationToken: '',
          );
          final continuationToken = state.issueHistoryBatchContinuation(
            repositoryId: repositoryId,
            requestKey: recoveryRequest.queryKey,
            fingerprint: conflictFingerprint,
            completedOids: completed,
            skippedOids: skipped,
            currentOid: oid,
            remainingOids: remaining,
          );
          final cancelled = mapped.category == GitErrorCategory.cancelled;
          final conflicted = mapped.category == GitErrorCategory.mergeConflict;
          final stoppedState = cancelled
              ? GitHistoryBatchState.cancelled
              : conflicted
              ? GitHistoryBatchState.conflicted
              : GitHistoryBatchState.failed;
          return _historyBatchResult(
            repositoryId: repositoryId,
            request: request,
            state: stoppedState,
            status: status,
            previousHead: previousHead,
            currentOid: oid,
            completedOids: completed,
            skippedOids: skipped,
            remainingOids: [oid, ...remaining],
            continuationToken: continuationToken,
            selectionFingerprint: conflictFingerprint,
            recoveryActions: const [
              GitHistoryBatchRecoveryAction.continueCurrent,
              GitHistoryBatchRecoveryAction.skipCurrent,
              GitHistoryBatchRecoveryAction.abortCurrent,
            ],
            summary: cancelled
                ? 'The batch was cancelled while applying a commit. Recover the current operation explicitly.'
                : conflicted
                ? 'Git stopped on a conflict. Recover the current commit before continuing the batch.'
                : '${request.action.label} stopped on $oid: ${mapped.userMessage} Recover the current operation explicitly.',
          );
        }
        final stoppedState = mapped.category == GitErrorCategory.cancelled
            ? GitHistoryBatchState.cancelled
            : GitHistoryBatchState.failed;
        return _historyBatchResult(
          repositoryId: repositoryId,
          request: request,
          state: stoppedState,
          status: status,
          previousHead: previousHead,
          currentOid: oid,
          completedOids: completed,
          skippedOids: skipped,
          remainingOids: [oid, ...remaining],
          summary:
              '${request.action.label} stopped on $oid: ${mapped.userMessage}',
        );
      }
    }
    final status = await getStatus(repositoryId);
    return _historyBatchResult(
      repositoryId: repositoryId,
      request: request,
      state: GitHistoryBatchState.completed,
      status: status,
      previousHead: previousHead,
      currentOid: null,
      completedOids: completed,
      skippedOids: skipped,
      remainingOids: const [],
      summary:
          '${request.action.label} completed for ${completed.length + skipped.length} reviewed commit(s).',
    );
  }

  Future<void> _runHistoryBatchRecovery(
    RepositoryHandle handle,
    List<String> args, {
    GitCancellationToken? cancellationToken,
  }) async {
    try {
      await _runner.run(
        GitInvocation(
          program: gitPath,
          args: args,
          cwd: handle.root,
          kind: GitOperationKind.mutation,
          outputPolicy: const OutputPolicy.capture(maxBytes: 512 * 1024),
          cancellationToken: cancellationToken,
          environment: const {'GIT_EDITOR': ':'},
        ),
      );
    } on GitError catch (error, stackTrace) {
      Error.throwWithStackTrace(_mapHistoryRollbackError(error), stackTrace);
    }
  }

  List<String> _historyBatchStepArgs(
    GitHistoryBatchRequest request,
    String oid,
  ) {
    final command = request.action == GitHistoryBatchAction.cherryPick
        ? 'cherry-pick'
        : 'revert';
    final mainline = request.mainlines[oid];
    return [
      command,
      '--no-edit',
      if (mainline != null) ...['-m', '$mainline'],
      oid,
    ];
  }

  GitHistoryBatchResult _historyBatchResult({
    required RepositoryId repositoryId,
    required GitHistoryBatchRequest request,
    required GitHistoryBatchState state,
    required GitStatusSnapshot status,
    required String previousHead,
    required String? currentOid,
    required List<String> completedOids,
    required List<String> skippedOids,
    required List<String> remainingOids,
    required String summary,
    List<GitHistoryBatchRecoveryAction> recoveryActions = const [],
    String? continuationToken,
    String selectionFingerprint = '',
  }) {
    return GitHistoryBatchResult(
      repositoryId: repositoryId,
      request: request,
      state: state,
      status: status,
      previousHead: previousHead,
      resultingHead: status.branch.oid ?? previousHead,
      completedOids: completedOids,
      skippedOids: skippedOids,
      currentOid: currentOid,
      remainingOids: remainingOids,
      summary: summary,
      recoveryActions: recoveryActions,
      selectionFingerprint: selectionFingerprint,
      continuationToken: continuationToken,
    );
  }

  Future<_HistoryBatchInspection> _inspectHistoryBatch(
    RepositoryId repositoryId,
    RepositoryHandle handle,
    GitHistoryBatchRequest request,
  ) async {
    if (request.revisions.isEmpty || request.revisions.length > 50) {
      throw const GitError(
        category: GitErrorCategory.invalidRevision,
        userMessage: 'Select between 1 and 50 commits for a batch operation.',
        diagnostic:
            'history batch revision count was outside the bounded range',
        retryable: false,
      );
    }
    final status = await getStatus(repositoryId);
    final currentHead = await _readHeadOid(handle);
    if (currentHead == null || currentHead.isEmpty) {
      throw const GitError(
        category: GitErrorCategory.unbornBranch,
        userMessage: 'Create a commit before starting a history batch.',
        diagnostic: 'history batch preview was requested without a HEAD',
        retryable: false,
      );
    }
    final currentBranch = status.branch.head;
    final targetBranch = request.targetBranch?.trim().isEmpty == true
        ? currentBranch
        : request.targetBranch?.trim() ?? currentBranch;
    if (targetBranch != null && !status.branch.isDetached) {
      _validateBranchName(targetBranch);
      await _validateBranchNameWithGit(handle, targetBranch);
    }
    final displayedOids = <String>[];
    for (final revision in request.revisions) {
      if (!_isCommitOid(revision)) {
        throw const GitError(
          category: GitErrorCategory.invalidRevision,
          userMessage: 'Batch selections must use full commit IDs.',
          diagnostic: 'history batch request contained a short, non-hex, or malformed commit ID',
          retryable: false,
        );
      }
      final resolved = await _resolveCommit(handle, revision);
      if (resolved.toLowerCase() != revision.toLowerCase()) {
        throw const GitError(
          category: GitErrorCategory.staleRollbackPreview,
          userMessage:
              'A selected commit changed. Refresh History and try again.',
          diagnostic:
              'history batch full commit ID resolved to a different object',
          retryable: true,
        );
      }
      displayedOids.add(resolved);
    }
    final duplicateOids = <String>[];
    final seen = <String>{};
    for (final oid in displayedOids) {
      if (!seen.add(oid)) duplicateOids.add(oid);
    }
    final parentCounts = await _readBatchParentCounts(handle, displayedOids);
    final mergeCommitOids = [
      for (final oid in displayedOids)
        if ((parentCounts[oid] ?? 0) > 1) oid,
    ];
    final mergeMainlineRequired = [
      for (final oid in mergeCommitOids)
        if (!_validBatchMainline(request.mainlines[oid], parentCounts[oid]!))
          oid,
    ];
    final containedOids = <String>[];
    if (request.action == GitHistoryBatchAction.cherryPick) {
      for (final oid in displayedOids) {
        if (await _isAncestor(handle, oid, currentHead)) containedOids.add(oid);
      }
    }
    final executionDirection =
        request.action == GitHistoryBatchAction.cherryPick
        ? GitHistoryBatchExecutionDirection.oldestToNewest
        : GitHistoryBatchExecutionDirection.newestToOldest;
    final executionOids = request.action == GitHistoryBatchAction.cherryPick
        ? displayedOids.reversed.toList(growable: false)
        : List<String>.of(displayedOids, growable: false);
    final impactedPaths = await _readHistoryBatchImpactPaths(
      repositoryId,
      displayedOids,
    );
    final fingerprint = _historyBatchStateFingerprint(
      status: status,
      currentHead: currentHead,
      request: request,
      executionOids: executionOids,
    );
    String? blockingMessage;
    final operationInProgress = await _detectBranchOperation(handle);
    if (currentBranch == null || status.branch.isDetached) {
      blockingMessage = 'Switch to a branch before starting a history batch.';
    } else if (targetBranch != currentBranch) {
      blockingMessage = 'The target branch must be the current branch.';
    } else if (status.changes.isNotEmpty) {
      blockingMessage = 'Commit or stash local changes before the batch.';
    } else if (operationInProgress != null) {
      blockingMessage = 'Finish or abort the in-progress Git operation first.';
    } else if (duplicateOids.isNotEmpty) {
      blockingMessage = 'Remove duplicate commits from the batch selection.';
    } else if (containedOids.isNotEmpty) {
      blockingMessage =
          'Some selected commits are already contained in the current branch.';
    } else if (mergeMainlineRequired.isNotEmpty) {
      blockingMessage =
          'Choose a mainline parent for each selected merge commit.';
    }
    return _HistoryBatchInspection(
      currentBranch: currentBranch,
      currentHead: currentHead,
      targetBranch: targetBranch,
      displayedOids: displayedOids,
      executionOids: executionOids,
      executionDirection: executionDirection,
      dirtyWorktree: !status.isClean,
      detachedHead: status.branch.isDetached,
      operationInProgress: operationInProgress,
      duplicateOids: duplicateOids,
      containedOids: containedOids,
      mergeCommitOids: mergeCommitOids,
      mergeMainlineRequired: mergeMainlineRequired,
      impactedPaths: impactedPaths,
      fingerprint: fingerprint,
      blockingMessage: blockingMessage,
    );
  }

  Future<Map<String, int>> _readBatchParentCounts(
    RepositoryHandle handle,
    Iterable<String> oids,
  ) async {
    final requested = oids.toList(growable: false);
    final output = await _runner.run(
      GitInvocation(
        program: gitPath,
        args: ['rev-list', '--parents', '--no-walk=unsorted', ...requested],
        cwd: handle.root,
        kind: GitOperationKind.read,
        outputPolicy: const OutputPolicy.capture(maxBytes: 512 * 1024),
      ),
    );
    final counts = <String, int>{};
    for (final line
        in utf8.decode(output.stdout, allowMalformed: true).split('\n')) {
      final fields = line.trim().split(RegExp(r'\s+'));
      if (fields.isEmpty || fields.first.isEmpty) continue;
      counts[fields.first] = fields.length - 1;
    }
    if (counts.length != requested.toSet().length) {
      throw const GitError(
        category: GitErrorCategory.parseFailure,
        userMessage: 'Git returned incomplete batch commit metadata.',
        diagnostic: 'rev-list did not return every selected batch commit',
        retryable: true,
      );
    }
    return counts;
  }

  Future<List<String>> _readHistoryBatchImpactPaths(
    RepositoryId repositoryId,
    Iterable<String> oids,
  ) async {
    final paths = <String>{};
    for (final oid in oids) {
      final changes = await getCommitFiles(repositoryId, oid);
      for (final change in changes) {
        paths.add(change.path);
        if (change.oldPath case final oldPath?) paths.add(oldPath);
      }
    }
    final result = paths.toList()..sort();
    return result;
  }

  String _historyBatchStateFingerprint({
    required GitStatusSnapshot status,
    required String currentHead,
    required GitHistoryBatchRequest request,
    required Iterable<String> executionOids,
  }) {
    return hashGitObjectBytes(
      utf8.encode(
        [
          status.contentHash,
          currentHead,
          status.branch.head ?? '',
          request.action.name,
          request.targetBranch ?? status.branch.head ?? '',
          ...request.revisions,
          ...executionOids,
          for (final entry
              in request.mainlines.entries.toList()
                ..sort((left, right) => left.key.compareTo(right.key)))
            '${entry.key}:${entry.value}',
        ].join('\u0000'),
      ),
    );
  }

  String _historyBatchRecoveryFingerprint({
    required GitStatusSnapshot status,
    required String currentHead,
    required GitHistoryBatchRequest request,
    required Iterable<String> executionOids,
  }) {
    return hashGitObjectBytes(
      utf8.encode(
        [
          currentHead,
          status.branch.head ?? '',
          request.action.name,
          request.targetBranch ?? status.branch.head ?? '',
          ...request.revisions,
          ...executionOids,
          for (final entry
              in request.mainlines.entries.toList()
                ..sort((left, right) => left.key.compareTo(right.key)))
            '${entry.key}:${entry.value}',
        ].join('\u0000'),
      ),
    );
  }

  bool _validBatchMainline(int? mainline, int parentCount) =>
      parentCount <= 1 ||
      mainline != null && mainline >= 1 && mainline <= parentCount;

  void _throwIfHistoryBatchBlocked(_HistoryBatchInspection inspection) {
    final message = inspection.blockingMessage;
    if (message == null) return;
    final category = inspection.operationInProgress != null
        ? GitErrorCategory.operationInProgress
        : inspection.detachedHead
        ? GitErrorCategory.detachedHead
        : inspection.dirtyWorktree
        ? GitErrorCategory.dirtyWorktree
        : GitErrorCategory.historyRollbackNotAllowed;
    throw GitError(
      category: category,
      userMessage: message,
      diagnostic: 'history batch preview was blocked before mutation',
      retryable: true,
    );
  }

  Future<_HistoryRollbackInspection> _inspectHistoryRollback(
    RepositoryId repositoryId,
    RepositoryHandle handle,
    GitHistoryRollbackRequest request,
  ) async {
    _validateHistoryRollbackRequest(request);
    final state = await _inspectHistoryRollbackState(
      repositoryId,
      handle,
      request,
    );
    var targetHead = state.currentHead;
    var revisionOids = <String>[];
    if (request.action == GitHistoryRollbackAction.reset) {
      _validateRevisionInput(request.targetRevision!);
      targetHead = await _resolveCommit(handle, request.targetRevision!);
    } else if (request.action == GitHistoryRollbackAction.undo) {
      targetHead = await _resolveCommit(handle, 'HEAD^');
    } else {
      revisionOids = [
        for (final revision in request.revisions)
          await _resolveCommit(handle, revision),
      ];
    }

    final commitsMoved = request.action == GitHistoryRollbackAction.revert
        ? revisionOids.length
        : await _readCommitCount(handle, targetHead, state.currentHead);
    final pushed = request.action == GitHistoryRollbackAction.revert
        ? false
        : await _hasPushedCommits(
            handle,
            targetHead,
            state.currentHead,
            state.upstreamHead,
            upstreamConfigured: state.upstreamConfigured,
          );
    final statusPaths = state.trackedStatusPaths;
    final commitPaths = request.action == GitHistoryRollbackAction.revert
        ? const <String>[]
        : await _readChangedPaths(handle, targetHead, state.currentHead);
    final preservedPaths = <String>{
      if (request.action == GitHistoryRollbackAction.revert)
        ...const <String>[],
      if (request.action != GitHistoryRollbackAction.revert &&
          (request.mode == GitResetMode.soft ||
              request.mode == GitResetMode.mixed))
        ...commitPaths,
      if (request.mode != GitResetMode.hard ||
          request.action == GitHistoryRollbackAction.revert)
        ...state.unstagedPaths,
    }.toList()..sort();
    final discardedPaths = <String>[];
    if (request.action == GitHistoryRollbackAction.reset &&
        request.mode == GitResetMode.hard) {
      discardedPaths.addAll({...commitPaths, ...statusPaths});
      discardedPaths.sort();
    }
    final indexEffect = request.action == GitHistoryRollbackAction.revert
        ? GitRollbackTreeEffect.unchanged
        : request.mode == GitResetMode.soft
        ? GitRollbackTreeEffect.preserved
        : GitRollbackTreeEffect.resetToTarget;
    final worktreeEffect =
        request.action == GitHistoryRollbackAction.revert ||
            request.mode == GitResetMode.soft ||
            request.mode == GitResetMode.mixed
        ? GitRollbackTreeEffect.preserved
        : GitRollbackTreeEffect.resetToTarget;
    final impact = GitRollbackImpact(
      headBefore: state.currentHead,
      headAfter: request.action == GitHistoryRollbackAction.revert
          ? state.currentHead
          : targetHead,
      indexEffect: indexEffect,
      worktreeEffect: worktreeEffect,
      stagedPathsBefore: state.stagedPaths,
      unstagedPathsBefore: state.unstagedPaths,
      potentiallyDiscardedPaths: discardedPaths,
      preservedPaths: preservedPaths,
      commitsMoved: commitsMoved,
    );
    final fingerprint = hashGitObjectBytes(
      utf8.encode(
        [
          state.status.contentHash,
          state.currentHead,
          targetHead,
          state.upstreamHead ?? '',
          state.currentBranch ?? '',
          state.operationInProgress ? 'operation' : 'idle',
          request.queryKey,
          ...revisionOids,
        ].join('\u0000'),
      ),
    );
    String? blockingMessage;
    if (state.operationInProgress) {
      blockingMessage = 'Finish or abort the in-progress Git operation first.';
    } else if (state.detachedHead) {
      blockingMessage = 'Switch to a branch before changing its history.';
    } else if (request.action != GitHistoryRollbackAction.revert &&
        state.branchProtected) {
      blockingMessage =
          'Reset and undo are blocked on protected branches such as main.';
    } else if (request.action != GitHistoryRollbackAction.revert && pushed) {
      blockingMessage =
          'This rollback would remove commits that are already pushed.';
    } else if (state.dirtyWorktree &&
        (request.action == GitHistoryRollbackAction.revert ||
            request.action == GitHistoryRollbackAction.undo ||
            request.mode != GitResetMode.soft)) {
      blockingMessage =
          'Commit or stash local changes before this history rollback.';
    } else if (request.action != GitHistoryRollbackAction.revert &&
        targetHead == state.currentHead) {
      blockingMessage = 'The selected target is already the current HEAD.';
    }
    return _HistoryRollbackInspection(
      currentBranch: state.currentBranch,
      currentHead: state.currentHead,
      targetHead: targetHead,
      upstreamHead: state.upstreamHead,
      branchProtected: state.branchProtected,
      pushedCommits: pushed,
      detachedHead: state.detachedHead,
      dirtyWorktree: state.dirtyWorktree,
      operationInProgress: state.operationInProgress,
      impact: impact,
      fingerprint: fingerprint,
      blockingMessage: blockingMessage,
      revisionOids: revisionOids,
    );
  }

  Future<_HistoryRollbackState> _inspectHistoryRollbackState(
    RepositoryId repositoryId,
    RepositoryHandle handle,
    GitHistoryRollbackRequest request,
  ) async {
    final status = await getStatus(repositoryId);
    final currentHead = await _readHeadOid(handle);
    if (currentHead == null || currentHead.isEmpty) {
      throw const GitError(
        category: GitErrorCategory.unbornBranch,
        userMessage: 'There is no commit to roll back yet.',
        diagnostic: 'history rollback requested on an unborn HEAD',
        retryable: false,
      );
    }
    final operation = await _readConflictOperation(handle);
    final upstreamHead = status.branch.upstream == null
        ? null
        : await _tryResolve(handle, '@{upstream}');
    final trackedChanges = status.changes
        .where((change) => !change.isUntracked)
        .toList(growable: false);
    final branch = status.branch.head;
    return _HistoryRollbackState(
      status: status,
      currentBranch: branch,
      currentHead: currentHead,
      upstreamHead: upstreamHead,
      upstreamConfigured: status.branch.upstream != null,
      branchProtected: _protectedRollbackBranches.contains(branch),
      pushedCommits: false,
      detachedHead: status.branch.isDetached,
      dirtyWorktree: !status.isClean,
      operationInProgress: operation != null,
      stagedPaths: trackedChanges
          .where((change) => change.isStaged)
          .map((change) => change.path)
          .toList(growable: false),
      unstagedPaths: trackedChanges
          .where((change) => change.isUnstaged)
          .map((change) => change.path)
          .toList(growable: false),
      trackedStatusPaths: trackedChanges
          .map((change) => change.path)
          .toList(growable: false),
    );
  }

  Future<bool> _hasPushedCommits(
    RepositoryHandle handle,
    String targetHead,
    String currentHead,
    String? upstreamHead, {
    required bool upstreamConfigured,
  }) async {
    if (!upstreamConfigured) return false;
    if (upstreamHead == null) return true;
    final total = await _readCommitCount(handle, targetHead, currentHead);
    if (total == 0) return false;
    final unpushed = await _readCommitCountExcluding(
      handle,
      targetHead,
      currentHead,
      upstreamHead,
    );
    return unpushed < total;
  }

  Future<int> _readCommitCountExcluding(
    RepositoryHandle handle,
    String targetHead,
    String currentHead,
    String excludedHead,
  ) async {
    final output = await _runner.run(
      GitInvocation(
        program: gitPath,
        args: [
          'rev-list',
          '--count',
          '$targetHead..$currentHead',
          '--not',
          excludedHead,
        ],
        cwd: handle.root,
        kind: GitOperationKind.read,
        outputPolicy: const OutputPolicy.capture(maxBytes: 4 * 1024),
      ),
    );
    return int.tryParse(utf8.decode(output.stdout).trim()) ?? 0;
  }

  Future<List<String>> _readChangedPaths(
    RepositoryHandle handle,
    String olderHead,
    String newerHead,
  ) async {
    final output = await _runner.run(
      GitInvocation(
        program: gitPath,
        args: ['diff', '--name-only', '-z', olderHead, newerHead, '--'],
        cwd: handle.root,
        kind: GitOperationKind.read,
        outputPolicy: const OutputPolicy.capture(maxBytes: 512 * 1024),
      ),
    );
    return _splitNulBytes(output.stdout)
        .where((bytes) => bytes.isNotEmpty)
        .map((bytes) => utf8.decode(bytes, allowMalformed: true))
        .toList(growable: false);
  }

  void _validateHistoryRollbackRequest(GitHistoryRollbackRequest request) {
    if (request.action == GitHistoryRollbackAction.reset &&
        (request.targetRevision == null || request.targetRevision!.isEmpty)) {
      throw const GitError(
        category: GitErrorCategory.invalidRevision,
        userMessage: 'Choose a commit to reset to.',
        diagnostic: 'reset request did not contain a target revision',
        retryable: false,
      );
    }
    if (request.action == GitHistoryRollbackAction.undo &&
        request.targetRevision != null) {
      throw const GitError(
        category: GitErrorCategory.invalidRevision,
        userMessage: 'Undo chooses the latest commit automatically.',
        diagnostic: 'undo request unexpectedly contained a target revision',
        retryable: false,
      );
    }
    if (request.action == GitHistoryRollbackAction.revert) {
      if (request.revisions.isEmpty || request.revisions.length > 32) {
        throw const GitError(
          category: GitErrorCategory.invalidRevision,
          userMessage: 'Choose between one and 32 commits to revert.',
          diagnostic: 'revert request exceeded the bounded commit selection',
          retryable: false,
        );
      }
      final seen = <String>{};
      for (final revision in request.revisions) {
        _validateRevisionInput(revision);
        if (!seen.add(revision)) {
          throw const GitError(
            category: GitErrorCategory.invalidRevision,
            userMessage: 'Do not select the same commit more than once.',
            diagnostic: 'revert request contained a duplicate revision',
            retryable: false,
          );
        }
      }
    }
  }

  void _throwIfHistoryRollbackBlocked(_HistoryRollbackInspection inspection) {
    final message = inspection.blockingMessage;
    if (message == null) return;
    final category = inspection.operationInProgress
        ? GitErrorCategory.operationInProgress
        : inspection.detachedHead
        ? GitErrorCategory.detachedHead
        : inspection.branchProtected
        ? GitErrorCategory.protectedBranch
        : inspection.pushedCommits
        ? GitErrorCategory.pushedHistory
        : inspection.dirtyWorktree
        ? GitErrorCategory.dirtyWorktree
        : GitErrorCategory.historyRollbackNotAllowed;
    throw GitError(
      category: category,
      userMessage: message,
      diagnostic: 'history rollback preflight rejected the request',
      retryable: false,
    );
  }

  GitHistoryRollbackResult _historyRollbackResult(
    RepositoryId repositoryId,
    GitHistoryRollbackRequest request,
    GitHistoryRollbackState state,
    GitStatusSnapshot status,
    String previousHead,
    String resultingHead,
    String summary,
    List<String> revisions,
    bool conflicted,
  ) => GitHistoryRollbackResult(
    repositoryId: repositoryId,
    request: request,
    state: state,
    status: status,
    previousHead: previousHead,
    resultingHead: resultingHead,
    summary: summary,
    revertedCommitOids: revisions,
    recoveryActions: conflicted
        ? const [
            GitHistoryRollbackRecoveryAction.continueRevert,
            GitHistoryRollbackRecoveryAction.abortRevert,
          ]
        : const [],
  );

  Future<GitHistoryPage> getHistory(
    RepositoryId repositoryId, {
    int limit = 50,
    int offset = 0,
    GitHistoryQuery? query,
  }) async {
    final effectiveQuery = query ?? GitHistoryQuery(limit: limit);
    final effectiveLimit = effectiveQuery.limit;
    final filters = effectiveQuery.filters;
    _validateHistoryQuery(effectiveQuery, legacyOffset: offset);
    final handle = await state.lookup(repositoryId);
    final requestedCursor = effectiveQuery.cursor;
    if (requestedCursor != null &&
        requestedCursor.queryKey != filters.queryKey) {
      throw const GitError(
        category: GitErrorCategory.staleOpaqueId,
        userMessage: 'History filters changed. Reload history to continue.',
        diagnostic: 'history cursor query key did not match current filters',
        retryable: true,
      );
    }
    final snapshot = requestedCursor == null
        ? await _captureHistorySnapshot(handle, filters)
        : _HistorySnapshot(
            tips: requestedCursor.snapshotTips,
            refs: requestedCursor.snapshotRefs,
          );
    final position = requestedCursor?.position ?? offset;
    // Flatten only a truly single-tip view. A repository may have one local
    // branch while stale remote refs or tags still point at another line of
    // history; using local branch count here hides that topology.
    final collapseToSingleLane =
        filters.ref.isNotEmpty || snapshot.tips.toSet().length == 1;
    final pageCursor = GitHistoryCursor(
      snapshotTips: snapshot.tips,
      snapshotRefs: snapshot.refs,
      position: position,
      queryKey: filters.queryKey,
    );
    if (snapshot.tips.isEmpty) {
      return GitHistoryPage(
        repositoryId: repositoryId,
        commits: const [],
        offset: position,
        limit: effectiveLimit,
        hasMore: false,
        collapseToSingleLane: true,
      );
    }
    final args = <String>[
      'log',
      '--no-color',
      '--format=%H%x00%P%x00%an%x00%ae%x00%aI%x00%s%x00%b%x00%G?%x00%GS%x00%GK%x00%GF%x00%x1e',
      '--date=iso-strict',
      '--topo-order',
      '--max-count=${effectiveLimit + 1}',
      '--skip=$position',
    ];
    if (filters.text.isNotEmpty) {
      args.addAll([
        '--fixed-strings',
        '--regexp-ignore-case',
        '--grep=${filters.text}',
      ]);
    }
    if (filters.author.isNotEmpty) args.add('--author=${filters.author}');
    if (filters.authoredAfter case final after?) {
      args.add('--since=${after.toUtc().toIso8601String()}');
    }
    if (filters.authoredBefore case final before?) {
      args.add('--until=${before.toUtc().toIso8601String()}');
    }
    args.addAll(snapshot.tips);
    if (filters.path.isNotEmpty) args.addAll(['--', filters.path]);
    final output = await _runner.run(
      GitInvocation(
        program: gitPath,
        args: args,
        cwd: handle.root,
        kind: GitOperationKind.read,
        outputPolicy: const OutputPolicy.capture(maxBytes: 8 * 1024 * 1024),
      ),
    );
    try {
      return parseGitHistory(
        output.stdout,
        repositoryId: repositoryId,
        offset: position,
        limit: effectiveLimit,
        cursor: pageCursor,
        snapshotRefs: snapshot.refs,
        collapseToSingleLane: collapseToSingleLane,
      );
    } on FormatException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        GitError(
          category: GitErrorCategory.parseFailure,
          userMessage: 'Git returned an unreadable history.',
          diagnostic: error.message,
          retryable: false,
        ),
        stackTrace,
      );
    }
  }

  Future<GitCommit> getCommit(
    RepositoryId repositoryId,
    String commitOid,
  ) async {
    _validateCommitOid(commitOid);
    final handle = await state.lookup(repositoryId);
    final output = await _runner.run(
      GitInvocation(
        program: gitPath,
        args: [
          'show',
          '--format=%H%x00%P%x00%an%x00%ae%x00%aI%x00%s%x00%b%x00%G?%x00%GS%x00%GK%x00%GF%x00%x1e',
          '--no-color',
          '--no-patch',
          '--date=iso-strict',
        ],
        cwd: handle.root,
        kind: GitOperationKind.read,
        outputPolicy: const OutputPolicy.capture(maxBytes: 512 * 1024),
      ),
    );
    try {
      final page = parseGitHistory(
        output.stdout,
        repositoryId: repositoryId,
        offset: 0,
        limit: 1,
      );
      if (page.commits.length != 1) throw const FormatException('no commit');
      return page.commits.single;
    } on FormatException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        GitError(
          category: GitErrorCategory.invalidRevision,
          userMessage: 'Git returned an unreadable commit.',
          diagnostic: error.message,
          retryable: false,
        ),
        stackTrace,
      );
    }
  }

  Future<List<GitCommitFileChange>> getCommitFiles(
    RepositoryId repositoryId,
    String commitOid,
  ) async {
    _validateCommitOid(commitOid);
    final handle = await state.lookup(repositoryId);
    final output = await _runner.run(
      GitInvocation(
        program: gitPath,
        args: [
          'diff-tree',
          '--root',
          '--no-commit-id',
          '--name-status',
          '-z',
          '-r',
          '-m',
          '--find-renames',
          '--find-copies',
          commitOid,
        ],
        cwd: handle.root,
        kind: GitOperationKind.read,
        outputPolicy: const OutputPolicy.capture(maxBytes: 2 * 1024 * 1024),
      ),
    );
    return _parseCommitFiles(output.stdout);
  }

  Future<GitCommitDiff> getCommitDiff(
    RepositoryId repositoryId,
    String commitOid,
    String path, {
    String? originalPath,
  }) async {
    _validateCommitOid(commitOid);
    _validatePath(path);
    if (originalPath != null) _validatePath(originalPath);
    final handle = await state.lookup(repositoryId);
    final output = await _runner.run(
      GitInvocation(
        program: gitPath,
        args: [
          'show',
          '-m',
          '--no-ext-diff',
          '--no-color',
          '--format=',
          '--find-renames',
          '--unified=3',
          commitOid,
          '--',
          path,
        ],
        cwd: handle.root,
        kind: GitOperationKind.read,
        outputPolicy: const OutputPolicy.capture(maxBytes: 8 * 1024 * 1024),
      ),
    );
    return GitCommitDiff(
      commitOid: commitOid,
      snapshot: parseUnifiedDiff(
        output.stdout,
        path: path,
        scope: GitDiffScope.commit,
      ),
    );
  }

  Future<List<GitBranch>> getBranches(RepositoryId repositoryId) async {
    final handle = await state.lookup(repositoryId);
    final output = await _runner.run(
      GitInvocation(
        program: gitPath,
        args: const [
          'for-each-ref',
          '--sort=refname',
          '--format=%(refname:short)%00%(objectname)%00%(upstream:short)%00%(HEAD)',
          'refs/heads/',
        ],
        cwd: handle.root,
        kind: GitOperationKind.read,
        outputPolicy: const OutputPolicy.capture(maxBytes: 512 * 1024),
      ),
    );
    try {
      final branches = parseGitBranches(output.stdout);
      final current = branches.where((branch) => branch.isCurrent).firstOrNull;
      if (current?.oid == null) return branches;
      final enriched = <GitBranch>[];
      for (final branch in branches) {
        if (branch.oid == null) {
          enriched.add(branch);
          continue;
        }
        final (ahead, behind) = await _readAheadBehind(
          handle,
          current!.oid,
          branch.oid,
        );
        enriched.add(
          branch.copyWith(
            relation: _branchRelation(ahead: ahead, behind: behind),
          ),
        );
      }
      return List.unmodifiable(enriched);
    } on FormatException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        GitError(
          category: GitErrorCategory.parseFailure,
          userMessage: 'Git returned an unreadable branch list.',
          diagnostic: error.message,
          retryable: false,
        ),
        stackTrace,
      );
    }
  }

  /// Reads remote-tracking refs and their local tracking relationships in one
  /// bounded snapshot. The snapshot fingerprint is used by update and
  /// checkout mutations so a moved remote ref cannot be mistaken for the ref
  /// the user reviewed.
  Future<GitRemoteBranchSnapshot> getRemoteBranchSnapshot(
    RepositoryId repositoryId,
  ) async {
    final handle = await state.lookup(repositoryId);
    final status = await getStatus(repositoryId);
    final remotes = await getRemotes(repositoryId);
    var remoteOutput = await _runner.run(
      GitInvocation(
        program: gitPath,
        args: const [
          'for-each-ref',
          '--sort=refname',
          '--format=%(refname)%00%(objectname)%00%(symref)',
          'refs/remotes/',
        ],
        cwd: handle.root,
        kind: GitOperationKind.read,
        outputPolicy: const OutputPolicy.capture(maxBytes: 2 * 1024 * 1024),
      ),
    );
    final localOutput = await _runner.run(
      GitInvocation(
        program: gitPath,
        args: const [
          'for-each-ref',
          '--sort=refname',
          '--format=%(refname:short)%00%(objectname)%00%(upstream:short)%00%(HEAD)',
          'refs/heads/',
        ],
        cwd: handle.root,
        kind: GitOperationKind.read,
        outputPolicy: const OutputPolicy.capture(maxBytes: 512 * 1024),
      ),
    );
    final tagOutput = await _runner.run(
      GitInvocation(
        program: gitPath,
        args: const [
          'for-each-ref',
          '--sort=refname',
          '--format=%(refname:short)%00%(objectname)%00%(*objectname)',
          'refs/tags/',
        ],
        cwd: handle.root,
        kind: GitOperationKind.read,
        outputPolicy: const OutputPolicy.capture(maxBytes: 512 * 1024),
      ),
    );
    late final List<GitRemoteBranch> remoteBranches;
    late final List<GitBranch> localBranches;
    try {
      remoteBranches = parseGitRemoteBranches(
        remoteOutput.stdout,
        remoteNames: remotes.map((remote) => remote.name),
      );
    } on FormatException catch (primaryError, primaryStackTrace) {
      try {
        remoteOutput = await _runner.run(
          GitInvocation(
            program: gitPath,
            args: const [
              'for-each-ref',
              '--sort=refname',
              '--format=%(refname)%00%(objectname)',
              'refs/remotes/',
            ],
            cwd: handle.root,
            kind: GitOperationKind.read,
            outputPolicy: const OutputPolicy.capture(maxBytes: 2 * 1024 * 1024),
          ),
        );
        remoteBranches = parseGitRemoteBranches(
          remoteOutput.stdout,
          remoteNames: remotes.map((remote) => remote.name),
        );
      } on Object catch (fallbackError) {
        final fallbackDiagnostic = fallbackError is GitError
            ? fallbackError.diagnostic
            : '$fallbackError';
        Error.throwWithStackTrace(
          GitError(
            category: GitErrorCategory.parseFailure,
            userMessage: 'Git returned an unreadable remote branch list.',
            diagnostic:
                'remote refs: primary=${primaryError.message}; '
                'fallback=$fallbackDiagnostic',
            retryable: false,
          ),
          primaryStackTrace,
        );
      }
    }
    try {
      localBranches = parseGitBranches(localOutput.stdout);
    } on FormatException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        GitError(
          category: GitErrorCategory.parseFailure,
          userMessage: 'Git returned an unreadable local branch list.',
          diagnostic: 'local refs: ${error.message}',
          retryable: false,
        ),
        stackTrace,
      );
    }
    final localRefs = [
      for (final branch in localBranches)
        if (branch.oid case final oid?)
          GitBranchRef(
            name: branch.name,
            oid: oid,
            upstream: branch.upstream,
            isCurrent: branch.isCurrent,
          ),
    ];
    final tags = <GitRepositoryRef>[];
    for (final rawLine
        in utf8.decode(tagOutput.stdout, allowMalformed: true).split('\n')) {
      final fields = rawLine.trimRight().split('\u0000');
      if (fields.length != 3 || fields[0].isEmpty) {
        if (rawLine.trim().isNotEmpty) {
          throw const GitError(
            category: GitErrorCategory.parseFailure,
            userMessage: 'Git returned an unreadable tag list.',
            diagnostic: 'tag ref record did not contain a name and peeled OID',
            retryable: false,
          );
        }
        continue;
      }
      final oid = fields[2].isNotEmpty ? fields[2] : fields[1];
      if (oid.isEmpty) continue;
      tags.add(GitRepositoryRef(name: fields[0], oid: oid));
    }
    final tracking = <String, String>{
      for (final branch in localBranches)
        if (branch.upstream case final upstream?)
          if (upstream.isNotEmpty) upstream: branch.name,
    };
    final linkedBranches = [
      for (final branch in remoteBranches)
        branch.copyWith(localTrackingBranch: tracking[branch.name]),
    ];
    var outgoing = 0;
    var incoming = 0;
    if (status.branch.oid case final currentOid?) {
      if (status.branch.upstream case final upstream?) {
        final upstreamBranch = linkedBranches
            .where((branch) => branch.name == upstream)
            .firstOrNull;
        if (upstreamBranch != null) {
          final counts = await _readAheadBehind(
            handle,
            upstreamBranch.oid,
            currentOid,
          );
          outgoing = counts.$1;
          incoming = counts.$2;
        }
      }
    }
    final fingerprint = hashGitObjectBytes([
      ...remoteOutput.stdout,
      ...localOutput.stdout,
      ...tagOutput.stdout,
      ...utf8.encode(status.contentHash),
    ]);
    return GitRemoteBranchSnapshot(
      repositoryId: repositoryId,
      fingerprint: fingerprint,
      currentBranch: status.branch.head,
      upstream: status.branch.upstream,
      branches: linkedBranches,
      localBranches: localRefs,
      tags: tags,
      incoming: incoming,
      outgoing: outgoing,
    );
  }

  Future<GitBranchActionResult> checkoutRemoteBranch(
    RepositoryId repositoryId,
    GitRemoteBranch branch, {
    String? localName,
  }) {
    final target = localName?.trim().isNotEmpty == true
        ? localName!.trim()
        : branch.branch;
    _validateBranchName(target);
    if (branch.isSymbolicHead || branch.name.contains('\u0000')) {
      throw const GitError(
        category: GitErrorCategory.remoteBranchNotFound,
        userMessage: 'Choose a concrete remote branch to check out.',
        diagnostic: 'a symbolic or invalid remote branch was requested',
        retryable: false,
      );
    }
    return state.runMutation(repositoryId, () async {
      final handle = await state.lookup(repositoryId);
      final remoteOid = await _readRefOid(
        handle,
        'refs/remotes/${branch.name}',
        missingCategory: GitErrorCategory.remoteBranchNotFound,
      );
      if (remoteOid != branch.oid) {
        throw const GitError(
          category: GitErrorCategory.staleRemoteRef,
          userMessage:
              'The remote branch moved. Refresh branches and try again.',
          diagnostic: 'remote-tracking branch OID changed after it was listed',
          retryable: true,
        );
      }
      await _validateBranchNameWithGit(handle, target);
      try {
        await _runner.run(
          GitInvocation(
            program: gitPath,
            args: ['switch', '--track', '--create', target, branch.name],
            cwd: handle.root,
            kind: GitOperationKind.mutation,
            outputPolicy: const OutputPolicy.capture(maxBytes: 128 * 1024),
          ),
        );
      } on GitError catch (error, stackTrace) {
        Error.throwWithStackTrace(_mapBranchError(error), stackTrace);
      }
      return GitBranchActionResult(
        repositoryId: repositoryId,
        branchName: target,
        status: await getStatus(repositoryId),
      );
    });
  }

  Future<GitRemoteBranchDeletePreview> previewRemoteBranchDelete(
    RepositoryId repositoryId,
    GitRemoteBranch branch,
  ) async {
    if (branch.isSymbolicHead) {
      throw const GitError(
        category: GitErrorCategory.remoteBranchNotFound,
        userMessage: 'A symbolic remote HEAD cannot be deleted.',
        diagnostic: 'remote branch deletion targeted a symbolic HEAD ref',
        retryable: false,
      );
    }
    final snapshot = await getRemoteBranchSnapshot(repositoryId);
    final current = snapshot.branches
        .where((candidate) => candidate.name == branch.name)
        .firstOrNull;
    if (current == null) {
      throw const GitError(
        category: GitErrorCategory.remoteBranchNotFound,
        userMessage:
            'The remote branch is no longer available. Refresh branches.',
        diagnostic: 'remote branch was not present in the current ref snapshot',
        retryable: true,
      );
    }
    final token = state.issueRemoteBranchDeletePreview(
      repositoryId: repositoryId,
      branchName: current.name,
      oid: current.oid,
      fingerprint: snapshot.fingerprint,
    );
    return GitRemoteBranchDeletePreview(
      repositoryId: repositoryId,
      branch: current,
      oid: current.oid,
      fingerprint: snapshot.fingerprint,
      token: token.value,
      expiresAt: token.expiresAt,
    );
  }

  Future<GitRemoteBranchActionResult> deleteRemoteBranch(
    RepositoryId repositoryId,
    GitRemoteBranchDeletePreview preview,
  ) => state.runMutation(repositoryId, () async {
    final handle = await state.lookup(repositoryId);
    final snapshot = await getRemoteBranchSnapshot(repositoryId);
    final current = snapshot.branches
        .where((candidate) => candidate.name == preview.branch.name)
        .firstOrNull;
    if (current == null) {
      throw const GitError(
        category: GitErrorCategory.remoteBranchNotFound,
        userMessage: 'The remote branch is no longer available.',
        diagnostic: 'remote branch disappeared before deletion',
        retryable: true,
      );
    }
    state.validateRemoteBranchDeletePreview(
      repositoryId: repositoryId,
      preview: preview,
      oid: current.oid,
      fingerprint: snapshot.fingerprint,
    );
    final remote = current.remote;
    final branchName = current.branch;
    final remoteConfig = _findRemote(await getRemotes(repositoryId), remote);
    final publishedOid = await _readRemoteBranchOid(
      handle,
      remote,
      branchName,
      remoteUrl: remoteConfig?.pushUrl ?? remoteConfig?.fetchUrl,
    );
    if (publishedOid != preview.oid) {
      throw const GitError(
        category: GitErrorCategory.staleRemoteRef,
        userMessage:
            'The remote branch moved. Refresh branches before deleting it.',
        diagnostic: 'published remote branch OID changed after it was reviewed',
        retryable: true,
      );
    }
    late final ProcessOutput output;
    try {
      output = await _runObjectCommand(
        handle,
        ['push', remote, '--delete', branchName],
        kind: GitOperationKind.remote,
        maxBytes: 512 * 1024,
        remoteUrl: remoteConfig?.pushUrl ?? remoteConfig?.fetchUrl,
      );
      await _runObjectCommand(
        handle,
        ['fetch', '--prune', remote],
        kind: GitOperationKind.remote,
        maxBytes: 512 * 1024,
        remoteUrl: remoteConfig?.fetchUrl ?? remoteConfig?.pushUrl,
      );
    } on GitError catch (error, stackTrace) {
      Error.throwWithStackTrace(_mapRemoteError(error), stackTrace);
    }
    state.consumeRemoteBranchDeletePreview(preview.token);
    final refreshed = await getRemoteBranchSnapshot(repositoryId);
    return GitRemoteBranchActionResult(
      repositoryId: repositoryId,
      branch: current,
      status: await getStatus(repositoryId),
      snapshot: refreshed,
      summary: _objectSummary(output, 'The remote branch was deleted.'),
    );
  });

  Future<GitUpdateProjectPreview> previewUpdateProject(
    RepositoryId repositoryId,
    GitUpdateProjectRequest request,
  ) async {
    if (request.phase != GitUpdatePhase.start) {
      throw const GitError(
        category: GitErrorCategory.updateNotAllowed,
        userMessage: 'Recovery actions do not need a new update preview.',
        diagnostic: 'a recovery phase was passed to update preview',
        retryable: false,
      );
    }
    final handle = await state.lookup(repositoryId);
    final status = await getStatus(repositoryId);
    final branch = status.branch.head;
    final upstream = status.branch.upstream;
    String? currentOid = status.branch.oid;
    String? upstreamOid;
    var blockingMessage = '';
    if (branch == null || status.branch.isDetached) {
      blockingMessage = 'Switch to a local branch before updating the project.';
    } else if (currentOid == null || currentOid.isEmpty) {
      blockingMessage = 'Create the first local commit before updating.';
    } else if (upstream == null || upstream.isEmpty) {
      blockingMessage = 'Set an upstream branch before updating the project.';
    } else {
      try {
        upstreamOid = await _readRefOid(
          handle,
          'refs/remotes/$upstream',
          missingCategory: GitErrorCategory.remoteBranchNotFound,
        );
      } on GitError catch (error) {
        if (error.category == GitErrorCategory.remoteBranchNotFound) {
          blockingMessage =
              'The tracked remote branch is missing. Fetch again.';
        } else {
          rethrow;
        }
      }
    }
    final dirty = !status.isClean;
    if (blockingMessage.isEmpty &&
        dirty &&
        request.localChanges == GitUpdateLocalChanges.reject) {
      blockingMessage = 'Commit or stash local changes before updating.';
    }
    if (currentOid == null || currentOid.isEmpty) currentOid = '(unborn)';
    if (upstreamOid == null || upstreamOid.isEmpty) upstreamOid = '(missing)';
    var incoming = 0;
    var outgoing = 0;
    if (blockingMessage.isEmpty) {
      final counts = await _readAheadBehind(handle, upstreamOid, currentOid);
      outgoing = counts.$1;
      incoming = counts.$2;
    }
    final fingerprint = _updateFingerprint(
      status,
      branch,
      upstream,
      currentOid,
      upstreamOid,
    );
    final token = blockingMessage.isEmpty
        ? state.issueUpdatePreview(
            repositoryId: repositoryId,
            request: request,
            fingerprint: fingerprint,
          )
        : null;
    return GitUpdateProjectPreview(
      repositoryId: repositoryId,
      request: request,
      branch: branch ?? '(detached)',
      upstream: upstream ?? '(none)',
      currentOid: currentOid,
      upstreamOid: upstreamOid,
      incoming: incoming,
      outgoing: outgoing,
      dirtyWorktree: dirty,
      requiresConfirmation: request.strategy == GitUpdateStrategy.resetToRemote,
      fingerprint: fingerprint,
      token: token?.value,
      expiresAt: token?.expiresAt,
      blockingMessage: blockingMessage.isEmpty ? null : blockingMessage,
    );
  }

  Future<GitUpdateProjectResult> executeUpdateProject(
    RepositoryId repositoryId,
    GitUpdateProjectRequest request, {
    GitCancellationToken? cancellationToken,
  }) => state.runMutation(repositoryId, () async {
    final handle = await state.lookup(repositoryId);
    final status = await getStatus(repositoryId);
    final branch = status.branch.head;
    final upstream = status.branch.upstream;
    if (branch == null || status.branch.isDetached || upstream == null) {
      throw const GitError(
        category: GitErrorCategory.updateNotAllowed,
        userMessage:
            'An attached branch with an upstream is required to update.',
        diagnostic: 'update requested without a current tracking branch',
        retryable: false,
      );
    }
    final upstreamOid = await _readRefOid(
      handle,
      'refs/remotes/$upstream',
      missingCategory: GitErrorCategory.remoteBranchNotFound,
    );
    final currentOid = status.branch.oid ?? '(unborn)';
    final fingerprint = _updateFingerprint(
      status,
      branch,
      upstream,
      currentOid,
      upstreamOid,
    );
    if (request.phase == GitUpdatePhase.start) {
      state.validateUpdatePreview(
        repositoryId: repositoryId,
        request: request,
        fingerprint: fingerprint,
      );
    } else {
      await _validateUpdateRecovery(handle, request.strategy);
    }
    var stashed = false;
    if (request.phase == GitUpdatePhase.start &&
        !status.isClean &&
        request.localChanges == GitUpdateLocalChanges.stash) {
      await _runner.run(
        GitInvocation(
          program: gitPath,
          args: const [
            'stash',
            'push',
            '--include-untracked',
            '--message=gift update',
          ],
          cwd: handle.root,
          kind: GitOperationKind.mutation,
          outputPolicy: const OutputPolicy.capture(maxBytes: 256 * 1024),
          cancellationToken: cancellationToken,
        ),
      );
      stashed = true;
    }
    final args = _updateArgs(request, upstream: upstream);
    try {
      await _runner.run(
        GitInvocation(
          program: gitPath,
          args: args,
          cwd: handle.root,
          kind: GitOperationKind.mutation,
          outputPolicy: const OutputPolicy.capture(maxBytes: 512 * 1024),
          cancellationToken: cancellationToken,
          environment: const {'GIT_EDITOR': ':'},
        ),
      );
      if (stashed) {
        await _runner.run(
          GitInvocation(
            program: gitPath,
            args: const ['stash', 'pop'],
            cwd: handle.root,
            kind: GitOperationKind.mutation,
            outputPolicy: const OutputPolicy.capture(maxBytes: 512 * 1024),
          ),
        );
      }
    } on GitError catch (error, stackTrace) {
      final afterFailure = await getStatus(repositoryId);
      if (afterFailure.conflicts.isNotEmpty &&
          request.strategy != GitUpdateStrategy.resetToRemote) {
        return GitUpdateProjectResult(
          repositoryId: repositoryId,
          request: request,
          state: GitUpdateState.conflicted,
          status: afterFailure,
          summary: 'Update paused because conflicts need to be resolved.',
          recoveryActions: const [
            GitUpdatePhase.continueOperation,
            GitUpdatePhase.abort,
          ],
        );
      }
      if (error.category == GitErrorCategory.cancelled) {
        return GitUpdateProjectResult(
          repositoryId: repositoryId,
          request: request,
          state: GitUpdateState.cancelled,
          status: afterFailure,
          summary: 'The project update was cancelled.',
        );
      }
      Error.throwWithStackTrace(_mapUpdateError(error), stackTrace);
    }
    if (request.confirmationToken case final token?) {
      state.consumeUpdatePreview(token);
    }
    final after = await getStatus(repositoryId);
    final resultState = request.phase == GitUpdatePhase.abort
        ? GitUpdateState.aborted
        : GitUpdateState.completed;
    return GitUpdateProjectResult(
      repositoryId: repositoryId,
      request: request,
      state: resultState,
      status: after,
      summary: request.phase == GitUpdatePhase.abort
          ? 'The project update was aborted.'
          : request.strategy == GitUpdateStrategy.resetToRemote
          ? 'The local branch was reset to its remote branch.'
          : 'The project was updated from its remote branch.',
    );
  });

  Future<GitBranchActionResult> createBranch(
    RepositoryId repositoryId,
    String name,
  ) => _runBranchAction(repositoryId, name, const ['switch', '--create']);

  /// Creates a branch ref at the selected full commit ID without changing
  /// the current branch. The commit is resolved again immediately before
  /// mutation so the command cannot accidentally use a visible row index or
  /// abbreviated display value.
  Future<GitBranchActionResult> createBranchAtCommit(
    RepositoryId repositoryId,
    String name,
    String commitOid,
  ) async {
    _validateBranchName(name);
    _validateFullCommitOid(commitOid);
    return state.runMutation(repositoryId, () async {
      final handle = await state.lookup(repositoryId);
      await _validateBranchNameWithGit(handle, name);
      final targetOid = await _resolveCommit(handle, commitOid);
      try {
        await _runner.run(
          GitInvocation(
            program: gitPath,
            args: ['branch', name, targetOid],
            cwd: handle.root,
            kind: GitOperationKind.mutation,
            outputPolicy: const OutputPolicy.capture(maxBytes: 128 * 1024),
          ),
        );
      } on GitError catch (error, stackTrace) {
        Error.throwWithStackTrace(_mapBranchError(error), stackTrace);
      }
      final status = await getStatus(repositoryId);
      return GitBranchActionResult(
        repositoryId: repositoryId,
        branchName: name,
        status: status,
      );
    });
  }

  Future<GitBranchActionResult> switchBranch(
    RepositoryId repositoryId,
    String name,
  ) => _runBranchAction(repositoryId, name, const ['switch']);

  Future<GitBranchActionResult> _runBranchAction(
    RepositoryId repositoryId,
    String name,
    List<String> command,
  ) async {
    // Keep the original create/switch contract while advanced operations use
    // the Git-backed validator below for their richer typed failures.
    _validateBranchName(name);
    return state.runMutation(repositoryId, () async {
      final handle = await state.lookup(repositoryId);
      await _validateBranchNameWithGit(handle, name);
      try {
        await _runner.run(
          GitInvocation(
            program: gitPath,
            args: [...command, name],
            cwd: handle.root,
            kind: GitOperationKind.mutation,
            outputPolicy: const OutputPolicy.capture(maxBytes: 128 * 1024),
          ),
        );
      } on GitError catch (error, stackTrace) {
        Error.throwWithStackTrace(_mapBranchError(error), stackTrace);
      }
      final status = await getStatus(repositoryId);
      return GitBranchActionResult(
        repositoryId: repositoryId,
        branchName: name,
        status: status,
      );
    });
  }

  /// Builds a bounded, repository-state-bound description before a branch
  /// operation can mutate anything. The preview is also the source of the
  /// token used by the corresponding start request.
  Future<GitBranchOperationPreview> previewBranchOperation(
    RepositoryId repositoryId,
    GitBranchOperationRequest request,
  ) async {
    if (request.phase != GitBranchOperationPhase.start) {
      throw const GitError(
        category: GitErrorCategory.branchOperationNotAllowed,
        userMessage: 'Recovery actions do not need a new start preview.',
        diagnostic: 'a non-start phase was passed to previewBranchOperation',
        retryable: false,
      );
    }
    final handle = await state.lookup(repositoryId);
    final inspection = await _inspectBranchOperation(
      repositoryId,
      handle,
      request,
    );
    final canCreateToken = inspection.blockingMessage == null;
    GitBranchPreviewToken? token;
    if (canCreateToken) {
      token = state.issueBranchPreview(
        repositoryId: repositoryId,
        request: request,
        fingerprint: inspection.fingerprint,
      );
    }
    return GitBranchOperationPreview(
      repositoryId: repositoryId,
      request: request,
      currentBranch: inspection.currentBranch,
      ahead: inspection.ahead,
      behind: inspection.behind,
      expectedCommits: inspection.expectedCommits,
      mergeBase: inspection.mergeBase,
      dirtyWorktree: inspection.dirtyWorktree,
      detachedHead: inspection.detachedHead,
      operationInProgress: inspection.operationInProgress,
      requiresConfirmation: true,
      token: token?.value,
      expiresAt: token?.expiresAt,
      blockingMessage: inspection.blockingMessage,
    );
  }

  /// Executes only the reviewed start request or one explicit recovery phase.
  /// A conflict is a normal result with its exact available recovery actions;
  /// callers never need to infer a command from a generic process failure.
  Future<GitBranchOperationResult> executeBranchOperation(
    RepositoryId repositoryId,
    GitBranchOperationRequest request, {
    GitCancellationToken? cancellationToken,
  }) async {
    return state.runMutation(repositoryId, () async {
      final handle = await state.lookup(repositoryId);
      final inspection = await _inspectBranchOperation(
        repositoryId,
        handle,
        request,
      );
      if (request.phase == GitBranchOperationPhase.start) {
        _throwIfBranchOperationBlocked(inspection);
        state.validateBranchPreview(
          repositoryId: repositoryId,
          request: request,
          fingerprint: inspection.fingerprint,
        );
        if (request.confirmationToken case final token?) {
          state.consumeBranchPreview(token);
        }
      } else {
        _validateRecoveryRequest(request, inspection);
      }

      final args = _branchOperationArgs(request, inspection);
      try {
        await _runner.run(
          GitInvocation(
            program: gitPath,
            args: args,
            cwd: handle.root,
            kind: GitOperationKind.mutation,
            outputPolicy: const OutputPolicy.capture(maxBytes: 512 * 1024),
            cancellationToken: cancellationToken,
          ),
        );
      } on GitError catch (error) {
        final afterFailure = await _inspectBranchOperation(
          repositoryId,
          handle,
          request,
        );
        final operationStillActive =
            afterFailure.operationInProgress == request.operation;
        if (error.category == GitErrorCategory.cancelled) {
          return _branchOperationResult(
            repositoryId,
            request,
            GitBranchOperationState.cancelled,
            await getStatus(repositoryId),
            'The operation was cancelled. Review the repository state before choosing a recovery action.',
            afterFailure.operationInProgress,
          );
        }
        if (operationStillActive) {
          return _branchOperationResult(
            repositoryId,
            request,
            GitBranchOperationState.conflicted,
            await getStatus(repositoryId),
            'Git stopped with conflicts. Resolve them, then choose an explicit recovery action.',
            afterFailure.operationInProgress,
          );
        }
        Error.throwWithStackTrace(
          _mapBranchOperationError(error),
          StackTrace.current,
        );
      }

      return _branchOperationResult(
        repositoryId,
        request,
        request.phase == GitBranchOperationPhase.abort
            ? GitBranchOperationState.aborted
            : GitBranchOperationState.completed,
        await getStatus(repositoryId),
        request.phase == GitBranchOperationPhase.abort
            ? 'The operation was aborted.'
            : 'The branch operation completed.',
        null,
      );
    });
  }

  Future<_BranchOperationInspection> _inspectBranchOperation(
    RepositoryId repositoryId,
    RepositoryHandle handle,
    GitBranchOperationRequest request,
  ) async {
    final status = await getStatus(repositoryId);
    final currentBranch = status.branch.head;
    final operationInProgress = await _detectBranchOperation(handle);
    if (request.phase != GitBranchOperationPhase.start) {
      return _inspectRecoveryOperation(
        handle,
        request,
        status,
        currentBranch,
        operationInProgress,
      );
    }
    var sourceValue = request.source?.trim();
    var target = request.target?.trim();
    if (sourceValue == null || sourceValue.isEmpty) {
      if (request.operation == GitBranchOperation.rebase &&
          currentBranch != null) {
        sourceValue = currentBranch;
      } else {
        throw const GitError(
          category: GitErrorCategory.parseFailure,
          userMessage: 'Choose a source branch or commit.',
          diagnostic: 'advanced branch operation source was missing',
          retryable: false,
        );
      }
    }
    final source = sourceValue;

    final needsAttachedHead =
        request.operation == GitBranchOperation.merge ||
        request.operation == GitBranchOperation.rebase ||
        request.operation == GitBranchOperation.cherryPick;
    if (needsAttachedHead && status.branch.isDetached) {
      return _blockedBranchOperationInspection(
        handle,
        request,
        status,
        source,
        target,
        currentBranch,
        operationInProgress,
      );
    }
    if (needsAttachedHead) {
      target ??= currentBranch;
    }

    String? sourceOid;
    String? targetOid;
    switch (request.operation) {
      case GitBranchOperation.rename:
        await _validateBranchNameWithGit(handle, source);
        final renameTarget = _requiredBranchName(target, 'new branch name');
        await _validateBranchNameWithGit(handle, renameTarget);
        sourceOid = await _requiredBranchOid(handle, source);
        targetOid = await _tryBranchOid(handle, renameTarget);
        target = renameTarget;
      case GitBranchOperation.delete:
        await _validateBranchNameWithGit(handle, source);
        sourceOid = await _requiredBranchOid(handle, source);
        if (target != null && target.isNotEmpty) {
          throw const GitError(
            category: GitErrorCategory.branchOperationNotAllowed,
            userMessage: 'Delete accepts only the branch to remove.',
            diagnostic: 'delete request unexpectedly contained a target',
            retryable: false,
          );
        }
        if (request.force == false && request.target != null) {
          throw const GitError(
            category: GitErrorCategory.branchOperationNotAllowed,
            userMessage: 'Delete accepts only the branch to remove.',
            diagnostic: 'delete request contained an empty target field',
            retryable: false,
          );
        }
      case GitBranchOperation.merge:
        await _validateBranchNameWithGit(handle, source);
        target = _requiredBranchName(target, 'target branch');
        await _validateBranchNameWithGit(handle, target);
        sourceOid = await _requiredBranchOid(handle, source);
        targetOid = await _requiredBranchOid(handle, target);
        if (!status.branch.isDetached) {
          _requireCurrentTarget(currentBranch, target);
        }
      case GitBranchOperation.rebase:
        target = _requiredBranchName(target, 'new base branch');
        await _validateBranchNameWithGit(handle, target);
        sourceOid = await _requiredBranchOid(handle, source);
        targetOid = await _requiredBranchOid(handle, target);
        if (!status.branch.isDetached) {
          _requireCurrentTarget(currentBranch, source);
        }
      case GitBranchOperation.cherryPick:
        _validateRevisionInput(source);
        target = _requiredBranchName(target, 'target branch');
        await _validateBranchNameWithGit(handle, target);
        sourceOid = await _resolveCommit(handle, source);
        targetOid = await _requiredBranchOid(handle, target);
        if (!status.branch.isDetached) {
          _requireCurrentTarget(currentBranch, target);
        }
    }

    if (request.operation != GitBranchOperation.delete && request.force) {
      throw const GitError(
        category: GitErrorCategory.branchOperationNotAllowed,
        userMessage: 'Force mode is available only for branch deletion.',
        diagnostic: 'force was set for a non-delete branch operation',
        retryable: false,
      );
    }

    final aheadBehind = await _readAheadBehind(handle, targetOid, sourceOid);
    final mergeBase = await _readMergeBase(handle, targetOid, sourceOid);
    final expectedCommits = await _readCommitCount(
      handle,
      targetOid,
      sourceOid,
    );
    final refFingerprint = await _readBranchFingerprint(handle);
    final fingerprint = [
      status.contentHash,
      status.branch.oid ?? '',
      currentBranch ?? '',
      refFingerprint,
      request.operation.name,
      source,
      target ?? '',
      sourceOid,
      targetOid ?? '',
    ].join('|');

    String? blockingMessage;
    if (operationInProgress != null) {
      blockingMessage =
          'A ${_operationLabel(operationInProgress)} operation is already in progress.';
    } else if (needsAttachedHead && status.branch.isDetached) {
      blockingMessage = 'Switch to a branch before this operation.';
    } else if (needsAttachedHead && !status.isClean) {
      blockingMessage = 'Commit or stash local changes before this operation.';
    } else if (request.operation == GitBranchOperation.delete &&
        source == currentBranch) {
      blockingMessage = 'The current branch cannot be deleted.';
    } else if (request.operation == GitBranchOperation.rename &&
        targetOid != null) {
      blockingMessage = 'That destination branch already exists.';
    }

    return _BranchOperationInspection(
      request: request,
      source: source,
      target: target,
      currentBranch: currentBranch,
      sourceOid: sourceOid,
      targetOid: targetOid,
      ahead: aheadBehind.$1,
      behind: aheadBehind.$2,
      expectedCommits: expectedCommits,
      mergeBase: mergeBase,
      dirtyWorktree: !status.isClean,
      detachedHead: status.branch.isDetached,
      operationInProgress: operationInProgress,
      fingerprint: fingerprint,
      blockingMessage: blockingMessage,
    );
  }

  Future<_BranchOperationInspection> _inspectRecoveryOperation(
    RepositoryHandle handle,
    GitBranchOperationRequest request,
    GitStatusSnapshot status,
    String? currentBranch,
    GitBranchOperation? operationInProgress,
  ) async {
    final source = request.source?.trim() ?? currentBranch ?? '';
    final target = request.target?.trim() ?? currentBranch;
    final fingerprint = [
      status.contentHash,
      currentBranch ?? '',
      await _readBranchFingerprint(handle),
      request.operation.name,
      source,
      target ?? '',
    ].join('|');
    return _BranchOperationInspection(
      request: request,
      source: source,
      target: target,
      currentBranch: currentBranch,
      sourceOid: status.branch.oid,
      targetOid: status.branch.oid,
      ahead: 0,
      behind: 0,
      expectedCommits: 0,
      mergeBase: null,
      dirtyWorktree: !status.isClean,
      detachedHead: status.branch.isDetached,
      operationInProgress: operationInProgress,
      fingerprint: fingerprint,
      blockingMessage: null,
    );
  }

  Future<_BranchOperationInspection> _blockedBranchOperationInspection(
    RepositoryHandle handle,
    GitBranchOperationRequest request,
    GitStatusSnapshot status,
    String source,
    String? target,
    String? currentBranch,
    GitBranchOperation? operationInProgress,
  ) async {
    final fingerprint = [
      status.contentHash,
      currentBranch ?? '',
      await _readBranchFingerprint(handle),
      request.operation.name,
      source,
      target ?? '',
    ].join('|');
    return _BranchOperationInspection(
      request: request,
      source: source,
      target: target,
      currentBranch: currentBranch,
      sourceOid: null,
      targetOid: null,
      ahead: 0,
      behind: 0,
      expectedCommits: 0,
      mergeBase: null,
      dirtyWorktree: !status.isClean,
      detachedHead: true,
      operationInProgress: operationInProgress,
      fingerprint: fingerprint,
      blockingMessage: operationInProgress == null
          ? 'Switch to a branch before this operation.'
          : 'A ${_operationLabel(operationInProgress)} operation is already in progress.',
    );
  }

  Future<GitBranchOperation?> _detectBranchOperation(
    RepositoryHandle handle,
  ) async {
    if (await _gitPathExists(handle.root, 'MERGE_HEAD')) {
      return GitBranchOperation.merge;
    }
    if (await _gitPathExists(handle.root, 'CHERRY_PICK_HEAD')) {
      return GitBranchOperation.cherryPick;
    }
    if (await _gitPathExists(handle.root, 'rebase-merge') ||
        await _gitPathExists(handle.root, 'rebase-apply')) {
      return GitBranchOperation.rebase;
    }
    return null;
  }

  Future<bool> _gitPathExists(String root, String path) async {
    try {
      final output = await _runner.run(
        GitInvocation(
          program: gitPath,
          args: ['rev-parse', '--git-path', path],
          cwd: root,
          kind: GitOperationKind.read,
          outputPolicy: const OutputPolicy.capture(maxBytes: 4 * 1024),
        ),
      );
      final rawPath = utf8.decode(output.stdout, allowMalformed: true).trim();
      if (rawPath.isEmpty) return false;
      final pathUri = Uri.file(rawPath);
      final absolutePath = pathUri.isAbsolute
          ? rawPath
          : '$root${Platform.pathSeparator}${rawPath.replaceAll('/', Platform.pathSeparator)}';
      return File(absolutePath).existsSync() ||
          Directory(absolutePath).existsSync();
    } on GitError {
      return false;
    }
  }

  Future<void> _validateBranchNameWithGit(
    RepositoryHandle handle,
    String name,
  ) async {
    if (name.isEmpty || name.contains('\u0000')) {
      throw const GitError(
        category: GitErrorCategory.invalidBranchName,
        userMessage: 'Enter a valid branch name accepted by Git.',
        diagnostic: 'branch name was empty or contained a NUL byte',
        retryable: false,
      );
    }
    try {
      await _runner.run(
        GitInvocation(
          program: gitPath,
          args: ['check-ref-format', '--branch', name],
          cwd: handle.root,
          kind: GitOperationKind.read,
          outputPolicy: const OutputPolicy.capture(maxBytes: 16 * 1024),
        ),
      );
    } on GitError catch (error, stackTrace) {
      if (error.category == GitErrorCategory.processFailed) {
        Error.throwWithStackTrace(
          error.copyWith(
            category: GitErrorCategory.invalidBranchName,
            userMessage: 'Enter a valid branch name accepted by Git.',
            diagnostic: 'git check-ref-format rejected the branch name',
            retryable: false,
          ),
          stackTrace,
        );
      }
      rethrow;
    }
  }

  Future<String?> _tryBranchOid(RepositoryHandle handle, String name) async {
    return _tryResolve(handle, 'refs/heads/$name');
  }

  Future<String> _requiredBranchOid(
    RepositoryHandle handle,
    String name,
  ) async {
    final oid = await _tryBranchOid(handle, name);
    if (oid == null) {
      throw GitError(
        category: GitErrorCategory.invalidRevision,
        userMessage: 'That branch does not exist.',
        diagnostic: 'local branch could not be resolved: $name',
        retryable: false,
      );
    }
    return oid;
  }

  Future<String> _resolveCommit(RepositoryHandle handle, String value) async {
    try {
      final oid = await _tryResolve(handle, '$value^{commit}');
      if (oid == null) throw const FormatException();
      return oid;
    } on GitError {
      rethrow;
    } on FormatException {
      throw const GitError(
        category: GitErrorCategory.invalidRevision,
        userMessage: 'That source does not point to a commit.',
        diagnostic: 'cherry-pick source could not be resolved to a commit',
        retryable: false,
      );
    }
  }

  Future<String?> _tryResolve(RepositoryHandle handle, String revision) async {
    try {
      final output = await _runner.run(
        GitInvocation(
          program: gitPath,
          args: ['rev-parse', '--verify', '--quiet', revision],
          cwd: handle.root,
          kind: GitOperationKind.read,
          outputPolicy: const OutputPolicy.capture(maxBytes: 4 * 1024),
        ),
      );
      final value = utf8.decode(output.stdout, allowMalformed: true).trim();
      return value.isEmpty ? null : value;
    } on GitError catch (error) {
      if (error.category == GitErrorCategory.processFailed &&
          error.exitCode == 1) {
        return null;
      }
      rethrow;
    }
  }

  Future<(int, int)> _readAheadBehind(
    RepositoryHandle handle,
    String? targetOid,
    String? sourceOid,
  ) async {
    if (targetOid == null || sourceOid == null) return (0, 0);
    final output = await _runner.run(
      GitInvocation(
        program: gitPath,
        args: [
          'rev-list',
          '--left-right',
          '--count',
          '$targetOid...$sourceOid',
        ],
        cwd: handle.root,
        kind: GitOperationKind.read,
        outputPolicy: const OutputPolicy.capture(maxBytes: 4 * 1024),
      ),
    );
    final values = utf8
        .decode(output.stdout, allowMalformed: true)
        .trim()
        .split(RegExp(r'\s+'));
    if (values.length != 2) return (0, 0);
    final behind = int.tryParse(values[0]) ?? 0;
    final ahead = int.tryParse(values[1]) ?? 0;
    return (ahead, behind);
  }

  GitBranchRelation _branchRelation({required int ahead, required int behind}) {
    if (ahead == 0 && behind == 0) return GitBranchRelation.sameTip;
    if (ahead == 0) return GitBranchRelation.currentAhead;
    if (behind == 0) return GitBranchRelation.branchAhead;
    return GitBranchRelation.diverged;
  }

  Future<String?> _readMergeBase(
    RepositoryHandle handle,
    String? targetOid,
    String? sourceOid,
  ) async {
    if (targetOid == null || sourceOid == null) return null;
    try {
      final output = await _runner.run(
        GitInvocation(
          program: gitPath,
          args: ['merge-base', targetOid, sourceOid],
          cwd: handle.root,
          kind: GitOperationKind.read,
          outputPolicy: const OutputPolicy.capture(maxBytes: 4 * 1024),
        ),
      );
      final value = utf8.decode(output.stdout, allowMalformed: true).trim();
      return value.isEmpty ? null : value;
    } on GitError catch (error) {
      if (error.category == GitErrorCategory.processFailed &&
          error.exitCode == 1) {
        return null;
      }
      rethrow;
    }
  }

  Future<int> _readCommitCount(
    RepositoryHandle handle,
    String? targetOid,
    String? sourceOid,
  ) async {
    if (targetOid == null || sourceOid == null) return 0;
    final output = await _runner.run(
      GitInvocation(
        program: gitPath,
        args: ['rev-list', '--count', '$targetOid..$sourceOid'],
        cwd: handle.root,
        kind: GitOperationKind.read,
        outputPolicy: const OutputPolicy.capture(maxBytes: 4 * 1024),
      ),
    );
    return int.tryParse(
          utf8.decode(output.stdout, allowMalformed: true).trim(),
        ) ??
        0;
  }

  Future<String> _readBranchFingerprint(RepositoryHandle handle) async {
    final output = await _runner.run(
      GitInvocation(
        program: gitPath,
        args: const [
          'for-each-ref',
          '--sort=refname',
          '--format=%(refname:short)%00%(objectname)',
          'refs/heads/',
        ],
        cwd: handle.root,
        kind: GitOperationKind.read,
        outputPolicy: const OutputPolicy.capture(maxBytes: 512 * 1024),
      ),
    );
    return utf8.decode(output.stdout, allowMalformed: true).trim();
  }

  List<String> _branchOperationArgs(
    GitBranchOperationRequest request,
    _BranchOperationInspection inspection,
  ) {
    if (request.phase == GitBranchOperationPhase.continueOperation) {
      return switch (request.operation) {
        GitBranchOperation.merge => const ['merge', '--continue'],
        GitBranchOperation.rebase => const ['rebase', '--continue'],
        GitBranchOperation.cherryPick => const ['cherry-pick', '--continue'],
        _ => throw _recoveryNotAllowed(request.operation, request.phase),
      };
    }
    if (request.phase == GitBranchOperationPhase.skip) {
      return switch (request.operation) {
        GitBranchOperation.rebase => const ['rebase', '--skip'],
        GitBranchOperation.cherryPick => const ['cherry-pick', '--skip'],
        _ => throw _recoveryNotAllowed(request.operation, request.phase),
      };
    }
    if (request.phase == GitBranchOperationPhase.abort) {
      return switch (request.operation) {
        GitBranchOperation.merge => const ['merge', '--abort'],
        GitBranchOperation.rebase => const ['rebase', '--abort'],
        GitBranchOperation.cherryPick => const ['cherry-pick', '--abort'],
        _ => throw _recoveryNotAllowed(request.operation, request.phase),
      };
    }
    return switch (request.operation) {
      GitBranchOperation.rename => [
        'branch',
        '--move',
        inspection.source,
        inspection.target!,
      ],
      GitBranchOperation.delete => [
        'branch',
        '--delete',
        if (request.force) '--force',
        inspection.source,
      ],
      GitBranchOperation.merge => ['merge', '--no-edit', inspection.source],
      GitBranchOperation.rebase => ['rebase', inspection.target!],
      GitBranchOperation.cherryPick => ['cherry-pick', inspection.source],
    };
  }

  void _throwIfBranchOperationBlocked(_BranchOperationInspection inspection) {
    final message = inspection.blockingMessage;
    if (message == null) return;
    final category = inspection.operationInProgress != null
        ? GitErrorCategory.operationInProgress
        : inspection.detachedHead
        ? GitErrorCategory.detachedHead
        : inspection.dirtyWorktree
        ? GitErrorCategory.dirtyWorktree
        : GitErrorCategory.branchOperationNotAllowed;
    throw GitError(
      category: category,
      userMessage: message,
      diagnostic: 'advanced branch operation preflight rejected the request',
      retryable: false,
    );
  }

  void _validateRecoveryRequest(
    GitBranchOperationRequest request,
    _BranchOperationInspection inspection,
  ) {
    if (inspection.operationInProgress != request.operation) {
      throw const GitError(
        category: GitErrorCategory.operationInProgress,
        userMessage: 'That recovery action is not available for the current repository state.',
        diagnostic: 'recovery operation did not match Git operation metadata',
        retryable: false,
      );
    }
    _recoveryActions(request.operation).contains(request.phase)
        ? null
        : throw _recoveryNotAllowed(request.operation, request.phase);
  }

  GitBranchOperationResult _branchOperationResult(
    RepositoryId repositoryId,
    GitBranchOperationRequest request,
    GitBranchOperationState state,
    GitStatusSnapshot status,
    String summary,
    GitBranchOperation? detectedOperation,
  ) {
    return GitBranchOperationResult(
      repositoryId: repositoryId,
      request: request,
      state: state,
      status: status,
      summary: summary,
      recoveryActions:
          state == GitBranchOperationState.conflicted ||
              state == GitBranchOperationState.cancelled
          ? _recoveryActions(detectedOperation ?? request.operation)
          : const [],
    );
  }

  List<GitBranchOperationPhase> _recoveryActions(
    GitBranchOperation operation,
  ) => operation == GitBranchOperation.merge
      ? const [
          GitBranchOperationPhase.continueOperation,
          GitBranchOperationPhase.abort,
        ]
      : operation == GitBranchOperation.rebase ||
            operation == GitBranchOperation.cherryPick
      ? const [
          GitBranchOperationPhase.continueOperation,
          GitBranchOperationPhase.skip,
          GitBranchOperationPhase.abort,
        ]
      : const [];

  String _operationLabel(GitBranchOperation operation) => switch (operation) {
    GitBranchOperation.rename => 'rename',
    GitBranchOperation.delete => 'delete',
    GitBranchOperation.merge => 'merge',
    GitBranchOperation.rebase => 'rebase',
    GitBranchOperation.cherryPick => 'cherry-pick',
  };

  void _validateFullCommitOid(String value) {
    if (!RegExp(r'^[0-9a-fA-F]{40}$').hasMatch(value)) {
      throw const GitError(
        category: GitErrorCategory.invalidRevision,
        userMessage: 'The selected commit ID is invalid.',
        diagnostic:
            'commit context action did not supply a full hexadecimal OID',
        retryable: false,
      );
    }
  }

  String _requiredBranchName(String? value, String label) {
    if (value == null || value.isEmpty) {
      throw GitError(
        category: GitErrorCategory.parseFailure,
        userMessage: 'Choose a $label.',
        diagnostic: 'advanced branch operation $label was missing',
        retryable: false,
      );
    }
    return value;
  }

  void _requireCurrentTarget(String? current, String requested) {
    if (current == null || current == '(detached)' || current != requested) {
      throw const GitError(
        category: GitErrorCategory.branchOperationNotAllowed,
        userMessage: 'The target must be the current branch.',
        diagnostic: 'advanced operation refused to switch branches implicitly',
        retryable: false,
      );
    }
  }

  void _validateRevisionInput(String value) {
    if (value.isEmpty || value.startsWith('-') || value.contains('\u0000')) {
      throw const GitError(
        category: GitErrorCategory.invalidRevision,
        userMessage: 'That source commit or ref is invalid.',
        diagnostic:
            'cherry-pick source was empty, option-like, or contained NUL',
        retryable: false,
      );
    }
  }

  void _validateComparisonPath(String? path) {
    if (path == null) return;
    if (path.isEmpty ||
        path.startsWith('-') ||
        path.startsWith('/') ||
        path.startsWith('\\') ||
        path.contains('\u0000') ||
        path.contains('\n') ||
        path.contains('\r') ||
        path.split(RegExp(r'[/\\]')).any((part) => part == '..')) {
      throw const GitError(
        category: GitErrorCategory.parseFailure,
        userMessage: 'Git could not inspect that comparison path.',
        diagnostic:
            'comparison path was empty, absolute, option-like, or '
            'contained a control character',
        retryable: false,
      );
    }
  }

  bool _isPathWithinComparisonScope(String path, String? scope) {
    if (scope == null || scope == '.') return true;
    final normalizedScope = scope.endsWith('/')
        ? scope.substring(0, scope.length - 1)
        : scope;
    return path == normalizedScope || path.startsWith('$normalizedScope/');
  }

  String _todoSubject(String subject) {
    final normalized = subject.replaceAll(RegExp(r'[\r\n\u0000]'), ' ').trim();
    return normalized.isEmpty ? '(no commit subject)' : normalized;
  }

  String _shellPath(String path) =>
      '"${path.replaceAll('\\', '/').replaceAll('"', '\\"')}"';

  Future<String> _readRefOid(
    RepositoryHandle handle,
    String ref, {
    required GitErrorCategory missingCategory,
  }) async {
    try {
      final output = await _runner.run(
        GitInvocation(
          program: gitPath,
          args: ['rev-parse', '--verify', '--quiet', '$ref^{commit}'],
          cwd: handle.root,
          kind: GitOperationKind.read,
          outputPolicy: const OutputPolicy.capture(maxBytes: 4 * 1024),
        ),
      );
      final oid = utf8.decode(output.stdout, allowMalformed: true).trim();
      if (_isCommitOid(oid)) return oid;
    } on GitError catch (error, stackTrace) {
      if (error.category != GitErrorCategory.processFailed) {
        Error.throwWithStackTrace(error, stackTrace);
      }
    }
    throw GitError(
      category: missingCategory,
      userMessage: 'The requested remote branch is no longer available.',
      diagnostic: 'could not resolve remote commit ref: $ref',
      retryable: true,
    );
  }

  Future<String> _readRemoteBranchOid(
    RepositoryHandle handle,
    String remote,
    String branch, {
    String? remoteUrl,
    String? credentialId,
  }) async {
    _validateRemoteName(remote);
    _validateBranchName(branch);
    try {
      final output = await _runWithCredentials(
        cwd: handle.root,
        args: ['ls-remote', '--refs', remote, 'refs/heads/$branch'],
        kind: GitOperationKind.read,
        maxBytes: 16 * 1024,
        credentialId: credentialId,
        remoteUrl: remoteUrl,
      );
      final fields = utf8
          .decode(output.stdout, allowMalformed: true)
          .trim()
          .split(RegExp(r'\s+'));
      if (fields.length >= 2 && _isCommitOid(fields[0])) return fields[0];
    } on GitError catch (error, stackTrace) {
      Error.throwWithStackTrace(_mapRemoteError(error), stackTrace);
    }
    throw GitError(
      category: GitErrorCategory.remoteBranchNotFound,
      userMessage: 'The remote branch is no longer available.',
      diagnostic: 'remote branch was not advertised by $remote: $branch',
      retryable: true,
    );
  }

  String _updateFingerprint(
    GitStatusSnapshot status,
    String? branch,
    String? upstream,
    String currentOid,
    String upstreamOid,
  ) => [
    status.contentHash,
    branch ?? '',
    upstream ?? '',
    currentOid,
    upstreamOid,
  ].join('|');

  List<String> _updateArgs(
    GitUpdateProjectRequest request, {
    String? upstream,
  }) {
    if (request.phase == GitUpdatePhase.continueOperation) {
      return switch (request.strategy) {
        GitUpdateStrategy.merge => const ['merge', '--continue'],
        GitUpdateStrategy.rebase => const ['rebase', '--continue'],
        GitUpdateStrategy.resetToRemote => throw const GitError(
          category: GitErrorCategory.updateNotAllowed,
          userMessage: 'Reset-to-remote has no conflict continuation step.',
          diagnostic: 'continue was requested for reset-to-remote',
          retryable: false,
        ),
      };
    }
    if (request.phase == GitUpdatePhase.abort) {
      return switch (request.strategy) {
        GitUpdateStrategy.merge => const ['merge', '--abort'],
        GitUpdateStrategy.rebase => const ['rebase', '--abort'],
        GitUpdateStrategy.resetToRemote => throw const GitError(
          category: GitErrorCategory.updateNotAllowed,
          userMessage: 'Reset-to-remote has no conflict abort step.',
          diagnostic: 'abort was requested for reset-to-remote',
          retryable: false,
        ),
      };
    }
    return switch (request.strategy) {
      GitUpdateStrategy.merge => ['merge', '--no-edit', upstream!],
      GitUpdateStrategy.rebase => ['rebase', upstream!],
      GitUpdateStrategy.resetToRemote => ['reset', '--hard', upstream!],
    };
  }

  Future<void> _validateUpdateRecovery(
    RepositoryHandle handle,
    GitUpdateStrategy strategy,
  ) async {
    final operation = await _detectBranchOperation(handle);
    final expected = switch (strategy) {
      GitUpdateStrategy.merge => GitBranchOperation.merge,
      GitUpdateStrategy.rebase => GitBranchOperation.rebase,
      GitUpdateStrategy.resetToRemote => null,
    };
    if (expected == null || operation != expected) {
      throw const GitError(
        category: GitErrorCategory.updateNotAllowed,
        userMessage: 'That update recovery action is no longer available.',
        diagnostic:
            'repository operation did not match update recovery strategy',
        retryable: true,
      );
    }
  }

  GitError _recoveryNotAllowed(
    GitBranchOperation operation,
    GitBranchOperationPhase phase,
  ) => GitError(
    category: GitErrorCategory.branchOperationNotAllowed,
    userMessage:
        'The selected recovery action is not available for this ${_operationLabel(operation)} operation.',
    diagnostic: 'unsupported recovery phase: ${operation.name}/${phase.name}',
    retryable: false,
  );

  Future<List<GitRemote>> getRemotes(RepositoryId repositoryId) async {
    final handle = await state.lookup(repositoryId);
    final output = await _runner.run(
      GitInvocation(
        program: gitPath,
        args: const ['remote', '--verbose'],
        cwd: handle.root,
        kind: GitOperationKind.read,
        outputPolicy: const OutputPolicy.capture(maxBytes: 512 * 1024),
      ),
    );
    try {
      return parseGitRemotes(output.stdout);
    } on FormatException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        GitError(
          category: GitErrorCategory.parseFailure,
          userMessage: 'Git returned an unreadable remote list.',
          diagnostic: error.message,
          retryable: false,
        ),
        stackTrace,
      );
    }
  }

  Future<GitCredentialOAuthResult> loginWithBrowser(
    GitCredentialProvider provider,
  ) async {
    final host = switch (provider) {
      GitCredentialProvider.github => 'github.com',
      GitCredentialProvider.gitlab => 'gitlab.com',
      GitCredentialProvider.generic => throw credentialInputError(
        'Browser sign-in is available for GitHub and GitLab only.',
        'generic Git credential provider has no OAuth host',
      ),
    };
    try {
      await _runner.run(
        GitInvocation(
          program: gitPath,
          args: ['credential-manager', provider.name, 'login'],
          cwd: Directory.current.path,
          kind: GitOperationKind.remote,
          outputPolicy: const OutputPolicy.capture(maxBytes: 128 * 1024),
          environment: const {'GCM_INTERACTIVE': 'Always'},
        ),
      );
    } on GitError catch (error, stackTrace) {
      Error.throwWithStackTrace(
        GitError(
          category: error.category,
          userMessage: 'Browser sign-in could not be completed. Install Git Credential Manager or use a token.',
          diagnostic: error.diagnostic,
          retryable: true,
          exitCode: error.exitCode,
        ),
        stackTrace,
      );
    }
    return GitCredentialOAuthResult(
      provider: provider,
      host: host,
      accountName:
          '${provider == GitCredentialProvider.github ? 'GitHub' : 'GitLab'} browser account',
    );
  }

  /// Resolves only the selected remote's web identity. The configured remote
  /// may contain credentials, so the raw value never crosses this boundary.
  Future<GitHostingSnapshot> getHostingRepository(
    RepositoryId repositoryId, {
    String remote = 'origin',
  }) async {
    _validateRemoteName(remote);
    final remotes = await getRemotes(repositoryId);
    final selected = _findRemote(remotes, remote);
    final remoteUrl = selected?.fetchUrl ?? selected?.pushUrl;
    if (remoteUrl == null) {
      return GitHostingSnapshot(
        repositoryId: repositoryId,
        remoteName: remote,
        reason: 'The $remote remote has no URL.',
      );
    }
    final repository = parseGitHostingRemote(remoteUrl);
    if (repository == null) {
      return GitHostingSnapshot(
        repositoryId: repositoryId,
        remoteName: remote,
        reason: 'This remote has no supported GitHub or GitLab web adapter.',
      );
    }
    return GitHostingSnapshot(
      repositoryId: repositoryId,
      remoteName: remote,
      repository: repository,
      sanitizedRemoteUrl: repository.webBase,
    );
  }

  Future<GitHostingLinks> getHostingLinks(
    RepositoryId repositoryId,
    String commitOid, {
    String? remote,
    String? path,
    int? lineStart,
    int? lineEnd,
  }) async {
    final snapshot = await getHostingRepository(
      repositoryId,
      remote: remote ?? 'origin',
    );
    final repository = snapshot.repository;
    if (repository == null) return const GitHostingLinks();
    return buildGitHostingLinks(
      repository,
      commitOid,
      path: path,
      lineStart: lineStart,
      lineEnd: lineEnd,
    );
  }

  Future<GitHostingReviewCapability> getHostingReviewCapability(
    RepositoryId repositoryId, {
    String remote = 'origin',
  }) async {
    final snapshot = await getHostingRepository(repositoryId, remote: remote);
    final repository = snapshot.repository;
    if (repository == null) {
      return GitHostingReviewCapability(
        provider: null,
        isSupported: false,
        reason: snapshot.reason ?? 'Hosting integration is unavailable.',
      );
    }
    return hostingReviewCapability(repository);
  }

  Future<GitRemoteOperationResult> fetch(
    RepositoryId repositoryId,
    String remote, {
    GitCancellationToken? cancellationToken,
    String? credentialId,
  }) => _runRemote(
    repositoryId,
    remote,
    GitRemoteOperation.fetch,
    cancellationToken: cancellationToken,
    credentialId: credentialId,
  );

  Future<GitRemoteOperationResult> pull(
    RepositoryId repositoryId,
    String remote, {
    GitCancellationToken? cancellationToken,
    String? credentialId,
  }) => _runRemote(
    repositoryId,
    remote,
    GitRemoteOperation.pull,
    cancellationToken: cancellationToken,
    credentialId: credentialId,
  );

  Future<GitRemoteOperationResult> push(
    RepositoryId repositoryId,
    String remote, {
    GitCancellationToken? cancellationToken,
    String? credentialId,
  }) => _runRemote(
    repositoryId,
    remote,
    GitRemoteOperation.push,
    cancellationToken: cancellationToken,
    credentialId: credentialId,
  );

  /// Captures the exact branch/tag scope and remote tip that the user is
  /// about to publish. The returned token is intentionally tied to both the
  /// request and the live remote OID, so a review cannot silently turn into a
  /// different push after another clone updates the remote.
  Future<GitPushPreview> previewPush(
    RepositoryId repositoryId,
    GitPushRequest request,
  ) async {
    final inspection = await _buildPushPreview(repositoryId, request);
    if (inspection.blockingMessage != null) return inspection;
    final token = state.issuePushPreview(
      repositoryId: repositoryId,
      request: request,
      fingerprint: inspection.fingerprint,
    );
    return _copyPushPreview(
      inspection,
      request: request.copyWith(confirmationToken: token.value),
      token: token.value,
      expiresAt: token.expiresAt,
    );
  }

  /// Publishes only the refspecs shown by [previewPush]. A remote rejection is
  /// returned as a typed result so the UI can offer retry or merge/rebase
  /// recovery without guessing from process text.
  Future<GitPushResult> executePush(
    RepositoryId repositoryId,
    GitPushRequest request, {
    GitCancellationToken? cancellationToken,
  }) => state.runMutation(repositoryId, () async {
    final inspection = await _buildPushPreview(repositoryId, request);
    if (inspection.blockingMessage != null) {
      throw _pushBlockingError(inspection);
    }
    state.validatePushPreview(
      repositoryId: repositoryId,
      request: request,
      fingerprint: inspection.fingerprint,
    );
    if (request.confirmationToken case final token?) {
      state.consumePushPreview(token);
    }
    final handle = await state.lookup(repositoryId);
    final remoteConfig = _findRemote(
      await getRemotes(repositoryId),
      request.remote,
    );
    final args = _pushArgs(inspection);
    late final ProcessOutput output;
    try {
      output = await _runWithCredentials(
        cwd: handle.root,
        args: args,
        kind: GitOperationKind.remote,
        maxBytes: 2 * 1024 * 1024,
        cancellationToken: cancellationToken,
        remoteUrl: remoteConfig?.pushUrl ?? remoteConfig?.fetchUrl,
        credentialId: request.credentialId,
      );
    } on GitError catch (error, stackTrace) {
      final mapped = _mapPushError(error, request.forceWithLease);
      final afterFailure = await getStatus(repositoryId);
      if (mapped.category == GitErrorCategory.cancelled) {
        return GitPushResult(
          repositoryId: repositoryId,
          request: request,
          state: GitPushState.cancelled,
          status: afterFailure,
          summary: 'The push was cancelled.',
          failureCategory: mapped.category,
          recoveryActions: const [GitPushRecoveryAction.retry],
        );
      }
      if (_isRecoverablePushFailure(mapped.category)) {
        return GitPushResult(
          repositoryId: repositoryId,
          request: request,
          state: GitPushState.rejected,
          status: afterFailure,
          summary: mapped.userMessage,
          failureCategory: mapped.category,
          recoveryActions: _pushRecoveryActions(mapped.category),
        );
      }
      Error.throwWithStackTrace(mapped, stackTrace);
    }
    final after = await getStatus(repositoryId);
    return GitPushResult(
      repositoryId: repositoryId,
      request: request,
      state: GitPushState.completed,
      status: after,
      summary: _objectSummary(
        output,
        request.setUpstream
            ? 'The current branch was pushed and linked to ${inspection.remote}/${inspection.targetBranch}.'
            : 'The selected changes were pushed.',
      ),
    );
  });

  Future<GitPushPreview> _buildPushPreview(
    RepositoryId repositoryId,
    GitPushRequest request,
  ) async {
    _validateRemoteName(request.remote);
    final handle = await state.lookup(repositoryId);
    final remotes = await getRemotes(repositoryId);
    final remoteConfig = _findRemote(remotes, request.remote);
    if (remoteConfig == null) {
      throw _objectNotFound('remote', request.remote);
    }
    final status = await getStatus(repositoryId);
    final currentBranch = status.branch.head ?? '';
    final localHead = status.branch.oid ?? '';
    final tags = <GitTag>[];
    var targetBranch = request.branch ?? currentBranch;
    var targetOid = localHead;
    String? remoteHead;
    var blockingMessage = <String>[];

    if (request.target == GitPushTarget.allTags) {
      if (request.forceWithLease) {
        blockingMessage.add(
          'Force-with-lease is available for branches, not tags.',
        );
      }
      if (request.setUpstream) {
        blockingMessage.add(
          'Remote tracking can be linked only when pushing the current branch.',
        );
      }
      final tagSnapshot = await getTags(repositoryId);
      final selectedNames = request.tagNames.isEmpty
          ? tagSnapshot.tags.map((tag) => tag.name).toList(growable: false)
          : request.tagNames;
      final seen = <String>{};
      for (final name in selectedNames) {
        _validateTagName(name);
        if (!seen.add(name)) {
          blockingMessage.add('A tag was selected more than once: $name.');
          continue;
        }
        final tag = tagSnapshot.tags
            .where((candidate) => candidate.name == name)
            .firstOrNull;
        if (tag == null) {
          blockingMessage.add(
            'The selected tag is no longer available: $name.',
          );
        } else {
          tags.add(tag);
        }
      }
      if (tags.isEmpty && blockingMessage.isEmpty) {
        blockingMessage.add('Select at least one tag to publish.');
      }
      final fingerprint = hashGitObjectBytes(
        utf8.encode(
          [
            status.contentHash,
            request.queryKey,
            tagSnapshot.fingerprint,
            ...tags.map((tag) => '${tag.name}:${_tagIdentity(tag)}'),
          ].join('|'),
        ),
      );
      return GitPushPreview(
        repositoryId: repositoryId,
        request: request,
        remote: request.remote,
        currentBranch: currentBranch,
        targetBranch: targetBranch,
        localHead: localHead,
        targetOid: targetOid,
        remoteHead: null,
        commits: const [],
        changedPaths: const [],
        tags: tags,
        dirtyWorktree: !status.isClean,
        protectedBranch: false,
        requiresConfirmation: false,
        fingerprint: fingerprint,
        blockingMessage: blockingMessage.isEmpty
            ? null
            : blockingMessage.join(' '),
      );
    }

    if (currentBranch.isEmpty || status.branch.isDetached) {
      blockingMessage.add('Switch to a local branch before pushing.');
    } else {
      _validateBranchName(targetBranch);
    }
    if (localHead.isEmpty) {
      blockingMessage.add('Create a commit before pushing.');
    }
    if (request.target == GitPushTarget.selectedCommit) {
      final selected = request.commitOid;
      if (selected == null || selected.isEmpty) {
        blockingMessage.add('Choose a commit to push up to.');
      } else {
        _validateCommitOid(selected);
        final resolved = await _tryResolve(handle, selected);
        if (resolved == null) {
          blockingMessage.add('The selected commit is no longer available.');
        } else {
          targetOid = resolved;
          if (localHead.isNotEmpty &&
              !await _isAncestor(handle, targetOid, localHead)) {
            blockingMessage.add(
              'Choose a commit reachable from the current branch.',
            );
          }
        }
      }
    }
    if (request.setUpstream && request.target != GitPushTarget.currentBranch) {
      blockingMessage.add(
        'Remote tracking can be linked only when pushing the current branch.',
      );
    }
    if (targetBranch.isNotEmpty &&
        currentBranch.isNotEmpty &&
        !status.branch.isDetached) {
      remoteHead = await _tryReadRemoteBranchOid(
        handle,
        request.remote,
        targetBranch,
        remoteUrl: remoteConfig.pushUrl ?? remoteConfig.fetchUrl,
        credentialId: request.credentialId,
      );
    }
    final protectedBranch = _isProtectedPushBranch(targetBranch);
    if (request.forceWithLease) {
      if (protectedBranch) {
        blockingMessage.add(
          'Force push is blocked for protected branch $targetBranch.',
        );
      } else if (remoteHead == null) {
        blockingMessage.add(
          'Force-with-lease needs an existing remote branch tip to review.',
        );
      } else if (request.expectedRemoteOid == null ||
          request.expectedRemoteOid!.isEmpty) {
        blockingMessage.add(
          'Refresh the remote tip before confirming force-with-lease.',
        );
      } else if (request.expectedRemoteOid != remoteHead) {
        blockingMessage.add(
          'The remote branch moved. Refresh the push review before continuing.',
        );
      } else {
        _validateCommitOid(request.expectedRemoteOid!);
      }
    }
    final remoteHeadAvailableLocally =
        remoteHead == null ||
        await _tryResolve(handle, '$remoteHead^{commit}') != null;
    final canCompareCommits = remoteHeadAvailableLocally;
    final commits = remoteHead == targetOid || !canCompareCommits
        ? const <GitPushCommit>[]
        : await _readPushCommits(handle, remoteHead, targetOid);
    final changedPaths = remoteHead == targetOid || !canCompareCommits
        ? const <String>[]
        : await _readPushChangedPaths(handle, remoteHead, targetOid);
    final fingerprint = hashGitObjectBytes(
      utf8.encode(
        [
          status.contentHash,
          request.queryKey,
          currentBranch,
          targetBranch,
          localHead,
          targetOid,
          remoteHead ?? '<missing>',
          ...commits.map((commit) => commit.oid),
          ...changedPaths,
        ].join('|'),
      ),
    );
    return GitPushPreview(
      repositoryId: repositoryId,
      request: request,
      remote: request.remote,
      currentBranch: currentBranch,
      targetBranch: targetBranch,
      localHead: localHead,
      targetOid: targetOid,
      remoteHead: remoteHead,
      commits: commits,
      changedPaths: changedPaths,
      tags: tags,
      dirtyWorktree: !status.isClean,
      protectedBranch: protectedBranch,
      requiresConfirmation: request.forceWithLease,
      fingerprint: fingerprint,
      blockingMessage: blockingMessage.isEmpty
          ? null
          : blockingMessage.join(' '),
    );
  }

  GitPushPreview _copyPushPreview(
    GitPushPreview preview, {
    required GitPushRequest request,
    String? token,
    DateTime? expiresAt,
  }) => GitPushPreview(
    repositoryId: preview.repositoryId,
    request: request,
    remote: preview.remote,
    currentBranch: preview.currentBranch,
    targetBranch: preview.targetBranch,
    localHead: preview.localHead,
    targetOid: preview.targetOid,
    remoteHead: preview.remoteHead,
    commits: preview.commits,
    changedPaths: preview.changedPaths,
    tags: preview.tags,
    dirtyWorktree: preview.dirtyWorktree,
    protectedBranch: preview.protectedBranch,
    requiresConfirmation: preview.requiresConfirmation,
    fingerprint: preview.fingerprint,
    blockingMessage: preview.blockingMessage,
    token: token,
    expiresAt: expiresAt,
  );

  Future<List<GitPushCommit>> _readPushCommits(
    RepositoryHandle handle,
    String? remoteHead,
    String targetOid,
  ) async {
    if (targetOid.isEmpty) return const [];
    final output = await _runner.run(
      GitInvocation(
        program: gitPath,
        args: [
          'log',
          '--reverse',
          '--max-count=100',
          '--no-decorate',
          '--format=%H%x00%s%x00%x1e',
          if (remoteHead == null) targetOid else '$remoteHead..$targetOid',
        ],
        cwd: handle.root,
        kind: GitOperationKind.read,
        outputPolicy: const OutputPolicy.capture(maxBytes: 2 * 1024 * 1024),
      ),
    );
    final commits = <GitPushCommit>[];
    final text = utf8.decode(output.stdout, allowMalformed: true);
    for (final record in text.split('\u001e')) {
      final fields = record.split('\u0000');
      if (fields.length < 2 || fields[0].isEmpty) continue;
      if (!_isCommitOid(fields[0])) continue;
      commits.add(GitPushCommit(oid: fields[0], subject: fields[1]));
    }
    return commits;
  }

  Future<List<String>> _readPushChangedPaths(
    RepositoryHandle handle,
    String? remoteHead,
    String targetOid,
  ) async {
    if (targetOid.isEmpty) return const [];
    if (remoteHead != null) {
      return _readChangedPaths(handle, remoteHead, targetOid);
    }
    final output = await _runner.run(
      GitInvocation(
        program: gitPath,
        args: [
          'diff-tree',
          '--root',
          '--no-commit-id',
          '--name-only',
          '-z',
          '-r',
          targetOid,
        ],
        cwd: handle.root,
        kind: GitOperationKind.read,
        outputPolicy: const OutputPolicy.capture(maxBytes: 512 * 1024),
      ),
    );
    return _splitNulBytes(output.stdout)
        .where((bytes) => bytes.isNotEmpty)
        .map((bytes) => utf8.decode(bytes, allowMalformed: true))
        .toSet()
        .toList(growable: false);
  }

  Future<String?> _tryReadRemoteBranchOid(
    RepositoryHandle handle,
    String remote,
    String branch, {
    String? remoteUrl,
    String? credentialId,
  }) async {
    try {
      return await _readRemoteBranchOid(
        handle,
        remote,
        branch,
        remoteUrl: remoteUrl,
        credentialId: credentialId,
      );
    } on GitError catch (error) {
      if (error.category == GitErrorCategory.remoteBranchNotFound) return null;
      rethrow;
    }
  }

  List<String> _pushArgs(GitPushPreview preview) {
    if (preview.request.target == GitPushTarget.allTags) {
      return [
        'push',
        preview.remote,
        ...preview.tags.map(
          (tag) => 'refs/tags/${tag.name}:refs/tags/${tag.name}',
        ),
      ];
    }
    return [
      'push',
      if (preview.request.forceWithLease)
        '--force-with-lease=refs/heads/${preview.targetBranch}:${preview.remoteHead}',
      if (preview.request.setUpstream) '--set-upstream',
      preview.remote,
      preview.request.setUpstream
          ? 'refs/heads/${preview.currentBranch}:refs/heads/${preview.targetBranch}'
          : '${preview.targetOid}:refs/heads/${preview.targetBranch}',
    ];
  }

  GitError _pushBlockingError(GitPushPreview preview) {
    final category = preview.protectedBranch && preview.request.forceWithLease
        ? GitErrorCategory.protectedBranch
        : preview.currentBranch.isEmpty
        ? GitErrorCategory.detachedHead
        : GitErrorCategory.stalePushPreview;
    return GitError(
      category: category,
      userMessage: preview.blockingMessage ?? 'Review the push again.',
      diagnostic: 'push preview was blocked before mutation',
      retryable: category == GitErrorCategory.stalePushPreview,
    );
  }

  Future<GitWorktreeSnapshot> getWorktrees(RepositoryId repositoryId) async {
    final handle = await state.lookup(repositoryId);
    final output = await _runner.run(
      GitInvocation(
        program: gitPath,
        args: const ['worktree', 'list', '--porcelain', '-z'],
        cwd: handle.root,
        kind: GitOperationKind.read,
        outputPolicy: const OutputPolicy.capture(maxBytes: 2 * 1024 * 1024),
      ),
    );
    late final List<GitWorktree> parsed;
    try {
      parsed = [
        for (final worktree in parseGitWorktrees(output.stdout))
          GitWorktree(
            path: _normalizeGitFilesystemPath(worktree.path),
            head: worktree.head,
            branch: worktree.branch,
            isLocked: worktree.isLocked,
            lockReason: worktree.lockReason,
            isPrunable: worktree.isPrunable,
            pruneReason: worktree.pruneReason,
          ),
      ];
    } on FormatException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        GitError(
          category: GitErrorCategory.parseFailure,
          userMessage: 'Git returned an unreadable worktree list.',
          diagnostic: error.message,
          retryable: false,
        ),
        stackTrace,
      );
    }
    final enriched = <GitWorktree>[];
    for (var index = 0; index < parsed.length; index++) {
      final worktree = parsed[index];
      var dirty = false;
      var dirtyPaths = const <String>[];
      if (!worktree.isPrunable && Directory(worktree.path).existsSync()) {
        try {
          final status = await _readWorktreeStatus(worktree.path);
          dirty = status.changes.isNotEmpty;
          dirtyPaths = {
            for (final change in status.changes) ...[
              change.path,
              ?change.originalPath,
            ],
          }.toList(growable: false);
        } on GitError {
          // A worktree can disappear between `worktree list` and status. Git
          // will mark it prunable on the next list, so keep this snapshot
          // usable and let the action preflight refresh it.
        }
      }
      enriched.add(
        worktree.copyWith(
          isMain: index == 0,
          isCurrent: _sameWorktreePath(worktree.path, handle.root),
          isDirty: dirty,
          dirtyPaths: dirtyPaths,
        ),
      );
    }
    final fingerprint = hashGitObjectBytes(
      utf8.encode(
        [
          ...enriched.map(
            (worktree) => [
              worktree.path,
              worktree.head ?? '',
              worktree.branch ?? '',
              worktree.isLocked,
              worktree.lockReason ?? '',
              worktree.isPrunable,
              worktree.pruneReason ?? '',
              worktree.isDirty,
              ...worktree.dirtyPaths,
            ].join('|'),
          ),
        ].join('\n'),
      ),
    );
    return GitWorktreeSnapshot(
      repositoryId: repositoryId,
      worktrees: enriched,
      fingerprint: fingerprint,
    );
  }

  Future<GitWorktreeCreateResult> createWorktree(
    RepositoryId repositoryId,
    GitWorktreeCreateRequest request,
  ) => state.runMutation(repositoryId, () async {
    final handle = await state.lookup(repositoryId);
    _validateWorktreeCreateRequest(request);
    final path = await _resolveWorktreePath(handle.root, request.path);
    final before = await getWorktrees(repositoryId);
    if (before.worktrees.any(
      (worktree) => _sameWorktreePath(worktree.path, path),
    )) {
      throw worktreeInputError(
        'That path is already registered as a worktree.',
        'worktree add targeted an existing registered path',
      );
    }
    if (request.branch case final branch?) {
      _validateBranchName(branch);
      if (request.createBranch &&
          await _tryResolve(handle, 'refs/heads/$branch') != null) {
        throw const GitError(
          category: GitErrorCategory.worktreeBranchOccupied,
          userMessage:
              'That branch already exists. Choose another branch name.',
          diagnostic: 'worktree create requested a branch that already exists',
          retryable: false,
        );
      }
    }
    if (request.startPoint case final startPoint?) {
      _validateRevisionInput(startPoint);
    }
    final args = <String>['worktree', 'add'];
    if (request.detach) {
      args.add('--detach');
    } else if (request.createBranch) {
      args.addAll(['-b', request.branch!]);
    }
    args.add(path);
    if (request.detach) {
      args.add(request.startPoint ?? 'HEAD');
    } else if (request.createBranch) {
      if (request.startPoint case final startPoint?) args.add(startPoint);
    } else {
      args.add(request.branch!);
    }
    late final ProcessOutput output;
    try {
      output = await _runner.run(
        GitInvocation(
          program: gitPath,
          args: args,
          cwd: handle.root,
          kind: GitOperationKind.mutation,
          outputPolicy: const OutputPolicy.capture(maxBytes: 512 * 1024),
        ),
      );
    } on GitError catch (error, stackTrace) {
      Error.throwWithStackTrace(_mapWorktreeError(error), stackTrace);
    }
    final snapshot = await getWorktrees(repositoryId);
    final created = snapshot.worktrees
        .where((worktree) => _sameWorktreePath(worktree.path, path))
        .firstOrNull;
    if (created == null) {
      throw const GitError(
        category: GitErrorCategory.parseFailure,
        userMessage: 'The new worktree was not found after creation.',
        diagnostic: 'git worktree add completed without a matching list entry',
        retryable: true,
      );
    }
    return GitWorktreeCreateResult(
      repositoryId: repositoryId,
      request: request,
      worktree: created,
      snapshot: snapshot,
      summary: _objectSummary(output, 'The worktree was created.'),
    );
  });

  Future<RepositoryOpened> openWorktree(
    RepositoryId repositoryId,
    GitWorktree worktree,
  ) async {
    final handle = await state.lookup(repositoryId);
    final snapshot = await getWorktrees(repositoryId);
    final current = snapshot.worktrees
        .where(
          (candidate) =>
              _sameWorktreePath(candidate.path, worktree.path) &&
              candidate.head == worktree.head &&
              candidate.branch == worktree.branch,
        )
        .firstOrNull;
    if (current == null || current.isPrunable) {
      throw const GitError(
        category: GitErrorCategory.staleWorktreePreview,
        userMessage:
            'The worktree changed or is no longer available. Refresh it.',
        diagnostic:
            'worktree path, branch, or HEAD no longer matched the listed entry',
        retryable: true,
      );
    }
    if (!Directory(current.path).existsSync()) {
      throw const GitError(
        category: GitErrorCategory.repositoryMoved,
        userMessage: 'The worktree folder is no longer available.',
        diagnostic: 'worktree path disappeared before it could be opened',
        retryable: true,
      );
    }
    if (_sameWorktreePath(handle.root, current.path)) {
      return state.register(handle.root);
    }
    return openRepository(current.path);
  }

  Future<GitWorktreeActionPreview> previewWorktreeAction(
    RepositoryId repositoryId,
    GitWorktreeActionRequest request,
  ) async {
    final inspection = await _buildWorktreeActionPreview(repositoryId, request);
    if (inspection.blockingMessage != null) return inspection;
    final token = state.issueWorktreePreview(
      repositoryId: repositoryId,
      request: request,
      fingerprint: inspection.fingerprint,
    );
    return _copyWorktreeActionPreview(
      inspection,
      request: _copyWorktreeRequest(request, token.value),
      token: token.value,
      expiresAt: token.expiresAt,
    );
  }

  Future<GitWorktreeActionResult> executeWorktreeAction(
    RepositoryId repositoryId,
    GitWorktreeActionRequest request, {
    GitCancellationToken? cancellationToken,
  }) => state.runMutation(repositoryId, () async {
    final inspection = await _buildWorktreeActionPreview(repositoryId, request);
    if (inspection.blockingMessage != null) {
      throw _worktreeBlockingError(inspection);
    }
    state.validateWorktreePreview(
      repositoryId: repositoryId,
      request: request,
      fingerprint: inspection.fingerprint,
    );
    if (request.confirmationToken case final token?) {
      state.consumeWorktreePreview(token);
    }
    final handle = await state.lookup(repositoryId);
    final args = switch (request.action) {
      GitWorktreeAction.remove => [
        'worktree',
        'remove',
        if (inspection.worktree.isDirty) '--force',
        inspection.worktree.path,
      ],
      GitWorktreeAction.lock => [
        'worktree',
        'lock',
        if (request.lockReason case final reason? when reason.trim().isNotEmpty)
          '--reason=$reason',
        inspection.worktree.path,
      ],
      GitWorktreeAction.unlock => [
        'worktree',
        'unlock',
        inspection.worktree.path,
      ],
      GitWorktreeAction.prune => const ['worktree', 'prune', '--verbose'],
    };
    late final ProcessOutput output;
    try {
      output = await _runner.run(
        GitInvocation(
          program: gitPath,
          args: args,
          cwd: handle.root,
          kind: GitOperationKind.mutation,
          outputPolicy: const OutputPolicy.capture(maxBytes: 512 * 1024),
          cancellationToken: cancellationToken,
        ),
      );
    } on GitError catch (error, stackTrace) {
      Error.throwWithStackTrace(_mapWorktreeError(error), stackTrace);
    }
    final snapshot = await getWorktrees(repositoryId);
    return GitWorktreeActionResult(
      repositoryId: repositoryId,
      request: request,
      action: request.action,
      status: await getStatus(repositoryId),
      snapshot: snapshot,
      summary: _objectSummary(output, _worktreeActionSummary(request.action)),
    );
  });

  Future<GitWorktreeActionPreview> _buildWorktreeActionPreview(
    RepositoryId repositoryId,
    GitWorktreeActionRequest request,
  ) async {
    if (request.path.trim().isEmpty ||
        request.path.contains('\u0000') ||
        request.path.runes.any((rune) => rune < 0x20)) {
      throw worktreeInputError(
        'Choose a valid worktree path.',
        'worktree action path was empty or contained control characters',
      );
    }
    final handle = await state.lookup(repositoryId);
    final snapshot = await getWorktrees(repositoryId);
    final normalized = _worktreePathFromInput(handle.root, request.path);
    final worktree = snapshot.worktrees
        .where((candidate) => _sameWorktreePath(candidate.path, normalized))
        .firstOrNull;
    if (worktree == null) {
      throw const GitError(
        category: GitErrorCategory.staleWorktreePreview,
        userMessage:
            'That worktree is no longer listed. Refresh the worktrees.',
        diagnostic:
            'worktree action targeted a path absent from the current list',
        retryable: true,
      );
    }
    var blockingMessage = <String>[];
    switch (request.action) {
      case GitWorktreeAction.remove:
        if (worktree.isMain) {
          blockingMessage.add('The main worktree cannot be removed.');
        }
        if (worktree.isCurrent) {
          blockingMessage.add('The currently open worktree cannot be removed.');
        }
        if (worktree.isLocked) {
          blockingMessage.add('Unlock this worktree before removing it.');
        }
        if (worktree.isPrunable) {
          blockingMessage.add('Use prune for a missing worktree record.');
        }
        if (worktree.isDirty && !request.confirmDirty) {
          blockingMessage.add(
            'This worktree has local changes. Confirm dirty removal to continue.',
          );
        }
      case GitWorktreeAction.lock:
        if (worktree.isLocked) {
          blockingMessage.add('The worktree is already locked.');
        }
        if (worktree.isPrunable) {
          blockingMessage.add('A missing worktree cannot be locked.');
        }
      case GitWorktreeAction.unlock:
        if (!worktree.isLocked) {
          blockingMessage.add('The worktree is not locked.');
        }
        if (worktree.isPrunable) {
          blockingMessage.add('A missing worktree cannot be unlocked.');
        }
      case GitWorktreeAction.prune:
        if (!worktree.isPrunable) {
          blockingMessage.add('That worktree has no stale record to prune.');
        }
    }
    final fingerprint = hashGitObjectBytes(
      utf8.encode(
        [
          snapshot.fingerprint,
          request.queryKey,
          worktree.path,
          worktree.head ?? '',
          worktree.branch ?? '',
          worktree.isLocked,
          worktree.isPrunable,
          worktree.isDirty,
          ...worktree.dirtyPaths,
        ].join('|'),
      ),
    );
    return GitWorktreeActionPreview(
      repositoryId: repositoryId,
      request: request,
      worktree: worktree,
      dirtyPaths: worktree.dirtyPaths,
      requiresConfirmation:
          request.action == GitWorktreeAction.remove && worktree.isDirty,
      fingerprint: fingerprint,
      blockingMessage: blockingMessage.isEmpty
          ? null
          : blockingMessage.join(' '),
    );
  }

  GitWorktreeActionPreview _copyWorktreeActionPreview(
    GitWorktreeActionPreview preview, {
    required GitWorktreeActionRequest request,
    required String token,
    required DateTime expiresAt,
  }) => GitWorktreeActionPreview(
    repositoryId: preview.repositoryId,
    request: request,
    worktree: preview.worktree,
    dirtyPaths: preview.dirtyPaths,
    requiresConfirmation: preview.requiresConfirmation,
    fingerprint: preview.fingerprint,
    blockingMessage: preview.blockingMessage,
    token: token,
    expiresAt: expiresAt,
  );

  GitWorktreeActionRequest _copyWorktreeRequest(
    GitWorktreeActionRequest request,
    String token,
  ) => GitWorktreeActionRequest(
    action: request.action,
    path: request.path,
    confirmDirty: request.confirmDirty,
    lockReason: request.lockReason,
    confirmationToken: token,
  );

  Future<ParsedGitStatus> _readWorktreeStatus(String path) async {
    final output = await _runner.run(
      GitInvocation(
        program: gitPath,
        args: const ['status', '--porcelain=v2', '-z', '--branch'],
        cwd: path,
        kind: GitOperationKind.read,
        outputPolicy: const OutputPolicy.capture(maxBytes: 512 * 1024),
      ),
    );
    try {
      return parseGitStatus(output.stdout);
    } on FormatException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        GitError(
          category: GitErrorCategory.parseFailure,
          userMessage: 'Git returned an unreadable worktree status.',
          diagnostic: error.message,
          retryable: true,
        ),
        stackTrace,
      );
    }
  }

  Future<String> _resolveWorktreePath(String root, String input) async {
    final path = _worktreePathFromInput(root, input);
    final directory = Directory(path);
    if (directory.existsSync()) return directory.resolveSymbolicLinks();
    final parent = directory.parent;
    if (!parent.existsSync()) {
      throw worktreeInputError(
        'Create the worktree parent folder first.',
        'worktree destination parent did not exist',
      );
    }
    final parentPath = await parent.resolveSymbolicLinks();
    final segments = directory.uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (segments.isEmpty) {
      throw worktreeInputError(
        'Choose a valid worktree destination.',
        'worktree destination did not contain a final path segment',
      );
    }
    return '$parentPath${Platform.pathSeparator}${segments.last}';
  }

  void _validateWorktreeCreateRequest(GitWorktreeCreateRequest request) {
    if (request.path.trim().isEmpty ||
        request.path.contains('\u0000') ||
        request.path.runes.any((rune) => rune < 0x20)) {
      throw worktreeInputError(
        'Choose a valid worktree destination.',
        'worktree create path was empty or contained control characters',
      );
    }
    if (request.detach && request.branch != null) {
      throw worktreeInputError(
        'Detached worktrees cannot also select a branch.',
        'worktree create combined detach and branch options',
      );
    }
    if (!request.detach && request.branch == null) {
      throw worktreeInputError(
        'Choose a branch or create a detached worktree.',
        'worktree create omitted both branch and detach mode',
      );
    }
    if (!request.createBranch && request.startPoint != null) {
      throw worktreeInputError(
        'An existing branch cannot use a separate start point.',
        'existing branch worktree request contained a start point',
      );
    }
  }

  GitError _worktreeBlockingError(GitWorktreeActionPreview preview) {
    final message =
        preview.blockingMessage ?? 'Review the worktree action again.';
    final category =
        message.contains('cannot be removed') || message.contains('Unlock')
        ? GitErrorCategory.worktreeOperationNotAllowed
        : message.contains('local changes')
        ? GitErrorCategory.dirtyWorktree
        : GitErrorCategory.staleWorktreePreview;
    return GitError(
      category: category,
      userMessage: message,
      diagnostic: 'worktree action was blocked before mutation',
      retryable: category == GitErrorCategory.staleWorktreePreview,
    );
  }

  String _worktreeActionSummary(GitWorktreeAction action) => switch (action) {
    GitWorktreeAction.remove => 'The worktree was removed.',
    GitWorktreeAction.lock => 'The worktree was locked.',
    GitWorktreeAction.unlock => 'The worktree was unlocked.',
    GitWorktreeAction.prune => 'Stale worktree records were pruned.',
  };

  Future<GitStashSnapshot> getStashes(RepositoryId repositoryId) async {
    final handle = await state.lookup(repositoryId);
    return _readStashSnapshot(repositoryId, handle);
  }

  Future<GitStashActionResult> createStash(
    RepositoryId repositoryId, {
    String message = '',
    bool includeUntracked = false,
  }) async {
    _validateObjectMessage(message, 'stash message');
    return state.runMutation(repositoryId, () async {
      final handle = await state.lookup(repositoryId);
      final args = <String>[
        'stash',
        'push',
        if (includeUntracked) '--include-untracked',
        if (message.trim().isNotEmpty) ...['--message=$message'],
      ];
      late final ProcessOutput output;
      try {
        output = await _runObjectCommand(handle, args);
      } on GitError catch (error, stackTrace) {
        Error.throwWithStackTrace(_mapObjectError(error), stackTrace);
      }
      return GitStashActionResult(
        repositoryId: repositoryId,
        action: GitStashAction.create,
        state: GitStashActionState.completed,
        status: await getStatus(repositoryId),
        snapshot: await _readStashSnapshot(repositoryId, handle),
        summary: _objectSummary(output, 'The changes were stashed.'),
      );
    });
  }

  Future<GitStashActionResult> applyStash(
    RepositoryId repositoryId,
    String stashOid, {
    required String fingerprint,
  }) => _runStashAction(
    repositoryId,
    stashOid,
    fingerprint: fingerprint,
    action: GitStashAction.apply,
    command: const ['stash', 'apply', '--index'],
  );

  Future<GitStashActionResult> popStash(
    RepositoryId repositoryId,
    String stashOid, {
    required String fingerprint,
  }) => _runStashAction(
    repositoryId,
    stashOid,
    fingerprint: fingerprint,
    action: GitStashAction.pop,
    command: const ['stash', 'pop', '--index'],
  );

  Future<GitObjectPreview> previewStashDrop(
    RepositoryId repositoryId,
    String stashOid,
  ) async {
    _validateObjectOid(stashOid, 'stash');
    final snapshot = await getStashes(repositoryId);
    final entry = _findStash(snapshot, stashOid);
    if (entry == null) throw _objectNotFound('stash', stashOid);
    return state.issueObjectPreview(
      repositoryId: repositoryId,
      action: GitObjectPreviewAction.dropStash,
      objectName: entry.selector,
      objectId: entry.oid,
      fingerprint: snapshot.fingerprint,
      details: [entry.subject, entry.oid],
    );
  }

  Future<GitStashActionResult> dropStash(
    RepositoryId repositoryId,
    GitObjectPreview preview,
  ) async {
    return state.runMutation(repositoryId, () async {
      final handle = await state.lookup(repositoryId);
      final snapshot = await _readStashSnapshot(repositoryId, handle);
      final stashOid = preview.objectId;
      if (stashOid == null) throw _objectNotFound('stash', preview.objectName);
      final entry = _findStash(snapshot, stashOid);
      if (entry == null) throw _objectNotFound('stash', stashOid);
      state.validateObjectPreview(
        repositoryId: repositoryId,
        preview: preview,
        fingerprint: snapshot.fingerprint,
        objectId: entry.oid,
      );
      state.consumeObjectPreview(preview.token);
      late final ProcessOutput output;
      try {
        output = await _runObjectCommand(handle, [
          'stash',
          'drop',
          entry.selector,
        ]);
      } on GitError catch (error, stackTrace) {
        Error.throwWithStackTrace(_mapObjectError(error), stackTrace);
      }
      return GitStashActionResult(
        repositoryId: repositoryId,
        action: GitStashAction.drop,
        state: GitStashActionState.completed,
        status: await getStatus(repositoryId),
        snapshot: await _readStashSnapshot(repositoryId, handle),
        stashOid: entry.oid,
        summary: _objectSummary(output, 'The stash was dropped.'),
      );
    });
  }

  Future<GitStashActionResult> branchFromStash(
    RepositoryId repositoryId,
    String branchName,
    String stashOid, {
    required String fingerprint,
  }) async {
    _validateObjectOid(stashOid, 'stash');
    return state.runMutation(repositoryId, () async {
      final handle = await state.lookup(repositoryId);
      await _validateBranchNameWithGit(handle, branchName);
      final snapshot = await _readStashSnapshot(repositoryId, handle);
      final entry = _requireFreshStash(snapshot, stashOid, fingerprint);
      late final ProcessOutput output;
      try {
        output = await _runObjectCommand(handle, [
          'stash',
          'branch',
          branchName,
          entry.selector,
        ]);
      } on GitError catch (error, stackTrace) {
        final status = await getStatus(repositoryId);
        if (status.conflicts.isNotEmpty) {
          return GitStashActionResult(
            repositoryId: repositoryId,
            action: GitStashAction.branch,
            state: GitStashActionState.conflicted,
            status: status,
            snapshot: await _readStashSnapshot(repositoryId, handle),
            stashOid: entry.oid,
            summary: 'The stash branch operation has conflicts to resolve.',
          );
        }
        Error.throwWithStackTrace(_mapObjectError(error), stackTrace);
      }
      return GitStashActionResult(
        repositoryId: repositoryId,
        action: GitStashAction.branch,
        state: GitStashActionState.completed,
        status: await getStatus(repositoryId),
        snapshot: await _readStashSnapshot(repositoryId, handle),
        stashOid: entry.oid,
        summary: _objectSummary(output, 'A branch was created from the stash.'),
      );
    });
  }

  Future<GitTagSnapshot> getTags(RepositoryId repositoryId) async {
    final handle = await state.lookup(repositoryId);
    final output = await _runObjectCommand(
      handle,
      const [
        'for-each-ref',
        '--sort=refname',
        '--format=%(refname:short)%00%(objectname)%00%(objecttype)%00%(*objectname)%00%(*objecttype)%00%(contents:subject)%00%(creatordate:iso-strict)',
        'refs/tags/',
      ],
      kind: GitOperationKind.read,
      maxBytes: 2 * 1024 * 1024,
    );
    try {
      return GitTagSnapshot(
        repositoryId: repositoryId,
        tags: parseGitTags(output.stdout),
        fingerprint: hashGitObjectBytes(output.stdout),
      );
    } on FormatException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        GitError(
          category: GitErrorCategory.parseFailure,
          userMessage: 'Git returned an unreadable tag list.',
          diagnostic: error.message,
          retryable: false,
        ),
        stackTrace,
      );
    }
  }

  Future<GitTagActionResult> createTag(
    RepositoryId repositoryId,
    String name, {
    String? target,
    bool annotated = false,
    String message = '',
  }) async {
    _validateTagName(name);
    _validateObjectMessage(message, 'tag message');
    return state.runMutation(repositoryId, () async {
      final handle = await state.lookup(repositoryId);
      await _validateTagNameWithGit(handle, name);
      final targetOid = await _resolveObjectCommit(handle, target ?? 'HEAD');
      if (annotated && message.trim().isEmpty) {
        throw const GitError(
          category: GitErrorCategory.objectOperationNotAllowed,
          userMessage: 'An annotated tag needs a message.',
          diagnostic: 'annotated tag message was empty',
          retryable: false,
        );
      }
      final args = <String>['tag', if (annotated) '-a', name, targetOid];
      if (annotated) args.addAll(['--message=$message']);
      late final ProcessOutput output;
      try {
        output = await _runObjectCommand(handle, args);
      } on GitError catch (error, stackTrace) {
        Error.throwWithStackTrace(_mapObjectError(error), stackTrace);
      }
      final tags = await getTags(repositoryId);
      return GitTagActionResult(
        repositoryId: repositoryId,
        action: GitTagAction.create,
        status: await getStatus(repositoryId),
        snapshot: tags,
        tag: tags.tags.where((tag) => tag.name == name).firstOrNull,
        summary: _objectSummary(output, 'The tag was created.'),
      );
    });
  }

  Future<GitTag> getTag(RepositoryId repositoryId, String name) async {
    _validateTagName(name);
    final snapshot = await getTags(repositoryId);
    final tag = snapshot.tags.where((value) => value.name == name).firstOrNull;
    if (tag == null) throw _objectNotFound('tag', name);
    if (tag.kind != GitTagKind.annotated || tag.tagObjectOid == null) {
      return tag;
    }
    final handle = await state.lookup(repositoryId);
    final output = await _runObjectCommand(
      handle,
      ['cat-file', 'tag', tag.tagObjectOid!],
      kind: GitOperationKind.read,
      maxBytes: 256 * 1024,
    );
    final raw = utf8.decode(output.stdout, allowMalformed: true);
    final separator = raw.indexOf('\n\n');
    final header = separator < 0 ? raw : raw.substring(0, separator);
    final body = separator < 0 ? '' : raw.substring(separator + 2).trim();
    final tagger = RegExp(
      r'^tagger (.+)$',
      multiLine: true,
    ).firstMatch(header)?.group(1);
    return GitTag(
      name: tag.name,
      targetOid: tag.targetOid,
      kind: tag.kind,
      tagObjectOid: tag.tagObjectOid,
      subject: tag.subject,
      message: body,
      tagger: tagger,
      createdAt: tag.createdAt,
    );
  }

  Future<GitObjectPreview> previewTagDelete(
    RepositoryId repositoryId,
    String name,
  ) async {
    final tag = await getTag(repositoryId, name);
    final snapshot = await getTags(repositoryId);
    return state.issueObjectPreview(
      repositoryId: repositoryId,
      action: GitObjectPreviewAction.deleteTag,
      objectName: tag.name,
      objectId: _tagIdentity(tag),
      fingerprint: snapshot.fingerprint,
      details: [tag.kind.name, tag.targetOid],
    );
  }

  Future<GitTagActionResult> deleteTag(
    RepositoryId repositoryId,
    GitObjectPreview preview,
  ) async {
    return state.runMutation(repositoryId, () async {
      final handle = await state.lookup(repositoryId);
      final snapshot = await getTags(repositoryId);
      final tag = snapshot.tags
          .where((value) => value.name == preview.objectName)
          .firstOrNull;
      if (tag == null) throw _objectNotFound('tag', preview.objectName);
      state.validateObjectPreview(
        repositoryId: repositoryId,
        preview: preview,
        fingerprint: snapshot.fingerprint,
        objectId: _tagIdentity(tag),
      );
      state.consumeObjectPreview(preview.token);
      late final ProcessOutput output;
      try {
        output = await _runObjectCommand(handle, ['tag', '--delete', tag.name]);
      } on GitError catch (error, stackTrace) {
        Error.throwWithStackTrace(_mapObjectError(error), stackTrace);
      }
      return GitTagActionResult(
        repositoryId: repositoryId,
        action: GitTagAction.delete,
        status: await getStatus(repositoryId),
        snapshot: await getTags(repositoryId),
        summary: _objectSummary(output, 'The tag was deleted.'),
      );
    });
  }

  Future<GitRemoteActionResult> addRemote(
    RepositoryId repositoryId,
    String name,
    String url,
  ) {
    _validateRemoteName(name);
    _validateRemoteUrl(url);
    return _runRemoteConfigAction(
      repositoryId,
      GitRemoteAction.add,
      name,
      ['remote', 'add', name, url],
      preflight: (remotes) {
        if (remotes.any((remote) => remote.name == name)) {
          throw _objectAlreadyExists('remote', name);
        }
      },
    );
  }

  Future<GitRemoteActionResult> renameRemote(
    RepositoryId repositoryId,
    String oldName,
    String newName,
  ) {
    _validateRemoteName(oldName);
    _validateRemoteName(newName);
    return _runRemoteConfigAction(
      repositoryId,
      GitRemoteAction.rename,
      oldName,
      ['remote', 'rename', oldName, newName],
      preflight: (remotes) {
        if (_findRemote(remotes, oldName) == null) {
          throw _objectNotFound('remote', oldName);
        }
        if (remotes.any((remote) => remote.name == newName)) {
          throw _objectAlreadyExists('remote', newName);
        }
      },
    );
  }

  Future<GitRemoteActionResult> setRemoteUrl(
    RepositoryId repositoryId,
    String name,
    String url, {
    bool push = false,
  }) {
    _validateRemoteName(name);
    _validateRemoteUrl(url);
    return _runRemoteConfigAction(
      repositoryId,
      GitRemoteAction.setUrl,
      name,
      ['remote', 'set-url', if (push) '--push', name, url],
      argsBuilder: push
          ? (remotes) {
              final remote = _findRemote(remotes, name)!;
              return [
                'remote',
                'set-url',
                if (remote.pushUrl == null) '--add',
                '--push',
                name,
                url,
              ];
            }
          : null,
      preflight: (remotes) {
        if (_findRemote(remotes, name) == null) {
          throw _objectNotFound('remote', name);
        }
      },
    );
  }

  Future<GitObjectPreview> previewRemoteRemove(
    RepositoryId repositoryId,
    String name,
  ) async {
    _validateRemoteName(name);
    final remotes = await getRemotes(repositoryId);
    final remote = _findRemote(remotes, name);
    if (remote == null) throw _objectNotFound('remote', name);
    return state.issueObjectPreview(
      repositoryId: repositoryId,
      action: GitObjectPreviewAction.removeRemote,
      objectName: name,
      objectId: _remoteIdentity(remote),
      fingerprint: _remoteFingerprint(remotes),
      details: [
        if (remote.fetchUrl case final url?) redactRemote(url),
        if (remote.pushUrl case final url?) redactRemote(url),
      ],
    );
  }

  Future<GitRemoteActionResult> removeRemote(
    RepositoryId repositoryId,
    GitObjectPreview preview,
  ) {
    return _runRemoteConfigAction(
      repositoryId,
      GitRemoteAction.remove,
      preview.objectName,
      ['remote', 'remove', preview.objectName],
      preview: preview,
      preflight: (remotes) {
        final remote = _findRemote(remotes, preview.objectName);
        if (remote == null) throw _objectNotFound('remote', preview.objectName);
        state.validateObjectPreview(
          repositoryId: repositoryId,
          preview: preview,
          fingerprint: _remoteFingerprint(remotes),
          objectId: _remoteIdentity(remote),
        );
      },
    );
  }

  Future<GitObjectPreview> previewRemotePrune(
    RepositoryId repositoryId,
    String name,
  ) async {
    _validateRemoteName(name);
    final remotes = await getRemotes(repositoryId);
    if (_findRemote(remotes, name) == null) {
      throw _objectNotFound('remote', name);
    }
    final handle = await state.lookup(repositoryId);
    final output = await _runObjectCommand(
      handle,
      ['remote', 'prune', '--dry-run', name],
      kind: GitOperationKind.read,
      maxBytes: 512 * 1024,
    );
    final details = utf8
        .decode([...output.stdout, ...output.stderr], allowMalformed: true)
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    return state.issueObjectPreview(
      repositoryId: repositoryId,
      action: GitObjectPreviewAction.pruneRemote,
      objectName: name,
      fingerprint: _remoteFingerprint(remotes),
      details: details,
    );
  }

  Future<GitRemoteActionResult> pruneRemote(
    RepositoryId repositoryId,
    GitObjectPreview preview,
  ) => _runRemoteConfigAction(
    repositoryId,
    GitRemoteAction.prune,
    preview.objectName,
    ['remote', 'prune', preview.objectName],
    preview: preview,
    preflight: (remotes) {
      if (_findRemote(remotes, preview.objectName) == null) {
        throw _objectNotFound('remote', preview.objectName);
      }
      state.validateObjectPreview(
        repositoryId: repositoryId,
        preview: preview,
        fingerprint: _remoteFingerprint(remotes),
      );
    },
  );

  Future<GitRemoteOperationResult> pushTag(
    RepositoryId repositoryId,
    String remote,
    String tagName, {
    GitCancellationToken? cancellationToken,
  }) async {
    _validateRemoteName(remote);
    _validateTagName(tagName);
    return state.runMutation(repositoryId, () async {
      final handle = await state.lookup(repositoryId);
      final remotes = await getRemotes(repositoryId);
      final selectedRemote = _findRemote(remotes, remote);
      if (_findRemote(remotes, remote) == null) {
        throw _objectNotFound('remote', remote);
      }
      await getTag(repositoryId, tagName);
      late final ProcessOutput output;
      try {
        output = await _runObjectCommand(
          handle,
          ['push', remote, 'refs/tags/$tagName'],
          kind: GitOperationKind.remote,
          maxBytes: 2 * 1024 * 1024,
          cancellationToken: cancellationToken,
          remoteUrl: selectedRemote?.pushUrl ?? selectedRemote?.fetchUrl,
        );
      } on GitError catch (error, stackTrace) {
        Error.throwWithStackTrace(_mapRemoteError(error), stackTrace);
      }
      return GitRemoteOperationResult(
        repositoryId: repositoryId,
        remote: remote,
        operation: GitRemoteOperation.push,
        target: tagName,
        status: await getStatus(repositoryId),
        summary: _objectSummary(output, 'The tag was pushed.'),
      );
    });
  }

  Future<GitUpstreamSnapshot> getUpstream(RepositoryId repositoryId) async {
    final status = await getStatus(repositoryId);
    return _upstreamSnapshot(repositoryId, status);
  }

  Future<GitUpstreamActionResult> setUpstream(
    RepositoryId repositoryId,
    String remote, {
    String? branch,
    String? remoteBranch,
  }) => _runUpstreamAction(
    repositoryId,
    GitUpstreamAction.set,
    remote,
    branch: branch,
    remoteBranch: remoteBranch,
  );

  Future<GitUpstreamActionResult> unsetUpstream(
    RepositoryId repositoryId, {
    String? branch,
  }) => _runUpstreamAction(
    repositoryId,
    GitUpstreamAction.unset,
    null,
    branch: branch,
  );

  Future<GitUpstreamActionResult> publishBranch(
    RepositoryId repositoryId,
    String remote, {
    String? branch,
  }) => _runUpstreamAction(
    repositoryId,
    GitUpstreamAction.publish,
    remote,
    branch: branch,
  );

  Future<GitStashSnapshot> _readStashSnapshot(
    RepositoryId repositoryId,
    RepositoryHandle handle,
  ) async {
    final output = await _runObjectCommand(
      handle,
      const ['stash', 'list', '--format=%H%x00%gd%x00%gs%x00%aI'],
      kind: GitOperationKind.read,
      maxBytes: 2 * 1024 * 1024,
    );
    try {
      return GitStashSnapshot(
        repositoryId: repositoryId,
        entries: parseGitStashes(output.stdout),
        fingerprint: hashGitObjectBytes(output.stdout),
      );
    } on FormatException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        GitError(
          category: GitErrorCategory.parseFailure,
          userMessage: 'Git returned an unreadable stash list.',
          diagnostic: error.message,
          retryable: false,
        ),
        stackTrace,
      );
    }
  }

  Future<GitStashActionResult> _runStashAction(
    RepositoryId repositoryId,
    String stashOid, {
    required String fingerprint,
    required GitStashAction action,
    required List<String> command,
  }) async {
    _validateObjectOid(stashOid, 'stash');
    return state.runMutation(repositoryId, () async {
      final handle = await state.lookup(repositoryId);
      final snapshot = await _readStashSnapshot(repositoryId, handle);
      final entry = _requireFreshStash(snapshot, stashOid, fingerprint);
      late final ProcessOutput output;
      try {
        output = await _runObjectCommand(handle, [...command, entry.selector]);
      } on GitError catch (error, stackTrace) {
        final status = await getStatus(repositoryId);
        if (status.conflicts.isNotEmpty || _looksLikeConflict(error)) {
          return GitStashActionResult(
            repositoryId: repositoryId,
            action: action,
            state: GitStashActionState.conflicted,
            status: status,
            snapshot: await _readStashSnapshot(repositoryId, handle),
            stashOid: entry.oid,
            summary: 'The stash operation has conflicts to resolve.',
          );
        }
        Error.throwWithStackTrace(_mapObjectError(error), stackTrace);
      }
      return GitStashActionResult(
        repositoryId: repositoryId,
        action: action,
        state: GitStashActionState.completed,
        status: await getStatus(repositoryId),
        snapshot: await _readStashSnapshot(repositoryId, handle),
        stashOid: entry.oid,
        summary: _objectSummary(
          output,
          action == GitStashAction.apply
              ? 'The stash was applied.'
              : 'The stash was popped.',
        ),
      );
    });
  }

  GitStashEntry _requireFreshStash(
    GitStashSnapshot snapshot,
    String stashOid,
    String fingerprint,
  ) {
    if (snapshot.fingerprint != fingerprint) {
      throw const GitError(
        category: GitErrorCategory.staleObject,
        userMessage: 'The stash list changed. Review the stash again.',
        diagnostic: 'stash list fingerprint no longer matched the selection',
        retryable: true,
      );
    }
    final entry = _findStash(snapshot, stashOid);
    if (entry == null) throw _objectNotFound('stash', stashOid);
    return entry;
  }

  Future<GitRemoteActionResult> _runRemoteConfigAction(
    RepositoryId repositoryId,
    GitRemoteAction action,
    String objectName,
    List<String> args, {
    required void Function(List<GitRemote>) preflight,
    GitObjectPreview? preview,
    List<String> Function(List<GitRemote> remotes)? argsBuilder,
  }) async {
    return state.runMutation(repositoryId, () async {
      final handle = await state.lookup(repositoryId);
      final remotes = await getRemotes(repositoryId);
      preflight(remotes);
      if (preview != null) state.consumeObjectPreview(preview.token);
      late final ProcessOutput output;
      try {
        output = await _runObjectCommand(
          handle,
          argsBuilder?.call(remotes) ?? args,
        );
      } on GitError catch (error, stackTrace) {
        Error.throwWithStackTrace(_mapObjectError(error), stackTrace);
      }
      return GitRemoteActionResult(
        repositoryId: repositoryId,
        action: action,
        remotes: await getRemotes(repositoryId),
        status: await getStatus(repositoryId),
        remoteName: objectName,
        summary: _objectSummary(output, 'The remote configuration changed.'),
      );
    });
  }

  Future<GitUpstreamActionResult> _runUpstreamAction(
    RepositoryId repositoryId,
    GitUpstreamAction action,
    String? remote, {
    String? branch,
    String? remoteBranch,
  }) async {
    if (remote != null) _validateRemoteName(remote);
    return state.runMutation(repositoryId, () async {
      final handle = await state.lookup(repositoryId);
      final before = await getStatus(repositoryId);
      final selectedBranch = branch ?? before.branch.head;
      if (selectedBranch == null ||
          selectedBranch.isEmpty ||
          before.branch.isDetached) {
        throw const GitError(
          category: GitErrorCategory.detachedHead,
          userMessage: 'Switch to a branch before changing upstream settings.',
          diagnostic: 'upstream operation requested without an attached branch',
          retryable: false,
        );
      }
      await _validateBranchNameWithGit(handle, selectedBranch);
      final remotes = await getRemotes(repositoryId);
      final selectedRemote = remote == null
          ? null
          : _findRemote(remotes, remote);
      if (action != GitUpstreamAction.unset &&
          (remote == null || _findRemote(remotes, remote) == null)) {
        throw _objectNotFound('remote', remote ?? '');
      }
      final args = switch (action) {
        GitUpstreamAction.set => [
          'branch',
          '--set-upstream-to=${remote!}/${remoteBranch ?? selectedBranch}',
          selectedBranch,
        ],
        GitUpstreamAction.unset => [
          'branch',
          '--unset-upstream',
          selectedBranch,
        ],
        GitUpstreamAction.publish => [
          'push',
          '--set-upstream',
          remote!,
          selectedBranch,
        ],
      };
      late final ProcessOutput output;
      try {
        output = await _runObjectCommand(
          handle,
          args,
          kind: action == GitUpstreamAction.publish
              ? GitOperationKind.remote
              : GitOperationKind.mutation,
          maxBytes: 2 * 1024 * 1024,
          remoteUrl: action == GitUpstreamAction.publish
              ? selectedRemote?.pushUrl ?? selectedRemote?.fetchUrl
              : null,
        );
      } on GitError catch (error, stackTrace) {
        Error.throwWithStackTrace(
          action == GitUpstreamAction.publish
              ? _mapRemoteError(error)
              : _mapObjectError(error),
          stackTrace,
        );
      }
      final status = await getStatus(repositoryId);
      return GitUpstreamActionResult(
        repositoryId: repositoryId,
        action: action,
        status: status,
        upstream: _upstreamSnapshot(repositoryId, status),
        summary: _objectSummary(output, 'Upstream settings were updated.'),
      );
    });
  }

  GitUpstreamSnapshot _upstreamSnapshot(
    RepositoryId repositoryId,
    GitStatusSnapshot status,
  ) {
    final upstream = status.branch.upstream;
    String? remote;
    String? remoteBranch;
    if (upstream != null && upstream.isNotEmpty) {
      final slash = upstream.indexOf('/');
      if (slash > 0) {
        remote = upstream.substring(0, slash);
        remoteBranch = upstream.substring(slash + 1);
      }
    }
    return GitUpstreamSnapshot(
      repositoryId: repositoryId,
      branch: status.branch.head,
      remote: remote,
      remoteBranch: remoteBranch,
      ahead: status.branch.ahead,
      behind: status.branch.behind,
    );
  }

  Future<ProcessOutput> _runObjectCommand(
    RepositoryHandle handle,
    List<String> args, {
    GitOperationKind kind = GitOperationKind.mutation,
    int maxBytes = 512 * 1024,
    GitCancellationToken? cancellationToken,
    String? remoteUrl,
    String? credentialId,
  }) => _runWithCredentials(
    cwd: handle.root,
    args: args,
    kind: kind,
    maxBytes: maxBytes,
    cancellationToken: cancellationToken,
    remoteUrl: remoteUrl,
    credentialId: credentialId,
  );

  Future<String> _resolveObjectCommit(
    RepositoryHandle handle,
    String revision,
  ) async {
    _validateRevisionInput(revision);
    final resolved = await _tryResolve(handle, '$revision^{commit}');
    if (resolved == null || !_isObjectOidValue(resolved)) {
      throw GitError(
        category: GitErrorCategory.invalidRevision,
        userMessage: 'That target does not point to a commit.',
        diagnostic:
            'object target could not be resolved to a commit: $revision',
        retryable: false,
      );
    }
    return resolved;
  }

  Future<void> _validateTagNameWithGit(
    RepositoryHandle handle,
    String name,
  ) async {
    try {
      await _runner.run(
        GitInvocation(
          program: gitPath,
          args: ['check-ref-format', 'refs/tags/$name'],
          cwd: handle.root,
          kind: GitOperationKind.read,
          outputPolicy: const OutputPolicy.capture(maxBytes: 16 * 1024),
        ),
      );
    } on GitError catch (error, stackTrace) {
      if (error.category == GitErrorCategory.processFailed) {
        Error.throwWithStackTrace(
          error.copyWith(
            category: GitErrorCategory.invalidObjectName,
            userMessage: 'Enter a valid tag name accepted by Git.',
            diagnostic: 'git check-ref-format rejected the tag name',
            retryable: false,
          ),
          stackTrace,
        );
      }
      rethrow;
    }
  }

  Future<GitRemoteOperationResult> _runRemote(
    RepositoryId repositoryId,
    String remote,
    GitRemoteOperation operation, {
    GitCancellationToken? cancellationToken,
    String? credentialId,
  }) async {
    _validateRemoteName(remote);
    return state.runMutation(repositoryId, () async {
      final handle = await state.lookup(repositoryId);
      final remoteConfig = _findRemote(await getRemotes(repositoryId), remote);
      final status = await getStatus(repositoryId);
      final branch = status.branch.head;
      if ((operation == GitRemoteOperation.pull ||
              operation == GitRemoteOperation.push) &&
          (branch == null || branch.isEmpty || branch == '(detached)')) {
        throw const GitError(
          category: GitErrorCategory.detachedHead,
          userMessage: 'Switch to a branch before synchronizing.',
          diagnostic: 'remote operation requested while HEAD was detached',
          retryable: false,
        );
      }
      final args = switch (operation) {
        GitRemoteOperation.fetch => ['fetch', '--prune', remote],
        GitRemoteOperation.pull => ['pull', '--ff-only', remote, branch!],
        GitRemoteOperation.push => ['push', remote, branch!],
      };
      late final ProcessOutput output;
      try {
        output = await _runWithCredentials(
          cwd: handle.root,
          args: args,
          kind: GitOperationKind.remote,
          maxBytes: 2 * 1024 * 1024,
          cancellationToken: cancellationToken,
          remoteUrl: operation == GitRemoteOperation.push
              ? remoteConfig?.pushUrl ?? remoteConfig?.fetchUrl
              : remoteConfig?.fetchUrl ?? remoteConfig?.pushUrl,
          credentialId: credentialId,
        );
      } on GitError catch (error, stackTrace) {
        Error.throwWithStackTrace(_mapRemoteError(error), stackTrace);
      }
      final refreshed = await getStatus(repositoryId);
      final outputText = redactBytes([...output.stdout, ...output.stderr])
          .trim();
      return GitRemoteOperationResult(
        repositoryId: repositoryId,
        remote: remote,
        operation: operation,
        status: refreshed,
        summary: outputText.isEmpty ? 'Operation complete.' : outputText,
      );
    });
  }

  Future<GitDiffSnapshot> getDiff(
    RepositoryId repositoryId,
    String path, {
    GitDiffScope scope = GitDiffScope.workingTree,
    String? originalPath,
  }) async {
    if (path.isEmpty ||
        path.contains('\u0000') ||
        originalPath?.contains('\u0000') == true) {
      throw const GitError(
        category: GitErrorCategory.parseFailure,
        userMessage: 'Git could not inspect that file path.',
        diagnostic: 'diff path was empty or contained a NUL byte',
        retryable: false,
      );
    }

    final handle = await state.lookup(repositoryId);
    final args = <String>[
      'diff',
      '--no-color',
      '--no-ext-diff',
      '--find-renames',
      '--unified=3',
      if (scope == GitDiffScope.staged) '--cached',
      '--',
      ...?originalPath == null ? null : [originalPath],
      path,
    ];
    final output = await _runner.run(
      GitInvocation(
        program: gitPath,
        args: args,
        cwd: handle.root,
        kind: GitOperationKind.read,
        outputPolicy: const OutputPolicy.capture(maxBytes: 4 * 1024 * 1024),
      ),
    );
    return parseUnifiedDiff(
      output.stdout,
      path: path,
      scope: scope,
    ).copyWith(repositoryId: repositoryId);
  }

  Future<GitComparisonSnapshot> compareRevisions(
    RepositoryId repositoryId,
    String left,
    String right, {
    String? path,
  }) => compareSources(
    repositoryId,
    GitComparisonSource.revision(left),
    GitComparisonSource.revision(right),
    path: path,
  );

  Future<GitComparisonSnapshot> compareSources(
    RepositoryId repositoryId,
    GitComparisonSource left,
    GitComparisonSource right, {
    String? path,
  }) async {
    _validateComparisonSource(left);
    _validateComparisonSource(right);
    _validateComparisonPath(path);
    if ((left.isText || right.isText) && (path == null || path.isEmpty)) {
      throw const GitError(
        category: GitErrorCategory.parseFailure,
        userMessage: 'Choose a file path when comparing external text.',
        diagnostic: 'external comparison source was missing a file path',
        retryable: false,
      );
    }

    final request = GitComparisonRequest(
      repositoryId: repositoryId,
      left: left,
      right: right,
      path: path,
    );
    final handle = await state.lookup(repositoryId);
    if (left.isText || right.isText) {
      final contents = await Future.wait([
        _loadComparisonContent(handle, left, path!),
        _loadComparisonContent(handle, right, path),
      ]);
      return _comparisonFromContents(request, contents[0], contents[1]);
    }

    if (left.kind == GitComparisonSourceKind.workingTree &&
        right.kind == GitComparisonSourceKind.workingTree) {
      throw const GitError(
        category: GitErrorCategory.parseFailure,
        userMessage: 'Choose one repository revision and one working tree.',
        diagnostic: 'comparison requested two working-tree endpoints',
        retryable: false,
      );
    }
    final leftOid = await _comparisonSourceOid(handle, left);
    final rightOid = await _comparisonSourceOid(handle, right);
    final args = _comparisonNameStatusArgs(left, right, path);
    final output = await _runner.run(
      GitInvocation(
        program: gitPath,
        args: args,
        cwd: handle.root,
        kind: GitOperationKind.read,
        outputPolicy: const OutputPolicy.capture(maxBytes: 2 * 1024 * 1024),
      ),
    );

    late final List<GitComparisonFile> files;
    try {
      files = parseGitComparisonFiles(output.stdout);
    } on FormatException catch (error) {
      throw GitError(
        category: GitErrorCategory.parseFailure,
        userMessage: 'Git returned an unreadable comparison result.',
        diagnostic: 'comparison name-status parser failed: $error',
        retryable: false,
      );
    }
    var fingerprintBytes = <int>[...output.stdout];
    if (left.kind == GitComparisonSourceKind.workingTree ||
        right.kind == GitComparisonSourceKind.workingTree) {
      final rawOutput = await _runner.run(
        GitInvocation(
          program: gitPath,
          args: _comparisonRawArgs(left, right, path),
          cwd: handle.root,
          kind: GitOperationKind.read,
          outputPolicy: const OutputPolicy.capture(maxBytes: 2 * 1024 * 1024),
        ),
      );
      fingerprintBytes = [...fingerprintBytes, ...rawOutput.stdout];
    }
    return GitComparisonSnapshot(
      request: request,
      files: files,
      fingerprint: comparisonFingerprint(
        request,
        fingerprintBytes,
        leftOid: leftOid,
        rightOid: rightOid,
      ),
    );
  }

  Future<GitThreeWayComparisonSnapshot> compareThreeWay(
    RepositoryId repositoryId,
    GitComparisonSource base,
    GitComparisonSource left,
    GitComparisonSource right, {
    required String path,
  }) async {
    _validateComparisonSource(base);
    _validateComparisonSource(left);
    _validateComparisonSource(right);
    _validateComparisonPath(path);
    if (path.isEmpty) {
      throw const GitError(
        category: GitErrorCategory.parseFailure,
        userMessage: 'Choose a file for the three-way comparison.',
        diagnostic: 'three-way comparison path was empty',
        retryable: false,
      );
    }
    final handle = await state.lookup(repositoryId);
    final request = GitThreeWayComparisonRequest(
      repositoryId: repositoryId,
      base: base,
      left: left,
      right: right,
      path: path,
    );
    final contents = await Future.wait([
      _loadComparisonContent(handle, base, path),
      _loadComparisonContent(handle, left, path),
      _loadComparisonContent(handle, right, path),
    ]);
    return GitThreeWayComparisonSnapshot(
      request: request,
      base: contents[0],
      left: contents[1],
      right: contents[2],
      fingerprint: hashGitObjectBytes(
        utf8.encode(
          '${request.queryKey}\u0000${contents.map((content) => content.contentHash).join('\u0000')}',
        ),
      ),
    );
  }

  void _validateComparisonSource(GitComparisonSource source) {
    switch (source.kind) {
      case GitComparisonSourceKind.revision ||
          GitComparisonSourceKind.branch ||
          GitComparisonSourceKind.tag:
        _validateRevisionInput(source.value);
      case GitComparisonSourceKind.workingTree:
        break;
      case GitComparisonSourceKind.clipboard || GitComparisonSourceKind.text:
        final bytes = utf8.encode(source.value);
        if (bytes.length > maxComparisonTextBytes) {
          throw const GitError(
            category: GitErrorCategory.outputOverflow,
            userMessage: 'The external comparison text is too large.',
            diagnostic:
                'clipboard or external comparison text exceeded the '
                'bounded source size',
            retryable: false,
          );
        }
        if (bytes.contains(0)) {
          throw const GitError(
            category: GitErrorCategory.parseFailure,
            userMessage: 'The external comparison text contains binary data.',
            diagnostic: 'clipboard or external comparison text contained NUL',
            retryable: false,
          );
        }
    }
  }

  Future<String?> _comparisonSourceOid(
    RepositoryHandle handle,
    GitComparisonSource source,
  ) => source.kind == GitComparisonSourceKind.workingTree
      ? Future<String?>.value()
      : _resolveCommit(handle, source.value);

  List<String> _comparisonNameStatusArgs(
    GitComparisonSource left,
    GitComparisonSource right,
    String? path,
  ) => [
    'diff',
    '--no-color',
    '--no-ext-diff',
    '--find-renames',
    '--find-copies',
    '--name-status',
    '-z',
    ..._comparisonGitEndpoints(left, right),
    '--',
    ...?path == null ? null : [path],
  ];

  List<String> _comparisonRawArgs(
    GitComparisonSource left,
    GitComparisonSource right,
    String? path,
  ) => [
    'diff',
    '--no-color',
    '--no-ext-diff',
    '--find-renames',
    '--find-copies',
    '--raw',
    '-z',
    ..._comparisonGitEndpoints(left, right),
    '--',
    ...?path == null ? null : [path],
  ];

  List<String> _comparisonPatchArgs(
    GitComparisonSource left,
    GitComparisonSource right,
    String path,
  ) => [
    'diff',
    '--no-color',
    '--no-ext-diff',
    '--find-renames',
    '--unified=3',
    ..._comparisonGitEndpoints(left, right),
    '--',
    path,
  ];

  List<String> _comparisonGitEndpoints(
    GitComparisonSource left,
    GitComparisonSource right,
  ) {
    if (left.kind == GitComparisonSourceKind.workingTree) {
      return [right.value];
    }
    if (right.kind == GitComparisonSourceKind.workingTree) {
      return [left.value];
    }
    return [left.value, right.value];
  }

  Future<GitComparisonContent> _loadComparisonContent(
    RepositoryHandle handle,
    GitComparisonSource source,
    String path,
  ) async {
    if (source.isText) {
      final bytes = utf8.encode(source.value);
      return _comparisonContentFromBytes(bytes);
    }
    if (source.kind == GitComparisonSourceKind.workingTree) {
      final file = _repositoryFile(handle.root, path);
      if (!file.existsSync()) return const GitComparisonContent.missing();
      try {
        final bytes = <int>[];
        await for (final chunk in file.openRead(
          0,
          maxComparisonTextBytes + 1,
        )) {
          bytes.addAll(chunk);
        }
        if (bytes.length > maxComparisonTextBytes) {
          return GitComparisonContent.oversized(byteLength: bytes.length);
        }
        return _comparisonContentFromBytes(bytes);
      } on FileSystemException {
        return const GitComparisonContent.unreadable();
      }
    }

    // Resolve the ref before reading its path. This keeps invalid revisions
    // distinguishable from a valid revision that does not contain the file.
    final oid = await _resolveCommit(handle, source.value);
    try {
      final output = await _runner.run(
        GitInvocation(
          program: gitPath,
          args: ['show', '--format=', '$oid:$path'],
          cwd: handle.root,
          kind: GitOperationKind.read,
          outputPolicy: const OutputPolicy.capture(
            maxBytes: maxComparisonTextBytes,
          ),
        ),
      );
      return _comparisonContentFromBytes(output.stdout);
    } on GitError catch (error) {
      if (error.category == GitErrorCategory.outputOverflow) {
        return const GitComparisonContent.oversized();
      }
      if (error.category == GitErrorCategory.processFailed) {
        return const GitComparisonContent.missing();
      }
      rethrow;
    }
  }

  GitComparisonContent _comparisonContentFromBytes(List<int> bytes) {
    final contentHash = hashGitObjectBytes(bytes);
    if (bytes.contains(0)) {
      return GitComparisonContent(
        state: GitComparisonContentState.binary,
        byteLength: bytes.length,
        contentHash: contentHash,
      );
    }
    try {
      return GitComparisonContent(
        state: GitComparisonContentState.available,
        text: utf8.decode(bytes),
        byteLength: bytes.length,
        contentHash: contentHash,
      );
    } on FormatException {
      return GitComparisonContent(
        state: GitComparisonContentState.binary,
        byteLength: bytes.length,
        contentHash: contentHash,
      );
    }
  }

  GitComparisonSnapshot _comparisonFromContents(
    GitComparisonRequest request,
    GitComparisonContent left,
    GitComparisonContent right,
  ) {
    final diff = _comparisonDiffFromContents(
      request.repositoryId,
      request.path!,
      left,
      right,
    );
    if (left.contentHash == right.contentHash && left.state == right.state) {
      return GitComparisonSnapshot(
        request: request,
        files: const [],
        fingerprint: _comparisonContentsFingerprint(request, left, right),
      );
    }
    final status = left.state == GitComparisonContentState.missing
        ? GitComparisonFileStatus.added
        : right.state == GitComparisonContentState.missing
        ? GitComparisonFileStatus.deleted
        : GitComparisonFileStatus.modified;
    return GitComparisonSnapshot(
      request: request,
      files: [
        GitComparisonFile(
          path: request.path!,
          status: status,
          additions: diff.additions,
          deletions: diff.deletions,
          isBinary: diff.isBinary,
          isOversized: diff.isOversized,
        ),
      ],
      fingerprint: _comparisonContentsFingerprint(request, left, right),
    );
  }

  String _comparisonContentsFingerprint(
    GitComparisonRequest request,
    GitComparisonContent left,
    GitComparisonContent right,
  ) => comparisonFingerprint(
    request,
    utf8.encode(
      '${left.state.name}\u0000${left.contentHash}\u0000'
      '${right.state.name}\u0000${right.contentHash}',
    ),
  );

  GitDiffSnapshot _comparisonDiffFromContents(
    RepositoryId repositoryId,
    String path,
    GitComparisonContent left,
    GitComparisonContent right,
  ) {
    final contentHash = hashGitObjectBytes(
      utf8.encode(
        '${left.state.name}\u0000${left.contentHash}\u0000'
        '${right.state.name}\u0000${right.contentHash}',
      ),
    );
    if (left.isOversized || right.isOversized) {
      return GitDiffSnapshot(
        repositoryId: repositoryId,
        path: path,
        scope: GitDiffScope.commit,
        lines: const [],
        contentHash: contentHash,
        isOversized: true,
      );
    }
    final unavailable =
        (!left.isAvailable && !left.isMissing) ||
        (!right.isAvailable && !right.isMissing);
    if (left.isBinary || right.isBinary || unavailable) {
      return GitDiffSnapshot(
        repositoryId: repositoryId,
        path: path,
        scope: GitDiffScope.commit,
        lines: const [],
        contentHash: contentHash,
        isBinary: left.isBinary || right.isBinary,
        isMissing: unavailable || (left.isMissing && right.isMissing),
      );
    }
    final oldLines = _comparisonTextLines(left.text);
    final newLines = _comparisonTextLines(right.text);
    var prefix = 0;
    while (prefix < oldLines.length &&
        prefix < newLines.length &&
        oldLines[prefix] == newLines[prefix]) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < oldLines.length - prefix &&
        suffix < newLines.length - prefix &&
        oldLines[oldLines.length - suffix - 1] ==
            newLines[newLines.length - suffix - 1]) {
      suffix++;
    }
    if (prefix == oldLines.length && prefix == newLines.length) {
      return GitDiffSnapshot(
        repositoryId: repositoryId,
        path: path,
        scope: GitDiffScope.commit,
        lines: const [],
        contentHash: contentHash,
      );
    }

    const contextLines = 3;
    final beforeStart = prefix > contextLines ? prefix - contextLines : 0;
    final trailing = suffix > contextLines ? contextLines : suffix;
    final oldChangeEnd = oldLines.length - suffix;
    final newChangeEnd = newLines.length - suffix;
    final oldStart = oldLines.isEmpty ? 0 : beforeStart + 1;
    final newStart = newLines.isEmpty ? 0 : beforeStart + 1;
    final oldCount = prefix - beforeStart + (oldChangeEnd - prefix) + trailing;
    final newCount = prefix - beforeStart + (newChangeEnd - prefix) + trailing;
    final hunkLines = <GitDiffLine>[];
    for (var index = beforeStart; index < prefix; index++) {
      hunkLines.add(
        GitDiffLine(
          kind: GitDiffLineKind.context,
          text: ' ${oldLines[index]}',
          oldLineNumber: index + 1,
          newLineNumber: index + 1,
          hunkIndex: 0,
        ),
      );
    }
    for (var index = prefix; index < oldChangeEnd; index++) {
      hunkLines.add(
        GitDiffLine(
          kind: GitDiffLineKind.deletion,
          text: '-${oldLines[index]}',
          oldLineNumber: index + 1,
          hunkIndex: 0,
        ),
      );
    }
    for (var index = prefix; index < newChangeEnd; index++) {
      hunkLines.add(
        GitDiffLine(
          kind: GitDiffLineKind.addition,
          text: '+${newLines[index]}',
          newLineNumber: index + 1,
          hunkIndex: 0,
        ),
      );
    }
    for (var index = 0; index < trailing; index++) {
      final oldIndex = oldLines.length - suffix + index;
      final newIndex = newLines.length - suffix + index;
      hunkLines.add(
        GitDiffLine(
          kind: GitDiffLineKind.context,
          text: ' ${oldLines[oldIndex]}',
          oldLineNumber: oldIndex + 1,
          newLineNumber: newIndex + 1,
          hunkIndex: 0,
        ),
      );
    }
    final hunk = GitDiffHunk(
      index: 0,
      oldStart: oldStart,
      oldCount: oldCount,
      newStart: newStart,
      newCount: newCount,
      section: '',
      lines: hunkLines,
    );
    final header = hunk.header(oldCount: oldCount, newCount: newCount);
    return GitDiffSnapshot(
      repositoryId: repositoryId,
      path: path,
      scope: GitDiffScope.commit,
      lines: [
        GitDiffLine(kind: GitDiffLineKind.metadata, text: '--- a/$path'),
        GitDiffLine(kind: GitDiffLineKind.metadata, text: '+++ b/$path'),
        GitDiffLine(
          kind: GitDiffLineKind.hunkHeader,
          text: header,
          hunkIndex: 0,
        ),
        ...hunkLines,
      ],
      contentHash: contentHash,
      oldPath: path,
      newPath: path,
      patchHeader: ['--- a/$path', '+++ b/$path'],
      hunks: [hunk],
    );
  }

  List<String> _comparisonTextLines(String? text) {
    if (text == null || text.isEmpty) return const [];
    final lines = text.split('\n');
    if (lines.last.isEmpty) lines.removeLast();
    return lines;
  }

  Future<GitDiffSnapshot> getComparisonDiff(
    RepositoryId repositoryId,
    GitComparisonSnapshot comparison,
    String path,
  ) async {
    if (comparison.request.repositoryId != repositoryId) {
      throw const GitError(
        category: GitErrorCategory.staleComparison,
        userMessage: 'This comparison belongs to a different repository.',
        diagnostic: 'comparison repository ID did not match the request',
        retryable: false,
      );
    }
    _validateComparisonSource(comparison.request.left);
    _validateComparisonSource(comparison.request.right);
    _validateComparisonPath(comparison.request.path);
    _validateComparisonPath(path);
    if ((comparison.request.left.isText || comparison.request.right.isText) &&
        comparison.request.path == null) {
      throw const GitError(
        category: GitErrorCategory.staleComparison,
        userMessage: 'Refresh this comparison with a file path.',
        diagnostic: 'external comparison no longer contained a file path',
        retryable: true,
      );
    }
    if (!_isPathWithinComparisonScope(path, comparison.request.path)) {
      throw const GitError(
        category: GitErrorCategory.comparisonFileNotFound,
        userMessage: 'That file is outside the selected comparison folder.',
        diagnostic: 'comparison file path escaped the requested path scope',
        retryable: false,
      );
    }

    final fresh = await compareSources(
      repositoryId,
      comparison.request.left,
      comparison.request.right,
      path: comparison.request.path,
    );
    if (fresh.fingerprint != comparison.fingerprint) {
      throw const GitError(
        category: GitErrorCategory.staleComparison,
        userMessage: 'The repository changed. Refresh the comparison.',
        diagnostic: 'comparison fingerprint no longer matched Git output',
        retryable: true,
      );
    }
    GitComparisonFile? selected;
    for (final file in fresh.files) {
      if (file.path == path || file.oldPath == path) {
        selected = file;
        break;
      }
    }
    if (selected == null) {
      throw const GitError(
        category: GitErrorCategory.comparisonFileNotFound,
        userMessage: 'That file is no longer part of the comparison.',
        diagnostic: 'requested comparison file was absent from fresh output',
        retryable: false,
      );
    }

    final handle = await state.lookup(repositoryId);
    if (comparison.request.left.isText || comparison.request.right.isText) {
      final contents = await Future.wait([
        _loadComparisonContent(handle, comparison.request.left, path),
        _loadComparisonContent(handle, comparison.request.right, path),
      ]);
      return _comparisonDiffFromContents(
        repositoryId,
        path,
        contents[0],
        contents[1],
      );
    }
    final output = await _runner.run(
      GitInvocation(
        program: gitPath,
        args: _comparisonPatchArgs(
          comparison.request.left,
          comparison.request.right,
          path,
        ),
        cwd: handle.root,
        kind: GitOperationKind.read,
        outputPolicy: const OutputPolicy.capture(maxBytes: 4 * 1024 * 1024),
      ),
    );
    return parseUnifiedDiff(
      output.stdout,
      path: path,
      scope: comparisonDiffScope(comparison.request),
    ).copyWith(repositoryId: repositoryId);
  }

  Future<GitComparisonTransferResult> applyComparison(
    RepositoryId repositoryId,
    GitComparisonSnapshot comparison,
    String path, {
    GitComparisonTransferAction action = GitComparisonTransferAction.apply,
  }) async {
    if (!_isHistoricalComparisonSource(comparison.request.left) ||
        !_isHistoricalComparisonSource(comparison.request.right)) {
      throw const GitError(
        category: GitErrorCategory.patchRejected,
        userMessage: 'Only repository revisions can be transferred.',
        diagnostic:
            'comparison transfer refused a working-tree or external-text '
            'source',
        retryable: false,
      );
    }
    return state.runMutation(repositoryId, () async {
      final diff = await getComparisonDiff(repositoryId, comparison, path);
      final patch = buildSelectedPatch(
        diff,
        GitPatchSelection(
          repositoryId: repositoryId,
          path: path,
          scope: GitDiffScope.commit,
          contentHash: diff.contentHash,
          hunkIndexes: diff.hunks.map((hunk) => hunk.index),
        ),
        reverse: action == GitComparisonTransferAction.revert,
      );
      final handle = await state.lookup(repositoryId);
      final reverse = action == GitComparisonTransferAction.revert;
      final args = ['apply', if (reverse) '--reverse'];
      try {
        await _runner.run(
          GitInvocation(
            program: gitPath,
            args: [...args, '--check'],
            cwd: handle.root,
            stdin: patch.bytes,
            kind: GitOperationKind.mutation,
            outputPolicy: const OutputPolicy.capture(maxBytes: 256 * 1024),
          ),
        );
        await _runner.run(
          GitInvocation(
            program: gitPath,
            args: args,
            cwd: handle.root,
            stdin: patch.bytes,
            kind: GitOperationKind.mutation,
            outputPolicy: const OutputPolicy.capture(maxBytes: 256 * 1024),
          ),
        );
      } on GitError catch (error, stackTrace) {
        if (error.category == GitErrorCategory.processFailed) {
          Error.throwWithStackTrace(
            error.copyWith(
              category: GitErrorCategory.patchRejected,
              userMessage: reverse
                  ? 'Git could not revert the reviewed changes.'
                  : 'Git could not apply the reviewed changes.',
              diagnostic:
                  'comparison transfer was rejected: ${error.diagnostic}',
              retryable: false,
            ),
            stackTrace,
          );
        }
        rethrow;
      }
      return GitComparisonTransferResult(
        repositoryId: repositoryId,
        path: path,
        action: action,
        status: await getStatus(repositoryId),
        summary: reverse
            ? 'Reviewed changes were reverted in the working tree.'
            : 'Reviewed changes were applied to the working tree.',
      );
    });
  }

  bool _isHistoricalComparisonSource(GitComparisonSource source) =>
      source.kind == GitComparisonSourceKind.revision ||
      source.kind == GitComparisonSourceKind.branch ||
      source.kind == GitComparisonSourceKind.tag;

  Future<GitChangelistSnapshot> getChangelists(
    RepositoryId repositoryId,
  ) async {
    final handle = await state.lookup(repositoryId);
    final data = await _readShelfData(handle);
    return _changelistSnapshot(repositoryId, data);
  }

  Future<GitChangelistSnapshot> createChangelist(
    RepositoryId repositoryId,
    String name,
  ) {
    _validateChangelistName(name);
    return state.runMutation(repositoryId, () async {
      final handle = await state.lookup(repositoryId);
      final data = await _readShelfData(handle);
      final lists = data.changelists
          .map(
            (list) => GitChangelist(
              id: list.id,
              name: list.name,
              paths: list.paths,
              isActive: false,
            ),
          )
          .toList();
      lists.add(
        GitChangelist(
          id: _newShelfId('list'),
          name: name.trim(),
          paths: const [],
          isActive: true,
        ),
      );
      final updated = GitShelfStoreData(
        changelists: lists,
        shelves: data.shelves,
      );
      await _writeShelfData(handle, updated);
      return _changelistSnapshot(repositoryId, updated);
    });
  }

  Future<GitChangelistSnapshot> renameChangelist(
    RepositoryId repositoryId,
    String changelistId,
    String name,
  ) {
    _validateChangelistName(name);
    return state.runMutation(repositoryId, () async {
      final handle = await state.lookup(repositoryId);
      final data = await _readShelfData(handle);
      if (!data.changelists.any((list) => list.id == changelistId)) {
        throw _shelfObjectNotFound('changelist', changelistId);
      }
      final updated = GitShelfStoreData(
        changelists: data.changelists.map(
          (list) => list.id == changelistId
              ? GitChangelist(
                  id: list.id,
                  name: name.trim(),
                  paths: list.paths,
                  isActive: list.isActive,
                )
              : list,
        ),
        shelves: data.shelves,
      );
      await _writeShelfData(handle, updated);
      return _changelistSnapshot(repositoryId, updated);
    });
  }

  Future<GitChangelistSnapshot> activateChangelist(
    RepositoryId repositoryId,
    String changelistId,
  ) => state.runMutation(repositoryId, () async {
    final handle = await state.lookup(repositoryId);
    final data = await _readShelfData(handle);
    if (!data.changelists.any((list) => list.id == changelistId)) {
      throw _shelfObjectNotFound('changelist', changelistId);
    }
    final updated = GitShelfStoreData(
      changelists: data.changelists.map(
        (list) => GitChangelist(
          id: list.id,
          name: list.name,
          paths: list.paths,
          isActive: list.id == changelistId,
        ),
      ),
      shelves: data.shelves,
    );
    await _writeShelfData(handle, updated);
    return _changelistSnapshot(repositoryId, updated);
  });

  Future<GitChangelistSnapshot> deleteChangelist(
    RepositoryId repositoryId,
    String changelistId,
  ) => state.runMutation(repositoryId, () async {
    final handle = await state.lookup(repositoryId);
    final data = await _readShelfData(handle);
    final selected = data.changelists
        .where((list) => list.id == changelistId)
        .firstOrNull;
    if (selected == null) {
      throw _shelfObjectNotFound('changelist', changelistId);
    }
    if (data.changelists.length == 1 || selected.id == 'default') {
      throw const GitError(
        category: GitErrorCategory.objectOperationNotAllowed,
        userMessage: 'The default changelist cannot be deleted.',
        diagnostic: 'attempted to delete the required default changelist',
        retryable: false,
      );
    }
    final fallback = data.changelists.firstWhere(
      (list) => list.id == 'default',
      orElse: () => data.changelists.first,
    );
    final movedPaths = {...fallback.paths, ...selected.paths};
    final lists = data.changelists
        .where((list) => list.id != changelistId)
        .map(
          (list) => list.id == fallback.id
              ? GitChangelist(
                  id: list.id,
                  name: list.name,
                  paths: movedPaths,
                  isActive: selected.isActive || list.isActive,
                )
              : list,
        )
        .toList();
    if (!lists.any((list) => list.isActive)) {
      final first = lists.first;
      lists[0] = GitChangelist(
        id: first.id,
        name: first.name,
        paths: first.paths,
        isActive: true,
      );
    }
    final updated = GitShelfStoreData(
      changelists: lists,
      shelves: data.shelves,
    );
    await _writeShelfData(handle, updated);
    return _changelistSnapshot(repositoryId, updated);
  });

  Future<GitChangelistSnapshot> moveChangelistPaths(
    RepositoryId repositoryId,
    Iterable<String> paths,
    String changelistId,
  ) => state.runMutation(repositoryId, () async {
    final requested = _validatedShelfPaths(paths);
    if (requested.isEmpty) {
      throw const GitError(
        category: GitErrorCategory.parseFailure,
        userMessage: 'Choose at least one path to move.',
        diagnostic: 'changelist move received no paths',
        retryable: false,
      );
    }
    final handle = await state.lookup(repositoryId);
    final data = await _readShelfData(handle);
    if (!data.changelists.any((list) => list.id == changelistId)) {
      throw _shelfObjectNotFound('changelist', changelistId);
    }
    final updated = GitShelfStoreData(
      changelists: data.changelists.map((list) {
        final remaining = list.paths.where((path) => !requested.contains(path));
        return GitChangelist(
          id: list.id,
          name: list.name,
          paths: list.id == changelistId
              ? {...remaining, ...requested}
              : remaining,
          isActive: list.isActive,
        );
      }),
      shelves: data.shelves,
    );
    await _writeShelfData(handle, updated);
    return _changelistSnapshot(repositoryId, updated);
  });

  Future<GitShelfSnapshot> getShelves(RepositoryId repositoryId) async {
    final handle = await state.lookup(repositoryId);
    final data = await _readShelfData(handle);
    return _shelfSnapshot(repositoryId, data);
  }

  Future<GitShelfActionResult> shelve(
    RepositoryId repositoryId, {
    String name = '',
    Iterable<String> paths = const <String>[],
  }) => state.runMutation(repositoryId, () async {
    final handle = await state.lookup(repositoryId);
    final data = await _readShelfData(handle);
    final status = await getStatus(repositoryId);
    final changedTracked = status.changes
        .where(
          (change) =>
              !change.isUntracked &&
              !change.isConflicted &&
              (change.isStaged || change.isUnstaged),
        )
        .map((change) => change.path)
        .toSet();
    final selected = paths.isEmpty
        ? changedTracked.toList()
        : _validatedShelfPaths(paths);
    if (selected.isEmpty) {
      throw const GitError(
        category: GitErrorCategory.objectOperationNotAllowed,
        userMessage: 'There are no tracked changes to shelve.',
        diagnostic: 'shelve found no staged or unstaged tracked paths',
        retryable: false,
      );
    }
    if (selected.any((path) => !changedTracked.contains(path))) {
      throw const GitError(
        category: GitErrorCategory.objectOperationNotAllowed,
        userMessage: 'Only current tracked changes can be shelved.',
        diagnostic: 'shelve selection contained an untracked, conflicted, or unchanged path',
        retryable: false,
      );
    }
    final baseRevision = await _readHeadOid(handle);
    if (baseRevision == null) {
      throw const GitError(
        category: GitErrorCategory.unbornBranch,
        userMessage: 'Create the first commit before shelving changes.',
        diagnostic: 'shelve requires a base revision for safe restoration',
        retryable: false,
      );
    }
    final output = await _runner.run(
      GitInvocation(
        program: gitPath,
        args: [
          'diff',
          '--no-color',
          '--no-ext-diff',
          '--binary',
          '--full-index',
          'HEAD',
          '--',
          ...selected,
        ],
        cwd: handle.root,
        kind: GitOperationKind.read,
        outputPolicy: const OutputPolicy.capture(maxBytes: maxShelfPatchBytes),
      ),
    );
    if (output.stdout.isEmpty) {
      throw const GitError(
        category: GitErrorCategory.objectOperationNotAllowed,
        userMessage: 'The selected paths have no shelvable content.',
        diagnostic: 'git diff HEAD returned an empty shelf patch',
        retryable: false,
      );
    }
    final shelf = GitShelf(
      id: _newShelfId('shelf'),
      name: _shelfName(name),
      baseRevision: baseRevision,
      paths: selected,
      patchBytes: output.stdout,
      createdAt: DateTime.now(),
    );
    final updated = GitShelfStoreData(
      changelists: data.changelists,
      shelves: [shelf, ...data.shelves],
    );
    await _writeShelfData(handle, updated);
    try {
      await _restoreShelvedPaths(handle, selected);
    } on Object {
      // The reusable shelf remains available when Git cannot clear the
      // working tree, so the user can recover it without losing the patch.
      rethrow;
    }
    return _shelfResult(
      repositoryId,
      GitShelfActionOutcome.shelved,
      updated,
      shelf: shelf,
      summary: 'Saved ${selected.length} tracked path(s) to the shelf.',
    );
  });

  Future<GitShelfActionResult> unshelve(
    RepositoryId repositoryId,
    String shelfId,
  ) => _applyShelf(repositoryId, shelfId, reverse: false);

  Future<GitShelfActionResult> restoreShelf(
    RepositoryId repositoryId,
    String shelfId,
  ) => _applyShelf(repositoryId, shelfId, reverse: true);

  Future<GitShelfActionResult> _applyShelf(
    RepositoryId repositoryId,
    String shelfId, {
    required bool reverse,
  }) => state.runMutation(repositoryId, () async {
    final handle = await state.lookup(repositoryId);
    final data = await _readShelfData(handle);
    final shelf = data.shelves.where((item) => item.id == shelfId).firstOrNull;
    if (shelf == null) throw _shelfObjectNotFound('shelf', shelfId);
    if (!reverse && shelf.baseRevision != null) {
      final base = await _tryResolve(handle, '${shelf.baseRevision}^{commit}');
      if (base == null) {
        return _shelfResult(
          repositoryId,
          GitShelfActionOutcome.baseMissing,
          data,
          shelf: shelf,
          summary: 'The shelf base revision is no longer available.',
        );
      }
    }
    final args = ['apply', if (reverse) '--reverse'];
    try {
      await _runner.run(
        GitInvocation(
          program: gitPath,
          args: [...args, '--check'],
          cwd: handle.root,
          stdin: shelf.patchBytes,
          kind: GitOperationKind.mutation,
          outputPolicy: const OutputPolicy.capture(maxBytes: 128 * 1024),
        ),
      );
      await _runner.run(
        GitInvocation(
          program: gitPath,
          args: args,
          cwd: handle.root,
          stdin: shelf.patchBytes,
          kind: GitOperationKind.mutation,
          outputPolicy: const OutputPolicy.capture(maxBytes: 128 * 1024),
        ),
      );
    } on GitError catch (error, stackTrace) {
      if (error.category == GitErrorCategory.processFailed) {
        return _shelfResult(
          repositoryId,
          GitShelfActionOutcome.conflict,
          data,
          shelf: shelf,
          summary: 'The shelf could not be applied to the current worktree.',
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
    return _shelfResult(
      repositoryId,
      reverse
          ? GitShelfActionOutcome.restored
          : GitShelfActionOutcome.unshelved,
      data,
      shelf: shelf,
      summary: reverse
          ? 'The selected shelf changes were restored from the worktree.'
          : 'The selected shelf remains available and was unshelved.',
    );
  });

  Future<GitShelfActionResult> deleteShelf(
    RepositoryId repositoryId,
    String shelfId,
  ) => state.runMutation(repositoryId, () async {
    final handle = await state.lookup(repositoryId);
    final data = await _readShelfData(handle);
    final shelf = data.shelves.where((item) => item.id == shelfId).firstOrNull;
    if (shelf == null) throw _shelfObjectNotFound('shelf', shelfId);
    final updated = GitShelfStoreData(
      changelists: data.changelists,
      shelves: data.shelves.where((item) => item.id != shelfId),
    );
    await _writeShelfData(handle, updated);
    return _shelfResult(
      repositoryId,
      GitShelfActionOutcome.deleted,
      updated,
      summary: 'Deleted the selected shelf; the working tree was unchanged.',
    );
  });

  Future<GitShelfActionResult> importShelf(
    RepositoryId repositoryId,
    String name,
    List<int> patchBytes, {
    String? baseRevision,
  }) {
    _validateShelfName(name);
    if (baseRevision != null) _validateRevisionInput(baseRevision);
    final paths = _validateShelfPatch(patchBytes);
    return state.runMutation(repositoryId, () async {
      final handle = await state.lookup(repositoryId);
      final data = await _readShelfData(handle);
      final shelf = GitShelf(
        id: _newShelfId('shelf'),
        name: _shelfName(name),
        baseRevision: baseRevision,
        paths: paths,
        patchBytes: patchBytes,
        createdAt: DateTime.now(),
        imported: true,
      );
      final updated = GitShelfStoreData(
        changelists: data.changelists,
        shelves: [shelf, ...data.shelves],
      );
      await _writeShelfData(handle, updated);
      return _shelfResult(
        repositoryId,
        GitShelfActionOutcome.imported,
        updated,
        shelf: shelf,
        summary: 'Imported a reusable patch without changing Git stash state.',
      );
    });
  }

  Future<List<int>> exportShelf(
    RepositoryId repositoryId,
    String shelfId,
  ) async {
    final handle = await state.lookup(repositoryId);
    final data = await _readShelfData(handle);
    final shelf = data.shelves.where((item) => item.id == shelfId).firstOrNull;
    if (shelf == null) throw _shelfObjectNotFound('shelf', shelfId);
    return List.unmodifiable(shelf.patchBytes);
  }

  Future<GitShelfStoreData> _readShelfData(RepositoryHandle handle) async {
    try {
      final data = await _shelfStore.read(handle.root);
      if (data.changelists.isNotEmpty) return data;
      final initial = GitShelfStoreData(
        changelists: [
          GitChangelist(
            id: 'default',
            name: 'Changes',
            paths: const [],
            isActive: true,
          ),
        ],
        shelves: data.shelves,
      );
      await _shelfStore.write(handle.root, initial);
      return initial;
    } on FormatException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        GitError(
          category: GitErrorCategory.parseFailure,
          userMessage: 'Saved shelf metadata could not be read.',
          diagnostic: error.message,
          retryable: false,
        ),
        stackTrace,
      );
    } on FileSystemException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        GitError(
          category: GitErrorCategory.permissionDenied,
          userMessage: 'Saved shelf metadata could not be opened.',
          diagnostic: error.message,
          retryable: true,
        ),
        stackTrace,
      );
    }
  }

  Future<void> _writeShelfData(
    RepositoryHandle handle,
    GitShelfStoreData data,
  ) async {
    try {
      await _shelfStore.write(handle.root, data);
    } on FormatException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        GitError(
          category: GitErrorCategory.outputOverflow,
          userMessage: 'The shelf store is too large to save safely.',
          diagnostic: error.message,
          retryable: false,
        ),
        stackTrace,
      );
    } on FileSystemException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        GitError(
          category: GitErrorCategory.permissionDenied,
          userMessage: 'The shelf could not be saved.',
          diagnostic: error.message,
          retryable: true,
        ),
        stackTrace,
      );
    }
  }

  GitChangelistSnapshot _changelistSnapshot(
    RepositoryId repositoryId,
    GitShelfStoreData data,
  ) {
    final fingerprint = hashGitObjectBytes(
      utf8.encode(
        jsonEncode(data.changelists.map((list) => list.toJson()).toList()),
      ),
    );
    return GitChangelistSnapshot(
      repositoryId: repositoryId,
      lists: data.changelists,
      fingerprint: fingerprint,
    );
  }

  GitShelfSnapshot _shelfSnapshot(
    RepositoryId repositoryId,
    GitShelfStoreData data,
  ) {
    final fingerprint = hashGitObjectBytes(
      utf8.encode(
        jsonEncode(data.shelves.map((shelf) => shelf.toJson()).toList()),
      ),
    );
    return GitShelfSnapshot(
      repositoryId: repositoryId,
      shelves: data.shelves,
      fingerprint: fingerprint,
    );
  }

  GitShelfActionResult _shelfResult(
    RepositoryId repositoryId,
    GitShelfActionOutcome outcome,
    GitShelfStoreData data, {
    GitShelf? shelf,
    required String summary,
  }) => GitShelfActionResult(
    repositoryId: repositoryId,
    outcome: outcome,
    changelists: _changelistSnapshot(repositoryId, data),
    shelves: _shelfSnapshot(repositoryId, data),
    shelf: shelf,
    summary: summary,
  );

  Future<void> _restoreShelvedPaths(
    RepositoryHandle handle,
    Iterable<String> paths,
  ) async {
    await _runner.run(
      GitInvocation(
        program: gitPath,
        args: [
          'restore',
          '--source=HEAD',
          '--staged',
          '--worktree',
          '--',
          ...paths,
        ],
        cwd: handle.root,
        kind: GitOperationKind.mutation,
        outputPolicy: const OutputPolicy.capture(maxBytes: 128 * 1024),
      ),
    );
  }

  List<String> _validatedShelfPaths(Iterable<String> paths) {
    final result = <String>{};
    for (final path in paths) {
      _validateComparisonPath(path);
      if (path == '.') {
        throw const GitError(
          category: GitErrorCategory.parseFailure,
          userMessage: 'Choose individual repository paths for a shelf.',
          diagnostic: 'shelf path was the repository root marker',
          retryable: false,
        );
      }
      result.add(path);
    }
    return result.toList();
  }

  List<String> _validateShelfPatch(List<int> bytes) {
    if (bytes.isEmpty ||
        bytes.length > maxShelfPatchBytes ||
        bytes.contains(0)) {
      throw const GitError(
        category: GitErrorCategory.outputOverflow,
        userMessage: 'The external patch is empty, binary, or too large.',
        diagnostic: 'imported shelf patch exceeded the bounded text contract',
        retryable: false,
      );
    }
    late final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        const GitError(
          category: GitErrorCategory.parseFailure,
          userMessage: 'The external patch is not valid UTF-8 text.',
          diagnostic: 'imported patch contained malformed UTF-8',
          retryable: false,
        ),
        stackTrace,
      );
    }
    final paths = <String>{};
    for (var line in text.split('\n')) {
      if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
      final prefix = line.startsWith('--- a/')
          ? '--- a/'.length
          : line.startsWith('+++ b/')
          ? '+++ b/'.length
          : line.startsWith('rename from ')
          ? 'rename from '.length
          : line.startsWith('rename to ')
          ? 'rename to '.length
          : null;
      if (prefix == null) continue;
      final candidate = line.substring(prefix).split('\t').first;
      if (candidate == '/dev/null') continue;
      _validateShelfPaths([candidate]);
      paths.add(candidate);
    }
    if (paths.isEmpty || !text.contains('diff --git ')) {
      throw const GitError(
        category: GitErrorCategory.parseFailure,
        userMessage: 'The external patch has no supported repository paths.',
        diagnostic: 'imported patch did not contain a Git file diff header',
        retryable: false,
      );
    }
    return paths.toList();
  }

  void _validateShelfPaths(Iterable<String> paths) {
    _validatedShelfPaths(paths);
  }

  void _validateChangelistName(String name) {
    final value = name.trim();
    if (value.isEmpty ||
        value.length > 120 ||
        value.contains('\u0000') ||
        value.contains('\n')) {
      throw const GitError(
        category: GitErrorCategory.parseFailure,
        userMessage: 'Enter a short changelist name.',
        diagnostic: 'changelist name was empty, too long, or contained a control character',
        retryable: false,
      );
    }
  }

  void _validateShelfName(String name) {
    if (name.trim().length > 120 ||
        name.contains('\u0000') ||
        name.contains('\n')) {
      throw const GitError(
        category: GitErrorCategory.parseFailure,
        userMessage: 'Enter a shorter shelf name.',
        diagnostic: 'shelf name exceeded the bounded metadata contract',
        retryable: false,
      );
    }
  }

  String _shelfName(String name) =>
      name.trim().isEmpty ? 'Shelf ${DateTime.now().toLocal()}' : name.trim();

  String _newShelfId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

  GitError _shelfObjectNotFound(String kind, String id) => GitError(
    category: GitErrorCategory.objectNotFound,
    userMessage: 'The selected $kind is no longer available.',
    diagnostic: '$kind identity was not found in shelf metadata: $id',
    retryable: true,
  );

  Future<GitFileHistorySnapshot> getFileHistory(
    RepositoryId repositoryId,
    GitFileHistoryQuery query,
  ) async {
    _validateFileHistoryQuery(query);
    final handle = await state.lookup(repositoryId);
    final args = <String>[
      'log',
      '--no-color',
      '--format=%H%x00%P%x00%an%x00%ae%x00%aI%x00%s%x00%b%x00%G?%x00%GS%x00%GK%x00%GF%x00%x1e',
      '--date=iso-strict',
      '--topo-order',
      '--max-count=${query.limit + 1}',
      '--skip=${query.offset}',
      if (query.follow) '--follow',
      '--',
      query.path,
    ];
    final output = await _runner.run(
      GitInvocation(
        program: gitPath,
        args: args,
        cwd: handle.root,
        kind: GitOperationKind.read,
        outputPolicy: const OutputPolicy.capture(maxBytes: 8 * 1024 * 1024),
      ),
    );
    late final GitHistoryPage page;
    try {
      page = parseGitHistory(
        output.stdout,
        repositoryId: repositoryId,
        offset: query.offset,
        limit: query.limit,
        queryKey: query.queryKey,
      );
    } on FormatException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        GitError(
          category: GitErrorCategory.parseFailure,
          userMessage: 'Git returned an unreadable file history.',
          diagnostic: error.message,
          retryable: false,
        ),
        stackTrace,
      );
    }
    final entries = <GitFileHistoryEntry>[];
    for (final commit in page.commits) {
      final changes = await getCommitFiles(repositoryId, commit.oid);
      final matching = changes.where((change) {
        if (query.scope == GitFileHistoryScope.directory) {
          return _pathInHistoryDirectory(change.path, query.path) ||
              (change.oldPath != null &&
                  _pathInHistoryDirectory(change.oldPath!, query.path));
        }
        return change.path == query.path || change.oldPath == query.path;
      }).firstOrNull;
      final originalPath =
          matching?.oldPath ??
          (matching != null && matching.path != query.path
              ? matching.path
              : null);
      entries.add(
        GitFileHistoryEntry(
          commit: commit,
          path: query.path,
          originalPath: originalPath,
        ),
      );
    }
    return GitFileHistorySnapshot(
      repositoryId: repositoryId,
      query: query,
      entries: entries,
      fingerprint: hashGitObjectBytes([
        ...output.stdout,
        ...utf8.encode(query.queryKey),
      ]),
      workingTreeFingerprint: await _workingFileFingerprint(handle, query.path),
      hasMore: page.hasMore,
    );
  }

  Future<GitBlameSnapshot> getBlame(
    RepositoryId repositoryId,
    String path, {
    GitBlameOptions options = const GitBlameOptions(),
  }) async {
    _validateHistoryPath(path);
    final handle = await state.lookup(repositoryId);
    final output = await _runner.run(
      GitInvocation(
        program: gitPath,
        args: [
          'blame',
          '--line-porcelain',
          if (options.ignoreWhitespace) '-w',
          if (options.detectMoves) '-M',
          if (options.detectCopies) '-C',
          '--',
          path,
        ],
        cwd: handle.root,
        kind: GitOperationKind.read,
        outputPolicy: const OutputPolicy.capture(maxBytes: 8 * 1024 * 1024),
      ),
    );
    try {
      final lines = _parseBlameLines(output.stdout, path);
      return GitBlameSnapshot(
        repositoryId: repositoryId,
        path: path,
        lines: lines,
        options: options,
        fingerprint: hashGitObjectBytes(output.stdout),
      );
    } on FormatException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        GitError(
          category: GitErrorCategory.parseFailure,
          userMessage: 'Git returned unreadable blame annotations.',
          diagnostic: error.message,
          retryable: false,
        ),
        stackTrace,
      );
    }
  }

  Future<GitRevisionGetResult> getFileFromRevision(
    RepositoryId repositoryId,
    GitFileHistorySnapshot history,
    String revision,
  ) => state.runMutation(repositoryId, () async {
    if (history.repositoryId != repositoryId) {
      throw const GitError(
        category: GitErrorCategory.staleComparison,
        userMessage: 'This file history belongs to another repository.',
        diagnostic: 'file history repository ID did not match the mutation',
        retryable: false,
      );
    }
    _validateFileHistoryQuery(history.query);
    _validateRevisionInput(revision);
    final handle = await state.lookup(repositoryId);
    final currentFingerprint = await _workingFileFingerprint(
      handle,
      history.query.path,
    );
    if (currentFingerprint != history.workingTreeFingerprint) {
      throw const GitError(
        category: GitErrorCategory.staleComparison,
        userMessage:
            'The file changed. Refresh its history before restoring it.',
        diagnostic: 'get-from-revision working-tree fingerprint was stale',
        retryable: true,
      );
    }
    final content = await _loadComparisonContent(
      handle,
      GitComparisonSource.revision(revision),
      history.query.path,
    );
    final status = await getStatus(repositoryId);
    if (content.isMissing) {
      return GitRevisionGetResult(
        repositoryId: repositoryId,
        path: history.query.path,
        revision: revision,
        outcome: GitRevisionGetOutcome.missing,
        status: status,
        summary: 'The selected revision does not contain this file.',
      );
    }
    if (content.isBinary) {
      return GitRevisionGetResult(
        repositoryId: repositoryId,
        path: history.query.path,
        revision: revision,
        outcome: GitRevisionGetOutcome.binary,
        status: status,
        summary: 'Binary file restoration requires an external review.',
      );
    }
    if (content.isOversized) {
      return GitRevisionGetResult(
        repositoryId: repositoryId,
        path: history.query.path,
        revision: revision,
        outcome: GitRevisionGetOutcome.oversized,
        status: status,
        summary: 'The selected file is too large to restore safely.',
      );
    }
    try {
      await _writeRepositoryBytes(
        handle,
        history.query.path,
        utf8.encode(content.text ?? ''),
      );
    } on FileSystemException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        GitError(
          category: GitErrorCategory.permissionDenied,
          userMessage: 'The selected revision could not be written.',
          diagnostic: error.message,
          retryable: true,
        ),
        stackTrace,
      );
    }
    return GitRevisionGetResult(
      repositoryId: repositoryId,
      path: history.query.path,
      revision: revision,
      outcome: GitRevisionGetOutcome.restored,
      status: await getStatus(repositoryId),
      summary: 'Restored the selected file from $revision.',
    );
  });

  void _validateFileHistoryQuery(GitFileHistoryQuery query) {
    _validateHistoryPath(query.path);
    if (query.limit < 1 || query.limit > 100 || query.offset < 0) {
      throw const GitError(
        category: GitErrorCategory.parseFailure,
        userMessage: 'The file history page size is invalid.',
        diagnostic: 'file history limit must be 1..100 and offset non-negative',
        retryable: false,
      );
    }
    if (query.follow && query.scope != GitFileHistoryScope.file) {
      throw const GitError(
        category: GitErrorCategory.parseFailure,
        userMessage: 'Rename following is available for one file at a time.',
        diagnostic: 'git log --follow was requested for a directory or range',
        retryable: false,
      );
    }
    final start = query.lineStart;
    final end = query.lineEnd;
    if ((start == null) != (end == null) ||
        (start != null && (start < 1 || end! < start))) {
      throw const GitError(
        category: GitErrorCategory.parseFailure,
        userMessage: 'The selected line range is invalid.',
        diagnostic: 'file history line range was incomplete or reversed',
        retryable: false,
      );
    }
  }

  void _validateHistoryPath(String path) {
    _validateComparisonPath(path);
    if (path == '.') {
      throw const GitError(
        category: GitErrorCategory.parseFailure,
        userMessage: 'Choose a file or directory path.',
        diagnostic: 'file history path was the repository root marker',
        retryable: false,
      );
    }
  }

  bool _pathInHistoryDirectory(String path, String directory) {
    final normalized = directory.endsWith('/')
        ? directory.substring(0, directory.length - 1)
        : directory;
    return path == normalized || path.startsWith('$normalized/');
  }

  List<GitBlameLine> _parseBlameLines(List<int> bytes, String path) {
    final text = utf8.decode(bytes);
    final result = <GitBlameLine>[];
    String? oid;
    String? author;
    DateTime? authoredAt;
    var originalLine = 0;
    var finalLine = 0;
    var originalPath = path;
    for (final line in text.split('\n')) {
      final header = RegExp(r'^([0-9a-fA-F]{40,64}) (\d+) (\d+)(?: (\d+))?$')
          .firstMatch(line);
      if (header != null) {
        oid = header.group(1);
        originalLine = int.parse(header.group(2)!);
        finalLine = int.parse(header.group(3)!);
        author = null;
        authoredAt = null;
        originalPath = path;
        continue;
      }
      if (line.startsWith('author ')) {
        author = line.substring('author '.length);
        continue;
      }
      if (line.startsWith('author-time ')) {
        final seconds = int.tryParse(line.substring('author-time '.length));
        if (seconds != null) {
          authoredAt = DateTime.fromMillisecondsSinceEpoch(
            seconds * 1000,
            isUtc: true,
          );
        }
        continue;
      }
      if (line.startsWith('filename ')) {
        originalPath = line.substring('filename '.length);
        continue;
      }
      if (line.startsWith('\t') && oid != null) {
        result.add(
          GitBlameLine(
            lineNumber: finalLine,
            text: line.substring(1),
            commitOid: oid,
            authorName: author ?? 'Unknown author',
            authoredAt: authoredAt,
            originalLineNumber: originalLine,
            originalPath: originalPath,
          ),
        );
        finalLine++;
        originalLine++;
      }
    }
    if (result.isEmpty && text.isNotEmpty) {
      throw const FormatException('blame output contained no annotated lines');
    }
    return result;
  }

  Future<String> _workingFileFingerprint(
    RepositoryHandle handle,
    String path,
  ) async {
    final file = _repositoryFile(handle.root, path);
    if (!await file.exists()) return 'missing';
    try {
      final bytes = <int>[];
      await for (final chunk in file.openRead(0, maxComparisonTextBytes + 1)) {
        bytes.addAll(chunk);
      }
      if (bytes.length > maxComparisonTextBytes) {
        return 'oversized:${bytes.length}';
      }
      return hashGitObjectBytes(bytes);
    } on FileSystemException catch (error) {
      return 'unreadable:${error.osError?.errorCode ?? error.message}';
    }
  }

  Future<void> _writeRepositoryBytes(
    RepositoryHandle handle,
    String path,
    List<int> bytes,
  ) async {
    final file = _repositoryFile(handle.root, path);
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.gift-revision.tmp');
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(file.path);
  }

  Future<GitStatusSnapshot> stage(RepositoryId repositoryId, String path) =>
      _mutatePath(repositoryId, const ['add'], path);

  Future<GitStatusSnapshot> unstage(RepositoryId repositoryId, String path) =>
      _mutatePath(repositoryId, const ['restore', '--staged'], path);

  Future<GitStatusSnapshot> stagePatch(
    RepositoryId repositoryId,
    GitPatchSelection selection,
  ) => _applyPatchSelection(
    repositoryId,
    selection,
    expectedScope: GitDiffScope.workingTree,
  );

  Future<GitStatusSnapshot> unstagePatch(
    RepositoryId repositoryId,
    GitPatchSelection selection,
  ) => _applyPatchSelection(
    repositoryId,
    selection,
    expectedScope: GitDiffScope.staged,
    reverse: true,
  );

  /// Checks repository state and identity without changing Git history.
  Future<GitCommitPreflight> preflightCommit(
    RepositoryId repositoryId, {
    GitCommitOptions options = const GitCommitOptions(),
  }) async {
    _validateCommitOptions(options);
    final status = await getStatus(repositoryId);
    final handle = await state.lookup(repositoryId);
    final headOid = await _readHeadOid(handle);
    final identity = await _readCommitIdentity(handle);
    GitError? failure;
    if (status.staged.isEmpty) {
      failure = _commitFailure(
        category: GitErrorCategory.dirtyWorktree,
        userMessage: 'Stage at least one change before committing.',
        diagnostic: 'commit preflight found no staged changes',
      );
    } else if (!identity.isComplete) {
      failure = _commitFailure(
        category: GitErrorCategory.missingIdentity,
        userMessage:
            'Git user.name and user.email are required before committing.',
        diagnostic:
            'effective identity was incomplete in ${identity.source}; '
            '${identity.guidance}',
      );
    } else if (options.amend && headOid == null) {
      failure = _commitFailure(
        category: GitErrorCategory.unbornBranch,
        userMessage: 'Amend is unavailable before the first commit.',
        diagnostic: 'commit --amend requested while HEAD has no commit',
      );
    }
    return GitCommitPreflight(
      status: status,
      identity: identity,
      hasHead: headOid != null,
      headOid: headOid,
      options: options,
      failure: failure,
    );
  }

  /// Loads the effective commit template without allowing an unbounded file
  /// read to reach the editor.
  Future<GitCommitTemplate> loadCommitTemplate(
    RepositoryId repositoryId,
  ) async {
    final handle = await state.lookup(repositoryId);
    final configuredPath = await _readConfigValue(handle, const [
      'config',
      '--get',
      'commit.template',
    ]);
    if (configuredPath == null || configuredPath.trim().isEmpty) {
      return const GitCommitTemplate();
    }
    final file = File(_resolveTemplatePath(handle.root, configuredPath));
    try {
      final length = await file.length();
      if (length > _maxCommitTemplateBytes) {
        throw const GitError(
          category: GitErrorCategory.outputOverflow,
          userMessage: 'The configured commit template is too large to load.',
          diagnostic: 'commit.template exceeded the bounded file size',
          retryable: false,
        );
      }
      final contents = utf8.decode(
        await file.readAsBytes(),
        allowMalformed: true,
      );
      return GitCommitTemplate(path: file.path, contents: contents);
    } on GitError {
      rethrow;
    } on FileSystemException catch (error) {
      throw GitError(
        category: GitErrorCategory.invalidGitConfig,
        userMessage: 'The configured commit template could not be read.',
        diagnostic: 'commit.template ${file.path}: ${error.message}',
        retryable: false,
      );
    }
  }

  /// Creates a commit from all currently staged content.
  ///
  /// The message is sent as UTF-8 on stdin through `--file=-`. This keeps
  /// arbitrary user text out of argv and preserves shell-safe execution.
  Future<GitCommitResult> commit(
    RepositoryId repositoryId,
    String message, {
    GitCommitOptions options = const GitCommitOptions(),
  }) async {
    if (message.trim().isEmpty) {
      throw _commitFailure(
        category: GitErrorCategory.parseFailure,
        userMessage: 'Enter a commit message.',
        diagnostic: 'commit message was empty or whitespace only',
      );
    }

    return state.runMutation(repositoryId, () async {
      final preflight = await preflightCommit(repositoryId, options: options);
      if (preflight.failure case final failure?) throw failure;

      final handle = await state.lookup(repositoryId);
      final beforeHead = preflight.headOid;
      try {
        await _runner.run(
          GitInvocation(
            program: gitPath,
            args: ['commit', ...options.toGitArguments(), '--file=-'],
            cwd: handle.root,
            stdin: utf8.encode(message),
            kind: GitOperationKind.mutation,
            outputPolicy: const OutputPolicy.capture(maxBytes: 256 * 1024),
          ),
        );
      } on GitError catch (error, stackTrace) {
        var afterHead = beforeHead;
        try {
          afterHead = await _readHeadOid(handle);
        } on GitError {
          // Preserve the conservative not-created outcome when the recovery
          // probe itself cannot read HEAD.
        }
        final outcome = beforeHead != afterHead
            ? GitCommitOutcome.createdButRefreshFailed
            : GitCommitOutcome.notCreated;
        Error.throwWithStackTrace(
          _mapCommitError(error).copyWith(commitOutcome: outcome),
          stackTrace,
        );
      }

      late final GitStatusSnapshot status;
      try {
        status = await getStatus(repositoryId);
      } on GitError catch (error, stackTrace) {
        Error.throwWithStackTrace(
          error.copyWith(
            category: GitErrorCategory.commitRefreshFailed,
            userMessage:
                'Commit created, but refreshing repository status failed. '
                'Verify history before retrying.',
            retryable: true,
            commitOutcome: GitCommitOutcome.createdButRefreshFailed,
          ),
          stackTrace,
        );
      }
      final commitOid = status.branch.oid;
      if (commitOid == null || commitOid.isEmpty) {
        throw _commitFailure(
          category: GitErrorCategory.commitRefreshFailed,
          userMessage:
              'Commit created, but Git did not return its new history ID. '
              'Verify history before retrying.',
          diagnostic: 'post-commit status did not contain branch.oid',
          retryable: true,
          outcome: GitCommitOutcome.createdButRefreshFailed,
        );
      }
      return GitCommitResult(
        repositoryId: repositoryId,
        commitOid: commitOid,
        status: status,
        options: options,
      );
    });
  }

  Future<GitLfsSnapshot> getLfsStatus(RepositoryId repositoryId) async {
    final handle = await state.lookup(repositoryId);
    String? version;
    var installation = GitLfsInstallationStatus.missing;
    try {
      final output = await _runner.run(
        GitInvocation(
          program: gitPath,
          args: const ['lfs', 'version'],
          cwd: handle.root,
          kind: GitOperationKind.read,
          outputPolicy: const OutputPolicy.capture(maxBytes: 64 * 1024),
        ),
      );
      final firstLine = utf8
          .decode(output.stdout, allowMalformed: true)
          .split(RegExp(r'\r?\n'))
          .first
          .trim();
      version = firstLine.isEmpty ? null : firstLine;
      installation = GitLfsInstallationStatus.available;
    } on GitError {
      // Git remains useful without the optional LFS extension. The attribute
      // and pointer scan below still explains what a missing extension means.
    }

    final trackedOutput = await _runner.run(
      GitInvocation(
        program: gitPath,
        args: const ['ls-files', '-z'],
        cwd: handle.root,
        kind: GitOperationKind.read,
        outputPolicy: const OutputPolicy.capture(maxBytes: 4 * 1024 * 1024),
      ),
    );
    final trackedPaths = utf8
        .decode(trackedOutput.stdout, allowMalformed: true)
        .split('\u0000')
        .where((path) => path.isNotEmpty)
        .take(2000)
        .toList(growable: false);

    final filteredPaths = <String>[];
    if (trackedPaths.isNotEmpty) {
      final attributes = await _runner.run(
        GitInvocation(
          program: gitPath,
          args: const ['check-attr', '-z', '--stdin', 'filter'],
          cwd: handle.root,
          stdin: utf8.encode('${trackedPaths.join('\u0000')}\u0000'),
          kind: GitOperationKind.read,
          outputPolicy: const OutputPolicy.capture(maxBytes: 4 * 1024 * 1024),
        ),
      );
      final fields = utf8
          .decode(attributes.stdout, allowMalformed: true)
          .split('\u0000');
      for (var index = 0; index + 2 < fields.length; index += 3) {
        if (fields[index + 2].trim() == 'lfs') {
          filteredPaths.add(fields[index]);
        }
      }
    }

    final files = <GitLfsFile>[];
    for (final path in filteredPaths) {
      final file = File(
        '${handle.root}${Platform.pathSeparator}'
        '${path.replaceAll('/', Platform.pathSeparator)}',
      );
      if (!file.existsSync()) {
        files.add(GitLfsFile(path: path, state: GitLfsFileState.missing));
        continue;
      }
      try {
        final bytes = await file
            .openRead(0, 1024)
            .fold<List<int>>(
              <int>[],
              (current, chunk) => current..addAll(chunk),
            );
        final text = utf8.decode(bytes, allowMalformed: true);
        final oid = RegExp(
          r'^oid sha256:([0-9a-f]{64})$',
          multiLine: true,
        ).firstMatch(text)?.group(1);
        final size = int.tryParse(
          RegExp(r'^size (\d+)$', multiLine: true).firstMatch(text)?.group(1) ??
              '',
        );
        final isPointer = text.startsWith(
          'version https://git-lfs.github.com/spec/v1',
        );
        files.add(
          GitLfsFile(
            path: path,
            state: isPointer
                ? GitLfsFileState.pointer
                : GitLfsFileState.hydrated,
            oid: oid,
            size: size,
          ),
        );
      } on Object {
        files.add(GitLfsFile(path: path, state: GitLfsFileState.missing));
      }
    }

    final diagnostics = <String>[];
    if (filteredPaths.isNotEmpty &&
        installation == GitLfsInstallationStatus.missing) {
      diagnostics.add(
        'Git LFS is not installed, but this repository uses LFS filters.',
      );
    }
    final pointerCount = files
        .where((file) => file.state == GitLfsFileState.pointer)
        .length;
    if (pointerCount > 0) {
      diagnostics.add(
        '$pointerCount LFS pointer file(s) are present; run Git LFS pull.',
      );
    }
    final fingerprint = hashGitObjectBytes(
      utf8.encode(
        [
          installation.name,
          version ?? '',
          ...filteredPaths,
          ...files.map(
            (file) => '${file.path}:${file.state.name}:${file.oid ?? ''}',
          ),
        ].join('\n'),
      ),
    );
    return GitLfsSnapshot(
      repositoryId: repositoryId,
      installation: installation,
      version: version,
      filteredPaths: List.unmodifiable(filteredPaths),
      files: List.unmodifiable(files),
      diagnostics: List.unmodifiable(diagnostics),
      fingerprint: fingerprint,
    );
  }

  Future<GitLfsPullResult> pullLfs(
    RepositoryId repositoryId, {
    GitCancellationToken? cancellationToken,
  }) => state.runMutation(repositoryId, () async {
    final before = await getLfsStatus(repositoryId);
    if (!before.isAvailable) {
      throw const GitError(
        category: GitErrorCategory.lfsUnavailable,
        userMessage: 'Git LFS is not installed.',
        diagnostic: 'git lfs version could not be executed',
        retryable: true,
      );
    }
    if (!before.hasLfsFilters) {
      return GitLfsPullResult(
        repositoryId: repositoryId,
        snapshot: before,
        summary: 'This repository has no Git LFS filters.',
      );
    }
    final handle = await state.lookup(repositoryId);
    String? remoteUrl;
    try {
      final remotes = await getRemotes(repositoryId);
      remoteUrl = remotes
          .firstWhere(
            (remote) => remote.name == 'origin',
            orElse: () => remotes.first,
          )
          .fetchUrl;
    } on Object {
      remoteUrl = null;
    }
    try {
      await _runWithCredentials(
        cwd: handle.root,
        args: const ['lfs', 'pull'],
        kind: GitOperationKind.mutation,
        maxBytes: 512 * 1024,
        cancellationToken: cancellationToken,
        remoteUrl: remoteUrl,
      );
    } on GitError catch (error, stackTrace) {
      Error.throwWithStackTrace(_mapLfsError(error), stackTrace);
    }
    final after = await getLfsStatus(repositoryId);
    return GitLfsPullResult(
      repositoryId: repositoryId,
      snapshot: after,
      summary: after.hasPointers
          ? 'Git LFS pull completed, but some pointer files remain.'
          : 'Git LFS objects were pulled successfully.',
    );
  });

  Future<GitSigningConfiguration> getSigningConfiguration(
    RepositoryId repositoryId,
  ) async {
    final handle = await state.lookup(repositoryId);
    final enabledValue = await _readConfigValue(handle, const [
      'config',
      '--get',
      '--bool',
      'commit.gpgSign',
    ]);
    final formatValue = await _readConfigValue(handle, const [
      'config',
      '--get',
      'gpg.format',
    ]);
    final signingKey = await _readConfigValue(handle, const [
      'config',
      '--get',
      'user.signingkey',
    ]);
    final program = await _readConfigValue(handle, const [
      'config',
      '--get',
      'gpg.program',
    ]);
    final sshProgram = await _readConfigValue(handle, const [
      'config',
      '--get',
      'gpg.ssh.program',
    ]);
    final format = switch (formatValue?.trim().toLowerCase()) {
      'ssh' => GitSigningFormat.ssh,
      'x509' => GitSigningFormat.x509,
      'openpgp' || 'gpg' || null => GitSigningFormat.openpgp,
      _ => GitSigningFormat.unknown,
    };
    return GitSigningConfiguration(
      repositoryId: repositoryId,
      enabled: enabledValue?.toLowerCase() == 'true',
      format: format,
      signingKey: signingKey,
      program: program,
      sshProgram: sshProgram,
      agentAvailable: signingKey != null,
      source: [
        if (enabledValue != null) 'commit.gpgSign=$enabledValue',
        if (formatValue != null) 'gpg.format=$formatValue',
        if (signingKey != null) 'user.signingkey=$signingKey',
      ].join(', '),
    );
  }

  Future<DiscardPreview> createDiscardPreview(
    RepositoryId repositoryId,
    String path,
  ) async {
    _validatePath(path);
    final status = await getStatus(repositoryId);
    final change = _findChange(status, path);
    if (change == null ||
        change.isUntracked ||
        change.isConflicted ||
        !change.isUnstaged) {
      throw const GitError(
        category: GitErrorCategory.dirtyWorktree,
        userMessage: 'Only tracked working-tree changes can be discarded.',
        diagnostic: 'discard preview requested for a non-discardable status',
        retryable: false,
      );
    }
    final diff = await getDiff(
      repositoryId,
      path,
      originalPath: change.originalPath,
    );
    return state.issueDiscardPreview(
      repositoryId: repositoryId,
      path: path,
      statusHash: status.contentHash,
      diffHash: diff.contentHash,
    );
  }

  Future<GitStatusSnapshot> discard(
    RepositoryId repositoryId,
    DiscardPreview preview,
  ) {
    return state.runMutation(repositoryId, () async {
      final record = state._validateDiscardPreview(repositoryId, preview);
      final status = await getStatus(repositoryId);
      final change = _findChange(status, record.path);
      if (status.contentHash != record.statusHash ||
          change == null ||
          change.isUntracked ||
          change.isConflicted ||
          !change.isUnstaged) {
        throw _staleDiscardError('status changed after the discard preview');
      }
      final diff = await getDiff(
        repositoryId,
        record.path,
        originalPath: change.originalPath,
      );
      if (diff.contentHash != record.diffHash) {
        throw _staleDiscardError('working-tree content changed after preview');
      }

      final handle = await state.lookup(repositoryId);
      // The path is supplied as a separate argv value after the `--` marker.
      // Keeping this invocation separate makes the preview token the only
      // source of the path used for the destructive operation.
      await _runner.run(
        GitInvocation(
          program: gitPath,
          args: ['restore', '--worktree', '--', record.path],
          cwd: handle.root,
          kind: GitOperationKind.mutation,
          outputPolicy: const OutputPolicy.capture(maxBytes: 64 * 1024),
        ),
      );
      state.consumeDiscardPreview(preview.token);
      return getStatus(repositoryId);
    });
  }

  void cancelDiscardPreview(DiscardPreview preview) {
    state.cancelDiscardPreview(preview);
  }

  Future<GitStatusSnapshot> _mutatePath(
    RepositoryId repositoryId,
    List<String> command,
    String path,
  ) async {
    _validatePath(path);
    return state.runMutation(repositoryId, () async {
      final handle = await state.lookup(repositoryId);
      await _runner.run(
        GitInvocation(
          program: gitPath,
          args: [...command, '--', path],
          cwd: handle.root,
          kind: GitOperationKind.mutation,
          outputPolicy: const OutputPolicy.capture(maxBytes: 64 * 1024),
        ),
      );
      // Return the post-mutation snapshot so the UI can update immediately.
      return getStatus(repositoryId);
    });
  }

  Future<GitStatusSnapshot> _applyPatchSelection(
    RepositoryId repositoryId,
    GitPatchSelection selection, {
    required GitDiffScope expectedScope,
    bool reverse = false,
  }) async {
    if (selection.scope != expectedScope) {
      throw const GitError(
        category: GitErrorCategory.stalePatch,
        userMessage: 'Choose the matching staged or working-tree diff.',
        diagnostic: 'patch operation scope did not match its command',
        retryable: false,
      );
    }
    return state.runMutation(repositoryId, () async {
      final status = await getStatus(repositoryId);
      final change = _findChange(status, selection.path);
      if (change == null ||
          change.isConflicted ||
          (expectedScope == GitDiffScope.workingTree
              ? !change.isUnstaged
              : !change.isStaged)) {
        throw const GitError(
          category: GitErrorCategory.stalePatch,
          userMessage: 'The selected change is no longer available.',
          diagnostic: 'patch operation status facet was no longer present',
          retryable: false,
        );
      }
      final diff = await getDiff(
        repositoryId,
        selection.path,
        scope: expectedScope,
        originalPath: change.originalPath,
      );
      final patch = buildSelectedPatch(diff, selection, reverse: reverse);
      final handle = await state.lookup(repositoryId);
      try {
        await _runner.run(
          GitInvocation(
            program: gitPath,
            args: ['apply', '--cached', if (reverse) '--reverse'],
            cwd: handle.root,
            stdin: patch.bytes,
            kind: GitOperationKind.mutation,
            outputPolicy: const OutputPolicy.capture(maxBytes: 256 * 1024),
          ),
        );
      } on GitError catch (error, stackTrace) {
        if (error.category == GitErrorCategory.processFailed) {
          Error.throwWithStackTrace(
            error.copyWith(
              category: GitErrorCategory.patchRejected,
              userMessage: 'Git could not apply the selected changes.',
              diagnostic: 'partial patch was rejected: ${error.diagnostic}',
              retryable: false,
            ),
            stackTrace,
          );
        }
        rethrow;
      }
      return getStatus(repositoryId);
    });
  }

  Future<GitCommitIdentity> _readCommitIdentity(RepositoryHandle handle) async {
    final localName = await _readConfigValue(handle, const [
      'config',
      '--local',
      '--get',
      'user.name',
    ]);
    final localEmail = await _readConfigValue(handle, const [
      'config',
      '--local',
      '--get',
      'user.email',
    ]);
    final globalName = await _readConfigValue(handle, const [
      'config',
      '--global',
      '--get',
      'user.name',
    ]);
    final globalEmail = await _readConfigValue(handle, const [
      'config',
      '--global',
      '--get',
      'user.email',
    ]);
    return GitCommitIdentity(
      localName: localName,
      localEmail: localEmail,
      globalName: globalName,
      globalEmail: globalEmail,
    );
  }

  Future<String?> _readConfigValue(
    RepositoryHandle handle,
    List<String> args,
  ) async {
    try {
      final output = await _runner.run(
        GitInvocation(
          program: gitPath,
          args: args,
          cwd: handle.root,
          kind: GitOperationKind.read,
          outputPolicy: const OutputPolicy.capture(maxBytes: 16 * 1024),
        ),
      );
      return utf8.decode(output.stdout, allowMalformed: true).trim();
    } on GitError catch (error) {
      // `git config --get` uses exit code 1 with no stderr when a key is
      // absent. Treat that expected lookup result as a missing value.
      if (error.exitCode == 1 && error.diagnostic.trim().isEmpty) return null;
      rethrow;
    }
  }

  Future<String?> _readHeadOid(RepositoryHandle handle) async {
    try {
      final output = await _runner.run(
        GitInvocation(
          program: gitPath,
          args: const ['rev-parse', '--verify', '--quiet', 'HEAD'],
          cwd: handle.root,
          kind: GitOperationKind.read,
          outputPolicy: const OutputPolicy.capture(maxBytes: 128),
        ),
      );
      final oid = utf8.decode(output.stdout, allowMalformed: true).trim();
      return oid.isEmpty ? null : oid;
    } on GitError catch (error) {
      // An unborn repository has no HEAD and rev-parse reports that as 1.
      if (error.exitCode == 1 && error.diagnostic.trim().isEmpty) return null;
      rethrow;
    }
  }

  Future<GitConflictSnapshot> _validateConflictSnapshot(
    RepositoryId repositoryId,
    String fingerprint,
  ) async {
    final snapshot = await getConflicts(repositoryId);
    if (snapshot.fingerprint != fingerprint) {
      throw const GitError(
        category: GitErrorCategory.staleConflict,
        userMessage: 'The conflict changed. Refresh it before resolving again.',
        diagnostic: 'unmerged index or worktree fingerprint no longer matched',
        retryable: true,
      );
    }
    return snapshot;
  }

  Future<GitConflictSnapshot> _validateConflictMutation(
    RepositoryId repositoryId,
    String path,
    String fingerprint,
  ) async {
    _validatePath(path);
    final snapshot = await _validateConflictSnapshot(repositoryId, fingerprint);
    if (_findConflict(snapshot, path) == null) {
      throw const GitError(
        category: GitErrorCategory.conflictResolutionNotAllowed,
        userMessage: 'That path is no longer conflicted.',
        diagnostic:
            'conflict mutation path was not in the current unmerged index',
        retryable: true,
      );
    }
    return snapshot;
  }

  Future<GitConflictSide?> _loadConflictSide(
    RepositoryHandle handle,
    GitConflictSide? side,
  ) async {
    if (side == null || side.oid == null) return side;
    try {
      final output = await _runner.run(
        GitInvocation(
          program: gitPath,
          args: ['cat-file', 'blob', side.oid!],
          cwd: handle.root,
          kind: GitOperationKind.read,
          outputPolicy: const OutputPolicy.capture(
            maxBytes: _maxConflictTextBytes,
          ),
        ),
      );
      return GitConflictSide(
        stage: side.stage,
        mode: side.mode,
        oid: side.oid,
        content: _conflictContent(output.stdout),
      );
    } on GitError catch (error) {
      if (error.category == GitErrorCategory.outputOverflow) {
        return GitConflictSide(
          stage: side.stage,
          mode: side.mode,
          oid: side.oid,
          content: const GitConflictContent(
            state: GitConflictContentState.tooLarge,
          ),
        );
      }
      return GitConflictSide(
        stage: side.stage,
        mode: side.mode,
        oid: side.oid,
        content: const GitConflictContent(
          state: GitConflictContentState.unreadable,
        ),
      );
    }
  }

  Future<GitConflictSide> _loadWorkingConflictSide(
    RepositoryHandle handle,
    String path,
  ) async {
    final file = _repositoryFile(handle.root, path);
    if (!file.existsSync()) {
      return const GitConflictSide(
        stage: 0,
        content: GitConflictContent.missing(),
      );
    }
    try {
      final bytes = <int>[];
      await for (final chunk in file.openRead(0, _maxConflictTextBytes + 1)) {
        bytes.addAll(chunk);
      }
      if (bytes.length > _maxConflictTextBytes) {
        return const GitConflictSide(
          stage: 0,
          content: GitConflictContent(state: GitConflictContentState.tooLarge),
        );
      }
      return GitConflictSide(stage: 0, content: _conflictContent(bytes));
    } on FileSystemException {
      return const GitConflictSide(
        stage: 0,
        content: GitConflictContent(state: GitConflictContentState.unreadable),
      );
    }
  }

  GitConflictContent _conflictContent(List<int> bytes) {
    final isBinary = bytes.contains(0);
    if (isBinary) {
      return GitConflictContent(
        state: GitConflictContentState.binary,
        byteLength: bytes.length,
      );
    }
    try {
      return GitConflictContent(
        state: GitConflictContentState.available,
        text: utf8.decode(bytes),
        byteLength: bytes.length,
      );
    } on FormatException {
      return GitConflictContent(
        state: GitConflictContentState.binary,
        byteLength: bytes.length,
      );
    }
  }

  Future<String> _readConflictFingerprint(
    RepositoryHandle handle,
    List<int> indexBytes,
    List<GitConflictEntry> conflicts,
  ) async {
    final bytes = <int>[...indexBytes, 0];
    final paths = conflicts.map((conflict) => conflict.path).toList()..sort();
    for (final path in paths) {
      bytes.addAll(utf8.encode(path));
      bytes.add(0);
      bytes.addAll(utf8.encode(await _readWorkingTreeOid(handle, path)));
      bytes.add(0);
    }
    return hashConflictBytes(bytes);
  }

  Future<String> _readWorkingTreeOid(
    RepositoryHandle handle,
    String path,
  ) async {
    final file = _repositoryFile(handle.root, path);
    if (!file.existsSync()) return 'missing';
    try {
      final output = await _runner.run(
        GitInvocation(
          program: gitPath,
          args: ['hash-object', '--no-filters', '--', path],
          cwd: handle.root,
          kind: GitOperationKind.read,
          outputPolicy: const OutputPolicy.capture(maxBytes: 128),
        ),
      );
      return utf8.decode(output.stdout, allowMalformed: true).trim();
    } on GitError catch (error) {
      if (error.exitCode == 1) return 'missing';
      rethrow;
    }
  }

  Future<GitConflictOperationMetadata?> _readConflictOperation(
    RepositoryHandle handle,
  ) async {
    final mergeHead = await _readGitFile(handle, 'MERGE_HEAD');
    if (mergeHead != null) {
      final heads = mergeHead
          .split(RegExp(r'\s+'))
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
      return GitConflictOperationMetadata(
        operation: GitConflictOperation.merge,
        mergeHeads: heads,
      );
    }
    final cherryPickHead = await _readGitFile(handle, 'CHERRY_PICK_HEAD');
    if (cherryPickHead != null) {
      return GitConflictOperationMetadata(
        operation: GitConflictOperation.cherryPick,
        mergeHeads: cherryPickHead.trim().isEmpty
            ? const []
            : [cherryPickHead.trim()],
      );
    }
    final revertHead = await _readGitFile(handle, 'REVERT_HEAD');
    if (revertHead != null) {
      return GitConflictOperationMetadata(
        operation: GitConflictOperation.revert,
        mergeHeads: revertHead.trim().isEmpty ? const [] : [revertHead.trim()],
      );
    }
    final rebaseMerge = await _readGitPath(handle, 'rebase-merge');
    final rebaseDirectory =
        rebaseMerge != null && Directory(rebaseMerge).existsSync()
        ? rebaseMerge
        : await _readGitPath(handle, 'rebase-apply');
    if (rebaseDirectory == null || !Directory(rebaseDirectory).existsSync()) {
      return null;
    }
    final headName = await _readFileAt(
      '$rebaseDirectory${Platform.pathSeparator}head-name',
    );
    final onto = await _readFileAt(
      '$rebaseDirectory${Platform.pathSeparator}onto',
    );
    final currentStep = int.tryParse(
      (await _readFileAt('$rebaseDirectory${Platform.pathSeparator}msgnum'))
              ?.trim() ??
          '',
    );
    final totalSteps = int.tryParse(
      (await _readFileAt('$rebaseDirectory${Platform.pathSeparator}end'))
              ?.trim() ??
          '',
    );
    return GitConflictOperationMetadata(
      operation: GitConflictOperation.rebase,
      headName: headName?.trim().replaceFirst('refs/heads/', ''),
      onto: onto?.trim(),
      currentStep: currentStep,
      totalSteps: totalSteps,
    );
  }

  Future<String?> _readGitFile(RepositoryHandle handle, String path) async {
    final resolved = await _readGitPath(handle, path);
    if (resolved == null) return null;
    return _readFileAt(resolved);
  }

  Future<String?> _readGitPath(RepositoryHandle handle, String path) async {
    try {
      final output = await _runner.run(
        GitInvocation(
          program: gitPath,
          args: ['rev-parse', '--git-path', path],
          cwd: handle.root,
          kind: GitOperationKind.read,
          outputPolicy: const OutputPolicy.capture(maxBytes: 4 * 1024),
        ),
      );
      final rawPath = utf8.decode(output.stdout, allowMalformed: true).trim();
      if (rawPath.isEmpty) return null;
      final pathUri = Uri.file(rawPath);
      if (pathUri.isAbsolute) return rawPath;
      return '${handle.root}${Platform.pathSeparator}${rawPath.replaceAll('/', Platform.pathSeparator)}';
    } on GitError {
      return null;
    }
  }

  Future<String?> _readFileAt(String path) async {
    final file = File(path);
    if (!file.existsSync()) return null;
    try {
      final bytes = <int>[];
      await for (final chunk in file.openRead(
        0,
        _maxConflictMetadataBytes + 1,
      )) {
        bytes.addAll(chunk);
      }
      if (bytes.length > _maxConflictMetadataBytes) return null;
      return utf8.decode(bytes, allowMalformed: true);
    } on FileSystemException {
      return null;
    }
  }

  Future<void> _writeConflictResult(
    RepositoryHandle handle,
    String path,
    List<int> bytes,
  ) => _repositoryFile(handle.root, path).writeAsBytes(bytes, flush: true);

  File _repositoryFile(String root, String path) {
    if (path.startsWith('/') ||
        path.startsWith('\\') ||
        path.split('/').any((part) => part == '..')) {
      throw const GitError(
        category: GitErrorCategory.conflictResolutionNotAllowed,
        userMessage: 'Git returned an unsafe conflict path.',
        diagnostic: 'conflict path escaped the repository root',
        retryable: false,
      );
    }
    return File(
      '$root${Platform.pathSeparator}${path.replaceAll('/', Platform.pathSeparator)}',
    );
  }

  List<String> _conflictOperationArgs(
    GitConflictOperation operation,
    GitConflictOperationAction action,
  ) {
    final flag = action == GitConflictOperationAction.abort
        ? '--abort'
        : '--continue';
    return switch (operation) {
      GitConflictOperation.merge => ['merge', flag],
      GitConflictOperation.rebase => ['rebase', flag],
      GitConflictOperation.cherryPick => ['cherry-pick', flag],
      GitConflictOperation.revert => ['revert', flag],
    };
  }

  void _validatePath(String path) {
    if (path.isEmpty || path.contains('\u0000')) {
      throw const GitError(
        category: GitErrorCategory.parseFailure,
        userMessage: 'Git could not update that file path.',
        diagnostic: 'mutation path was empty or contained a NUL byte',
        retryable: false,
      );
    }
  }

  Future<ProcessOutput> _runGit(String cwd, List<String> args) => _runner.run(
    GitInvocation(
      program: gitPath,
      args: args,
      cwd: cwd,
      kind: GitOperationKind.read,
      outputPolicy: const OutputPolicy.capture(
        maxBytes: CaptureOutputPolicy.defaultCaptureBytes,
      ),
    ),
  );

  Future<ProcessOutput> _runForRepository(String cwd, List<String> args) async {
    try {
      return await _runGit(cwd, args);
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(_asNotRepository(error), stackTrace);
    }
  }

  Future<_HistorySnapshot> _captureHistorySnapshot(
    RepositoryHandle handle,
    GitHistoryFilters filters,
  ) async {
    final output = await _runner.run(
      GitInvocation(
        program: gitPath,
        args: const [
          'for-each-ref',
          '--sort=refname',
          '--format=%(refname)%00%(objectname)%00%(objecttype)%00%(*objectname)%00%(*objecttype)',
        ],
        cwd: handle.root,
        kind: GitOperationKind.read,
        outputPolicy: const OutputPolicy.capture(maxBytes: 2 * 1024 * 1024),
      ),
    );
    final refs = _parseHistoryRefs(output.stdout);
    try {
      final head = await _runner.run(
        GitInvocation(
          program: gitPath,
          args: const ['rev-parse', '--verify', '--quiet', 'HEAD'],
          cwd: handle.root,
          kind: GitOperationKind.read,
          outputPolicy: const OutputPolicy.capture(maxBytes: 4 * 1024),
        ),
      );
      final headOid = utf8.decode(head.stdout, allowMalformed: true).trim();
      if (_isCommitOid(headOid) &&
          !refs.any((ref) => ref.name == 'HEAD' && ref.targetOid == headOid)) {
        refs.add(GitCommitRef(name: 'HEAD', targetOid: headOid));
      }
    } on GitError {
      // An unborn repository has no HEAD; its history is simply empty.
    }

    var tips = <String>{
      for (final ref in refs)
        if (_isCommitOid(ref.targetOid)) ref.targetOid,
    }.toList()..sort();
    if (filters.ref.isNotEmpty) {
      final selected = await _resolveHistoryRef(handle, filters.ref);
      tips = [selected];
    }
    return _HistorySnapshot(tips: tips, refs: refs);
  }

  Future<String> _resolveHistoryRef(RepositoryHandle handle, String ref) async {
    late final ProcessOutput output;
    try {
      output = await _runner.run(
        GitInvocation(
          program: gitPath,
          args: ['rev-parse', '--verify', '--quiet', '$ref^{commit}'],
          cwd: handle.root,
          kind: GitOperationKind.read,
          outputPolicy: const OutputPolicy.capture(maxBytes: 4 * 1024),
        ),
      );
    } on GitError catch (_, stackTrace) {
      Error.throwWithStackTrace(
        _historyFailure(
          category: GitErrorCategory.invalidRevision,
          userMessage: 'That history ref does not point to a commit.',
          diagnostic: 'history ref could not be resolved',
        ),
        stackTrace,
      );
    }
    final oid = utf8.decode(output.stdout, allowMalformed: true).trim();
    if (!_isCommitOid(oid)) {
      throw _historyFailure(
        category: GitErrorCategory.invalidRevision,
        userMessage: 'That history ref does not point to a commit.',
        diagnostic: 'history ref resolved to an invalid commit ID',
      );
    }
    return oid;
  }

  List<GitCommitRef> _parseHistoryRefs(List<int> bytes) {
    final refs = <GitCommitRef>[];
    final text = utf8.decode(bytes, allowMalformed: true);
    for (final line in text.split('\n')) {
      final fields = line.split('\u0000');
      if (fields.length < 4) continue;
      final name = fields[0].trim();
      final objectType = fields[2].trim();
      // `%(objectname)` is the tag object for an annotated tag. The `*`
      // atoms dereference it, so the history model always stores a commit ID
      // and can attach the tag to the actual commit row.
      final oid = objectType == 'tag' ? fields[3].trim() : fields[1].trim();
      if (name.isEmpty || !_isCommitOid(oid)) continue;
      refs.add(GitCommitRef(name: name, targetOid: oid));
    }
    return refs;
  }

  List<GitCommitFileChange> _parseCommitFiles(List<int> bytes) {
    final fields = utf8.decode(bytes, allowMalformed: true).split('\u0000');
    final changes = <GitCommitFileChange>[];
    var index = 0;
    while (index < fields.length) {
      final status = fields[index++];
      if (status.isEmpty) continue;
      if (index >= fields.length) break;
      final code = status[0];
      final fileStatus = switch (code) {
        'A' => GitCommitFileStatus.added,
        'C' => GitCommitFileStatus.copied,
        'D' => GitCommitFileStatus.deleted,
        'M' => GitCommitFileStatus.modified,
        'R' => GitCommitFileStatus.renamed,
        'T' => GitCommitFileStatus.typeChanged,
        'U' => GitCommitFileStatus.unmerged,
        _ => GitCommitFileStatus.unknown,
      };
      if (code == 'R' || code == 'C') {
        final oldPath = fields[index++];
        if (index >= fields.length) break;
        final path = fields[index++];
        changes.add(
          GitCommitFileChange(status: fileStatus, oldPath: oldPath, path: path),
        );
      } else {
        changes.add(
          GitCommitFileChange(status: fileStatus, path: fields[index++]),
        );
      }
    }
    return List.unmodifiable(changes);
  }

  void _validateHistoryQuery(
    GitHistoryQuery query, {
    required int legacyOffset,
  }) {
    if (query.limit < 1 || query.limit > 100 || legacyOffset < 0) {
      throw const GitError(
        category: GitErrorCategory.parseFailure,
        userMessage: 'Git history paging values are invalid.',
        diagnostic: 'history limit must be 1..100 and position must be >= 0',
        retryable: false,
      );
    }
    final filters = query.filters;
    for (final value in [
      filters.text,
      filters.author,
      filters.path,
      filters.ref,
    ]) {
      if (value.length > 256 ||
          value.runes.any((rune) => rune < 0x20 || rune == 0x7f)) {
        throw _historyFailure(
          category: GitErrorCategory.parseFailure,
          userMessage: 'That history filter is too long or invalid.',
          diagnostic: 'history filter exceeded 256 characters or contained NUL',
        );
      }
    }
    if (filters.ref.startsWith('-') ||
        filters.ref.contains(RegExp(r'[\r\n\t ]'))) {
      throw _historyFailure(
        category: GitErrorCategory.invalidRevision,
        userMessage: 'Enter a valid branch or ref name.',
        diagnostic: 'history ref contained whitespace or began with a dash',
      );
    }
    if (filters.authoredAfter != null &&
        filters.authoredBefore != null &&
        filters.authoredAfter!.isAfter(filters.authoredBefore!)) {
      throw _historyFailure(
        category: GitErrorCategory.parseFailure,
        userMessage: 'The history date range is invalid.',
        diagnostic: 'history lower date was after upper date',
      );
    }
    final cursor = query.cursor;
    if (cursor != null && cursor.position < 0) {
      throw _historyFailure(
        category: GitErrorCategory.staleOpaqueId,
        userMessage: 'That history page cursor is invalid.',
        diagnostic: 'history cursor position was negative',
      );
    }
  }

  void _validateCommitOid(String oid) {
    if (!_isCommitOid(oid)) {
      throw _historyFailure(
        category: GitErrorCategory.invalidRevision,
        userMessage: 'That commit ID is invalid.',
        diagnostic: 'commit inspection received a non-hex commit ID',
      );
    }
  }

  bool _isCommitOid(String value) =>
      RegExp(r'^[0-9a-fA-F]{40,64}$').hasMatch(value);

  bool _isProtectedPushBranch(String branch) =>
      branch == 'main' ||
      branch == 'master' ||
      branch == 'develop' ||
      branch.startsWith('release/');
}

class _HistorySnapshot {
  _HistorySnapshot({required this.tips, required this.refs});

  final List<String> tips;
  final List<GitCommitRef> refs;
}

class _BranchOperationInspection {
  const _BranchOperationInspection({
    required this.request,
    required this.source,
    required this.target,
    required this.currentBranch,
    required this.sourceOid,
    required this.targetOid,
    required this.ahead,
    required this.behind,
    required this.expectedCommits,
    required this.mergeBase,
    required this.dirtyWorktree,
    required this.detachedHead,
    required this.operationInProgress,
    required this.fingerprint,
    required this.blockingMessage,
  });

  final GitBranchOperationRequest request;
  final String source;
  final String? target;
  final String? currentBranch;
  final String? sourceOid;
  final String? targetOid;
  final int ahead;
  final int behind;
  final int expectedCommits;
  final String? mergeBase;
  final bool dirtyWorktree;
  final bool detachedHead;
  final GitBranchOperation? operationInProgress;
  final String fingerprint;
  final String? blockingMessage;
}

class _HistoryRollbackState {
  const _HistoryRollbackState({
    required this.status,
    required this.currentBranch,
    required this.currentHead,
    required this.upstreamHead,
    required this.upstreamConfigured,
    required this.branchProtected,
    required this.pushedCommits,
    required this.detachedHead,
    required this.dirtyWorktree,
    required this.operationInProgress,
    required this.stagedPaths,
    required this.unstagedPaths,
    required this.trackedStatusPaths,
  });

  final GitStatusSnapshot status;
  final String? currentBranch;
  final String currentHead;
  final String? upstreamHead;
  final bool upstreamConfigured;
  final bool branchProtected;
  final bool pushedCommits;
  final bool detachedHead;
  final bool dirtyWorktree;
  final bool operationInProgress;
  final List<String> stagedPaths;
  final List<String> unstagedPaths;
  final List<String> trackedStatusPaths;
}

class _HistoryRollbackInspection {
  const _HistoryRollbackInspection({
    required this.currentBranch,
    required this.currentHead,
    required this.targetHead,
    required this.upstreamHead,
    required this.branchProtected,
    required this.pushedCommits,
    required this.detachedHead,
    required this.dirtyWorktree,
    required this.operationInProgress,
    required this.impact,
    required this.fingerprint,
    required this.blockingMessage,
    required this.revisionOids,
  });

  final String? currentBranch;
  final String currentHead;
  final String targetHead;
  final String? upstreamHead;
  final bool branchProtected;
  final bool pushedCommits;
  final bool detachedHead;
  final bool dirtyWorktree;
  final bool operationInProgress;
  final GitRollbackImpact impact;
  final String fingerprint;
  final String? blockingMessage;
  final List<String> revisionOids;
}

class _InteractiveRebaseInspection {
  const _InteractiveRebaseInspection({
    required this.currentBranch,
    required this.currentHead,
    required this.upstreamHead,
    required this.mergeCommitCount,
    required this.branchProtected,
    required this.pushedCommits,
    required this.detachedHead,
    required this.dirtyWorktree,
    required this.operationInProgress,
    required this.fingerprint,
    required this.blockingMessage,
    required this.optionLimitations,
  });

  final String? currentBranch;
  final String currentHead;
  final String? upstreamHead;
  final int mergeCommitCount;
  final bool branchProtected;
  final bool pushedCommits;
  final bool detachedHead;
  final bool dirtyWorktree;
  final GitConflictOperation? operationInProgress;
  final String fingerprint;
  final String? blockingMessage;
  final List<String> optionLimitations;
}

class _InteractiveRebaseRecovery {
  const _InteractiveRebaseRecovery({
    required this.fingerprint,
    required this.operation,
    required this.hasConflicts,
    required this.originalHead,
  });

  final String fingerprint;
  final GitConflictOperationMetadata? operation;
  final bool hasConflicts;
  final String? originalHead;
}

class _InteractiveRebaseEditor {
  const _InteractiveRebaseEditor({
    required this.directory,
    required this.sequenceEditorCommand,
    required this.messageEditorCommand,
  });

  final Directory directory;
  final String sequenceEditorCommand;
  final String messageEditorCommand;

  Future<void> dispose() async {
    if (directory.existsSync()) await directory.delete(recursive: true);
  }
}

GitError _historyFailure({
  required GitErrorCategory category,
  required String userMessage,
  required String diagnostic,
}) => GitError(
  category: category,
  userMessage: userMessage,
  diagnostic: diagnostic,
  retryable: false,
);

class _RepositoryRecord {
  _RepositoryRecord(this.root);

  final String root;
  int generation = 0;
  String? statusHash;
  int statusGeneration = 0;
}

const _maxCommitTemplateBytes = 512 * 1024;

const _protectedRollbackBranches = {'main', 'master'};

String _resolveTemplatePath(String root, String configuredPath) {
  var path = configuredPath.trim();
  if (path == '~' || path.startsWith('~/') || path.startsWith('~\\')) {
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home != null && home.isNotEmpty) {
      path = '$home${path.substring(1)}';
    }
  }
  if (Uri.file(path).isAbsolute) return path;
  return '$root${Platform.pathSeparator}$path';
}

GitError _commitFailure({
  required GitErrorCategory category,
  required String userMessage,
  required String diagnostic,
  bool retryable = false,
  GitCommitOutcome outcome = GitCommitOutcome.notCreated,
}) {
  return GitError(
    category: category,
    userMessage: userMessage,
    diagnostic: diagnostic,
    retryable: retryable,
    commitOutcome: outcome,
  );
}

void _validateCommitOptions(GitCommitOptions options) {
  final author = options.author;
  if (author == null) return;
  final invalid =
      author.name.trim().isEmpty ||
      author.email.trim().isEmpty ||
      author.name.contains(RegExp(r'[\r\n<>]')) ||
      author.email.contains(RegExp(r'[\r\n<>]'));
  if (invalid) {
    throw _commitFailure(
      category: GitErrorCategory.invalidCommitOptions,
      userMessage: 'Enter a valid author name and email.',
      diagnostic: 'author override contained an empty or unsafe identity',
    );
  }
}

GitChange? _findChange(GitStatusSnapshot snapshot, String path) {
  for (final change in snapshot.changes) {
    if (change.path == path) return change;
  }
  return null;
}

GitError _staleDiscardError(String diagnostic) {
  return GitError(
    category: GitErrorCategory.staleConfirmation,
    userMessage:
        'The file changed before it could be discarded. Review it again.',
    diagnostic: diagnostic,
    retryable: true,
  );
}

GitError _mapLfsError(GitError error) {
  if (error.category != GitErrorCategory.processFailed) return error;
  final diagnostic = error.diagnostic;
  if (RegExp(
    r'(?:git lfs|lfs|pointer|smudge|filter)',
    caseSensitive: false,
  ).hasMatch(diagnostic)) {
    return error.copyWith(
      category: GitErrorCategory.lfsObjectsMissing,
      userMessage: 'Git LFS could not download all required objects. Check the remote and try again.',
      retryable: true,
    );
  }
  return error;
}

GitError _mapCommitError(GitError error) {
  if (error.category != GitErrorCategory.processFailed) return error;
  if (RegExp(
    r'(?:gpg|gpg2|signing|secret key|cannot sign)',
    caseSensitive: false,
  ).hasMatch(error.diagnostic)) {
    return error.copyWith(
      category: GitErrorCategory.signingFailed,
      userMessage: 'Git could not sign this commit.',
      retryable: false,
    );
  }
  if (RegExp(
    r'\b(?:hook|pre-commit|commit-msg|pre-merge-commit|post-commit)\b',
    caseSensitive: false,
  ).hasMatch(error.diagnostic)) {
    return error.copyWith(
      category: GitErrorCategory.hookRejected,
      userMessage: 'The commit hook rejected this commit.',
      retryable: false,
    );
  }
  return error;
}

GitError _mapBranchError(GitError error) {
  if (error.category != GitErrorCategory.processFailed) return error;
  final diagnostic = error.diagnostic;
  if (RegExp(
    r'(local changes|would be overwritten|uncommitted changes)',
    caseSensitive: false,
  ).hasMatch(diagnostic)) {
    return error.copyWith(
      category: GitErrorCategory.dirtyWorktree,
      userMessage: 'Commit or stash local changes before switching branches.',
      retryable: false,
    );
  }
  if (RegExp(r'already exists', caseSensitive: false).hasMatch(diagnostic)) {
    return error.copyWith(
      userMessage: 'That branch already exists.',
      retryable: false,
    );
  }
  return error;
}

GitError _mapBranchOperationError(GitError error) {
  if (error.category != GitErrorCategory.processFailed) return error;
  final diagnostic = error.diagnostic;
  if (RegExp(
    r'(local changes|would be overwritten|uncommitted changes)',
    caseSensitive: false,
  ).hasMatch(diagnostic)) {
    return error.copyWith(
      category: GitErrorCategory.dirtyWorktree,
      userMessage: 'Commit or stash local changes before this operation.',
      retryable: false,
    );
  }
  if (RegExp(
    r'(not a valid branch name|invalid ref)',
    caseSensitive: false,
  ).hasMatch(diagnostic)) {
    return error.copyWith(
      category: GitErrorCategory.invalidBranchName,
      userMessage: 'Enter a valid branch name accepted by Git.',
      retryable: false,
    );
  }
  if (RegExp(
    r'(non-fast-forward|would be overwritten)',
    caseSensitive: false,
  ).hasMatch(diagnostic)) {
    return error.copyWith(
      category: GitErrorCategory.nonFastForward,
      userMessage:
          'Git could not apply the operation without rewriting history.',
      retryable: false,
    );
  }
  return error;
}

GitError _mapInteractiveRebaseError(GitError error) {
  if (error.category != GitErrorCategory.processFailed) return error;
  if (RegExp(
    r'\b(?:hook|pre-commit|commit-msg|post-commit|pre-rebase)\b',
    caseSensitive: false,
  ).hasMatch(error.diagnostic)) {
    return error.copyWith(
      category: GitErrorCategory.hookRejected,
      userMessage: 'A Git hook stopped the interactive rebase.',
      retryable: false,
    );
  }
  return error.copyWith(
    category: GitErrorCategory.historyRollbackNotAllowed,
    userMessage: 'Git could not complete the interactive rebase.',
    retryable: false,
  );
}

void _validateBranchName(String name) {
  final invalid =
      name.isEmpty ||
      name != name.trim() ||
      name.startsWith('-') ||
      name.endsWith('.') ||
      name.endsWith('/') ||
      name.startsWith('.') ||
      name.startsWith('/') ||
      name.contains('..') ||
      name.contains('@{') ||
      RegExp(r'[\u0000-\u0020~^:?*\\\[\]]').hasMatch(name) ||
      name.contains('//');
  if (invalid) {
    throw const GitError(
      category: GitErrorCategory.parseFailure,
      userMessage: 'Enter a valid branch name.',
      diagnostic: 'branch name failed Git ref validation',
      retryable: false,
    );
  }
}

void _validateRemoteName(String name) {
  if (name.isEmpty ||
      name != name.trim() ||
      name.contains('\u0000') ||
      RegExp(r'[\s/]').hasMatch(name)) {
    throw const GitError(
      category: GitErrorCategory.parseFailure,
      userMessage: 'Enter a valid remote name.',
      diagnostic: 'remote name was empty or contained whitespace/path syntax',
      retryable: false,
    );
  }
}

void _validateRemoteUrl(String url) {
  if (url.isEmpty ||
      url.length > 4096 ||
      url.runes.any((rune) => rune < 0x20 || rune == 0x7f)) {
    throw const GitError(
      category: GitErrorCategory.parseFailure,
      userMessage: 'Enter a valid remote URL.',
      diagnostic: 'remote URL was empty, too long, or contained a control byte',
      retryable: false,
    );
  }
}

void _validateObjectMessage(String message, String label) {
  if (message.length > 16 * 1024 ||
      message.runes.any((rune) => rune == 0 || rune == 0x7f)) {
    throw GitError(
      category: GitErrorCategory.parseFailure,
      userMessage: 'The $label is too long or contains an invalid character.',
      diagnostic: '$label exceeded the bounded input contract',
      retryable: false,
    );
  }
}

void _validateObjectOid(String oid, String label) {
  if (!_isObjectOidValue(oid)) {
    throw GitError(
      category: GitErrorCategory.invalidObjectName,
      userMessage: 'That $label identity is invalid.',
      diagnostic: '$label action received a non-hex object ID',
      retryable: false,
    );
  }
}

void _validateTagName(String name) {
  if (name.isEmpty ||
      name.startsWith('-') ||
      name.contains('\u0000') ||
      name.contains(RegExp(r'[\r\n]'))) {
    throw const GitError(
      category: GitErrorCategory.invalidObjectName,
      userMessage: 'Enter a valid tag name.',
      diagnostic:
          'tag name was empty, option-like, or contained a control line',
      retryable: false,
    );
  }
}

bool _isObjectOidValue(String value) =>
    RegExp(r'^[0-9a-fA-F]{40,64}$').hasMatch(value);

GitStashEntry? _findStash(GitStashSnapshot snapshot, String oid) =>
    snapshot.entries.where((entry) => entry.oid == oid).firstOrNull;

GitRemote? _findRemote(List<GitRemote> remotes, String name) =>
    remotes.where((remote) => remote.name == name).firstOrNull;

String _tagIdentity(GitTag tag) => tag.tagObjectOid ?? tag.targetOid;

String _remoteIdentity(GitRemote remote) =>
    '${remote.name}|${remote.fetchUrl ?? ''}|${remote.pushUrl ?? ''}';

String _remoteFingerprint(List<GitRemote> remotes) {
  final values = remotes.map(_remoteIdentity).toList()..sort();
  return hashGitObjectBytes(utf8.encode(values.join('\u0000')));
}

GitError _objectNotFound(String kind, String name) => GitError(
  category: GitErrorCategory.objectNotFound,
  userMessage: 'That $kind could not be found.',
  diagnostic: '$kind was not present in the current repository snapshot: $name',
  retryable: true,
);

GitError _objectAlreadyExists(String kind, String name) => GitError(
  category: GitErrorCategory.objectOperationNotAllowed,
  userMessage: 'That $kind already exists.',
  diagnostic: 'duplicate $kind name: $name',
  retryable: false,
);

bool _looksLikeConflict(GitError error) =>
    error.category == GitErrorCategory.mergeConflict ||
    RegExp(
      r'(conflict|unmerged|could not apply)',
      caseSensitive: false,
    ).hasMatch(error.diagnostic);

String _objectSummary(ProcessOutput output, String fallback) {
  final text = redactBytes([...output.stdout, ...output.stderr]).trim();
  return text.isEmpty ? fallback : text;
}

GitError _mapObjectError(GitError error) {
  if (error.category != GitErrorCategory.processFailed) return error;
  if (_looksLikeConflict(error)) {
    return error.copyWith(
      category: GitErrorCategory.mergeConflict,
      userMessage: 'Git stopped because conflicts remain.',
      retryable: true,
    );
  }
  return error;
}

GitError _mapHistoryRollbackError(GitError error) {
  if (error.category != GitErrorCategory.processFailed) return error;
  if (_looksLikeConflict(error)) {
    return error.copyWith(
      category: GitErrorCategory.mergeConflict,
      userMessage:
          'Git could not complete the rollback because conflicts remain.',
      retryable: true,
    );
  }
  return error;
}

GitError _mapRemoteError(GitError error) {
  if (error.category != GitErrorCategory.processFailed) return error;
  final diagnostic = error.diagnostic;
  if (RegExp(
    r'(stale info|stale remote|force-with-lease)',
    caseSensitive: false,
  ).hasMatch(diagnostic)) {
    return error.copyWith(
      category: GitErrorCategory.staleRemoteRef,
      userMessage: 'The remote branch moved before the push was accepted.',
      retryable: true,
    );
  }
  if (RegExp(
    r'(authentication failed|could not read username|permission denied|access denied)',
    caseSensitive: false,
  ).hasMatch(diagnostic)) {
    return error.copyWith(
      category: GitErrorCategory.authenticationRequired,
      userMessage: 'Git needs authentication for this remote.',
      retryable: true,
    );
  }
  if (RegExp(
    r'(could not resolve host|connection timed out|network is unreachable|failed to connect)',
    caseSensitive: false,
  ).hasMatch(diagnostic)) {
    return error.copyWith(
      category: GitErrorCategory.networkUnavailable,
      userMessage: 'The remote could not be reached.',
      retryable: true,
    );
  }
  if (RegExp(
    r'(non-fast-forward|rejected.*fetch first|updates were rejected)',
    caseSensitive: false,
  ).hasMatch(diagnostic)) {
    return error.copyWith(
      category: GitErrorCategory.nonFastForward,
      userMessage:
          'The remote rejected this push because it is not fast-forward.',
      retryable: false,
    );
  }
  if (RegExp(
    r'(merge conflict|automatic merge failed|conflict)',
    caseSensitive: false,
  ).hasMatch(diagnostic)) {
    return error.copyWith(
      category: GitErrorCategory.mergeConflict,
      userMessage: 'Git could not complete the operation because of conflicts.',
      retryable: false,
    );
  }
  return error;
}

GitError _mapPushError(GitError error, bool forceWithLease) {
  final mapped = _mapRemoteError(error);
  if (forceWithLease && mapped.category == GitErrorCategory.nonFastForward) {
    return mapped.copyWith(
      category: GitErrorCategory.staleRemoteRef,
      userMessage: 'The remote branch moved before the lease was accepted.',
      retryable: true,
    );
  }
  return mapped;
}

GitError _mapWorktreeError(GitError error) {
  if (error.category != GitErrorCategory.processFailed) return error;
  final diagnostic = error.diagnostic;
  if (RegExp(
    r'(already exists|already used|is already checked out|branch .* exists)',
    caseSensitive: false,
  ).hasMatch(diagnostic)) {
    return error.copyWith(
      category: GitErrorCategory.worktreeBranchOccupied,
      userMessage: 'That branch or worktree is already in use.',
      retryable: false,
    );
  }
  if (RegExp(
    r'(dirty|modified|contains modified)',
    caseSensitive: false,
  ).hasMatch(diagnostic)) {
    return error.copyWith(
      category: GitErrorCategory.dirtyWorktree,
      userMessage: 'The worktree has local changes that must be confirmed.',
      retryable: false,
    );
  }
  if (RegExp(
    r'(locked|lock file)',
    caseSensitive: false,
  ).hasMatch(diagnostic)) {
    return error.copyWith(
      category: GitErrorCategory.worktreeOperationNotAllowed,
      userMessage: 'The worktree is locked. Unlock it before removing it.',
      retryable: false,
    );
  }
  return error;
}

String _worktreePathFromInput(String root, String input) {
  final value = input.trim();
  final absolute =
      value.startsWith('/') ||
      value.startsWith('\\') ||
      RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value);
  final path = absolute
      ? value
      : '$root${Platform.pathSeparator}${value.replaceAll('/', Platform.pathSeparator)}';
  return Directory(path).absolute.path;
}

bool _sameWorktreePath(String left, String right) {
  final normalizedLeft = Directory(left).absolute.path
      .replaceAll('\\', '/')
      .replaceAll(RegExp(r'/+$'), '');
  final normalizedRight = Directory(right).absolute.path
      .replaceAll('\\', '/')
      .replaceAll(RegExp(r'/+$'), '');
  return Platform.isWindows
      ? normalizedLeft.toLowerCase() == normalizedRight.toLowerCase()
      : normalizedLeft == normalizedRight;
}

void _addRepositoryPathDirectories(
  Map<String, GitRepositoryPathKind> paths,
  String filePath,
) {
  final segments = filePath.split('/');
  var current = '';
  for (var index = 0; index < segments.length - 1; index++) {
    current = current.isEmpty ? segments[index] : '$current/${segments[index]}';
    paths.putIfAbsent(current, () => GitRepositoryPathKind.directory);
  }
}

bool _isRecoverablePushFailure(GitErrorCategory category) => switch (category) {
  GitErrorCategory.nonFastForward ||
  GitErrorCategory.staleRemoteRef ||
  GitErrorCategory.authenticationRequired ||
  GitErrorCategory.permissionDenied ||
  GitErrorCategory.networkUnavailable => true,
  _ => false,
};

List<GitPushRecoveryAction> _pushRecoveryActions(GitErrorCategory category) =>
    switch (category) {
      GitErrorCategory.nonFastForward => const [
        GitPushRecoveryAction.merge,
        GitPushRecoveryAction.rebase,
      ],
      GitErrorCategory.staleRemoteRef => const [GitPushRecoveryAction.retry],
      _ => const [GitPushRecoveryAction.retry],
    };

GitError _mapUpdateError(GitError error) {
  if (error.category != GitErrorCategory.processFailed) return error;
  if (RegExp(
    r'(local changes|would be overwritten|uncommitted changes)',
    caseSensitive: false,
  ).hasMatch(error.diagnostic)) {
    return error.copyWith(
      category: GitErrorCategory.dirtyWorktree,
      userMessage: 'Commit or stash local changes before updating.',
      retryable: false,
    );
  }
  if (_looksLikeConflict(error)) {
    return error.copyWith(
      category: GitErrorCategory.mergeConflict,
      userMessage: 'The update stopped because conflicts need to be resolved.',
      retryable: true,
    );
  }
  return error.copyWith(
    category: GitErrorCategory.updateNotAllowed,
    userMessage: 'Git could not update the project from its remote branch.',
    retryable: true,
  );
}

String _normalizeGitFilesystemPath(String path) {
  if (!Platform.isWindows) return path;
  return path.replaceAll('/', r'\');
}

Future<String> _canonicalizeDirectory(String path, {bool moved = false}) async {
  final directory = Directory(path);
  try {
    if (!await directory.exists()) {
      throw const FileSystemException('directory does not exist');
    }
    return await directory.resolveSymbolicLinks();
  } on Object catch (error) {
    throw GitError(
      category: moved
          ? GitErrorCategory.repositoryMoved
          : GitErrorCategory.notRepository,
      userMessage: moved
          ? 'The repository folder is no longer available.'
          : 'The selected folder is not a Git repository.',
      diagnostic: 'could not resolve selected folder: $error',
      retryable: moved,
    );
  }
}

GitError _asNotRepository(Object error) {
  if (error is GitError && error.category == GitErrorCategory.processFailed) {
    return GitError(
      category: GitErrorCategory.notRepository,
      userMessage: 'The selected folder is not a Git repository.',
      diagnostic: error.diagnostic,
      retryable: false,
      exitCode: error.exitCode,
    );
  }
  if (error is GitError) return error;
  return GitError(
    category: GitErrorCategory.notRepository,
    userMessage: 'The selected folder is not a Git repository.',
    diagnostic: '$error',
    retryable: false,
  );
}

String _newRepositoryId() {
  final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}

String _newOpaqueToken() => _newRepositoryId();

List<List<int>> _splitNulBytes(List<int> bytes) {
  final records = <List<int>>[];
  var start = 0;
  for (var index = 0; index < bytes.length; index++) {
    if (bytes[index] != 0) continue;
    records.add(bytes.sublist(start, index));
    start = index + 1;
  }
  if (start < bytes.length) records.add(bytes.sublist(start));
  return records;
}

const _maxConflictTextBytes = 4 * 1024 * 1024;
const _maxConflictMetadataBytes = 64 * 1024;

GitConflictEntry? _findConflict(GitConflictSnapshot snapshot, String path) {
  for (final conflict in snapshot.conflicts) {
    if (conflict.path == path) return conflict;
  }
  return null;
}

GitError _mapConflictError(GitError error) {
  if (error.category != GitErrorCategory.processFailed) return error;
  if (RegExp(
    r'(unmerged|conflict|resolve|merge conflict|cherry-pick|rebase)',
    caseSensitive: false,
  ).hasMatch(error.diagnostic)) {
    return error.copyWith(
      category: GitErrorCategory.mergeConflict,
      userMessage: 'Git could not finish because conflicts remain.',
      retryable: true,
    );
  }
  return error;
}

class _HistoryBatchPreviewRecord {
  const _HistoryBatchPreviewRecord({
    required this.repositoryId,
    required this.requestKey,
    required this.fingerprint,
    required this.expiresAt,
  });

  final RepositoryId repositoryId;
  final String requestKey;
  final String fingerprint;
  final DateTime expiresAt;
}

class _HistoryBatchContinuationRecord {
  _HistoryBatchContinuationRecord({
    required this.repositoryId,
    required this.requestKey,
    required this.fingerprint,
    required List<String> completedOids,
    required List<String> skippedOids,
    required this.currentOid,
    required List<String> remainingOids,
    required this.expiresAt,
  }) : completedOids = List.unmodifiable(completedOids),
       skippedOids = List.unmodifiable(skippedOids),
       remainingOids = List.unmodifiable(remainingOids);

  final RepositoryId repositoryId;
  final String requestKey;
  final String fingerprint;
  final List<String> completedOids;
  final List<String> skippedOids;
  final String currentOid;
  final List<String> remainingOids;
  final DateTime expiresAt;
}

bool _sameStrings(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

class _HistoryBatchInspection {
  const _HistoryBatchInspection({
    required this.currentBranch,
    required this.currentHead,
    required this.targetBranch,
    required this.displayedOids,
    required this.executionOids,
    required this.executionDirection,
    required this.dirtyWorktree,
    required this.detachedHead,
    required this.operationInProgress,
    required this.duplicateOids,
    required this.containedOids,
    required this.mergeCommitOids,
    required this.mergeMainlineRequired,
    required this.impactedPaths,
    required this.fingerprint,
    required this.blockingMessage,
  });

  final String? currentBranch;
  final String currentHead;
  final String? targetBranch;
  final List<String> displayedOids;
  final List<String> executionOids;
  final GitHistoryBatchExecutionDirection executionDirection;
  final bool dirtyWorktree;
  final bool detachedHead;
  final GitBranchOperation? operationInProgress;
  final List<String> duplicateOids;
  final List<String> containedOids;
  final List<String> mergeCommitOids;
  final List<String> mergeMainlineRequired;
  final List<String> impactedPaths;
  final String fingerprint;
  final String? blockingMessage;
}
