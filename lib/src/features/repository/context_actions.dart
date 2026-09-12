import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gift/src/backend/diff.dart';
import 'package:gift/src/backend/domain.dart';

/// Stable object kinds that can participate in contextual actions.
///
/// More object kinds can be added without changing the menu presenter. The
/// identity is always supplied by the caller from an immutable Git snapshot.
enum ContextActionTargetKind { change, commit, branch, remote, repository }

/// A stable identity for the object that owns a contextual action menu.
class ContextActionTarget {
  const ContextActionTarget({
    required this.kind,
    required this.identity,
    required this.label,
    this.originalPath,
    this.diffScope,
  });

  const ContextActionTarget.change({
    required String path,
    String? originalPath,
    GitDiffScope? diffScope,
  }) : this(
         kind: ContextActionTargetKind.change,
         identity: path,
         label: path,
         originalPath: originalPath,
         diffScope: diffScope,
       );

  const ContextActionTarget.branch({
    required String name,
    required String label,
  }) : this(kind: ContextActionTargetKind.branch, identity: name, label: label);

  const ContextActionTarget.remote({
    required String name,
    required String label,
  }) : this(kind: ContextActionTargetKind.remote, identity: name, label: label);
  const ContextActionTarget.repository({
    required String path,
    required String label,
  }) : this(
         kind: ContextActionTargetKind.repository,
         identity: path,
         label: label,
       );

  const ContextActionTarget.commit({required String oid, required String label})
    : this(kind: ContextActionTargetKind.commit, identity: oid, label: label);

  final ContextActionTargetKind kind;
  final String identity;
  final String label;
  final String? originalPath;
  final GitDiffScope? diffScope;

  @override
  int get hashCode =>
      Object.hash(kind, identity, label, originalPath, diffScope);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContextActionTarget &&
          other.kind == kind &&
          other.identity == identity &&
          other.label == label &&
          other.originalPath == originalPath &&
          other.diffScope == diffScope;
}

/// The immutable repository/object state captured when a menu is opened.
class ContextActionSnapshot {
  const ContextActionSnapshot({
    required this.repository,
    required this.target,
    required this.fingerprint,
  });

  final RepositoryOpened repository;
  final ContextActionTarget target;
  final String fingerprint;

  @override
  int get hashCode => Object.hash(repository, target, fingerprint);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContextActionSnapshot &&
          other.repository == repository &&
          other.target == target &&
          other.fingerprint == fingerprint;
}

enum ContextActionId {
  inspect,
  stage,
  unstage,
  stageSelectedPatch,
  discard,
  moveToChangelist,
  shelve,
  ignoreLocal,
  ignoreRepository,
  fileHistory,
  blame,
  compare,
  compareBranch,
  copyRelativePath,
  copyAbsolutePath,
  reveal,
  cherryPick,
  revert,
  createBranch,
  createTag,
  reset,
  copyFullHash,
  copyShortHash,
  checkoutBranch,
  mergeBranch,
  rebaseBranch,
  renameBranch,
  deleteBranch,
  pushBranch,
  upstream,
  copyBranchName,
  copyBranchRef,
  compareRemote,
  checkoutRemote,
  deleteRemote,
  cherryPickRemote,
  hostLink,
  openRepository,
  activateRepository,
  closeRepository,
  closeOtherRepositories,
  removeRecentRepository,
  copyRepositoryPath,
  revealRepository,
  openNestedRepository,
}

enum ContextActionGroup { inspect, workflow, destructive }

enum ContextActionRoute {
  inspect,
  stage,
  unstage,
  stageSelectedPatch,
  discard,
  moveToChangelist,
  shelve,
  ignoreLocal,
  ignoreRepository,
  fileHistory,
  blame,
  compare,
  compareBranch,
  copyRelativePath,
  copyAbsolutePath,
  reveal,
  cherryPick,
  revert,
  createBranch,
  createTag,
  reset,
  copyFullHash,
  copyShortHash,
  checkoutBranch,
  mergeBranch,
  rebaseBranch,
  renameBranch,
  deleteBranch,
  pushBranch,
  upstream,
  copyBranchName,
  copyBranchRef,
  compareRemote,
  checkoutRemote,
  deleteRemote,
  cherryPickRemote,
  hostLink,
  openRepository,
  activateRepository,
  closeRepository,
  closeOtherRepositories,
  removeRecentRepository,
  copyRepositoryPath,
  revealRepository,
  openNestedRepository,
}

/// One item in a context menu, including its availability and reviewed route.
/// The result of evaluating whether a descriptor can run against its snapshot.
class ContextActionAvailability {
  const ContextActionAvailability({required this.enabled, this.disabledReason})
    : assert(enabled || disabledReason != null);

  final bool enabled;
  final String? disabledReason;

  @override
  int get hashCode => Object.hash(enabled, disabledReason);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContextActionAvailability &&
          other.enabled == enabled &&
          other.disabledReason == disabledReason;
}

class ContextActionDescriptor {
  ContextActionDescriptor({
    required this.id,
    required this.label,
    required this.icon,
    required this.group,
    required this.route,
    required this.snapshot,
    bool enabled = true,
    String? disabledReason,
  }) : availability = ContextActionAvailability(
         enabled: enabled,
         disabledReason: disabledReason,
       );

  final ContextActionId id;
  final String label;
  final IconData icon;
  final ContextActionGroup group;
  final ContextActionRoute route;
  final ContextActionSnapshot snapshot;
  final ContextActionAvailability availability;

  bool get enabled => availability.enabled;
  String? get disabledReason => availability.disabledReason;
  bool get isDisabled => !enabled;

  @override
  int get hashCode =>
      Object.hash(id, label, icon, group, route, snapshot, availability);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContextActionDescriptor &&
          other.id == id &&
          other.label == label &&
          other.icon == icon &&
          other.group == group &&
          other.route == route &&
          other.snapshot == snapshot &&
          other.availability == availability;
}

typedef ContextActionHandler = FutureOr<void> Function(
  ContextActionDescriptor action,
);

/// Presents the same typed actions from secondary click, keyboard, and an
/// optional [ContextActionMenuButton].
///
/// [showMenu] supplies arrow-key navigation and Escape dismissal. This widget
/// adds the desktop invocation keys, pointer anchoring, stale-snapshot checks,
/// and focus restoration around that standard Flutter behavior.
class ContextActionMenu extends StatefulWidget {
  ContextActionMenu({
    required this.snapshot,
    required List<ContextActionDescriptor> actions,
    required this.onAction,
    required this.child,
    this.focusNode,
    super.key,
  }) : actions = List.unmodifiable(actions);

  final ContextActionSnapshot snapshot;
  final List<ContextActionDescriptor> actions;
  final ContextActionHandler onAction;
  final Widget child;
  final FocusNode? focusNode;

  @override
  State<ContextActionMenu> createState() => _ContextActionMenuState();

  static void Function(BuildContext context)? openTriggerOf(
    BuildContext context,
  ) => context
      .dependOnInheritedWidgetOfExactType<_ContextActionMenuScope>()
      ?.openFromTrigger;
}

class _ContextActionMenuState extends State<ContextActionMenu> {
  late final FocusNode _internalFocusNode;
  bool _menuOpen = false;

  FocusNode get _focusNode => widget.focusNode ?? _internalFocusNode;

  @override
  void initState() {
    super.initState();
    _internalFocusNode = FocusNode(debugLabel: 'context-action-target');
  }

  @override
  void dispose() {
    _internalFocusNode.dispose();
    super.dispose();
  }

  void _focusTarget() => _focusNode.requestFocus();

  void _openFromTarget() {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;
    _openAtGlobal(renderObject.localToGlobal(Offset.zero));
  }

  void _openFromTrigger(BuildContext triggerContext) {
    final renderObject = triggerContext.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      _openFromTarget();
      return;
    }
    _openAtGlobal(renderObject.localToGlobal(Offset.zero));
  }

  void _openAtGlobal(Offset globalPosition) {
    if (_menuOpen || widget.actions.isEmpty) return;
    unawaited(_showMenu(globalPosition));
  }

  Future<void> _showMenu(Offset globalPosition) async {
    _menuOpen = true;
    final openedSnapshot = widget.snapshot;
    try {
      final selected = await showMenu<ContextActionDescriptor>(
        context: context,
        position: _menuPosition(globalPosition),
        items: _menuItems(context),
        constraints: const BoxConstraints(minWidth: 220, maxWidth: 300),
        semanticLabel: 'Context actions for ${openedSnapshot.target.label}',
        requestFocus: true,
      );
      if (!mounted) return;
      _focusTarget();
      if (selected == null || widget.snapshot != openedSnapshot) return;
      if (selected.snapshot != openedSnapshot || !selected.enabled) return;
      await widget.onAction(selected);
    } finally {
      _menuOpen = false;
    }
  }

  RelativeRect _menuPosition(Offset globalPosition) {
    final overlay = Overlay.of(context).context.findRenderObject();
    if (overlay is! RenderBox || !overlay.hasSize) {
      return RelativeRect.fill;
    }
    final local = overlay.globalToLocal(globalPosition);
    return RelativeRect.fromLTRB(
      local.dx,
      local.dy,
      overlay.size.width - local.dx,
      overlay.size.height - local.dy,
    );
  }

  List<PopupMenuEntry<ContextActionDescriptor>> _menuItems(
    BuildContext context,
  ) {
    final items = <PopupMenuEntry<ContextActionDescriptor>>[];
    ContextActionGroup? previousGroup;
    for (final action in widget.actions) {
      if (action.group != previousGroup) {
        if (items.isNotEmpty) items.add(const PopupMenuDivider(height: 1));
        items.add(_groupHeading(context, action.group));
        previousGroup = action.group;
      }
      items.add(_actionItem(context, action));
    }
    return items;
  }

  PopupMenuEntry<ContextActionDescriptor> _groupHeading(
    BuildContext context,
    ContextActionGroup group,
  ) {
    final label = switch (group) {
      ContextActionGroup.inspect => 'INSPECT',
      ContextActionGroup.workflow => 'WORKFLOW',
      ContextActionGroup.destructive => 'DESTRUCTIVE',
    };
    return PopupMenuItem<ContextActionDescriptor>(
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

  PopupMenuEntry<ContextActionDescriptor> _actionItem(
    BuildContext context,
    ContextActionDescriptor action,
  ) {
    final reason = action.disabledReason;
    return PopupMenuItem<ContextActionDescriptor>(
      value: action,
      enabled: action.enabled,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Semantics(
        button: true,
        enabled: action.enabled,
        label: action.enabled
            ? action.label
            : '${action.label}: ${reason ?? 'Unavailable'}',
        child: Row(
          crossAxisAlignment: reason == null
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: reason == null ? 0 : 2),
              child: Icon(action.icon, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: reason == null
                  ? Text(action.label)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(action.label),
                        Text(
                          reason,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final shiftPressed = HardwareKeyboard.instance.logicalKeysPressed.any(
      (key) =>
          key == LogicalKeyboardKey.shiftLeft ||
          key == LogicalKeyboardKey.shiftRight,
    );
    if (event.logicalKey == LogicalKeyboardKey.contextMenu ||
        (event.logicalKey == LogicalKeyboardKey.f10 && shiftPressed)) {
      _openFromTarget();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return _ContextActionMenuScope(
      open: _openFromTarget,
      openFromTrigger: _openFromTrigger,
      child: Semantics(
        container: true,
        label: 'Context actions for ${widget.snapshot.target.label}',
        child: Listener(
          onPointerDown: (event) {
            if (event.buttons & kPrimaryMouseButton != 0 &&
                event.buttons & kSecondaryMouseButton == 0) {
              _focusTarget();
            }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onSecondaryTapUp: (details) =>
                _openAtGlobal(details.globalPosition),
            child: Focus(
              focusNode: _focusNode,
              canRequestFocus: true,
              onKeyEvent: _handleKeyEvent,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

class _ContextActionMenuScope extends InheritedWidget {
  const _ContextActionMenuScope({
    required this.open,
    required this.openFromTrigger,
    required super.child,
  });

  final VoidCallback open;
  final void Function(BuildContext context) openFromTrigger;

  @override
  bool updateShouldNotify(_ContextActionMenuScope oldWidget) =>
      oldWidget.open != open || oldWidget.openFromTrigger != openFromTrigger;
}

/// An overflow affordance that invokes the parent [ContextActionMenu].
class ContextActionMenuButton extends StatelessWidget {
  const ContextActionMenuButton({
    super.key,
    this.icon = Icons.more_vert,
    this.semanticLabel,
  });

  final IconData icon;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final openTrigger = ContextActionMenu.openTriggerOf(context);
    final baseStyle = Theme.of(context).iconButtonTheme.style;
    final label = semanticLabel ?? 'More actions';
    return Semantics(
      excludeSemantics: true,
      button: true,
      enabled: openTrigger != null,
      label: label,
      child: IconButton(
        tooltip: label,
        onPressed: openTrigger == null ? null : () => openTrigger(context),
        style: baseStyle?.copyWith(
          backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
          side: const WidgetStatePropertyAll(BorderSide.none),
          minimumSize: const WidgetStatePropertyAll(Size(32, 32)),
          maximumSize: const WidgetStatePropertyAll(Size(32, 32)),
          padding: const WidgetStatePropertyAll(EdgeInsets.all(7)),
        ),
        icon: Icon(icon, size: 18),
      ),
    );
  }
}
